extends Node

const MindNarrator = preload("res://scripts/mind_narrator.gd")
const MindScheduler = preload("res://scripts/mind_scheduler.gd")
const GuardianGrounding = preload("res://scripts/guardian_grounding.gd")
const GuardianLlmMock = preload("res://scripts/guardian_llm_mock.gd")

# In-process Guardian LLM via godot_llama (llama.cpp GDExtension).
# Steam/desktop builds bundle the GGUF under res://assets/guardian/ (CI fetch).
# Dev/slim builds ask once, then download to user://guardian/ after consent.

signal status_changed(message: String)
signal ready_changed(is_ready: bool)
signal consent_required(needs_download: bool)
signal download_progress_changed(progress: float, detail: String)
signal generation_partial(cache_key: String, partial_text: String)

const MODEL_URL: String = (
	"https://huggingface.co/bartowski/SmolLM2-360M-Instruct-GGUF/resolve/main/"
	+ "SmolLM2-360M-Instruct-Q4_K_M.gguf")
const MODEL_FILENAME: String = "SmolLM2-360M-Instruct-Q4_K_M.gguf"
# Pinned hash — scripts/supply_chain/manifest.env (SYSTEMIC #1/#3).
const MODEL_SHA256: String = (
	"2fa3f013dcdd7b99f9b237717fa0b12d75bbb89984cc1274be1471a465bac9c2")
const MODEL_BYTES_APPROX: int = 250_000_000
const MODEL_MIN_BYTES: int = 200_000_000
const MODEL_MAX_BYTES: int = 290_000_000
const QUEUE_MAX: int = 24
const N_CTX: int = 1024
# Hard cap on what we hand the tokenizer. The native side truncates an
# over-long prompt from the FRONT (dropping the instructions), so trim here.
const MAX_PROMPT_CHARS: int = 2400
# Generation watchdog (SYSTEMIC #15). 80 tokens at ~35 tok/s plus prompt eval
# is ~3 s on a mid CPU; past this the job resolves with its template line.
const GEN_TIMEOUT_MS_DEFAULT: int = 12000
const GEN_HARD_GRACE_MS: int = 15000
# Platform matrix (#14): desktop/Steam bundles SmolLM2-360M; Web/Android = template-only.
# See AGENTS.md § Guardian voice tiers.

enum State { UNAVAILABLE, WAITING_CONSENT, DOWNLOADING, LOADING, READY, BUSY, TEMPLATE_ONLY, ERROR }
var state: int = State.UNAVAILABLE
var last_error: String = ""
var download_progress: float = 0.0

var _llama: RefCounted = null
var _queue: Array = []
var _queue_seq: int = 0
var _last_spoken_seq: int = -1
var _current_job: Dictionary = {}
var _http: HTTPRequest = null
var _load_timer: Timer = null
var _pending_load_path: String = ""
var _partial_text: String = ""
var _mem_check_timer: float = 0.0
var _download_fail_reason: String = ""

# Threading (SYSTEMIC #15): model verify/load and every generation run off the
# main thread. Only one native generation is ever in flight.
var _gen_thread: Thread = null
var _io_thread: Thread = null
var _load_cancelled: bool = false
var _native_busy: bool = false
var _native_text: String = ""
var _native_error: String = ""
var _job_seq: int = 0
var _active_job_id: int = -1   # job whose result we still want (-1: none)
var _running_job_id: int = -1  # job the worker is executing (-1: idle)
var _job_started_ms: int = 0
var gen_timeout_ms: int = GEN_TIMEOUT_MS_DEFAULT
var _mock: bool = false
var _zombie_threads: Array = []
# Debug/test visibility.
var last_result: Dictionary = {}
var result_log: Array = []  # last 8 {key, raw, line, source, reason}
var retractions: int = 0


func _ready() -> void:
	set_process(false)
	var tree := get_tree()
	if tree != null and tree.has_signal("scene_changed") \
			and not tree.is_connected("scene_changed", _on_scene_changed):
		tree.connect("scene_changed", _on_scene_changed)
	if GuardianLlmMock.active():
		call_deferred("enable_mock", true)
		return
	if not _platform_supported():
		state = State.TEMPLATE_ONLY
		return
	if not _extension_available():
		state = State.TEMPLATE_ONLY
		last_error = ""
		return
	# Never load the GGUF at startup — a 250MB in-process model can hard-crash
	# Godot before the menu appears. Consent UI + lazy load on first use only.
	call_deferred("_init_idle_state")


