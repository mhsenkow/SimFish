# Species Library autoload.
#
# Tracks every distinct genotype the player has encountered across fish,
# shrimp, snails, and plants. Two scopes:
#   - tank_entries: discoveries made in the currently-loaded tank. Persisted
#     inside the tank's state.json (saved by SimDriver.save_state, restored by
#     load_state). Cleared when the player switches tanks.
#   - global_entries: cross-tank "pinned" species. Persisted to a single
#     user://species_library_global.json file. Survives tank deletion.
#
# A discovery is keyed by a canonical hash of visible traits so micro-drift
# does not spawn duplicate cards, but real morph changes do.
#
# Call SpeciesLibrary.record_discovery(genome, source) when any organism enters
# the world; the singleton dedupes and emits species_discovered for the HUD
# toast on the FIRST encounter of a given key.

extends Node

signal species_discovered(entry: Dictionary)
signal library_changed

const GLOBAL_PATH := "user://species_library_global.json"
const GLOBAL_VERSION := 2

const ORGANISM_FISH := "fish"
const ORGANISM_SHRIMP := "shrimp"
const ORGANISM_SNAIL := "snail"
const ORGANISM_PLANT := "plant"

var tank_entries: Array = []
var global_entries: Array = []

# Suppression flag for bulk load — sim_driver replays saved entities via load_state.
var _loading: bool = false


func _ready() -> void:
	_load_global()


# ============================================================================
# Discovery
# ============================================================================

# Record a discovery. Returns true iff this is a NEW species_key in tank scope.
func record_discovery(genome: Dictionary, source: String, silent: bool = false) -> bool:
	if genome == null or genome.is_empty():
		return false
	var key: String = species_key(genome)
	var existing: Dictionary = _find_by_key(tank_entries, key)
	if not existing.is_empty():
		existing["count_seen"] = int(existing.get("count_seen", 0)) + 1
		return false

	var entry: Dictionary = _make_entry(genome, key, source)
	tank_entries.append(entry)
	library_changed.emit()
	if not _loading and not silent:
		species_discovered.emit(entry)
	return true


func get_tank_entries() -> Array:
	return tank_entries.duplicate(true)


func get_global_entries() -> Array:
	return global_entries.duplicate(true)


func find_in_tank(key: String) -> Dictionary:
	return _find_by_key(tank_entries, key)


func find_in_global(key: String) -> Dictionary:
	return _find_by_key(global_entries, key)


func is_pinned(key: String) -> bool:
	return not _find_by_key(global_entries, key).is_empty()


func pin_to_global(key: String) -> void:
	if is_pinned(key):
		return
	var src: Dictionary = _find_by_key(tank_entries, key)
	if src.is_empty():
		return
	global_entries.append(src.duplicate(true))
	_save_global()
	library_changed.emit()


func unpin_from_global(key: String) -> void:
	for i in global_entries.size():
		if String(global_entries[i].get("species_key", "")) == key:
			global_entries.remove_at(i)
			_save_global()
			library_changed.emit()
			return


# ============================================================================
# Tank lifecycle hooks (called by SimDriver save/load)
# ============================================================================

func clear_tank() -> void:
	tank_entries.clear()
	library_changed.emit()


func set_tank_entries(entries: Array) -> void:
	_loading = true
	tank_entries = entries.duplicate(true)
	_loading = false
	library_changed.emit()


# ============================================================================
# Genome → canonical key
# ============================================================================

func organism_type(genome: Dictionary) -> String:
	return String(genome.get("organism_type", ORGANISM_FISH))


func parent_keys_for_breeding(genomes: Array) -> Array:
	var out: Array = []
	for g in genomes:
		if g is Dictionary and not (g as Dictionary).is_empty():
			var key: String = make_species_key(g)
			if key != "" and not out.has(key):
				out.append(key)
	return out


func species_key(g: Dictionary) -> String:
	return make_species_key(g)


func make_species_key(g: Dictionary) -> String:
	return _species_key_from_genome(g)


func _species_key_from_genome(g: Dictionary) -> String:
	match organism_type(g):
		ORGANISM_SHRIMP:
			return _species_key_shrimp(g)
		ORGANISM_SNAIL:
			return _species_key_snail(g)
		ORGANISM_PLANT:
			return _species_key_plant(g)
		_:
			return _species_key_fish(g)


func _species_key_fish(g: Dictionary) -> String:
	var parts: Array = [
		"fish",
		String(g.get("species", "?")),
		_color_to_hex(g.get("base_color", Color.WHITE)),
		_color_to_hex(g.get("accent_color", Color.GRAY)),
		_color_to_hex(g.get("tail_color", g.get("accent_color", Color.GRAY))),
		String(g.get("body_shape", "")),
		String(g.get("swim_pattern", "")),
		"ts" + str(int(g.get("tail_shape", 0))),
		"mo" + str(int(g.get("mouth_orientation", 0))),
		"pt" + str(int(g.get("pattern_type", 0))),
		"b" + ("1" if bool(g.get("has_barbels", false)) else "0"),
		"a" + ("1" if bool(g.get("armor_plates", false)) else "0"),
		"ad" + ("1" if bool(g.get("adipose_fin", false)) else "0"),
		"e" + str(int(round(clampf(float(g.get("body_elongation", 1.0)), 0.5, 2.0) * 2.0))),
		"d" + str(int(round(clampf(float(g.get("body_depth_factor", 1.0)), 0.5, 2.0) * 2.0))),
		"h" + str(int(round(clampf(float(g.get("head_proportion", 1.0)), 0.5, 2.0) * 2.0))),
	]
	return "::".join(parts)


