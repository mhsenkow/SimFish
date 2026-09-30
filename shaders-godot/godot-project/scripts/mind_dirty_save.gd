class_name MindDirtySave
extends RefCounted

# PERFORMANCE_UNTHROTTLED #36 — per-fish dirty fields for delta mind saves.

static var _dirty: Dictionary = {}  # fish_id -> PackedStringArray
# mark() is reached from mind worker threads (episodes appended on a
# MindFishProxy carry the real fish id) while the main thread reads/clears
# on save — every access to _dirty goes through this lock.
static var _mutex: Mutex = Mutex.new()


static func reset_for_test() -> void:
	_mutex.lock()
	_dirty.clear()
	_mutex.unlock()


static func mark(f, field: String) -> void:
	if f == null or field == "":
		return
	var fid: String = str(f.id)
	if fid == "":
		return
	_mutex.lock()
	var arr: PackedStringArray = _dirty.get(fid, PackedStringArray()) as PackedStringArray
	if not arr.has(field):
		arr.append(field)
	_dirty[fid] = arr
	_mutex.unlock()


static func mark_all_mind(f) -> void:
	mark(f, "full")


static func clear(f) -> void:
	if f == null:
		return
	var fid: String = str(f.id)
	if fid != "":
		_mutex.lock()
		_dirty.erase(fid)
		_mutex.unlock()


static func is_dirty(f) -> bool:
	if f == null:
		return false
	var fid: String = str(f.id)
	if fid == "":
		return false
	_mutex.lock()
	var has: bool = _dirty.has(fid)
	_mutex.unlock()
	return has


static func fields(f: Fish) -> PackedStringArray:
	var fid: String = str(f.id) if f != null else ""
	if fid == "":
		return PackedStringArray()
	_mutex.lock()
	var out: PackedStringArray = (_dirty[fid] as PackedStringArray).duplicate() \
			if _dirty.has(fid) else PackedStringArray()
	_mutex.unlock()
	return out


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