func _init_idle_state() -> void:
	if _mock:
		return
	if not _platform_supported() or not _extension_available():
		return
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		if not cfg.guardian_companion_enabled or not cfg.guardian_voice_enabled:
			state = State.TEMPLATE_ONLY
			return
		if bool(cfg.sentience_voice_off):
			state = State.TEMPLATE_ONLY
			return
	var consent: String = str(cfg.guardian_mind_consent) if cfg != null else "pending"
	var bundled: String = _bundled_model_path()
	if consent == "declined":
		_set_template_only()
		return
	# First-run info for builds that already ship the GGUF (Steam / dev fetch).
	if bundled != "" and cfg != null and not cfg.guardian_mind_info_seen:
		state = State.WAITING_CONSENT
		emit_signal("consent_required", false)
		return
	# Bundled model needs no download — info dismissal should stick as accepted.
	if bundled != "" and consent == "pending" and cfg != null and cfg.guardian_mind_info_seen:
		cfg.guardian_mind_consent = "accepted"
		cfg.save_to_disk()
		consent = "accepted"
	if consent == "accepted":
		_begin_load_or_download()
		return
	# Slim build: user:// model on disk but not yet accepted.
	if FileAccess.file_exists(_model_path()):
		state = State.WAITING_CONSENT
		emit_signal("consent_required", true)
		return
	# Slim build: nothing local yet.
	state = State.WAITING_CONSENT
	emit_signal("consent_required", true)


func _begin_load_or_download() -> void:
	var path: String = _resolve_model_path()
	if path != "":
		schedule_load_if_accepted(2.0)
	elif _bundled_model_path() == "":
		_download_model()
	else:
		schedule_load_if_accepted(2.0)


func _model_file_exists() -> bool:
	return _bundled_model_path() != "" or FileAccess.file_exists(_model_path())


func _resolve_model_path() -> String:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		var custom: String = String(cfg.guardian_custom_gguf_path).strip_edges()
		if custom != "":
			if _is_acceptable_model_path(custom):
				return custom
			push_warning("[GuardianLlm] invalid custom GGUF — clearing setting")
			cfg.guardian_custom_gguf_path = ""
			cfg.save_to_disk()
	var bundled: String = _bundled_model_path()
	if bundled != "":
		return bundled
	var user_path: String = _model_path()
	if FileAccess.file_exists(user_path):
		return user_path
	return ""


func _is_acceptable_model_path(path: String) -> bool:
	if path == "" or not FileAccess.file_exists(path):
		return false
	if not path.to_lower().ends_with(".gguf"):
		return false
	return _verify_model_file(path)


func schedule_load_if_accepted(delay_sec: float = 3.0) -> void:
	if state in [State.LOADING, State.READY, State.BUSY, State.DOWNLOADING]:
		return
	if not _platform_supported() or not _extension_available():
		return
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	if not cfg.guardian_companion_enabled or not cfg.guardian_voice_enabled:
		return
	if str(cfg.guardian_mind_consent) != "accepted":
		return
	var path: String = _resolve_model_path()
	if path == "":
		return
	state = State.LOADING
	emit_signal("status_changed", status_summary())
	_schedule_load_model(path, delay_sec)


func _begin_load_if_needed() -> void:
	schedule_load_if_accepted(0.5)


func _schedule_load_model(path: String, delay_sec: float) -> void:
	# NOTE: callers set state = LOADING *before* scheduling, so LOADING must not
	# be in this guard — it used to be, which silently meant the bundled model
	# never loaded (only the post-download path, entered from DOWNLOADING, did).
	if state in [State.READY, State.BUSY] or _io_thread_busy():
		return
	if path == "":
		return
	_pending_load_path = path
	if _load_timer == null:
		_load_timer = Timer.new()
		_load_timer.one_shot = true
		_load_timer.timeout.connect(_on_load_timer)
		add_child(_load_timer)
	_load_timer.stop()
	_load_timer.wait_time = maxf(delay_sec, 0.1)
	_load_timer.start()


func _on_load_timer() -> void:
	var path: String = _pending_load_path
	_pending_load_path = ""
	if path != "":
		call_deferred("_load_model", path)


func ensure_boot() -> void:
	if _mock:
		return
	if not _platform_supported() or not _extension_available():
		return
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		if not cfg.guardian_companion_enabled:
			state = State.TEMPLATE_ONLY
			return
		if not cfg.guardian_voice_enabled:
			state = State.TEMPLATE_ONLY
			return
	var consent: String = str(cfg.guardian_mind_consent) if cfg != null else "pending"
	if consent == "declined":
		_set_template_only()
		return
	var bundled: String = _bundled_model_path()
	if bundled != "" and cfg != null and not cfg.guardian_mind_info_seen:
		state = State.WAITING_CONSENT
		emit_signal("consent_required", false)
		return
	if bundled != "" and consent == "pending":
		cfg.guardian_mind_consent = "accepted"
		cfg.guardian_mind_info_seen = true
		cfg.save_to_disk()
		consent = "accepted"
	if consent == "accepted":
		_begin_load_or_download()
		return
	if FileAccess.file_exists(_model_path()):
		state = State.WAITING_CONSENT
		emit_signal("consent_required", true)
		return
	state = State.WAITING_CONSENT
	emit_signal("consent_required", true)


func _platform_supported() -> bool:
	return not OS.has_feature("web") and not OS.has_feature("android")


func _voice_budget_allows_inprocess() -> bool:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return true
	if bool(cfg.sentience_voice_off):
		return false
	if bool(cfg.battery_saver):
		return false
	if str(cfg.device_tier) == "low":
		return false
	return true


