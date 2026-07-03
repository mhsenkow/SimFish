class_name ShaderUniformLedger
extends RefCounted

# PERFORMANCE_UNTHROTTLED #77 — debug ratchet for redundant shader uniform writes.

static var _counts: Dictionary = {}
static var _last: Dictionary = {}
static var _enabled: bool = false
static var _window_s: float = 1.0
static var _window_t: float = 0.0


static func reset_for_test() -> void:
	_counts.clear()
	_last.clear()
	_enabled = false
	_window_t = 0.0


static func set_debug(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		_counts.clear()
		_last.clear()


static func tick(dt: float) -> void:
	if not _enabled:
		return
	_window_t += dt
	if _window_t < _window_s:
		return
	_window_t = 0.0
	_counts.clear()


static func write(mat: ShaderMaterial, param: StringName, value: Variant) -> void:
	if mat == null:
		return
	if _enabled:
		var key: String = "%d|%s" % [mat.get_instance_id(), String(param)]
		if _last.has(key) and _values_equal(_last[key], value):
			_counts[key] = int(_counts.get(key, 0)) + 1
		_last[key] = value
	mat.set_shader_parameter(param, value)


static func _values_equal(a: Variant, b: Variant) -> bool:
	if a is Vector3 and b is Vector3:
		return (a as Vector3).is_equal_approx(b as Vector3)
	if a is Color and b is Color:
		return (a as Color).is_equal_approx(b as Color)
	return a == b


static func worst_redundant() -> Dictionary:
	var worst_key: String = ""
	var worst_n: int = 0
	for k in _counts:
		var n: int = int(_counts[k])
		if n > worst_n:
			worst_n = n
			worst_key = str(k)
	return {"key": worst_key, "count": worst_n}


static func smoke_ok(max_per_sec: int = 10) -> bool:
	return int(worst_redundant().get("count", 0)) <= max_per_sec
