extends Node

const MindNarrator = preload("res://scripts/mind_narrator.gd")
const MindScheduler = preload("res://scripts/mind_scheduler.gd")

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


func _ready() -> void:
	set_process(false)
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
	if state in [State.LOADING, State.READY, State.BUSY]:
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
	_queue.clear()
	_current_job = {}
	_partial_text = ""
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
	if abs_path != "" and FileAccess.file_exists(abs_path):
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
	var situation: String = str(context.get("situation", ""))
	var stream: bool = situation.begins_with("keeper_") or situation == "away_recap"
	var n_pred: int = num_predict if num_predict > 0 \
			else MindNarrator.num_predict_for_situation(situation)
	if cache_key.begins_with("cog|"):
		n_pred = mini(n_pred, MindNarrator.NUM_PREDICT_FISH_THOUGHT)
	_queue.append({
		"key": cache_key,
		"prompt": prompt,
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
	if state in [State.READY, State.BUSY]:
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
	if not _verify_model_sha256(partial):
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
	if not _verify_model_file(path):
		_reject_model_path(path, "model file size out of range")
		state = State.TEMPLATE_ONLY
		emit_signal("status_changed", "Template voice (model unavailable — re-download in Settings)")
		_sync_ai_tier()
		return
	if not _verify_model_sha256(path):
		_reject_model_path(path, "model checksum mismatch")
		state = State.TEMPLATE_ONLY
		emit_signal("status_changed", "Template voice (model corrupted — re-download in Settings)")
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
	if inst == null:
		state = State.TEMPLATE_ONLY
		last_error = ""
		emit_signal("status_changed", status_summary())
		return
	_llama = inst
	if not _llama.is_available():
		state = State.TEMPLATE_ONLY
		last_error = ""
		emit_signal("status_changed", status_summary())
		return
	# CPU-only avoids Metal/GPU init crashes during scene transitions on macOS.
	var err: int = _llama.load_model(path, {"n_gpu_layers": 0})
	if err != OK:
		state = State.TEMPLATE_ONLY
		last_error = ""
		emit_signal("status_changed", "Template voice (model unavailable — re-download in Settings)")
		emit_signal("ready_changed", false)
		_sync_ai_tier()
		return
	var threads: int = maxi(1, mini(4, OS.get_processor_count() - 1))
	err = _llama.create_context({
		"n_ctx": 1024,
		"threads": threads,
		"threads_batch": threads,
	})
	if err != OK:
		state = State.TEMPLATE_ONLY
		last_error = ""
		emit_signal("status_changed", "Template voice (model unavailable — re-download in Settings)")
		emit_signal("ready_changed", false)
		_sync_ai_tier()
		return
	_llama.context.generation_finished.connect(_on_generation_finished)
	_llama.context.generation_error.connect(_on_generation_error)
	_connect_partial_stream()
	state = State.READY
	last_error = ""
	emit_signal("ready_changed", true)
	emit_signal("status_changed", status_summary())
	_sync_ai_tier()
	set_process(true)
	call_deferred("_warmup_model")
	_pump_queue()


func _warmup_model() -> void:
	if state != State.READY or _llama == null or not _queue.is_empty():
		return
	_current_job = {"key": "", "fallback": "", "context": {}, "stream": false,
			"num_predict": MindNarrator.NUM_PREDICT_WARMUP}
	state = State.BUSY
	_partial_text = ""
	_llama.context.reset()
	_llama.context.set_prompt("Reply with one word: ready")
	# generate_stream is non-blocking (#19) — native inference runs off the main thread.
	_llama.context.generate_stream(MindNarrator.NUM_PREDICT_WARMUP,
			{"temperature": 0.05, "seed": 1})
	# generation_finished returns to READY and pumps queue.


func _connect_partial_stream() -> void:
	if _llama == null or _llama.context == null:
		return
	for sig_name in ["generation_token", "generation_update", "token_generated"]:
		if _llama.context.has_signal(sig_name):
			var cb := Callable(self, "_on_generation_partial")
			if not _llama.context.is_connected(sig_name, cb):
				_llama.context.connect(sig_name, cb)


func _on_generation_partial(token: String) -> void:
	if not bool(_current_job.get("stream", false)):
		return
	_partial_text += str(token)
	var key: String = str(_current_job.get("key", ""))
	if key != "":
		emit_signal("generation_partial", key, _partial_text.strip_edges())
		var ai := get_node_or_null("/root/AIDirector")
		if ai != null:
			if key.begins_with("thought|") and ai.has_method("notify_thought_streaming"):
				ai.call("notify_thought_streaming", key, _partial_text.strip_edges())
			elif ai.has_method("notify_guardian_line_streaming"):
				ai.call("notify_guardian_line_streaming", key, _partial_text.strip_edges())


func _pump_queue() -> void:
	if _llama == null or state != State.READY or _queue.is_empty():
		return
	state = State.BUSY
	_current_job = _queue[0]
	_partial_text = ""
	_llama.context.reset()
	_llama.context.set_prompt(str(_current_job.get("prompt", "")))
	var rng_seed: int = _seed_from_key(str(_current_job.get("key", "")))
	var params: Dictionary = {
		"temperature": 0.35,
		"top_p": 0.9,
		"repeat_penalty": 1.12,
		"seed": rng_seed,
	}
	var n_pred: int = int(_current_job.get("num_predict", MindNarrator.NUM_PREDICT_GUARDIAN))
	_llama.context.generate_stream(n_pred, params)


func _on_generation_finished(full_text: String) -> void:
	var fb: String = str(_current_job.get("fallback", ""))
	var ctx: Dictionary = _current_job.get("context", {})
	var key: String = str(_current_job.get("key", ""))
	var max_w: int = MindNarrator.GUARDIAN_MAX_WORDS
	var fin: Dictionary
	if key.begins_with("thought|"):
		var sit: String = str(ctx.get("situation", ""))
		max_w = MindNarrator.FISH_REPLY_MAX_WORDS if sit == "keeper_reply" \
				else MindNarrator.FISH_THOUGHT_MAX_WORDS
		if sit == "keeper_reply":
			fin = MindNarrator.finalize_reply_line(ctx, full_text, fb, max_w)
		else:
			fin = MindNarrator.finalize_line(ctx, full_text, fb, max_w)
	else:
		fin = MindNarrator.finalize_line(ctx, full_text, fb, max_w)
	var line: String = String(fin.get("line", fb))
	var spoken_seq: int = int(_current_job.get("seq", -1))
	if spoken_seq >= 0:
		_last_spoken_seq = spoken_seq
	if not _queue.is_empty():
		_queue.pop_front()
	state = State.READY
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
			ai.emit_signal("guardian_line_ready", key, line, "inprocess")
	_pump_queue()


func cancel_thought_generation(cache_key: String) -> void:
	var keep: Array = []
	for job in _queue:
		var k: String = str(job.get("key", ""))
		if k.contains(cache_key):
			continue
		keep.append(job)
	_queue = keep
	if str(_current_job.get("key", "")).contains(cache_key):
		_current_job = {}
		if _llama != null and _llama.context != null \
				and _llama.context.has_method("stop_generation"):
			_llama.context.stop_generation()
		state = State.READY


func _on_generation_error(message: String) -> void:
	push_warning("[GuardianLlm] generation error: %s" % message)
	if _current_job.is_empty() and _queue.is_empty():
		state = State.READY
		return
	var retries: int = int(_current_job.get("_error_retries", 0))
	if retries < 1 and not _current_job.is_empty():
		_current_job["_error_retries"] = retries + 1
		state = State.READY
		_pump_queue()
		return
	var fb: String = str(_current_job.get("fallback", ""))
	if fb != "":
		_on_generation_finished(fb)
		return
	if not _queue.is_empty():
		_queue.pop_front()
	_current_job = {}
	state = State.READY
	_pump_queue()


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
