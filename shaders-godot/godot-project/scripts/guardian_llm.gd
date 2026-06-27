extends Node

# In-process Guardian LLM via godot_llama (llama.cpp GDExtension).
# Steam/desktop builds bundle the GGUF under res://assets/guardian/ (CI fetch).
# Dev/slim builds ask once, then download to user://guardian/ after consent.

signal status_changed(message: String)
signal ready_changed(is_ready: bool)
signal consent_required(needs_download: bool)

const MODEL_URL: String = (
	"https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/"
	+ "SmolLM2-360M-Instruct-Q4_K_M.gguf")
const MODEL_FILENAME: String = "SmolLM2-360M-Instruct-Q4_K_M.gguf"
const MODEL_BYTES_APPROX: int = 250_000_000

enum State { UNAVAILABLE, WAITING_CONSENT, DOWNLOADING, LOADING, READY, BUSY, TEMPLATE_ONLY, ERROR }
var state: int = State.UNAVAILABLE
var last_error: String = ""
var download_progress: float = 0.0

var _llama: RefCounted = null
var _queue: Array = []
var _current_job: Dictionary = {}
var _http: HTTPRequest = null
var _boot_pending: bool = false


func _ready() -> void:
	set_process(false)
	if not _platform_supported():
		state = State.TEMPLATE_ONLY
		return
	if not _extension_available():
		state = State.TEMPLATE_ONLY
		last_error = ""
		return
	call_deferred("ensure_boot")


func _platform_supported() -> bool:
	return not OS.has_feature("web") and not OS.has_feature("android")


func _extension_available() -> bool:
	return ClassDB.class_exists("LlamaModel")


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
	_boot_pending = false
	var bundled: String = _bundled_model_path()
	if bundled != "":
		if cfg != null and not cfg.guardian_mind_info_seen:
			state = State.WAITING_CONSENT
			emit_signal("consent_required", false)
			return
		_load_model(bundled)
		return
	var user_path: String = _model_path()
	if FileAccess.file_exists(user_path):
		_load_model(user_path)
		return
	var consent: String = cfg.guardian_mind_consent if cfg != null else "pending"
	match consent:
		"accepted":
			_download_model()
		"declined":
			_set_template_only()
		_:
			state = State.WAITING_CONSENT
			emit_signal("consent_required", true)


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
			_load_model(bundled)
		elif FileAccess.file_exists(_model_path()):
			_load_model(_model_path())
		else:
			_download_model()
	else:
		_set_template_only()


func on_bundled_info_dismissed() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.guardian_mind_info_seen = true
		cfg.save_to_disk()
	var bundled: String = _bundled_model_path()
	if bundled != "":
		_load_model(bundled)
	else:
		ensure_boot()


func is_ready() -> bool:
	return state == State.READY or state == State.BUSY


func status_summary() -> String:
	match state:
		State.UNAVAILABLE:
			return last_error if last_error != "" else "Guardian voice unavailable"
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


func queue_generate(cache_key: String, prompt: String, fallback: String) -> void:
	if not is_ready():
		if state in [State.UNAVAILABLE, State.ERROR, State.TEMPLATE_ONLY, State.WAITING_CONSENT]:
			if not _boot_pending:
				_boot_pending = true
				call_deferred("ensure_boot")
		return
	_queue.append({
		"key": cache_key,
		"prompt": prompt,
		"fallback": fallback,
	})
	if state == State.READY:
		_pump_queue()


func _set_template_only() -> void:
	state = State.TEMPLATE_ONLY
	last_error = ""
	emit_signal("status_changed", status_summary())
	var ai := get_node_or_null("/root/AIDirector")
	if ai != null and ai.has_method("_update_active_llm_tier"):
		ai._update_active_llm_tier()


func _bundled_model_path() -> String:
	var res_path: String = "res://assets/guardian/%s" % MODEL_FILENAME
	if not ResourceLoader.exists(res_path):
		return ""
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	if abs_path != "" and FileAccess.file_exists(abs_path):
		return abs_path
	return ""


func _model_path() -> String:
	return "user://guardian/%s" % MODEL_FILENAME


