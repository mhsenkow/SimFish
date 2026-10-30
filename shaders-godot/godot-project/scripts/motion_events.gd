class_name MotionEvents
extends RefCounted

# A tiny bus for motion moments (CREATURE_MOTION_700 #61): dart_started,
# strike, gulp, landed, flip, clamped, startled, wall_bump. Audio, particles,
# the camera and neighbours subscribe instead of each reaction being wired by
# hand. Static so any creature can emit without a reference to the world.
#
# A short ring of recent events backs the debug overlay and smokes.

const RECENT_MAX: int = 64

static var _subs: Dictionary = {}
static var _recent: Array[Dictionary] = []
static var enabled: bool = true


static func subscribe(kind: StringName, callable: Callable) -> void:
	var list: Array = _subs.get(kind, [])
	if not list.has(callable):
		list.append(callable)
	_subs[kind] = list


static func unsubscribe(kind: StringName, callable: Callable) -> void:
	var list: Array = _subs.get(kind, [])
	list.erase(callable)


static func emit(kind: StringName, source: Object, position: Vector3, strength: float = 1.0,
		extra: Dictionary = {}) -> void:
	if not enabled:
		return
	var ev: Dictionary = {
		"kind": kind, "source_id": source.get_instance_id() if source != null else 0,
		"position": position, "strength": strength,
		"time_ms": Time.get_ticks_msec(),
	}
	if not extra.is_empty():
		ev.merge(extra)
	_recent.append(ev)
	if _recent.size() > RECENT_MAX:
		_recent.pop_front()
	var list: Array = _subs.get(kind, [])
	for i in range(list.size() - 1, -1, -1):
		var c: Callable = list[i]
		if not c.is_valid():
			list.remove_at(i)
			continue
		c.call(ev)


static func recent(kind: StringName = &"") -> Array[Dictionary]:
	if kind == &"":
		return _recent.duplicate()
	var out: Array[Dictionary] = []
	for ev in _recent:
		if ev["kind"] == kind:
			out.append(ev)
	return out


static func clear() -> void:
	_subs.clear()
	_recent.clear()
