extends Node

# Preloaded so we don't depend on the global class_name registry — that
# registry is populated by the editor's resource scan, and a freshly
# imported project (or a headless --check-only run) may fail before the
# scan completes. preload() resolves immediately at parse time.
const CreatureNaming = preload("res://scripts/creature_naming.gd")
const FishMind = preload("res://scripts/fish_mind.gd")
const MindNarrator = preload("res://scripts/mind_narrator.gd")
const MindScheduler = preload("res://scripts/mind_scheduler.gd")
const MindConversation = preload("res://scripts/mind_conversation.gd")
const CognitiveSchema = preload("res://scripts/cognitive_schema.gd")
const FishMindScience = preload("res://scripts/fish_mind_science.gd")

const OLLAMA_PARSE_MAX_BYTES: int = 8192


static func _capped_ollama_utf8(body: PackedByteArray) -> String:
	if body.size() > OLLAMA_PARSE_MAX_BYTES:
		body = body.slice(0, OLLAMA_PARSE_MAX_BYTES)
	return body.get_string_from_utf8()


static func _parse_ollama_outer(body: PackedByteArray) -> Dictionary:
	var text: String = _capped_ollama_utf8(body)
	if text.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var parsed: Variant = json.get_data()
	return parsed if parsed is Dictionary else {}


static func _parse_ollama_json_text(text: String) -> Dictionary:
	if text.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var parsed: Variant = json.get_data()
	return parsed if parsed is Dictionary else {}


static func _parse_ollama_inner_response(body: PackedByteArray) -> Dictionary:
	var outer: Dictionary = _parse_ollama_outer(body)
	var inner_text: String = String(outer.get("response", ""))
	if inner_text.length() > OLLAMA_PARSE_MAX_BYTES:
		inner_text = inner_text.substr(0, OLLAMA_PARSE_MAX_BYTES)
	return _parse_ollama_json_text(inner_text)

# AIDirector — optional local-Ollama bridge that adds names, bios, mood
# nudges, and ambient narration WITHOUT any cloud calls.
#
# Design rules:
#   1. If Ollama is unreachable, every public method returns sensible
#      offline defaults. The sim never blocks on the network.
#   2. We never call once-per-creature per-frame. Names + bios are batched
#      (one HTTP call refills a pool of 24). The intent field is one call
#      every ~60 sim seconds, sampled locally by all creatures. Chronicle
#      lines are produced opportunistically when interesting events fire.
#   3. All requests fail-soft. A transient HTTP error flips conn_state to
#      ERROR and the offline pool takes over until the next successful
#      call (any successful call clears the error).
#
# Wired into the project as an autoload (see project.godot).

signal connection_tested(success: bool, message: String)
signal chronicle_line(text: String, tags: PackedStringArray)
signal name_pool_refilled(count: int)
signal fish_bio_ready(fish_id: String, bio: String)
signal config_changed()
# Fired by design_tank() when Ollama returns a tank-config dict (or empty
# dict on failure). The scenario picker subscribes one-shot to get the
# generated config and apply it to TankConfig.
signal tank_designed(config: Dictionary)
signal guardian_line_ready(cache_key: String, line: String, source: String)
signal guardian_line_streaming(cache_key: String, partial: String)
signal fish_thought_ready(fish_id: String, line: String, source: String)
signal fish_thought_streaming(fish_id: String, partial: String, situation: String)


# ---- Public state (read freely) -----------------------------------------
enum ConnState { UNKNOWN, OK, CHECKING, OFFLINE, ERROR }
var conn_state: int = ConnState.UNKNOWN
var last_error: String = ""
var last_ok_unix: int = 0
# Populated by test_connection — every model the local Ollama instance
# reports installed. The settings panel reads this to power its
# "Use installed model" picker.
var available_models: PackedStringArray = PackedStringArray()


# ---- Config (mirrors TankConfig; set via apply_config()) ----------------
var enabled: bool = false
var endpoint: String = "http://localhost:11434"
# Default to qwen2.5:3b — small (~2GB), fast, strong at structured JSON
# outputs, and not Meta. If the user has already installed something else
# the "Use installed model" button auto-substitutes from their list.
var model: String = "qwen2.5:3b"
var naming_theme: String = ""        # free-text e.g. "Greek gods", "trees"
var chronicle_enabled: bool = false
var intent_refresh_period_s: float = 60.0
# Embedded tier (#1–4): optional local /api/generate shim (llama.cpp server or
# Ollama on a second port). Checked before the pro Ollama endpoint for
# Guardian voice lines.
var embedded_enabled: bool = false
var embedded_endpoint: String = "http://127.0.0.1:8080"
var embedded_model: String = "Qwen2.5-0.5B-Instruct-Q4_K_M"
var guardian_voice_enabled: bool = true
var fish_thought_voice_enabled: bool = true
var sentience_voice_off: bool = false
var voice_language: String = ""
var embedded_conn_state: int = ConnState.UNKNOWN
var active_llm_tier: String = "template"


# ---- Name pool ----------------------------------------------------------
var _ai_name_pool: Array = []
const NAME_POOL_TARGET: int = 24
const NAME_POOL_REFILL_BELOW: int = 6
var _name_fetch_in_flight: bool = false

# ---- Fish bio batch (#38) ----
var _bio_pending: Array = []
var _bio_results: Dictionary = {}
var _bio_in_flight: bool = false
const BIO_BATCH_MAX: int = 8


# ---- Intent field -------------------------------------------------------
# A 4x4x4 grid (64 cells) of soft "mood attractors". Each cell holds:
#   {mood: String, drift: Vector3 (precomputed), intensity: float 0..1}
# Cells are addressed by normalized tank-relative position (0..1 on each
# axis). Creatures sample the closest cell and apply a tiny additive
# steering term — 0.05..0.15 units/sec at most. The point is to bias
# group behavior over a minute or two, not to override local steering.
const INTENT_GRID: int = 4
var _intent_cells: Array = []   # length 64, each Dictionary or null
var _intent_timer: float = 0.0
var _intent_in_flight: bool = false
var _intent_last_refresh_unix: int = 0


# ---- Per-named-fish mood ---------------------------------------------
# id -> {mood: String, drift: Vector3, expires_unix: int}
var _fish_moods: Dictionary = {}


# ---- HTTP clients (one per task type so requests don't serialize) ------
var _http_test: HTTPRequest
var _http_names: HTTPRequest
var _http_intent: HTTPRequest
var _http_chronicle: HTTPRequest
var _http_bios: HTTPRequest
var _http_design: HTTPRequest
var _http_embedded_test: HTTPRequest
var _http_guardian: HTTPRequest
var _design_in_flight: bool = false
var _guardian_pending: Array = []
var _guardian_in_flight: bool = false
var _guardian_line_cache: Dictionary = {}
const GUARDIAN_MAX_WORDS: int = 22
const GUARDIAN_LINE_CACHE_MAX: int = 64
const INTENT_DRIFT_MAX: float = 0.15   # model may flavor, never steer (#3)
const TIER_TIMEOUT_S: float = 6.0
const HTTP_TIMEOUT_TEST_S: float = 8.0
const HTTP_TIMEOUT_GUARDIAN_EMBEDDED_S: float = 5.0

var _thought_cache: Dictionary = {}
var _thought_pending: Array = []
var _thought_in_flight: bool = false
var _followed_fish_id: String = ""
var _crisis_active: bool = false
var _minute_batch_timer: float = 0.0
var _minute_batch_in_flight: bool = false