func suspend_voice(unload_model: bool = true) -> void:
	cancel_all("suspend")
	_load_cancelled = true
	if _load_timer != null:
		_load_timer.stop()
	_pending_load_path = ""
	# A running worker keeps its own wrapper reference, so dropping ours is safe.
	if unload_model and _llama != null:
		_llama = null
	_set_template_only()


func _partial_path() -> String:
	return "%s.part" % _model_path()


func _verify_model_file(path: String) -> bool:
	if path == "" or not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var size: int = f.get_length()
	f.close()
	return size >= MODEL_MIN_BYTES and size <= MODEL_MAX_BYTES * 2


func _verify_model_sha256(path: String) -> bool:
	if MODEL_SHA256 == "":
		return true
	var got: String = _sha256_file(path)
	if got == MODEL_SHA256:
		return true
	push_warning("[GuardianLlm] model SHA256 mismatch (got %s…)" % got.substr(0, 12))
	return false


func _sha256_file(path: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	while f.get_position() < f.get_length():
		ctx.update(f.get_buffer(65536))
	f.close()
	return ctx.finish().hex_encode()


func _reject_model_path(path: String, reason: String) -> void:
	push_warning("[GuardianLlm] %s — %s" % [reason, path])
	var abs_path: String = ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	# Only ever delete files we downloaded ourselves — never a player's custom
	# GGUF or the bundled res:// copy.
	var ours: bool = path.begins_with("user://guardian/") \
			or abs_path == ProjectSettings.globalize_path(_model_path()) \
			or abs_path == ProjectSettings.globalize_path(_partial_path())
	if ours and abs_path != "" and FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)
	var partial: String = _partial_path()
	if FileAccess.file_exists(partial):
		DirAccess.remove_absolute(partial)
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null and String(cfg.guardian_custom_gguf_path).strip_edges() == path:
		cfg.guardian_custom_gguf_path = ""
		cfg.save_to_disk()


func _extension_available() -> bool:
	return ClassDB.class_exists("LlamaModel")


func on_consent_result(accepted: bool) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	cfg.guardian_mind_consent = "accepted" if accepted else "declined"
	cfg.save_to_disk()
	if accepted:
		var bundled: String = _bundled_model_path()
		if bundled != "":
			cfg.guardian_mind_info_seen = true
			cfg.save_to_disk()
			state = State.LOADING
			emit_signal("status_changed", status_summary())
			_schedule_load_model(bundled, 0.5)
		elif FileAccess.file_exists(_model_path()):
			state = State.LOADING
			emit_signal("status_changed", status_summary())
			_schedule_load_model(_model_path(), 0.5)
		else:
			_download_model()
	else:
		_set_template_only()


func on_bundled_info_dismissed() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.guardian_mind_info_seen = true
		cfg.guardian_mind_consent = "accepted"
		cfg.save_to_disk()
	var bundled: String = _bundled_model_path()
	if bundled != "":
		state = State.LOADING
		emit_signal("status_changed", status_summary())
		_schedule_load_model(bundled, 0.5)
	else:
		ensure_boot()


func is_ready() -> bool:
	return state == State.READY or state == State.BUSY


func status_summary() -> String:
	match state:
		State.UNAVAILABLE:
			if _resolve_model_path() != "":
				return "Guardian mind not loaded yet"
			return last_error if last_error != "" else "Guardian mind not installed"
		State.WAITING_CONSENT:
			return "Waiting for your choice…"
		State.TEMPLATE_ONLY:
			return "Template voice (enable Guardian mind in Settings)"
		State.DOWNLOADING:
			return "Downloading Guardian mind… %.0f%%" % (download_progress * 100.0)
		State.LOADING:
			return "Loading Guardian mind…"
		State.READY, State.BUSY:
			return "Guardian mind ready (on-device)"
		State.ERROR:
			return "Guardian mind error: %s" % last_error
		_:
			return ""


func queue_generate(cache_key: String, prompt: String, fallback: String,
		context: Dictionary = {}, num_predict: int = -1) -> void:
	# Never load the GGUF from here — first guardian line during sim startup
	# used to trigger an in-process load and hard-crash Godot. Template
	# fallback is returned synchronously by AIDirector until load finishes.
	if not is_ready():
		return
	var kind: String = GuardianGrounding.kind_for(cache_key, context)
	var model_prompt: String = grounded_prompt(kind, context, fallback, prompt)
	var situation: String = str(context.get("situation", ""))
	var stream: bool = situation.begins_with("keeper_") or situation == "away_recap"
	var n_pred: int = num_predict if num_predict > 0 \
			else MindNarrator.num_predict_for_situation(situation)
	if cache_key.begins_with("cog|"):
		n_pred = mini(n_pred, MindNarrator.NUM_PREDICT_FISH_THOUGHT)
	# Same key already waiting → keep the newer context, drop the older job.
	for i in range(_queue.size() - 1, -1, -1):
		if str((_queue[i] as Dictionary).get("key", "")) == cache_key and cache_key != "":
			_queue.remove_at(i)
	_queue.append({
		"key": cache_key,
		"kind": kind,
		"prompt": model_prompt,
		"fallback": fallback,
		"context": context.duplicate(true),
		"stream": stream,
		"num_predict": n_pred,
		"seq": _queue_seq,
	})
	_queue_seq += 1
	while _queue.size() > QUEUE_MAX:
		_queue.pop_front()
	if state == State.READY:
		_pump_queue()