func _download_model() -> void:
	state = State.DOWNLOADING
	download_progress = 0.0
	emit_signal("status_changed", status_summary())
	DirAccess.make_dir_recursive_absolute("user://guardian")
	if _http != null and is_instance_valid(_http):
		_http.queue_free()
	_http = HTTPRequest.new()
	_http.name = "GuardianModelDownload"
	_http.timeout = 0.0
	_http.use_threads = true
	_http.download_file = _model_path()
	_http.request_completed.connect(_on_download_completed)
	add_child(_http)
	var err: int = _http.request(MODEL_URL)
	if err != OK:
		state = State.ERROR
		last_error = "Could not start model download (error %d)" % err
		emit_signal("status_changed", status_summary())
		return
	set_process(true)


func _process(_dt: float) -> void:
	if state != State.DOWNLOADING or _http == null or not is_instance_valid(_http):
		set_process(false)
		return
	# HTTPRequest has no download_progress signal — poll byte counters instead.
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


func _on_download_completed(result: int, code: int, _h: PackedStringArray, _body: PackedByteArray) -> void:
	set_process(false)
	if _http != null and is_instance_valid(_http):
		_http.queue_free()
		_http = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		state = State.ERROR
		last_error = "Model download failed (HTTP %d)" % code
		emit_signal("status_changed", status_summary())
		return
	download_progress = 1.0
	_load_model(_model_path())


func _load_model(path: String) -> void:
	state = State.LOADING
	emit_signal("status_changed", status_summary())
	var wrapper: GDScript = load("res://addons/godot_llama/godot_llama.gd") as GDScript
	if wrapper == null:
		state = State.ERROR
		last_error = "Guardian engine missing from this build"
		emit_signal("status_changed", status_summary())
		return
	_llama = wrapper.new()
	if not _llama.is_available():
		state = State.TEMPLATE_ONLY
		last_error = ""
		emit_signal("status_changed", status_summary())
		return
	var err: int = _llama.load_model(path)
	if err != OK:
		state = State.ERROR
		last_error = "Model load failed: %s" % error_string(err)
		emit_signal("status_changed", status_summary())
		return
	var threads: int = maxi(1, OS.get_processor_count() - 1)
	err = _llama.create_context({
		"n_ctx": 2048,
		"threads": threads,
		"threads_batch": threads,
	})
	if err != OK:
		state = State.ERROR
		last_error = "Context create failed: %s" % error_string(err)
		emit_signal("status_changed", status_summary())
		return
	_llama.context.generation_finished.connect(_on_generation_finished)
	_llama.context.generation_error.connect(_on_generation_error)
	state = State.READY
	last_error = ""
	emit_signal("ready_changed", true)
	emit_signal("status_changed", status_summary())
	var ai := get_node_or_null("/root/AIDirector")
	if ai != null and ai.has_method("_update_active_llm_tier"):
		ai._update_active_llm_tier()
	_pump_queue()


func _pump_queue() -> void:
	if _llama == null or state != State.READY or _queue.is_empty():
		return
	state = State.BUSY
	_current_job = _queue[0]
	_llama.context.reset()
	_llama.context.set_prompt(str(_current_job.get("prompt", "")))
	var rng_seed: int = _seed_from_key(str(_current_job.get("key", "")))
	var params: Dictionary = {
		"temperature": 0.35,
		"top_p": 0.9,
		"repeat_penalty": 1.12,
		"seed": rng_seed,
	}
	_llama.context.generate_stream(64, params)


func _on_generation_finished(full_text: String) -> void:
	var fb: String = str(_current_job.get("fallback", ""))
	var line: String = _sanitize_output(full_text)
	if line == "":
		line = fb
	var key: String = str(_current_job.get("key", ""))
	if not _queue.is_empty():
		_queue.pop_front()
	state = State.READY
	var ai := get_node_or_null("/root/AIDirector")
	if ai != null and line != fb and key != "":
		if ai.has_method("_cache_guardian_line"):
			ai._cache_guardian_line(key, line)
		ai.emit_signal("guardian_line_ready", key, line, "inprocess")
	_pump_queue()


func _on_generation_error(message: String) -> void:
	push_warning("[GuardianLlm] generation error: %s" % message)
	if not _queue.is_empty():
		_queue.pop_front()
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
	var low: String = s.to_lower()
	for bad in ["fuck", "shit"]:
		if bad in low:
			return ""
	return s


static func _seed_from_key(key: String) -> int:
	var h: int = 0
	for i in key.length():
		h = (h * 31 + key.unicode_at(i)) & 0x7fffffff
	return h if h > 0 else 1