# ---- Lifecycle ---------------------------------------------------------
# _ready runs after every other autoload that lists this one as a
# dependency, but TankConfig (also an autoload) fires BEFORE us in the
# project.godot order — and its load_from_disk() can call apply_config()
# straight away, which (for a saved ai_enabled=true tank) calls
# test_connection() before our _ready has built the HTTPRequest nodes.
# Solution: build them lazily via _ensure_http(), so the first call after
# autoload instantiation triggers creation regardless of _ready timing.
func _ready() -> void:
	_ensure_http()
	# Pre-fill an empty intent grid so get_intent_drift() is safe before
	# the first refresh lands. Empty cells return Vector3.ZERO.
	if _intent_cells.is_empty():
		_intent_cells.resize(INTENT_GRID * INTENT_GRID * INTENT_GRID)
	# Suspend per-frame _process / _physics_process when AI is disabled so
	# the engine doesn't invoke a method-that-returns-immediately every
	# frame. apply_config flips these back on when the user enables AI.
	set_process(enabled)
	set_physics_process(enabled)


func _ensure_http() -> void:
	if _http_test == null:
		_http_test = _make_http("HttpTest", _on_test_response)
	if _http_names == null:
		_http_names = _make_http("HttpNames", _on_names_response)
	if _http_intent == null:
		_http_intent = _make_http("HttpIntent", _on_intent_response)
	if _http_chronicle == null:
		_http_chronicle = _make_http("HttpChronicle", _on_chronicle_response)
	if _http_bios == null:
		_http_bios = _make_http("HttpBios", _on_bios_response)
	if _http_design == null:
		_http_design = _make_http("HttpDesign", _on_design_response)
	if _http_embedded_test == null:
		_http_embedded_test = _make_http("HttpEmbeddedTest", _on_embedded_test_response)
	if _http_guardian == null:
		_http_guardian = _make_http("HttpGuardian", _on_guardian_response)
		_http_guardian.timeout = HTTP_TIMEOUT_TEST_S


func _make_http(node_name: String, callback: Callable) -> HTTPRequest:
	var h := HTTPRequest.new()
	h.name = node_name
	h.timeout = HTTP_TIMEOUT_TEST_S
	h.request_completed.connect(callback)
	add_child(h)
	return h


func _process(dt: float) -> void:
	MindNarrator.tick_global_cooldown(dt)
	if not enabled:
		return
	# Drive the throttle. SimDriver polls intent_refresh_due() and calls
	# push_tank_summary() when ready, so we only track elapsed seconds here.
	_intent_timer += dt
	_minute_batch_timer += dt
	if _minute_batch_timer >= intent_refresh_period_s:
		_minute_batch_timer = 0.0
		flush_minute_batch({})
	# Background top-up of the name pool. Free, no game impact when off.
	if conn_state == ConnState.OK and _ai_name_pool.size() < NAME_POOL_REFILL_BELOW \
			and not _name_fetch_in_flight:
		_request_name_batch()


# True when enough time has passed since the last intent refresh AND no
# refresh is currently in flight. SimDriver calls this once per sim tick;
# when true, it builds a tank summary and calls push_tank_summary().
func intent_refresh_due() -> bool:
	if not enabled or conn_state != ConnState.OK:
		return false
	if _intent_in_flight or _minute_batch_in_flight:
		return false
	return _intent_timer >= intent_refresh_period_s


# PERFORMANCE_UNTHROTTLED #94 — one director round-trip per minute when possible.
func flush_minute_batch(summary: Dictionary) -> void:
	if not enabled or conn_state != ConnState.OK or _minute_batch_in_flight:
		return
	_minute_batch_in_flight = true
	if _bio_pending.size() > 0 and not _bio_in_flight:
		_request_bio_batch()
	if chronicle_enabled and _chronicle_queue.size() > 0:
		_flush_chronicle()
	if not _intent_in_flight and _intent_timer >= intent_refresh_period_s and not summary.is_empty():
		push_tank_summary(summary)
	# Coalesce thought API pressure with the minute window (#55).
	if _thought_pending.size() > 0 and not _thought_in_flight and _effective_fish_thought_voice():
		_pump_fish_thought()
	_minute_batch_in_flight = false


# ---- Config plumbing ---------------------------------------------------
# Called by main / tank_config whenever AI settings change. Re-checks
# the connection if 'enabled' just flipped on.
func apply_config(cfg: Dictionary) -> void:
	var was_enabled: bool = enabled
	enabled = bool(cfg.get("ai_enabled", enabled))
	endpoint = String(cfg.get("ai_endpoint", endpoint)).strip_edges()
	if endpoint.ends_with("/"):
		endpoint = endpoint.substr(0, endpoint.length() - 1)
	model = String(cfg.get("ai_model", model)).strip_edges()
	naming_theme = String(cfg.get("ai_naming_theme", naming_theme)).strip_edges()
	chronicle_enabled = bool(cfg.get("ai_chronicle", chronicle_enabled))
	embedded_enabled = bool(cfg.get("ai_embedded_enabled", embedded_enabled))
	embedded_endpoint = String(cfg.get("ai_embedded_endpoint", embedded_endpoint)).strip_edges()
	if embedded_endpoint.ends_with("/"):
		embedded_endpoint = embedded_endpoint.substr(0, embedded_endpoint.length() - 1)
	embedded_model = String(cfg.get("ai_embedded_model", embedded_model)).strip_edges()
	guardian_voice_enabled = bool(cfg.get("guardian_voice_enabled", guardian_voice_enabled))
	fish_thought_voice_enabled = bool(cfg.get("fish_thought_voice_enabled", fish_thought_voice_enabled))
	sentience_voice_off = bool(cfg.get("sentience_voice_off", sentience_voice_off))
	voice_language = String(cfg.get("voice_language", voice_language))
	_warn_plaintext_remote_endpoint(endpoint, "Ollama endpoint")
	_warn_plaintext_remote_endpoint(embedded_endpoint, "Embedded LLM endpoint")
	if sentience_voice_off:
		_disable_all_voice_immediately()
	elif enabled and not was_enabled:
		test_connection()
	elif not enabled:
		conn_state = ConnState.UNKNOWN
		_ai_name_pool.clear()
		_intent_cells.clear()
		_intent_cells.resize(INTENT_GRID * INTENT_GRID * INTENT_GRID)
	if embedded_enabled:
		test_embedded_connection()
	elif not embedded_enabled:
		embedded_conn_state = ConnState.UNKNOWN
		_update_active_llm_tier()
	# Sync per-frame processing to the current enabled state so the engine
	# stops calling _process / _physics_process when AI is off.
	set_process(enabled)
	set_physics_process(enabled)
	emit_signal("config_changed")


func notify_guardian_line_streaming(cache_key: String, partial: String) -> void:
	guardian_line_streaming.emit(cache_key, partial)


func notify_thought_streaming(cache_key: String, partial: String) -> void:
	if not cache_key.begins_with("thought|"):
		return
	var body: String = cache_key.substr(8)
	var parts: PackedStringArray = body.split("|")
	if parts.size() < 2:
		return
	var fid: String = parts[0]
	var situation: String = parts[1] if parts.size() > 1 else ""
	emit_signal("fish_thought_streaming", fid, partial, situation)