# The tiny model gets a compact grounded prompt built from the context rather
# than the caller's JSON-dump prompt (which overflowed n_ctx). Falls back to the
# caller's prompt, trimmed, when the context carries nothing to ground on.
static func grounded_prompt(kind: String, context: Dictionary, fallback: String,
		caller_prompt: String) -> String:
	var has_subject: bool = str(context.get("fish_name", "")) != "" \
			or str(context.get("species", "")) != ""
	if has_subject:
		return GuardianGrounding.build_prompt(kind, context, fallback)
	if caller_prompt.length() > MAX_PROMPT_CHARS:
		return caller_prompt.substr(0, MAX_PROMPT_CHARS)
	return caller_prompt


func _sync_ai_tier() -> void:
	var director := get_node_or_null("/root/AIDirector")
	if director != null and director.has_method("_update_active_llm_tier"):
		director._update_active_llm_tier()


func _set_template_only() -> void:
	state = State.TEMPLATE_ONLY
	last_error = ""
	emit_signal("status_changed", status_summary())
	_sync_ai_tier()


func _bundled_model_path() -> String:
	var res_path: String = "res://assets/guardian/%s" % MODEL_FILENAME
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	if abs_path != "" and FileAccess.file_exists(abs_path):
		return abs_path
	return ""


func _model_path() -> String:
	return "user://guardian/%s" % MODEL_FILENAME


func _download_model() -> void:
	state = State.DOWNLOADING
	download_progress = 0.0
	_download_fail_reason = ""
	emit_signal("status_changed", status_summary())
	DirAccess.make_dir_recursive_absolute("user://guardian")
	if _http != null and is_instance_valid(_http):
		_http.queue_free()
	_http = HTTPRequest.new()
	_http.name = "GuardianModelDownload"
	_http.timeout = 0.0
	_http.use_threads = true
	var partial: String = _partial_path()
	var resume_from: int = 0
	if FileAccess.file_exists(partial):
		var pf := FileAccess.open(partial, FileAccess.READ)
		if pf != null:
			resume_from = int(pf.get_length())
			pf.close()
	_http.download_file = partial
	_http.request_completed.connect(_on_download_completed)
	add_child(_http)
	var headers: PackedStringArray = PackedStringArray()
	if resume_from > 0:
		headers.append("Range: bytes=%d-" % resume_from)
		emit_signal("download_progress_changed", download_progress,
				"Resuming download at %.0f MB…" % (float(resume_from) / 1_000_000.0))
	var err: int = _http.request(MODEL_URL, headers)
	if err != OK:
		state = State.ERROR
		_download_fail_reason = "Could not start download (error %d)" % err
		last_error = _download_fail_reason
		emit_signal("status_changed", status_summary())
		return
	set_process(true)


func _process(_dt: float) -> void:
	if state == State.DOWNLOADING and _http != null and is_instance_valid(_http):
		var received: int = _http.get_downloaded_bytes()
		var total: int = _http.get_body_size()
		var next: float = download_progress
		if total > 0:
			next = clampf(float(received) / float(total), 0.0, 1.0)
		elif received > 0:
			next = clampf(float(received) / float(MODEL_BYTES_APPROX), 0.0, 0.99)
		if absf(next - download_progress) >= 0.01:
			download_progress = next
			emit_signal("status_changed", status_summary())
			emit_signal("download_progress_changed", download_progress, status_summary())
		return
	if _native_busy:
		_process_watchdog()
	if state in [State.READY, State.BUSY]:
		if _mock:
			return
		_mem_check_timer += _dt
		if _mem_check_timer >= 4.0:
			_mem_check_timer = 0.0
			_check_memory_pressure()
		return
	set_process(false)


func _check_memory_pressure() -> void:
	var used: int = int(OS.get_static_memory_usage())
	if used > 2_600_000_000:
		push_warning("[GuardianLlm] high memory (%.0f MB) — dropping in-process tier" % (float(used) / 1_000_000.0))
		cancel_thought_generation("keeper_")
		suspend_voice(true)
	elif used > 2_200_000_000:
		cancel_thought_generation("keeper_reply")


