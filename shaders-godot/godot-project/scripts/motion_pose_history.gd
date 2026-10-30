class_name MotionPoseHistory
extends RefCounted

# Ring buffer of recent motion samples for one creature (CREATURE_MOTION_700
# #62). Backs onion skins, speed graphs and the curvature overlay (#81–#84)
# and feeds MotionMetrics in probes. Debug only: nothing in the game loop
# depends on it.

var capacity: int = 300
var times: PackedFloat32Array = PackedFloat32Array()
var heads: PackedVector3Array = PackedVector3Array()
var tails: PackedVector3Array = PackedVector3Array()
var speeds: PackedFloat32Array = PackedFloat32Array()
var yaws: PackedFloat32Array = PackedFloat32Array()
var _start: int = 0
var _count: int = 0


func _init(cap: int = 300) -> void:
	capacity = maxi(cap, 2)
	times.resize(capacity)
	heads.resize(capacity)
	tails.resize(capacity)
	speeds.resize(capacity)
	yaws.resize(capacity)


func push(t: float, head: Vector3, tail: Vector3, speed: float, yaw: float) -> void:
	var i: int = (_start + _count) % capacity
	if _count == capacity:
		_start = (_start + 1) % capacity
	else:
		_count += 1
	times[i] = t
	heads[i] = head
	tails[i] = tail
	speeds[i] = speed
	yaws[i] = yaw


func size() -> int:
	return _count


func _index(k: int) -> int:
	return (_start + k) % capacity


func ordered_heads() -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(_count)
	for k in _count:
		out[k] = heads[_index(k)]
	return out


func ordered_tails() -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(_count)
	for k in _count:
		out[k] = tails[_index(k)]
	return out


func ordered_speeds() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_count)
	for k in _count:
		out[k] = speeds[_index(k)]
	return out


func ordered_yaws() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_count)
	for k in _count:
		out[k] = yaws[_index(k)]
	return out


func ordered_times() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_count)
	for k in _count:
		out[k] = times[_index(k)]
	return out


func clear() -> void:
	_start = 0
	_count = 0
