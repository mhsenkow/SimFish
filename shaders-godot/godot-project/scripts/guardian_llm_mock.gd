extends RefCounted

# META #77 — deterministic stand-in for the in-process model, so smokes and CI
# can drive the full queue → generate → validate → display pipeline headlessly
# with no GDExtension, no GGUF, and no wall-clock nondeterminism.
#
# Enable with the env var WALSTAD_LLM_MOCK=1, or GuardianLlmMock.forced = true
# (then GuardianLlm.enable_mock(true) on the live autoload). Output is a canned
# line picked by prompt hash (same prompt → same line on every machine), unless
# a test registered an override for a cache-key substring. The override text
# HANG_TOKEN simulates a generation that never returns (watchdog tests).

const ENV_VAR: String = "WALSTAD_LLM_MOCK"
const HANG_TOKEN: String = "<<HANG>>"

# Canned lines are chosen to pass the grounding validator in a neutral state
# (they start with "I"/"The" because MindNarrator.validate_line flags any other
# capitalized word as an unknown fish name).
const CANNED: Dictionary = {
	"guardian": [
		"The light moves slow along the glass today.",
		"I kept watch by the front glass for you.",
		"The plants lean toward the light, and I wait with them.",
		"I noticed you at the glass, and the water felt softer.",
	],
	"thought": [
		"I drift under the leaves and watch.",
		"The current carries a small speck past me.",
		"I stay low near the roots for a while.",
		"The others circle, and I follow slowly.",
	],
	"reply": [
		"I hear the sound.",
		"I stay close to you.",
		"The sound feels warm.",
		"I know that sound.",
	],
}

static var forced: bool = false
static var _overrides: Dictionary = {}  # cache-key substring -> raw model text
static var calls: int = 0
static var last_prompt: String = ""
static var last_key: String = ""


static func active() -> bool:
	if forced:
		return true
	var v: String = OS.get_environment(ENV_VAR).strip_edges().to_lower()
	return v in ["1", "true", "yes", "on"]


static func reset() -> void:
	_overrides.clear()
	calls = 0
	last_prompt = ""
	last_key = ""


static func set_override(key_substring: String, raw_text: String) -> void:
	_overrides[key_substring] = raw_text


static func clear_override(key_substring: String) -> void:
	_overrides.erase(key_substring)


static func prompt_hash(prompt: String) -> int:
	# FNV-1a 32-bit — stable across platforms/Godot versions (String.hash() is
	# an engine detail we don't want golden tests to depend on).
	var h: int = 0x811c9dc5
	var bytes: PackedByteArray = prompt.to_utf8_buffer()
	for b in bytes:
		h = ((h ^ int(b)) * 0x01000193) & 0xffffffff
	return h


static func respond(prompt: String, cache_key: String, kind: String) -> String:
	calls += 1
	last_prompt = prompt
	last_key = cache_key
	for k in _overrides.keys():
		if String(k) != "" and cache_key.contains(String(k)):
			return String(_overrides[k])
	var pool: Array = CANNED.get(kind, CANNED["guardian"]) as Array
	return String(pool[prompt_hash(prompt) % pool.size()])