func _on_download_completed(result: int, code: int, _h: PackedStringArray, _body: PackedByteArray) -> void:
	set_process(false)
	if _http != null and is_instance_valid(_http):
		_http.queue_free()
		_http = null
	var partial: String = _partial_path()
	var ok_code: bool = code == 200 or code == 206
	if result != HTTPRequest.RESULT_SUCCESS or not ok_code:
		_download_fail_reason = "Download failed (HTTP %d). Check your connection and retry in Settings." % code
		if FileAccess.file_exists(partial):
			# Keep partial for resume — do not delete.
			pass
		state = State.TEMPLATE_ONLY
		last_error = ""
		emit_signal("status_changed", _download_fail_reason)
		emit_signal("download_progress_changed", 0.0, _download_fail_reason)
		return
	if not _verify_model_file(partial):
		_download_fail_reason = "Download incomplete or corrupted — retry in Settings (resume supported)."
		state = State.TEMPLATE_ONLY
		last_error = ""
		emit_signal("status_changed", _download_fail_reason)
		emit_signal("download_progress_changed", 0.0, _download_fail_reason)
		return
	# Hashing 250MB takes ~1 s — verify on a worker thread (SYSTEMIC #15).
	if _io_thread_busy():
		return
	emit_signal("download_progress_changed", 1.0, "Verifying download…")
	_io_thread = Thread.new()
	_io_thread.start(_thread_verify_download.bind(partial))


# WORKER THREAD.
func _thread_verify_download(partial: String) -> void:
	var ok: bool = _verify_model_sha256(partial)
	call_deferred("_on_download_verified", partial, ok)


func _on_download_verified(partial: String, ok: bool) -> void:
	_join_io_thread()
	if not ok:
		_download_fail_reason = "Download checksum failed — retry in Settings."
		_reject_model_path(partial, "checksum mismatch")
		state = State.TEMPLATE_ONLY
		last_error = ""
		emit_signal("status_changed", _download_fail_reason)
		emit_signal("download_progress_changed", 0.0, _download_fail_reason)
		return
	if FileAccess.file_exists(_model_path()):
		DirAccess.remove_absolute(_model_path())
	var rename_err: Error = DirAccess.rename_absolute(partial, _model_path())
	if rename_err != OK:
		_download_fail_reason = "Could not finalize model file (error %d)" % rename_err
		state = State.TEMPLATE_ONLY
		emit_signal("status_changed", _download_fail_reason)
		return
	download_progress = 1.0
	emit_signal("download_progress_changed", 1.0, "Download complete — loading mind…")
	_schedule_load_model(_model_path(), 0.5)


func _load_model(path: String) -> void:
	if not _voice_budget_allows_inprocess():
		state = State.TEMPLATE_ONLY
		var why: String = "Template voice (battery saver — enable model when plugged in)"
		emit_signal("status_changed", why)
		_sync_ai_tier()
		return
	if _io_thread_busy():
		# A verify/load is already running off-thread — its callback decides.
		return
	if not _verify_model_file(path):
		_reject_model_path(path, "model file size out of range")
		state = State.TEMPLATE_ONLY
		emit_signal("status_changed", "Template voice (model unavailable — re-download in Settings)")
		_sync_ai_tier()
		return
	state = State.LOADING
	emit_signal("status_changed", status_summary())
	var wrapper: GDScript = load("res://addons/godot_llama/godot_llama.gd") as GDScript
	if wrapper == null:
		state = State.ERROR
		last_error = "Guardian engine missing from this build"
		emit_signal("status_changed", status_summary())
		return
	var inst: RefCounted = wrapper.new() as RefCounted
	if inst == null or not inst.is_available():
		state = State.TEMPLATE_ONLY
		last_error = ""
		emit_signal("status_changed", status_summary())
		return
	# SYSTEMIC #15: SHA-256 of a 250MB file, llama_model_load and context
	# creation are each hundreds of ms to seconds — all run on a worker thread.
	# Half the cores (max 4): leave the rest for the render + sim threads so
	# inference contention never starves the main loop.
	var threads: int = clampi(OS.get_processor_count() >> 1, 1, 4)
	_load_cancelled = false
	_io_thread = Thread.new()
	_io_thread.start(_thread_load_model.bind(inst, path, threads))


# WORKER THREAD — touches only the wrapper it was handed, never the tree.
func _thread_load_model(inst: RefCounted, path: String, threads: int) -> void:
	var res: Dictionary = {"ok": false, "path": path, "reason": "", "inst": inst}
	# The pinned hash only describes OUR SmolLM2 file; a player's custom GGUF
	# is size/extension-checked only (it used to fail the hash and be deleted).
	if path.get_file() == MODEL_FILENAME and not _verify_model_sha256(path):
		res["reason"] = "sha"
		call_deferred("_on_model_loaded", res)
		return
	# CPU-only avoids Metal/GPU init crashes during scene transitions on macOS.
	var err: int = inst.load_model(path, {"n_gpu_layers": 0})
	if err != OK:
		res["reason"] = "load"
		call_deferred("_on_model_loaded", res)
		return
	err = inst.create_context({
		"n_ctx": N_CTX,
		"threads": threads,
		"threads_batch": threads,
	})
	if err != OK:
		res["reason"] = "context"
		call_deferred("_on_model_loaded", res)
		return
	res["ok"] = true
	call_deferred("_on_model_loaded", res)


