class_name TimeAuthority
extends RefCounted

# REFINEMENT_II #73 — one owner for pause / aquascape / focus time_scale freezes.

static var _base_scale: float = 1.0
static var _pause_reasons: Dictionary = {}  # reason -> true


static func reset_for_test() -> void:
	_base_scale = 1.0
	_pause_reasons.clear()


static func set_base_scale(s: float) -> void:
	_base_scale = maxf(0.0, s)
	_apply(null)


static func base_scale() -> float:
	return _base_scale


static func is_paused() -> bool:
	return not _pause_reasons.is_empty()


static func push_pause(sim: Node, reason: String) -> void:
	if reason == "":
		return
	_pause_reasons[reason] = true
	_apply(sim)


static func pop_pause(sim: Node, reason: String) -> void:
	_pause_reasons.erase(reason)
	_apply(sim)


static func _apply(sim: Node) -> void:
	if sim == null:
		return
	if not _pause_reasons.is_empty():
		sim.time_scale = 0.0
	else:
		sim.time_scale = _base_scale