func _warn_plaintext_remote_endpoint(url: String, label: String) -> void:
	if url == "" or not url.begins_with("http://"):
		return
	var rest: String = url.substr(7)
	var host: String = rest.split("/")[0].split(":")[0].to_lower()
	if host in ["localhost", "127.0.0.1", "::1", "[::1]"]:
		return
	push_warning("[AIDirector] %s uses plaintext HTTP (%s) — prompts travel unencrypted." % [
		label, url,
	])


func _effective_guardian_voice() -> bool:
	return guardian_voice_enabled and not sentience_voice_off


func _effective_fish_thought_voice() -> bool:
	return fish_thought_voice_enabled and not sentience_voice_off


func _disable_all_voice_immediately() -> void:
	_guardian_pending.clear()
	_thought_pending.clear()
	_guardian_in_flight = false
	_thought_in_flight = false
	active_llm_tier = "template"
	var glm: Node = get_node_or_null("/root/GuardianLlm")
	if glm != null and glm.has_method("suspend_voice"):
		glm.call("suspend_voice", true)


func _voice_lang_code() -> String:
	return MindNarrator.resolve_voice_language(voice_language)


# Probe /api/tags to verify the endpoint responds AND the configured
# model is installed. Emits connection_tested(success, message).
func test_connection() -> void:
	_ensure_http()
	if endpoint == "":
		conn_state = ConnState.ERROR
		last_error = "Endpoint is empty."
		emit_signal("connection_tested", false, last_error)
		return
	conn_state = ConnState.CHECKING
	var url: String = endpoint + "/api/tags"
	var err: int = _http_test.request(url, PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_GET)
	if err != OK:
		conn_state = ConnState.ERROR
		last_error = "Could not start request (Godot error %d)." % err
		emit_signal("connection_tested", false, last_error)


func _on_test_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		conn_state = ConnState.OFFLINE
		last_error = "Ollama did not respond at %s (HTTP %d, result %d). Is `ollama serve` running?" % [endpoint, code, result]
		emit_signal("connection_tested", false, last_error)
		return
	var parsed: Dictionary = _parse_ollama_outer(body)
	if parsed.is_empty():
		conn_state = ConnState.ERROR
		last_error = "Ollama returned malformed JSON."
		emit_signal("connection_tested", false, last_error)
		return
	var models_arr: Array = parsed.get("models", [])
	var have_model: bool = false
	available_models = PackedStringArray()
	for m in models_arr:
		var nm: String = String(m.get("name", ""))
		available_models.append(nm)
		if nm == model or nm.begins_with(model + ":"):
			have_model = true
	if not have_model:
		conn_state = ConnState.ERROR
		last_error = "Connected, but `%s` is not installed. Pick one of your installed models (button below) or run `ollama pull %s`." % [model, model]
		emit_signal("connection_tested", false, last_error)
		return
	conn_state = ConnState.OK
	last_error = ""
	last_ok_unix = int(Time.get_unix_time_from_system())
	_update_active_llm_tier()
	emit_signal("connection_tested", true, "Connected to Ollama. Model `%s` ready." % model)


# Pick the most sensible model from `available_models` for our workload
# (short JSON outputs: names + region moods + 1-sentence chronicle).
# Priority order — Meta/Llama models are deliberately excluded from the
# preference list:
#   1. Anything already matching the user's configured `model` family
#   2. qwen2.5 (3B–7B is the sweet spot for short JSON)
#   3. mistral
#   4. granite4 (small + fast IBM model)
#   5. gemma3 (Google)
#   6. qwen2 / qwen3 (broader Qwen family)
#   7. deepseek-r1 (reasoning model — capable but slower due to thinking
#      tokens; placed last among non-Llama options)
# Anything else only fires as a true last-resort fallback, and even then
# we skip llama/llava/tinyllama families and vision/embedder models.
func pick_best_installed_model() -> String:
	if available_models.is_empty():
		return ""
	# 1. Family match against current configured model.
	var family: String = model.split(":")[0]
	if family != "" and not _is_meta_family(family):
		for m in available_models:
			if String(m).begins_with(family + ":"):
				return String(m)
	# 2..N: hardcoded preference list (non-Meta only).
	var prefs: PackedStringArray = PackedStringArray([
		"qwen2.5", "mistral", "granite4", "gemma3",
		"qwen2", "qwen3", "deepseek-r1",
	])
	for pref in prefs:
		for m in available_models:
			if String(m).begins_with(pref + ":") or String(m) == pref:
				return String(m)
	# Fallback: first installed model that isn't a vision-only / embedder
	# / Llama-family model. We'd rather return "" (and let the caller
	# show an error) than silently pick something the user explicitly
	# said they don't want.
	for m in available_models:
		var s: String = String(m).to_lower()
		if "vision" in s or "embed" in s or "moondream" in s:
			continue
		if _is_meta_family(s.split(":")[0]):
			continue
		return String(m)
	return ""


func _is_meta_family(name_prefix: String) -> bool:
	# Llama, llava (built on Llama), tinyllama, llama2-uncensored, etc.
	# Anything starting with "llama" or "llava" or "tinyllama" is Meta-derived.
	var s: String = name_prefix.to_lower()
	return s.begins_with("llama") or s.begins_with("llava") or s == "tinyllama"


# ---- Naming -----------------------------------------------------------
# Returns a name immediately. When the AI pool has one queued we use that;
# otherwise we use the offline fallback AND kick off a background refill.
# This means the very first fish in a session uses an offline name (no
# blocking wait) and subsequent fish get LLM names as the pool fills.
func consume_name(organism_kind: String, already_used: Dictionary = {}) -> Dictionary:
	if enabled and conn_state == ConnState.OK and _ai_name_pool.size() > 0:
		# Find first pool entry not already in use.
		for i in range(_ai_name_pool.size()):
			var candidate: String = String(_ai_name_pool[i])
			if not already_used.has(candidate.to_lower()):
				_ai_name_pool.remove_at(i)
				if _ai_name_pool.size() < NAME_POOL_REFILL_BELOW and not _name_fetch_in_flight:
					_request_name_batch()
				return {"name": candidate, "source": "ai"}
		# All pool entries clashed — fall through to offline.
	if enabled and conn_state != ConnState.OK and not _name_fetch_in_flight:
		# Opportunistic: try a refill so the next fish benefits.
		_request_name_batch()
	return {"name": CreatureNaming.generate_name(organism_kind, already_used), "source": "offline"}


func _request_name_batch() -> void:
	if not enabled or endpoint == "":
		return
	_ensure_http()
	_name_fetch_in_flight = true
	var theme_clause: String = ""
	if naming_theme != "":
		theme_clause = " The names should feel like: %s." % naming_theme
	var prompt: String = "Return a JSON object with one key 'names' whose value is an array of exactly %d distinct short pet names suitable for individual aquarium creatures.%s Each name is 1-2 syllables, gender-neutral, no titles, no surnames. Return ONLY the JSON." % [NAME_POOL_TARGET, theme_clause]
	var payload: Dictionary = {
		"model": model,
		"prompt": prompt,
		"stream": false,
		"format": "json",
		"options": {"temperature": 1.05}
	}
	var url: String = endpoint + "/api/generate"
	var err: int = _http_names.request(url,
			PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST,
			JSON.stringify(payload))
	if err != OK:
		_name_fetch_in_flight = false