func _on_model_loaded(res: Dictionary) -> void:
	_join_io_thread()
	var path: String = String(res.get("path", ""))
	if _load_cancelled or not _voice_budget_allows_inprocess():
		_load_cancelled = false
		if state == State.LOADING:
			_set_template_only()
		return
	if not bool(res.get("ok", false)):
		var reason: String = String(res.get("reason", ""))
		if reason == "sha":
			_reject_model_path(path, "model checksum mismatch")
			state = State.TEMPLATE_ONLY
			emit_signal("status_changed", "Template voice (model corrupted — re-download in Settings)")
		else:
			state = State.TEMPLATE_ONLY
			last_error = ""
			emit_signal("status_changed", "Template voice (model unavailable — re-download in Settings)")
			emit_signal("ready_changed", false)
		_sync_ai_tier()
		return
	_llama = res.get("inst") as RefCounted
	_connect_native_signals()
	state = State.READY
	last_error = ""
	emit_signal("ready_changed", true)
	emit_signal("status_changed", status_summary())
	_sync_ai_tier()
	set_process(true)
	if _queue.is_empty():
		_start_job({"key": "", "prompt": "Reply with one word: ready", "fallback": "",
				"context": {}, "stream": false, "num_predict": MindNarrator.NUM_PREDICT_WARMUP,
				"_warmup": true})
	else:
		_pump_queue()


# Native signals fire on the generation thread. Every connection is DEFERRED so
# the handlers run on the main thread, in emission order, via the message queue.
func _connect_native_signals() -> void:
	if _llama == null or _llama.context == null:
		return
	var ctx: Object = _llama.context
	var pairs: Array = [
		["token_generated", Callable(self, "_on_generation_partial")],
		["generation_finished", Callable(self, "_on_native_finished")],
		["generation_error", Callable(self, "_on_native_error")],
	]
	for pair in pairs:
		var sig: String = String(pair[0])
		var cb: Callable = pair[1]
		if ctx.has_signal(sig) and not ctx.is_connected(sig, cb):
			ctx.connect(sig, cb, CONNECT_DEFERRED)


# ---- Mock mode (META #77) -----------------------------------------------------

func enable_mock(on: bool = true) -> void:
	_mock = on
	if on:
		GuardianLlmMock.forced = true
		state = State.READY
		last_error = ""
		set_process(true)
		emit_signal("ready_changed", true)
		emit_signal("status_changed", status_summary())
	else:
		GuardianLlmMock.forced = false
		cancel_all("mock_off")
		state = State.TEMPLATE_ONLY
		emit_signal("ready_changed", false)
	_sync_ai_tier()


func is_mock() -> bool:
	return _mock


# ---- Job pump -----------------------------------------------------------------

func _pump_queue() -> void:
	if state != State.READY or _native_busy or _queue.is_empty():
		return
	if _llama == null and not _mock:
		return
	var job: Dictionary = _queue.pop_front()
	_start_job(job)


func _start_job(job: Dictionary) -> void:
	_job_seq += 1
	var jid: int = _job_seq
	job["_jid"] = jid
	job["streamed"] = false
	job["stream_blocked"] = false
	_current_job = job
	_active_job_id = jid
	_running_job_id = jid
	_native_busy = true
	_native_text = ""
	_native_error = ""
	_partial_text = ""
	_job_started_ms = Time.get_ticks_msec()
	state = State.BUSY
	set_process(true)
	var key: String = str(job.get("key", ""))
	var n_pred: int = int(job.get("num_predict", MindNarrator.NUM_PREDICT_GUARDIAN))
	var params: Dictionary = GuardianGrounding.generation_params(key, n_pred)
	if bool(job.get("_warmup", false)):
		params = {"temperature": 0.05, "seed": 1, "max_tokens": n_pred}
	var prompt: String = str(job.get("prompt", ""))
	if _mock:
		_mock_generate(jid, prompt, key, str(job.get("kind", GuardianGrounding.KIND_GUARDIAN)),
				bool(job.get("stream", false)))
		return
	_join_gen_thread()
	_gen_thread = Thread.new()
	var stream: bool = bool(job.get("stream", false))
	_gen_thread.start(_thread_generate.bind(jid, _llama, prompt, n_pred, params, stream))


# WORKER THREAD. llama.cpp's generate/generate_stream are SYNCHRONOUS (the
# old "non-blocking" comment was wrong — see godot_llama src/llama_context.cpp
# _generate_internal): tokenize + prompt decode + every sampled token ran on
# the main thread. Here they run on a dedicated thread; the native signals
# reach us deferred, and the final hand-off is a deferred call.
func _thread_generate(jid: int, llama: RefCounted, prompt: String, n_pred: int,
		params: Dictionary, stream: bool) -> void:
	if llama != null and llama.get("context") != null:
		var ctx: Object = llama.context
		ctx.reset()
		ctx.set_prompt(prompt)
		if stream:
			ctx.generate_stream(n_pred, params)
		else:
			ctx.generate(n_pred, params)
	call_deferred("_on_worker_done", jid)


