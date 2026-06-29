class_name MindTrace
extends RefCounted

# META #18 — cognition trace bus. A ring buffer of structured per-tick cognitive
# events (focus, ignition, winner count, surprise, prediction error). Powers the
# in-game debugger, the eval harness, and replay inspection — and costs ~nothing
# when no listener is attached (record() no-ops unless explicitly enabled, so it's
# off in normal play).

const CAP: int = 256

static var _enabled: bool = false
static var _ring: Array = []


static func set_enabled(on: bool) -> void:
	_enabled = on
	if not on:
		_ring.clear()


static func is_enabled() -> bool:
	return _enabled


# Append one cognitive event. No-op (and zero allocation) when disabled.
static func record(fish_id: String, event: Dictionary) -> void:
	if not _enabled:
		return
	event["id"] = fish_id
	_ring.append(event)
	while _ring.size() > CAP:
		_ring.remove_at(0)


static func recent(n: int = 32) -> Array:
	if _ring.size() <= n:
		return _ring.duplicate()
	return _ring.slice(_ring.size() - n, _ring.size())


static func size() -> int:
	return _ring.size()


static func clear() -> void:
	_ring.clear()
