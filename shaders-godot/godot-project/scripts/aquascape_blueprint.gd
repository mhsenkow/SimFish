# Blueprint save, share codes, and local library.
# AQUASCAPING_CRAFT #71–73, #77, #90.
class_name AquascapeBlueprint
extends RefCounted

const PREFIX: String = "WLBP1:"
const PREFIX_V2: String = "WLBP2:"
const LIB_PATH: String = "user://aquascape_blueprints.json"


static func encode_voxels(voxels: Array, meta: Dictionary = {}) -> String:
	if voxels.is_empty():
		return ""
	var compact: Array = AquascapeCraft.compress_voxels(voxels)
	var payload: Dictionary = {
		"v": 2,
		"voxels": compact,
		"meta": meta,
		"author": meta.get("author", ""),
		"lineage": meta.get("lineage", ""),
	}
	var json: String = JSON.stringify(payload)
	var packed: PackedByteArray = json.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	return PREFIX_V2 + Marshalls.raw_to_base64(packed)


static func decode_voxels(code: String) -> Dictionary:
	var c: String = code.strip_edges()
	var is_v2: bool = c.begins_with(PREFIX_V2)
	if not is_v2 and not c.begins_with(PREFIX):
		return {}
	var packed: PackedByteArray = Marshalls.base64_to_raw(
		c.substr((PREFIX_V2 if is_v2 else PREFIX).length()))
	if packed.is_empty():
		return {}
	var raw: PackedByteArray = packed.decompress_dynamic(1 << 20, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not (parsed is Dictionary):
		return {}
	var d: Dictionary = parsed as Dictionary
	if int(d.get("v", 1)) >= 2 and d.get("voxels") is Array:
		d["voxels"] = AquascapeCraft.decompress_voxels(d["voxels"])
	return d


static func load_library() -> Array:
	if not FileAccess.file_exists(LIB_PATH):
		return []
	var f := FileAccess.open(LIB_PATH, FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Array:
		return parsed
	return []


static func save_library(entries: Array) -> void:
	var f := FileAccess.open(LIB_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(entries))


static func add_to_library(name: String, voxels: Array, author: String = "") -> void:
	var lib: Array = load_library()
	lib.append({
		"name": name,
		"voxels": voxels,
		"author": author,
		"created_unix": int(Time.get_unix_time_from_system()),
	})
	save_library(lib)


static func starter_blueprints() -> Array:
	var out: Array = []
	for oid in ["castle", "arch", "torii", "shipwreck", "cave_mouth"]:
		var voxels: Array = AquascapeObjectLibrary.voxels_for(oid)
		if voxels.is_empty():
			continue
		out.append({
			"name": AquascapeObjectLibrary.get_object(oid).get("name", oid),
			"voxels": voxels,
			"author": "walstad loom",
			"starter": true,
		})
	return out


static func load_library_merged() -> Array:
	var lib: Array = load_library()
	for s in starter_blueprints():
		var found: bool = false
		for e in lib:
			if e is Dictionary and String(e.get("name", "")) == String(s.get("name", "")):
				found = true
				break
		if not found:
			lib.append(s)
	return lib


static func remove_from_library(index: int) -> void:
	var lib: Array = load_library()
	if index < 0 or index >= lib.size():
		return
	lib.remove_at(index)
	save_library(lib)


static func showcase_blueprints() -> Array:
	return [
		{
			"name": "Zen gate path",
			"author": "walstad loom",
			"blurb": "Torii + pebbles — calm foreground anchor.",
			"voxels": AquascapeObjectLibrary.voxels_for("torii")
				+ AquascapeObjectLibrary.voxels_for("pebble"),
		},
		{
			"name": "Reef wreck",
			"author": "walstad loom",
			"blurb": "Ship + anchor — swim-through hidey holes.",
			"voxels": AquascapeObjectLibrary.voxels_for("shipwreck"),
		},
		{
			"name": "Tall keep (6 towers)",
			"author": "community",
			"blurb": "Parametric castle — remix-friendly centerpiece.",
			"voxels": AquascapeObjectLibrary.voxels_for("castle", {"towers": 6, "height": 9}),
		},
	]