func _mock_generate(jid: int, prompt: String, key: String, kind: String, stream: bool) -> void:
	var text: String = GuardianLlmMock.respond(prompt, key, kind)
	if text == GuardianLlmMock.HANG_TOKEN:
		return  # never completes — the watchdog (or a cancel) must resolve it
	if stream:
		for w in text.split(" ", false):
			call_deferred("_on_generation_partial", w + " ", 0)
	call_deferred("_on_native_finished", text)
	call_deferred("_on_worker_done", jid)


func _on_native_finished(full_text: String) -> void:
	_native_text = full_text


func _on_native_error(message: String) -> void:
	_native_error = message
	push_warning("[GuardianLlm] generation error: %s" % message)


func _on_worker_done(jid: int) -> void:
	if jid != _running_job_id:
		return
	_join_gen_thread()
	_native_busy = false
	_running_job_id = -1
	var stale: bool = jid != _active_job_id
	if stale:
		# Cancelled or timed out — the job was already resolved with its fallback.
		if state == State.BUSY:
			state = State.READY
		_pump_queue()
		return
	_active_job_id = -1
	if _native_text == "" and _native_error != "":
		var retries: int = int(_current_job.get("_error_retries", 0))
		if retries < 1 and not bool(_current_job.get("_warmup", false)):
			var again: Dictionary = _current_job.duplicate(true)
			again["_error_retries"] = retries + 1
			_queue.push_front(again)
			_current_job = {}
			state = State.READY
			_pump_queue()
			return
	_on_generation_finished(_native_text)


func _process_watchdog() -> void:
	if not _native_busy:
		return
	var age: int = Time.get_ticks_msec() - _job_started_ms
	if _active_job_id != -1 and age > gen_timeout_ms:
		push_warning("[GuardianLlm] generation exceeded %d ms — template fallback" % gen_timeout_ms)
		_native_cancel()
		_resolve_current_with_fallback("timeout")
	elif _active_job_id == -1 and age > gen_timeout_ms + GEN_HARD_GRACE_MS:
		# The native loop ignored cancel (a single stuck decode). Stop routing
		# voice through it; the thread keeps its own wrapper reference.
		push_warning("[GuardianLlm] native generation unresponsive — dropping to template voice")
		_native_busy = false
		_running_job_id = -1
		if _gen_thread != null:
			_zombie_threads.append(_gen_thread)  # never joined: it would block the main thread
		_gen_thread = null
		_llama = null
		_set_template_only()


func _native_cancel() -> void:
	if _mock:
		# A hung mock job completes as soon as it is cancelled, like the native
		# loop does at its next token.
		if _native_busy and _running_job_id != -1:
			call_deferred("_on_worker_done", _running_job_id)
		return
	if _llama != null and _llama.get("context") != null and _llama.context.has_method("cancel"):
		_llama.context.cancel()


# Resolve the in-flight job with its template line (already on screen), then
# let the thread wind down; its result is discarded as stale.
func _resolve_current_with_fallback(reason: String) -> void:
	var job: Dictionary = _current_job
	_current_job = {}
	_active_job_id = -1
	if job.is_empty() or bool(job.get("_warmup", false)):
		return
	MindNarrator.gen_attempts += 1
	MindNarrator.fallback_uses += 1
	MindNarrator.last_reject_reason = reason
	var key: String = str(job.get("key", ""))
	var fb: String = str(job.get("fallback", ""))
	if bool(job.get("streamed", false)):
		_retract_stream(key, fb)
	if key.begins_with("cog|"):
		MindScheduler.on_model_result(key.substr(4), fb, job.get("context", {}))


func _on_generation_partial(token: String, _token_id: int = 0) -> void:
	if _current_job.is_empty() or not bool(_current_job.get("stream", false)):
		return
	if bool(_current_job.get("stream_blocked", false)):
		return
	_partial_text += str(token)
	var key: String = str(_current_job.get("key", ""))
	if key == "":
		return
	var kind: String = str(_current_job.get("kind", GuardianGrounding.KIND_GUARDIAN))
	var ctx: Dictionary = _current_job.get("context", {})
	var shown: String = GuardianGrounding.repair(ctx, _partial_text)
	if not GuardianGrounding.partial_ok(kind, ctx, _partial_text):
		# The final line will be rejected anyway: stop streaming, restore the
		# template on screen, and stop spending CPU on it.
		_current_job["stream_blocked"] = true
		if bool(_current_job.get("streamed", false)):
			_retract_stream(key, str(_current_job.get("fallback", "")))
		_current_job["streamed"] = false
		_native_cancel()
		return
	if shown == "":
		return
	_current_job["streamed"] = true
	emit_signal("generation_partial", key, shown)
	_emit_stream(key, shown)


func _emit_stream(key: String, text: String) -> void:
	var ai := get_node_or_null("/root/AIDirector")
	if ai == null:
		return
	if key.begins_with("thought|") and ai.has_method("notify_thought_streaming"):
		ai.call("notify_thought_streaming", key, text)
	elif not key.begins_with("thought|") and not key.begins_with("cog|") \
			and ai.has_method("notify_guardian_line_streaming"):
		ai.call("notify_guardian_line_streaming", key, text)


