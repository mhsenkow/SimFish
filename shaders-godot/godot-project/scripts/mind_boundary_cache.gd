class_name MindBoundaryCache
extends RefCounted

# PERFORMANCE_UNTHROTTLED #59 — boundary clearance at 2 Hz + aquascape invalidation.

const REFRESH_S: float = 0.5

static var _entries: Dictionary = {}  # fish_id -> {t, lateral, vertical}
static var _epoch: int = 0


static func reset_for_test() -> void:
	_entries.clear()
	_epoch = 0


static func invalidate_all() -> void:
	_entries.clear()
	_epoch += 1


static func lateral(f: Fish, gp: Vector3, body_m: float, heading_hint: Vector3) -> Dictionary:
	if f == null:
		return {"clearance": 99.0, "inward": Vector3.ZERO, "body_m": body_m}
	var fid: String = str(f.id)
	var now: float = Time.get_ticks_msec() / 1000.0
	if fid != "" and _entries.has(fid):
		var e: Dictionary = _entries[fid] as Dictionary
		if int(e.get("epoch", -1)) == _epoch and now - float(e.get("t", 0.0)) < REFRESH_S:
			return e.get("lateral", {}) as Dictionary
	var info: Dictionary = f._lateral_boundary_context_uncached(gp, body_m, heading_hint)
	if fid != "":
		var row: Dictionary = _entries.get(fid, {}) as Dictionary
		row["t"] = now
		row["epoch"] = _epoch
		row["lateral"] = info
		_entries[fid] = row
	return info