func _on_names_response(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_name_fetch_in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		conn_state = ConnState.OFFLINE
		return
	var inner: Dictionary = _parse_ollama_inner_response(body)
	if inner.is_empty():
		return
	var names: Variant = inner.get("names", [])
	if not (names is Array):
		return
	var added: int = 0
	for n in names:
		var s: String = String(n).strip_edges().capitalize()
		# Filter: keep 2-20 chars; drop anything obviously not a name
		# (numbers, punctuation-only, very long phrases the model may emit).
		if s.length() < 2 or s.length() > 20:
			continue
		_ai_name_pool.append(s)
		added += 1
	conn_state = ConnState.OK
	last_ok_unix = int(Time.get_unix_time_from_system())
	emit_signal("name_pool_refilled", added)


# One-line character bio per named fish (#38). Returns offline/epithet text
# immediately; queues an LLM batch when online. Later bios arrive via
# fish_bio_ready.
func queue_fish_bio(fish: Node) -> String:
	if fish == null or not is_instance_valid(fish):
		return ""
	var fid: String = String(fish.get("id") if fish.get("id") != null else "")
	if fid != "" and _bio_results.has(fid):
		if fish.get("character_bio") != null:
			fish.character_bio = String(_bio_results[fid])
		return String(_bio_results[fid])
	var existing: String = String(fish.get("character_bio") if fish.get("character_bio") != null else "")
	if existing != "":
		return existing
	var offline: String = FishMind.offline_character_bio(fish)
	if fish.get("character_bio") != null:
		fish.character_bio = offline
	var fname: String = String(fish.get("fish_name") if fish.get("fish_name") != null else "")
	if not enabled or conn_state != ConnState.OK or fid == "" or fname == "":
		return offline
	for e in _bio_pending:
		if String(e.get("id", "")) == fid:
			return offline
	var pers: Dictionary = {}
	var pers_v: Variant = fish.get("personality")
	if pers_v is Dictionary:
		pers = (pers_v as Dictionary).duplicate()
	_bio_pending.append({
		"id": fid,
		"name": fname,
		"species": String(fish.get("species") if fish.get("species") != null else ""),
		"personality": pers,
		"generation": int(fish.get("generation") if fish.get("generation") != null else 0),
		"lineage": String(fish.get("parent_lineage") if fish.get("parent_lineage") != null else ""),
	})
	if not _bio_in_flight:
		_request_bio_batch()
	return offline


func set_followed_fish(fish_id: String) -> void:
	_followed_fish_id = fish_id


func set_crisis_active(active: bool) -> void:
	_crisis_active = active


func fish_deserves_model_voice(f: Fish, sim: Node = null) -> bool:
	if f == null:
		return false
	if f.is_guardian:
		return true
	if not f.is_voiced_individual():
		return false
	if String(f.id) == _followed_fish_id:
		return true
	if sim != null and sim.has_method("is_creature_favorited"):
		if sim.is_creature_favorited(f):
			return true
	return f.fish_name != "" and f.familiarity >= FishMind.VOICED_FAMILIARITY


func queue_fish_thought(f: Fish, sim: Node, situation: String = "inspect") -> String:
	if f == null or not is_instance_valid(f):
		return ""
	var is_reply: bool = situation.begins_with("keeper_")
	if not _effective_fish_thought_voice() and not is_reply:
		return f.get_inspect_thought() if f.has_method("get_inspect_thought") else ""
	if not fish_deserves_model_voice(f, sim) and not is_reply:
		return f.get_inspect_thought() if f.has_method("get_inspect_thought") else ""
	if _crisis_active:
		return f.get_inspect_thought() if f.has_method("get_inspect_thought") else ""
	if not is_reply and not MindNarrator.global_voice_ready():
		return f.get_inspect_thought() if f.has_method("get_inspect_thought") else ""
	var fid: String = String(f.id)
	var keeper_text: String = str(f._keeper_pending.get("keeper_text", "")) if is_reply else ""
	var cache_key: String = MindConversation.reply_cache_key(f, keeper_text) if is_reply \
			else _thought_cache_key(f, situation)
	if not is_reply and _thought_cache.has(cache_key):
		return String(_thought_cache[cache_key])
	var ctx: Dictionary = MindContext.build_for_fish(f, sim, situation)
	if is_reply:
		ctx = MindContext.build_for_keeper_turn(f, sim, situation)
		ctx = MindConversation.enrich_context(ctx, f, sim)
		if sim != null and sim.get("_guardian_arc") is Dictionary:
			var ms: Variant = (sim._guardian_arc as Dictionary).get("shared_milestones", null)
			if ms is PackedStringArray and (ms as PackedStringArray).size() > 0:
				ctx["shared_milestones"] = ms
	ctx["voice_style"] = MindNarrator.voice_style_label(fid, f.personality, f.species)
	ctx["primary_process"] = FishMindScience.primary_process(f)
	ctx["fish_id"] = fid
	var fb: String = MindNarrator.template_fish_reply(ctx) if is_reply \
			else MindNarrator.template_fish_thought(ctx)
	if situation == "keeper_initiate" and fb == "I hear you":
		fb = "…wanted to say something"
	if situation == "keeper_goodbye" and fb == "I hear you":
		fb = "…drifting now"
	if fb == "":
		fb = f.get_inspect_thought()
	if is_reply:
		# Template tier always returns immediately; model upgrades async.
		if not MindConversation.should_reply_model(f, {"ok": true}):
			return fb
	elif not MindNarrator.should_attempt_generation(ctx):
		return fb
	if not _effective_guardian_voice() and not enabled:
		return fb
	for e in _thought_pending:
		if String(e.get("cache_key", "")) == cache_key:
			return fb
	_thought_pending.append({
		"fish_id": fid,
		"context": ctx,
		"fallback": fb,
		"cache_key": cache_key,
		"situation": situation,
	})
	_pump_fish_thought()
	return fb


func _pump_fish_thought() -> void:
	if _thought_pending.is_empty() or _thought_in_flight:
		return
	if MindScheduler.should_throttle_external():
		var drop: Dictionary = _thought_pending[0]
		var drop_key: String = String(drop.get("cache_key", ""))
		var drop_fb: String = String(drop.get("fallback", ""))
		if drop_key != "":
			_thought_cache[drop_key] = drop_fb
		_thought_pending.pop_front()
		MindScheduler.note_external_throttled()
		if not _thought_pending.is_empty():
			_pump_fish_thought()
		return
	var job: Dictionary = _thought_pending[0]
	var ctx: Dictionary = job.get("context", {})
	var fb: String = String(job.get("fallback", ""))
	var cache_key: String = String(job.get("cache_key", ""))
	var full_key: String = "thought|" + cache_key
	var glm: Node = get_node_or_null("/root/GuardianLlm")
	if _effective_guardian_voice() and glm != null and glm.has_method("queue_generate") \
			and glm.has_method("is_ready") and bool(glm.call("is_ready")):
		var sit: String = str(ctx.get("situation", ""))
		var prompt: String = MindNarrator.build_fish_reply_prompt(ctx, _voice_lang_code()) \
				if sit.begins_with("keeper_") \
				else MindNarrator.build_fish_thought_prompt(ctx, _voice_lang_code())
		var n_pred: int = MindNarrator.num_predict_for_situation(sit)
		glm.call("queue_generate", full_key, prompt, fb, ctx, n_pred)
		_thought_pending.pop_front()
		return
	var llm: Dictionary = _resolve_guardian_llm()
	if llm.is_empty():
		_thought_pending.pop_front()
		if not _thought_pending.is_empty():
			_pump_fish_thought()
		return
	_guardian_pending.append({
		"context": ctx,
		"fallback": fb,
		"cache_key": full_key,
		"endpoint": String(llm.get("endpoint", "")),
		"model": String(llm.get("model", "")),
		"tier": String(llm.get("tier", "ollama")),
		"fish_id": String(job.get("fish_id", "")),
		"is_thought": true,
	})
	_thought_pending.pop_front()
	if not _guardian_in_flight:
		_request_guardian_line()


func _cache_thought(cache_key: String, line: String, fish_id: String) -> void:
	var key: String = cache_key
	if key.begins_with("thought|"):
		key = key.substr(8)
	if "|keeper_reply|" in key:
		# Replies are per-message — do not reuse across turns.
		pass
	else:
		_thought_cache[key] = line
	MindNarrator.mark_voice_spoke()
	emit_signal("fish_thought_ready", fish_id, line, "model")
	while _thought_cache.size() > 48:
		_thought_cache.erase(String(_thought_cache.keys()[0]))


func _request_bio_batch() -> void:
	if not enabled or endpoint == "" or _bio_pending.is_empty():
		return
	_ensure_http()
	_bio_in_flight = true
	var batch: Array = _bio_pending.slice(0, mini(BIO_BATCH_MAX, _bio_pending.size()))
	var prompt: String = "You are an aquarium chronicler. For each fish below, write ONE warm character sentence (max 18 words) capturing personality from traits. Output JSON: {\"bios\":[{\"id\":\"...\",\"line\":\"...\"}]}. Fish: %s" % JSON.stringify(batch)
	var payload: Dictionary = {
		"model": model,
		"prompt": prompt,
		"stream": false,
		"format": "json",
		"options": {"temperature": 0.9, "seed": _guardian_seed("bio|%s" % JSON.stringify(batch))}
	}
	var url: String = endpoint + "/api/generate"
	var err: int = _http_bios.request(url,
			PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST,
			JSON.stringify(payload))
	if err != OK:
		_bio_in_flight = false


func _on_bios_response(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_bio_in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		conn_state = ConnState.OFFLINE
		return
	var inner: Dictionary = _parse_ollama_inner_response(body)
	if inner.is_empty():
		return
	var bios: Variant = inner.get("bios", [])
	if bios is Array:
		for b_v in bios:
			if not (b_v is Dictionary):
				continue
			var fid: String = String(b_v.get("id", ""))
			var line: String = String(b_v.get("line", "")).strip_edges()
			if fid == "" or line == "":
				continue
			_bio_results[fid] = line
			emit_signal("fish_bio_ready", fid, line)
	# Drop processed entries from the pending queue.
	var served: Dictionary = {}
	if bios is Array:
		for b_v2 in bios:
			if b_v2 is Dictionary:
				served[String(b_v2.get("id", ""))] = true
	var keep: Array = []
	for e in _bio_pending:
		if not served.has(String(e.get("id", ""))):
			keep.append(e)
	_bio_pending = keep
	if not _bio_pending.is_empty():
		_request_bio_batch()
	conn_state = ConnState.OK
	last_ok_unix = int(Time.get_unix_time_from_system())


# ---- Intent field ------------------------------------------------------
# Sample the intent grid at a tank-relative position [0..1, 0..1, 0..1].
# Returns a small drift Vector3 (length ≤ 0.15) suitable for adding to
# a creature's desired velocity, plus a mood word for debug HUDs.
func get_intent_drift(rel_pos: Vector3) -> Dictionary:
	if _intent_cells.is_empty():
		return {"drift": Vector3.ZERO, "mood": "", "intensity": 0.0}
	var ix: int = clampi(int(rel_pos.x * INTENT_GRID), 0, INTENT_GRID - 1)
	var iy: int = clampi(int(rel_pos.y * INTENT_GRID), 0, INTENT_GRID - 1)
	var iz: int = clampi(int(rel_pos.z * INTENT_GRID), 0, INTENT_GRID - 1)
	var idx: int = ix + iy * INTENT_GRID + iz * INTENT_GRID * INTENT_GRID
	var cell: Variant = _intent_cells[idx]
	if not (cell is Dictionary):
		return {"drift": Vector3.ZERO, "mood": "", "intensity": 0.0}
	var drift: Vector3 = cell.get("drift", Vector3.ZERO)
	if drift is Vector3 and drift.length() > INTENT_DRIFT_MAX:
		drift = drift.normalized() * INTENT_DRIFT_MAX
	return {
		"drift": drift,
		"mood": String(cell.get("mood", "")),
		"intensity": float(cell.get("intensity", 0.0)),
	}


# Called by SimDriver each refresh window. The summary dict is small:
#   { fish_count, shrimp_count, snail_count, o2, ammonia, day_phase,
#     named_fish: [{id, name, hunger, stress}], recent_events: [...] }
# The LLM converts it to coarse "regions of feeling" which we encode
# locally into drift vectors. We deliberately keep the LLM output small
# (≤ 12 region descriptors + ≤ 8 fish moods + 1 narration line) so it
# fits in a single sub-second response on a 3B model.
func push_tank_summary(summary: Dictionary) -> void:
	if not enabled or conn_state != ConnState.OK or _intent_in_flight:
		return
	_ensure_http()
	_intent_in_flight = true
	_intent_timer = 0.0   # reset so intent_refresh_due() doesn't fire again until period elapses
	var prompt: String = _build_intent_prompt(summary)
	var payload: Dictionary = {
		"model": model,
		"prompt": prompt,
		"stream": false,
		"format": "json",
		"options": {"temperature": 0.85}
	}
	var url: String = endpoint + "/api/generate"
	var err: int = _http_intent.request(url,
			PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST,
			JSON.stringify(payload))
	if err != OK:
		_intent_in_flight = false


func _build_intent_prompt(summary: Dictionary) -> String:
	# We hand the LLM a compact 'world report' and ask for a structured
	# response. Regions use named cubes: x ∈ {left, mid, right}, y ∈ {bottom,
	# middle, top}, z ∈ {front, mid, back}. Names compress 4×4×4 -> 27 cells
	# the model can talk about. We post-process by mapping each named region
	# to its grid cells.
	return "You are an aquarium narrator. Given this tank state, output JSON with three keys: regions (array of {region, mood}), fish_moods (array of {id, mood}), narration (1 sentence). Valid regions: top-front, top-back, mid-front, mid-back, bottom-front, bottom-back, center. Valid moods: calm, curious, hungry, restless, sleepy, playful, shy, alert. Tank state: %s" % JSON.stringify(summary)


func _on_intent_response(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_intent_in_flight = false
	_intent_last_refresh_unix = int(Time.get_unix_time_from_system())
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		conn_state = ConnState.OFFLINE
		return
	var inner: Dictionary = _parse_ollama_inner_response(body)
	if inner.is_empty():
		return
	_apply_intent_payload(inner)
	conn_state = ConnState.OK
	last_ok_unix = int(Time.get_unix_time_from_system())


func _apply_intent_payload(payload: Dictionary) -> void:
	# Reset the grid
	_intent_cells.clear()
	_intent_cells.resize(INTENT_GRID * INTENT_GRID * INTENT_GRID)
	var regions: Variant = payload.get("regions", [])
	if regions is Array:
		for r_v in regions:
			if not (r_v is Dictionary):
				continue
			var region_name: String = String(r_v.get("region", "")).to_lower()
			var mood: String = String(r_v.get("mood", "")).to_lower()
			_apply_region_mood(region_name, mood)
	# Per-named-fish moods, expire after ~3 intent windows so they fade
	# gracefully if the LLM stops mentioning that fish.
	var fish_moods: Variant = payload.get("fish_moods", [])
	var now: int = int(Time.get_unix_time_from_system())
	var expiry: int = now + int(intent_refresh_period_s * 3.0)
	if fish_moods is Array:
		for fm_v in fish_moods:
			if not (fm_v is Dictionary):
				continue
			var fid: String = String(fm_v.get("id", ""))
			var fm: String = String(fm_v.get("mood", "")).to_lower()
			if fid != "" and fm != "":
				_fish_moods[fid] = {
					"mood": fm,
					"drift": _mood_drift(fm) * 0.6,
					"expires_unix": expiry,
				}
	# Prune expired
	var stale: Array = []
	for k in _fish_moods.keys():
		if int(_fish_moods[k].get("expires_unix", 0)) < now:
			stale.append(k)
	for k in stale:
		_fish_moods.erase(k)
	# Chronicle line
	if chronicle_enabled:
		var line: String = String(payload.get("narration", "")).strip_edges()
		if line != "":
			emit_signal("chronicle_line", line, PackedStringArray(["intent"]))


func _apply_region_mood(region_name: String, mood: String) -> void:
	# Map named region -> (x range, y range, z range) on the 4×4×4 grid.
	var x_range: Vector2i
	var y_range: Vector2i
	var z_range: Vector2i
	match region_name:
		"top-front":    x_range = Vector2i(0,3); y_range = Vector2i(2,3); z_range = Vector2i(0,1)
		"top-back":     x_range = Vector2i(0,3); y_range = Vector2i(2,3); z_range = Vector2i(2,3)
		"mid-front":   x_range = Vector2i(0,3); y_range = Vector2i(1,2); z_range = Vector2i(0,1)
		"mid-back":    x_range = Vector2i(0,3); y_range = Vector2i(1,2); z_range = Vector2i(2,3)
		"bottom-front": x_range = Vector2i(0,3); y_range = Vector2i(0,1); z_range = Vector2i(0,1)
		"bottom-back":  x_range = Vector2i(0,3); y_range = Vector2i(0,1); z_range = Vector2i(2,3)
		"center":       x_range = Vector2i(1,2); y_range = Vector2i(1,2); z_range = Vector2i(1,2)
		_:              return
	var drift: Vector3 = _mood_drift(mood)
	var cell: Dictionary = {"drift": drift, "mood": mood, "intensity": 1.0}
	for xi in range(x_range.x, x_range.y + 1):
		for yi in range(y_range.x, y_range.y + 1):
			for zi in range(z_range.x, z_range.y + 1):
				var idx: int = xi + yi * INTENT_GRID + zi * INTENT_GRID * INTENT_GRID
				_intent_cells[idx] = cell.duplicate()


# Translate a mood word into a small drift vector. Drifts are in
# tank-relative space (the caller multiplies by a world scale).
func _mood_drift(mood: String) -> Vector3:
	match mood:
		"calm":     return Vector3(0.0, 0.0, 0.0)
		"sleepy":   return Vector3(0.0, -0.1, 0.0)
		"curious":  return Vector3(randf_range(-1, 1), 0.05, randf_range(-1, 1)).normalized() * 0.12
		"hungry":   return Vector3(0.0, 0.15, 0.0)  # bias upward (food is dropped from above)
		"restless": return Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * 0.15
		"playful":  return Vector3(randf_range(-1, 1), 0.1, randf_range(-1, 1)).normalized() * 0.13
		"shy":      return Vector3(0.0, -0.05, 0.0)
		"alert":    return Vector3(0.0, 0.08, 0.0)
		_:          return Vector3.ZERO


# Per-named-fish mood drift (or zero). Called by fish.gd for fish that
# have a stable id and a recent LLM mention.
func get_fish_mood_drift(fish_id: String) -> Vector3:
	if fish_id == "" or not _fish_moods.has(fish_id):
		return Vector3.ZERO
	var v: Variant = _fish_moods[fish_id].get("drift", Vector3.ZERO)
	return v if v is Vector3 else Vector3.ZERO


# ---- Chronicle (event-driven narration) -------------------------------
# SimDriver / fish / shrimp call this when something notable happens.
# We queue events and flush them in batches (every ~3 events or ~15 s)
# to keep LLM calls bounded.
var _chronicle_queue: Array = []
var _chronicle_flush_timer: float = 0.0
const CHRONICLE_FLUSH_INTERVAL: float = 18.0
const CHRONICLE_FLUSH_AT_SIZE: int = 4


func note_event(event_type: String, summary: String) -> void:
	if not enabled or not chronicle_enabled:
		return
	_chronicle_queue.append({"type": event_type, "summary": summary})
	if _chronicle_queue.size() >= CHRONICLE_FLUSH_AT_SIZE:
		_flush_chronicle()


func _physics_process(dt: float) -> void:
	if not enabled or not chronicle_enabled:
		return
	_chronicle_flush_timer += dt
	if _chronicle_flush_timer >= CHRONICLE_FLUSH_INTERVAL and _chronicle_queue.size() > 0:
		_flush_chronicle()


func _flush_chronicle() -> void:
	_chronicle_flush_timer = 0.0
	if _chronicle_queue.is_empty():
		return
	if conn_state != ConnState.OK:
		_chronicle_queue.clear()  # don't accumulate unbounded when offline
		return
	_ensure_http()
	var batch: Array = _chronicle_queue.duplicate()
	_chronicle_queue.clear()
	var prompt: String = "You are an aquarium chronicler. Compose ONE sentence (max 20 words) summarising these tank events in past tense, warm and observational. Output JSON with one key 'line'. Events: %s" % JSON.stringify(batch)
	var payload: Dictionary = {
		"model": model,
		"prompt": prompt,
		"stream": false,
		"format": "json",
		"options": {"temperature": 0.9}
	}
	var url: String = endpoint + "/api/generate"
	_http_chronicle.request(url,
			PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST,
			JSON.stringify(payload))


func _on_chronicle_response(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var inner: Dictionary = _parse_ollama_inner_response(body)
	if inner.is_empty():
		return
	var line: String = String(inner.get("line", "")).strip_edges()
	if line != "" and not MindNarrator.chronicle_repeat(line):
		MindNarrator.remember_chronicle(line)
		emit_signal("chronicle_line", line, PackedStringArray(["chronicle"]))


# ---- UI helpers --------------------------------------------------------
# ---- Wildcard tank designer -------------------------------------------
# Ask Ollama to translate a freeform tank prompt ("zen carpet only", "red
# plant showcase", "chaotic alien biosphere") into a TankConfig override
# dict the scenario picker can apply. Fires `tank_designed(config)` when
# the LLM response lands (empty dict on failure). One request in flight
# at a time — second calls bail until the first finishes.
func design_tank(user_prompt: String) -> void:
	if not enabled or conn_state != ConnState.OK:
		emit_signal("tank_designed", {})
		return
	if _design_in_flight:
		return
	_ensure_http()
	_design_in_flight = true
	var sys_prompt: String = (
		"You design aquarium tanks. Given the user's vibe, return JSON with "
		+ "these keys ONLY: tank_preset (one of: classic_community, community, "
		+ "tetra_school, apex_tank, showcase, reef, polyp_lab, iwagumi_school, "
		+ "cichlid_pairs, blackwater_biotope), substrate_type (one of: aquasoil, "
		+ "sand, eco_complete, inert_gravel, ocean_sand), aeration_type (filter, "
		+ "disk, stick, none), tank_shape (box, cylinder, cube, hex, sphere), "
		+ "tank_half_w (float 3-12), tank_half_d (float 3-8), tank_height (float "
		+ "5-10), light_fixture (bar, spotlight), lighting_preset (planted, "
		+ "cozy_shop, sunny, dim_warm, reef), co2_level (float 0-1), "
		+ "light_spectrum (float 0-1 where 0=cool blue, 1=warm red). Pick a "
		+ "preset that matches the vibe. Use ocean_sand ONLY with the reef "
		+ "preset. User vibe: "
		+ user_prompt)
	var payload: Dictionary = {
		"model": model,
		"prompt": sys_prompt,
		"stream": false,
		"format": "json",
		"options": {"temperature": 0.9}
	}
	var url: String = endpoint + "/api/generate"
	var err: int = _http_design.request(url,
			PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST,
			JSON.stringify(payload))
	if err != OK:
		_design_in_flight = false
		emit_signal("tank_designed", {})


func _on_design_response(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_design_in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		emit_signal("tank_designed", {})
		return
	var inner: Dictionary = _parse_ollama_inner_response(body)
	if inner.is_empty():
		emit_signal("tank_designed", {})
		return
	# Validate + sanitize: LLM can produce nonsense values. Clamp floats,
	# whitelist enum-style strings, drop anything we don't recognize.
	var clean: Dictionary = _sanitize_design(inner)
	emit_signal("tank_designed", clean)


# Whitelist + clamp the LLM-supplied design dict so a hallucinated value
# can't crash the spawn pipeline. Keys not in the whitelist are dropped.
func _sanitize_design(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var presets: PackedStringArray = PackedStringArray([
		"classic_community", "community", "tetra_school", "apex_tank",
		"showcase", "reef", "polyp_lab", "iwagumi_school",
		"cichlid_pairs", "blackwater_biotope"])
	var substrates: PackedStringArray = PackedStringArray([
		"aquasoil", "sand", "eco_complete", "inert_gravel", "ocean_sand"])
	var aerations: PackedStringArray = PackedStringArray([
		"filter", "disk", "stick", "none"])
	var shapes: PackedStringArray = PackedStringArray([
		"box", "cylinder", "cube", "hex", "sphere"])
	var fixtures: PackedStringArray = PackedStringArray(["bar", "spotlight"])
	var lightings: PackedStringArray = PackedStringArray([
		"planted", "cozy_shop", "sunny", "dim_warm", "reef"])
	if d.has("tank_preset") and String(d["tank_preset"]) in presets:
		out["tank_preset"] = String(d["tank_preset"])
	if d.has("substrate_type") and String(d["substrate_type"]) in substrates:
		out["substrate_type"] = String(d["substrate_type"])
	if d.has("aeration_type") and String(d["aeration_type"]) in aerations:
		out["aeration_type"] = String(d["aeration_type"])
	if d.has("tank_shape") and String(d["tank_shape"]) in shapes:
		out["tank_shape"] = String(d["tank_shape"])
	if d.has("light_fixture") and String(d["light_fixture"]) in fixtures:
		out["light_fixture"] = String(d["light_fixture"])
	if d.has("lighting_preset") and String(d["lighting_preset"]) in lightings:
		out["lighting_preset"] = String(d["lighting_preset"])
	if d.has("tank_half_w"):
		out["tank_half_w"] = clampf(float(d["tank_half_w"]), 3.0, 12.0)
	if d.has("tank_half_d"):
		out["tank_half_d"] = clampf(float(d["tank_half_d"]), 3.0, 8.0)
	if d.has("tank_height"):
		out["tank_height"] = clampf(float(d["tank_height"]), 5.0, 10.0)
	if d.has("co2_level"):
		out["co2_level"] = clampf(float(d["co2_level"]), 0.0, 1.0)
	if d.has("light_spectrum"):
		out["light_spectrum"] = clampf(float(d["light_spectrum"]), 0.0, 1.0)
	# Coherence guards: ocean_sand only with reef preset.
	if String(out.get("substrate_type", "")) == "ocean_sand":
		out["tank_preset"] = "reef"
	elif String(out.get("tank_preset", "")) == "reef":
		out["substrate_type"] = "ocean_sand"
	return out


func status_summary() -> String:
	var bits: Array[String] = []
	match conn_state:
		ConnState.UNKNOWN:  bits.append("Ollama: not tested")
		ConnState.OK:       bits.append("Ollama · %s · %d names" % [model, _ai_name_pool.size()])
		ConnState.CHECKING: bits.append("Ollama: checking…")
		ConnState.OFFLINE:  bits.append("Ollama offline")
		ConnState.ERROR:    bits.append("Ollama error: %s" % last_error)
	if embedded_enabled:
		match embedded_conn_state:
			ConnState.OK:       bits.append("HTTP embedded · %s" % embedded_model)
			ConnState.CHECKING: bits.append("HTTP embedded: checking…")
			ConnState.OFFLINE:  bits.append("HTTP embedded offline")
			ConnState.ERROR:    bits.append("HTTP embedded error")
	var glm: Node = get_node_or_null("/root/GuardianLlm")
	if glm != null and glm.has_method("status_summary"):
		var built_in: String = String(glm.call("status_summary")).strip_edges()
		if built_in != "":
			bits.append("Built-in mind: %s" % built_in)
	bits.append("Speaking via: %s" % MindNarrator.tier_display_name(active_llm_tier))
	if MindNarrator.gen_attempts > 0:
		bits.append(MindNarrator.health_summary(active_llm_tier))
	return " · ".join(bits)


# ---- Embedded tier (#1–5, #7–8) ----------------------------------------
func test_embedded_connection() -> void:
	_ensure_http()
	if not embedded_enabled or embedded_endpoint == "":
		embedded_conn_state = ConnState.UNKNOWN
		_update_active_llm_tier()
		return
	embedded_conn_state = ConnState.CHECKING
	var payload: Dictionary = {
		"model": embedded_model,
		"prompt": "Reply with the single word: ok",
		"stream": false,
		"options": {"temperature": 0.0, "num_predict": 4},
	}
	var err: int = _http_embedded_test.request(
			embedded_endpoint + "/api/generate",
			PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST,
			JSON.stringify(payload))
	if err != OK:
		embedded_conn_state = ConnState.OFFLINE
		_update_active_llm_tier()


func _on_embedded_test_response(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		embedded_conn_state = ConnState.OK
	else:
		embedded_conn_state = ConnState.OFFLINE
	_update_active_llm_tier()
	emit_signal("config_changed")


func _update_active_llm_tier() -> void:
	var glm: Node = get_node_or_null("/root/GuardianLlm")
	if _effective_guardian_voice() and glm != null and glm.has_method("is_ready") \
			and bool(glm.call("is_ready")):
		active_llm_tier = "inprocess"
	elif _effective_guardian_voice() and embedded_enabled \
			and embedded_conn_state == ConnState.OK:
		active_llm_tier = "embedded"
	elif enabled and conn_state == ConnState.OK:
		active_llm_tier = "ollama"
	else:
		active_llm_tier = "template"


func guardian_llm_available() -> bool:
	_update_active_llm_tier()
	return active_llm_tier != "template"


func _resolve_guardian_llm() -> Dictionary:
	if _effective_guardian_voice() and embedded_enabled \
			and embedded_conn_state == ConnState.OK:
		return {
			"endpoint": embedded_endpoint,
			"model": embedded_model,
			"tier": "embedded",
		}
	if enabled and conn_state == ConnState.OK:
		return {"endpoint": endpoint, "model": model, "tier": "ollama"}
	return {}


# ---- Guardian voice (#20–27) -------------------------------------------
# Returns the fallback line immediately; queues an async upgrade when a
# local model is reachable. Cached by cache_key (guardian + day + situation)
# so reloads don't reshuffle the voice (#8).
func queue_guardian_line(context: Dictionary, fallback: String, cache_key: String) -> String:
	var fb: String = fallback.strip_edges()
	if cache_key != "" and _guardian_line_cache.has(cache_key):
		var cached: String = String(_guardian_line_cache[cache_key])
		if cached != "":
			return cached
	if fb == "":
		return fb
	if not MindNarrator.should_attempt_generation(context):
		return fb
	var glm: Node = get_node_or_null("/root/GuardianLlm")
	if _effective_guardian_voice() and glm != null and glm.has_method("queue_generate"):
		var prompt: String = MindNarrator.build_guardian_prompt(context, _voice_lang_code())
		var ctx_for_job: Dictionary = context.duplicate(true)
		ctx_for_job["situation"] = str(context.get("situation", ""))
		glm.call("queue_generate", cache_key, prompt, fb, ctx_for_job)
		_update_active_llm_tier()
		return fb
	var llm: Dictionary = _resolve_guardian_llm()
	if llm.is_empty():
		return fb
	for e in _guardian_pending:
		if String(e.get("cache_key", "")) == cache_key:
			return fb
	_guardian_pending.append({
		"context": context.duplicate(true),
		"fallback": fb,
		"cache_key": cache_key,
		"endpoint": String(llm.get("endpoint", "")),
		"model": String(llm.get("model", "")),
		"tier": String(llm.get("tier", "ollama")),
	})
	if not _guardian_in_flight:
		_request_guardian_line()
	return fb


func _request_guardian_line() -> void:
	if _guardian_pending.is_empty():
		return
	_ensure_http()
	var job: Dictionary = _guardian_pending[0]
	_guardian_in_flight = true
	var ctx: Dictionary = job.get("context", {})
	var situation: String = str(ctx.get("situation", ""))
	var prompt: String = MindNarrator.build_guardian_prompt(ctx, _voice_lang_code())
	var rng_seed: int = _guardian_seed(str(job.get("cache_key", "")))
	var tier: String = String(job.get("tier", "ollama"))
	var stream_recap: bool = situation == "away_recap"
	_http_guardian.timeout = HTTP_TIMEOUT_GUARDIAN_EMBEDDED_S if tier == "embedded" else TIER_TIMEOUT_S
	var payload: Dictionary = {
		"model": str(job.get("model", model)),
		"prompt": prompt,
		"stream": stream_recap,
		"options": {
			"temperature": 0.35,
			"seed": rng_seed,
			"num_predict": MindNarrator.num_predict_for_situation(situation),
		},
	}
	var url: String = String(job.get("endpoint", endpoint)) + "/api/generate"
	var err: int = _http_guardian.request(url,
			PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST,
			JSON.stringify(payload))
	if err != OK:
		_guardian_in_flight = false
		_guardian_pending.pop_front()
		if not _guardian_pending.is_empty():
			_request_guardian_line()


func _on_guardian_response(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_guardian_in_flight = false
	var job: Dictionary = {}
	if not _guardian_pending.is_empty():
		job = _guardian_pending.pop_front()
	var fb: String = String(job.get("fallback", ""))
	var cache_key: String = String(job.get("cache_key", ""))
	var tier: String = String(job.get("tier", "ollama"))
	var ctx: Dictionary = job.get("context", {})
	var line: String = fb
	var ok: bool = result == HTTPRequest.RESULT_SUCCESS and code == 200
	if ok:
		var outer: Dictionary = _parse_ollama_outer(body)
		if not outer.is_empty():
			var raw: String = String(outer.get("response", ""))
			if raw.length() > OLLAMA_PARSE_MAX_BYTES:
				raw = raw.substr(0, OLLAMA_PARSE_MAX_BYTES)
			var max_w: int = GUARDIAN_MAX_WORDS
			if bool(job.get("is_thought", false)):
				max_w = MindNarrator.FISH_THOUGHT_MAX_WORDS
			var fin: Dictionary = MindNarrator.finalize_line(ctx, raw, fb, max_w)
			line = String(fin.get("line", fb))
	elif tier == "embedded" and enabled and conn_state == ConnState.OK \
			and not bool(job.get("is_thought", false)):
		_guardian_pending.push_front({
			"context": ctx.duplicate(true),
			"fallback": fb,
			"cache_key": cache_key,
			"endpoint": endpoint,
			"model": model,
			"tier": "ollama",
		})
		if not _guardian_pending.is_empty():
			_request_guardian_line()
		return
	if line == "" or line.length() < 3:
		line = fb
	if bool(job.get("is_thought", false)):
		if line != fb and cache_key != "":
			_cache_thought(cache_key, line, String(job.get("fish_id", "")))
	elif line != fb and cache_key != "":
		_cache_guardian_line(cache_key, line)
		emit_signal("guardian_line_ready", cache_key, line, tier)
	if not _guardian_pending.is_empty():
		_request_guardian_line()


func _build_guardian_prompt(ctx: Dictionary) -> String:
	return MindNarrator.build_guardian_prompt(ctx, _voice_lang_code())


func _cache_guardian_line(cache_key: String, line: String) -> void:
	if cache_key == "" or line.strip_edges() == "":
		return
	_guardian_line_cache[cache_key] = line.strip_edges()
	while _guardian_line_cache.size() > GUARDIAN_LINE_CACHE_MAX:
		var oldest: String = String(_guardian_line_cache.keys()[0])
		_guardian_line_cache.erase(oldest)


func _sanitize_guardian_output(text: String) -> String:
	return MindNarrator.sanitize_prose(text, GUARDIAN_MAX_WORDS)


func _guardian_seed(cache_key: String) -> int:
	var h: int = 0
	for i in cache_key.length():
		h = (h * 31 + cache_key.unicode_at(i)) & 0x7fffffff
	return h if h > 0 else 1


func _thought_cache_key(f: Fish, situation: String) -> String:
	var fid: String = String(f.id)
	var feel: String = FishMind.emotional_state(f)
	var vseed: int = MindNarrator.voice_style_seed(fid, f.personality)
	return "%s|%s|%s|v%d" % [fid, situation, feel, vseed]


func export_voice_caches() -> Dictionary:
	return {
		"guardian": _guardian_line_cache.duplicate(true),
		"thought": _thought_cache.duplicate(true),
		"bio": _bio_results.duplicate(true),
	}


func import_voice_caches(d: Dictionary) -> void:
	var g: Variant = d.get("guardian", null)
	if g is Dictionary:
		_guardian_line_cache = (g as Dictionary).duplicate(true)
	var t: Variant = d.get("thought", null)
	if t is Dictionary:
		_thought_cache = (t as Dictionary).duplicate(true)
	var b: Variant = d.get("bio", null)
	if b is Dictionary:
		_bio_results = (b as Dictionary).duplicate(true)
