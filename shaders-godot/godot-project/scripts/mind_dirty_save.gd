class_name MindDirtySave
extends RefCounted

# PERFORMANCE_UNTHROTTLED #36 — per-fish dirty fields for delta mind saves.

static var _dirty: Dictionary = {}  # fish_id -> PackedStringArray


static func reset_for_test() -> void:
	_dirty.clear()


static func mark(f: Fish, field: String) -> void:
	if f == null or field == "":
		return
	var fid: String = str(f.id)
	if fid == "":
		return
	var arr: PackedStringArray = _dirty.get(fid, PackedStringArray()) as PackedStringArray
	if not arr.has(field):
		arr.append(field)
	_dirty[fid] = arr


static func mark_all_mind(f: Fish) -> void:
	mark(f, "full")


static func clear(f: Fish) -> void:
	if f == null:
		return
	var fid: String = str(f.id)
	if fid != "":
		_dirty.erase(fid)


static func is_dirty(f: Fish) -> bool:
	if f == null:
		return false
	var fid: String = str(f.id)
	return fid != "" and _dirty.has(fid)


static func fields(f: Fish) -> PackedStringArray:
	var fid: String = str(f.id) if f != null else ""
	if fid == "" or not _dirty.has(fid):
		return PackedStringArray()
	return (_dirty[fid] as PackedStringArray).duplicate()


static func filter_dict(f: Fish, full: Dictionary) -> Dictionary:
	if f == null:
		return full
	if not is_dirty(f):
		return {"schema_version": full.get("schema_version", 1), "delta": false}
	var dirty: PackedStringArray = fields(f)
	if dirty.has("full"):
		clear(f)
		return full
	var out: Dictionary = {"schema_version": full.get("schema_version", 1), "delta": true}
	for field in dirty:
		if full.has(field):
			out[field] = full[field]
	clear(f)
	return out
