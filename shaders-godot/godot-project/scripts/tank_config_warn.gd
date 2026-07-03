class_name TankConfigWarn
extends RefCounted

# REFINEMENT_II #20 — one push_warning per missing config key per session.

static var _warned: Dictionary = {}


static func reset_for_test() -> void:
	_warned.clear()


static func bool_or_warn(cfg: Node, key: String, default: bool) -> bool:
	if cfg == null or cfg.get(key) == null:
		_warn_once(key, default)
		return default
	return bool(cfg.get(key))


static func float_or_warn(cfg: Node, key: String, default: float) -> float:
	if cfg == null or cfg.get(key) == null:
		_warn_once(key, default)
		return default
	return float(cfg.get(key))


static func _warn_once(key: String, default: Variant) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning("[TankConfig] missing '%s' — using default %s" % [key, str(default)])