# A partial that was streamed to the UI and then rejected must not linger:
# re-stream the template line over it.
func _retract_stream(key: String, fallback: String) -> void:
	if key == "" or fallback.strip_edges() == "":
		return
	retractions += 1
	emit_signal("generation_partial", key, fallback)
	_emit_stream(key, fallback)


func _on_generation_finished(full_text: String) -> void:
	var job: Dictionary = _current_job
	_current_job = {}
	state = State.READY
	if job.is_empty() or bool(job.get("_warmup", false)):
		_pump_queue()
		return
	var fb: String = str(job.get("fallback", ""))
	var ctx: Dictionary = job.get("context", {})
	var key: String = str(job.get("key", ""))
	var kind: String = str(job.get("kind", GuardianGrounding.kind_for(key, ctx)))
	var fin: Dictionary = GuardianGrounding.finalize(kind, ctx, full_text, fb)
	var line: String = String(fin.get("line", fb))
	last_result = {"key": key, "raw": full_text, "line": line,
			"source": str(fin.get("source", "")), "reason": str(fin.get("reason", ""))}
	result_log.append(last_result)
	while result_log.size() > 8:
		result_log.pop_front()
	var spoken_seq: int = int(job.get("seq", -1))
	if spoken_seq >= 0:
		_last_spoken_seq = spoken_seq
	if line == fb and bool(job.get("streamed", false)):
		_retract_stream(key, fb)
	if key.begins_with("cog|"):
		MindScheduler.on_model_result(key.substr(4), line, ctx)
		_pump_queue()
		return
	var ai := get_node_or_null("/root/AIDirector")
	if ai != null and line != fb and key != "":
		if key.begins_with("thought|") and ai.has_method("_cache_thought"):
			var fid: String = String(ctx.get("fish_id", ""))
			ai.call("_cache_thought", key, line, fid)
		elif ai.has_method("_cache_guardian_line"):
			ai._cache_guardian_line(key, line)
			ai.emit_signal("guardian_line_ready", key, line, "mock" if _mock else "inprocess")
	_pump_queue()


func cancel_thought_generation(cache_key: String) -> void:
	var keep: Array = []
	for job in _queue:
		var k: String = str(job.get("key", ""))
		if k.contains(cache_key):
			continue
		keep.append(job)
	_queue = keep
	if not _current_job.is_empty() and str(_current_job.get("key", "")).contains(cache_key):
		_current_job = {}
		_active_job_id = -1
		_native_cancel()
		# State stays BUSY until the thread winds down (_on_worker_done).


# Drop everything queued and abandon the in-flight job (scene change, quit,
# voice turned off). Never blocks: the worker finishes at its next token.
func cancel_all(_reason: String = "") -> void:
	_queue.clear()
	if not _current_job.is_empty():
		_current_job = {}
		_active_job_id = -1
		_native_cancel()
	_partial_text = ""


func _on_scene_changed() -> void:
	cancel_all("scene_changed")


func _io_thread_busy() -> bool:
	return _io_thread != null and _io_thread.is_started()


func _join_io_thread() -> void:
	if _io_thread != null and _io_thread.is_started():
		_io_thread.wait_to_finish()
	_io_thread = null


func _join_gen_thread() -> void:
	if _gen_thread != null and _gen_thread.is_started():
		_gen_thread.wait_to_finish()
	_gen_thread = null


func _exit_tree() -> void:
	_shutdown_threads()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_shutdown_threads()


# Quit path only: cancel, then join so no native thread outlives the engine.
# Worst case this waits for one token (generation) or the rest of a model
# load — acceptable at exit, never during play.
func _shutdown_threads() -> void:
	cancel_all("shutdown")
	_load_cancelled = true
	if _gen_thread != null and _gen_thread.is_started():
		_native_cancel()
		_gen_thread.wait_to_finish()
	_gen_thread = null
	if _io_thread != null and _io_thread.is_started():
		_io_thread.wait_to_finish()
	_io_thread = null
	_native_busy = false


static func _sanitize_output(text: String) -> String:
	var s: String = text.strip_edges()
	for tag in ["<|im_end|>", "<|endoftext|>", "<|im_start|>", "\n"]:
		if tag == "\n":
			if "\n" in s:
				s = s.split("\n", false)[0].strip_edges()
		else:
			s = s.replace(tag, "")
	s = s.strip_edges()
	if s.length() > 220:
		s = s.substr(0, 220).strip_edges()
	var spam := RegEx.new()
	if spam.compile("(.)\\1{10,}") == OK and spam.search(s) != null:
		return ""
	var prof := RegEx.new()
	if prof.compile("(?i)\\b(fuck|shit)\\b") == OK and prof.search(s) != null:
		return ""
	return s


static func _seed_from_key(key: String) -> int:
	var h: int = 0
	for i in key.length():
		h = (h * 31 + key.unicode_at(i)) & 0x7fffffff
	return h if h > 0 else 1