func _species_key_shrimp(g: Dictionary) -> String:
	var parts: Array = [
		"shrimp",
		String(g.get("species", "shrimp")),
		_color_to_hex(g.get("base_color", Color.WHITE)),
		_color_to_hex(g.get("accent_color", Color.GRAY)),
		"s" + str(int(round(clampf(float(g.get("adult_voxel_scale", 0.1)), 0.06, 0.2) * 40.0))),
		"c" + ("1" if bool(g.get("is_cleaner", false)) else "0"),
	]
	return "::".join(parts)


func _species_key_snail(g: Dictionary) -> String:
	var parts: Array = [
		"snail",
		_color_to_hex(g.get("shell_color", Color.WHITE)),
		"sz" + str(int(round(clampf(float(g.get("shell_size", 1.0)), 0.5, 1.6) * 4.0))),
		String(g.get("shell_shape", "turbo")),
	]
	return "::".join(parts)


func _species_key_plant(g: Dictionary) -> String:
	var ramp_parts: Array = []
	var ramp: Variant = g.get("ramp_override", [])
	if ramp is Array:
		for c in ramp:
			ramp_parts.append(_color_to_hex(c))
	var parts: Array = [
		"plant",
		String(g.get("species", g.get("leaf_form", "plant"))),
		String(g.get("leaf_form", "column")),
		"h" + str(int(round(float(g.get("max_height", 12)) / 4.0))),
		"r" + str(int(round(float(g.get("growth_rate", 0.18)) * 20.0))),
		"|".join(ramp_parts),
	]
	return "::".join(parts)


# ============================================================================
# Internal
# ============================================================================

func _make_entry(genome: Dictionary, key: String, source: String) -> Dictionary:
	var otype: String = organism_type(genome)
	var display: String = _display_name_for(genome, otype)
	var parent_keys: Array = []
	var pk: Variant = genome.get("parent_keys", [])
	if pk is Array:
		parent_keys = pk.duplicate()
	return {
		"species_key": key,
		"organism_type": otype,
		"display_name": display,
		"species": String(genome.get("species", "")),
		"genome": _genome_to_serialisable(genome),
		"source": source,
		"first_seen_unix": int(Time.get_unix_time_from_system()),
		"count_seen": 1,
		"generation": int(genome.get("generation", 0)),
		"parent_lineage": String(genome.get("parent_lineage", "Founders")),
		"parent_keys": parent_keys,
	}


func _display_name_for(genome: Dictionary, otype: String) -> String:
	match otype:
		ORGANISM_SHRIMP:
			var n: String = String(genome.get("shrimp_name", ""))
			if n != "":
				return n
		ORGANISM_SNAIL:
			var sn: String = String(genome.get("snail_name", ""))
			if sn != "":
				return sn
		ORGANISM_PLANT:
			var pn: String = String(genome.get("plant_name", ""))
			if pn != "":
				return pn
		_:
			var fn: String = String(genome.get("fish_name", ""))
			if fn != "":
				return fn
			if genome.has("_display_name"):
				return String(genome["_display_name"])
	return String(genome.get("species", otype))


func _find_by_key(arr: Array, key: String) -> Dictionary:
	for e in arr:
		if e is Dictionary and String(e.get("species_key", "")) == key:
			return e
	return {}


func _genome_to_serialisable(g: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in g.keys():
		var v: Variant = g[k]
		if v is Color:
			out[k] = [v.r, v.g, v.b, v.a]
		elif k == "ramp_override" and v is Array:
			var ramp_out: Array = []
			for c in v:
				if c is Color:
					ramp_out.append([(c as Color).r, (c as Color).g, (c as Color).b, (c as Color).a])
				else:
					ramp_out.append(c)
			out[k] = ramp_out
		else:
			out[k] = v
	return out


func genome_from_serialisable(g: Dictionary) -> Dictionary:
	const COLOR_KEYS: Array[String] = [
		"base_color", "accent_color", "tail_color", "shell_color",
	]
	var out: Dictionary = {}
	for k in g.keys():
		var v: Variant = g[k]
		if (k in COLOR_KEYS) and v is Array and (v as Array).size() >= 3:
			var arr: Array = v
			out[k] = Color(
				float(arr[0]), float(arr[1]), float(arr[2]),
				float(arr[3]) if arr.size() >= 4 else 1.0)
		elif k == "ramp_override" and v is Array:
			var ramp: Array = []
			for c in v:
				if c is Array and (c as Array).size() >= 3:
					var a: Array = c
					ramp.append(Color(
						float(a[0]), float(a[1]), float(a[2]),
						float(a[3]) if a.size() >= 4 else 1.0))
				else:
					ramp.append(c)
			out[k] = ramp
		else:
			out[k] = v
	return out


func _color_to_hex(c: Variant) -> String:
	if c is Color:
		return (c as Color).to_html(false)
	if c is Array and (c as Array).size() >= 3:
		var a: Array = c
		return Color(float(a[0]), float(a[1]), float(a[2])).to_html(false)
	return "000000"


func _load_global() -> void:
	if not FileAccess.file_exists(GLOBAL_PATH):
		return
	var f := FileAccess.open(GLOBAL_PATH, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	var d: Dictionary = parsed
	var entries: Variant = d.get("entries", [])
	if entries is Array:
		global_entries = entries


func _save_global() -> void:
	var d: Dictionary = {
		"version": GLOBAL_VERSION,
		"saved_unix": int(Time.get_unix_time_from_system()),
		"entries": global_entries,
	}
	var f := FileAccess.open(GLOBAL_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(d, "  "))
	f.close()
