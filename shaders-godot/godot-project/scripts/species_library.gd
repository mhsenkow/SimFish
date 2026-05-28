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


func analyze_organism(organism: String, include_global: bool = true) -> Dictionary:
	var entries: Array = _entries_for_type(organism, include_global)
	if entries.is_empty():
		return {"entry_count": 0, "organism_type": organism}
	match organism:
		ORGANISM_SHRIMP:
			return _analyze_shrimp(entries)
		ORGANISM_SNAIL:
			return _analyze_snail(entries)
		ORGANISM_PLANT:
			return _analyze_plant(entries)
		_:
			return _analyze_fish(entries)


func _entries_for_type(organism: String, include_global: bool) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var sources: Array = [tank_entries]
	if include_global:
		sources.append(global_entries)
	for arr in sources:
		for e in arr:
			if not (e is Dictionary):
				continue
			var d: Dictionary = e
			if String(d.get("organism_type", "")) != organism:
				continue
			var key: String = String(d.get("species_key", ""))
			if key == "" or seen.has(key):
				continue
			seen[key] = true
			out.append(d)
	return out


func _analyze_fish(entries: Array) -> Dictionary:
	var n: int = entries.size()
	var pred_snail_n: int = 0
	var pred_shrimp_n: int = 0
	var armor_n: int = 0
	var barbels_n: int = 0
	var max_gen: int = 0
	var elong_sum: float = 0.0
	var depth_sum: float = 0.0
	var head_sum: float = 0.0
	var fin_sum: float = 0.0
	var speed_sum: float = 0.0
	var claw_sum: float = 0.0
	var size_potential_sum: float = 0.0
	var shape_counts: Dictionary = {}
	for e in entries:
		var g: Dictionary = genome_from_serialisable(e.get("genome", {}))
		if bool(g.get("snail_predator", false)):
			pred_snail_n += 1
		if bool(g.get("shrimp_predator", false)):
			pred_shrimp_n += 1
		if bool(g.get("armor_plates", false)):
			armor_n += 1
		if bool(g.get("has_barbels", false)):
			barbels_n += 1
		max_gen = maxi(max_gen, int(e.get("generation", 0)))
		elong_sum += clampf(float(g.get("body_elongation", 1.0)), 0.5, 2.0)
		depth_sum += clampf(float(g.get("body_depth_factor", 1.0)), 0.5, 2.0)
		head_sum += clampf(float(g.get("head_proportion", 1.0)), 0.5, 2.0)
		fin_sum += clampf(float(g.get("fin_length_factor", 1.0)), 0.5, 2.5)
		speed_sum += clampf(float(g.get("max_speed", 1.2)), 0.4, 3.2)
		claw_sum += clampf(float(g.get("jaw_claw_size", 0.0)), 0.0, 1.2)
		size_potential_sum += clampf(float(g.get("size_potential", 1.0)), 0.6, 2.4)
		var body_shape: String = String(g.get("body_shape", "fusiform"))
		shape_counts[body_shape] = int(shape_counts.get(body_shape, 0)) + 1
	return {
		"organism_type": ORGANISM_FISH,
		"entry_count": n,
		"max_generation": max_gen,
		"snail_predator_ratio": float(pred_snail_n) / float(maxi(1, n)),
		"shrimp_predator_ratio": float(pred_shrimp_n) / float(maxi(1, n)),
		"armor_ratio": float(armor_n) / float(maxi(1, n)),
		"barbels_ratio": float(barbels_n) / float(maxi(1, n)),
		"avg_elongation": elong_sum / float(maxi(1, n)),
		"avg_depth": depth_sum / float(maxi(1, n)),
		"avg_head": head_sum / float(maxi(1, n)),
		"avg_fin_length": fin_sum / float(maxi(1, n)),
		"avg_speed": speed_sum / float(maxi(1, n)),
		"avg_jaw_claw_size": claw_sum / float(maxi(1, n)),
		"avg_size_potential": size_potential_sum / float(maxi(1, n)),
		"dominant_body_shape": _mode_key(shape_counts),
	}


func _analyze_shrimp(entries: Array) -> Dictionary:
	var n: int = entries.size()
	var cleaner_n: int = 0
	var max_gen: int = 0
	var spines_sum: float = 0.0
	var toxin_sum: float = 0.0
	var size_sum: float = 0.0
	var speed_sum: float = 0.0
	var claw_sum: float = 0.0
	var length_sum: float = 0.0
	for e in entries:
		var g: Dictionary = genome_from_serialisable(e.get("genome", {}))
		if bool(g.get("is_cleaner", false)):
			cleaner_n += 1
		max_gen = maxi(max_gen, int(e.get("generation", 0)))
		spines_sum += clampf(float(g.get("defense_spines", 0.0)), 0.0, 1.0)
		toxin_sum += clampf(float(g.get("toxin_level", 0.0)), 0.0, 1.0)
		size_sum += clampf(float(g.get("adult_voxel_scale", 0.10)), 0.06, 0.30)
		speed_sum += clampf(float(g.get("max_speed", 0.85)), 0.4, 1.6)
		claw_sum += clampf(float(g.get("claw_size", 0.25)), 0.0, 1.2)
		length_sum += clampf(float(g.get("body_length_factor", 1.0)), 0.75, 1.7)
	return {
		"organism_type": ORGANISM_SHRIMP,
		"entry_count": n,
		"max_generation": max_gen,
		"cleaner_ratio": float(cleaner_n) / float(maxi(1, n)),
		"avg_spines": spines_sum / float(maxi(1, n)),
		"avg_toxin": toxin_sum / float(maxi(1, n)),
		"avg_size": size_sum / float(maxi(1, n)),
		"avg_speed": speed_sum / float(maxi(1, n)),
		"avg_claw_size": claw_sum / float(maxi(1, n)),
		"avg_length_factor": length_sum / float(maxi(1, n)),
	}


func _analyze_snail(entries: Array) -> Dictionary:
	var n: int = entries.size()
	var max_gen: int = 0
	var size_sum: float = 0.0
	var spines_sum: float = 0.0
	var toxin_sum: float = 0.0
	var shape_counts: Dictionary = {}
	for e in entries:
		var g: Dictionary = genome_from_serialisable(e.get("genome", {}))
		max_gen = maxi(max_gen, int(e.get("generation", 0)))
		size_sum += clampf(float(g.get("shell_size", 1.0)), 0.5, 1.7)
		spines_sum += clampf(float(g.get("shell_spines", 0.0)), 0.0, 1.0)
		toxin_sum += clampf(float(g.get("toxin_level", 0.0)), 0.0, 1.0)
		var shape: String = String(g.get("shell_shape", "turbo"))
		shape_counts[shape] = int(shape_counts.get(shape, 0)) + 1
	return {
		"organism_type": ORGANISM_SNAIL,
		"entry_count": n,
		"max_generation": max_gen,
		"avg_shell_size": size_sum / float(maxi(1, n)),
		"avg_spines": spines_sum / float(maxi(1, n)),
		"avg_toxin": toxin_sum / float(maxi(1, n)),
		"dominant_shell_shape": _mode_key(shape_counts),
	}


func _analyze_plant(entries: Array) -> Dictionary:
	var n: int = entries.size()
	var max_gen: int = 0
	var h_sum: float = 0.0
	var gr_sum: float = 0.0
	var sway_sum: float = 0.0
	var leaf_len_sum: float = 0.0
	var roots_sum: float = 0.0
	var form_counts: Dictionary = {}
	for e in entries:
		var g: Dictionary = genome_from_serialisable(e.get("genome", {}))
		max_gen = maxi(max_gen, int(e.get("generation", 0)))
		h_sum += clampf(float(g.get("max_height", 12.0)), 4.0, 60.0)
		gr_sum += clampf(float(g.get("growth_rate", 0.18)), 0.04, 0.70)
		sway_sum += clampf(float(g.get("sway_amplitude", 0.22)), 0.0, 1.0)
		leaf_len_sum += clampf(float(g.get("leaf_length", 4.0)), 1.0, 18.0)
		roots_sum += clampf(float(g.get("max_roots", 6.0)), 2.0, 18.0)
		var form: String = String(g.get("leaf_form", "column"))
		form_counts[form] = int(form_counts.get(form, 0)) + 1
	return {
		"organism_type": ORGANISM_PLANT,
		"entry_count": n,
		"max_generation": max_gen,
		"avg_height": h_sum / float(maxi(1, n)),
		"avg_growth_rate": gr_sum / float(maxi(1, n)),
		"avg_sway": sway_sum / float(maxi(1, n)),
		"avg_leaf_length": leaf_len_sum / float(maxi(1, n)),
		"avg_max_roots": roots_sum / float(maxi(1, n)),
		"dominant_leaf_form": _mode_key(form_counts),
	}


func _mode_key(counts: Dictionary) -> String:
	var best_key: String = ""
	var best_n: int = -1
	for k in counts.keys():
		var n: int = int(counts.get(k, 0))
		if n > best_n:
			best_n = n
			best_key = String(k)
	return best_key


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
		String(g.get("subspecies_id", g.get("species", "?"))),
		_color_to_hex(g.get("base_color", Color.WHITE)),
		_color_to_hex(g.get("accent_color", Color.GRAY)),
		_color_to_hex(g.get("tail_color", g.get("accent_color", Color.GRAY))),
		_color_to_hex(g.get("marking_color", g.get("accent_color", Color.GRAY))),
		String(g.get("body_shape", "")),
		String(g.get("swim_pattern", "")),
		"ts" + str(int(g.get("tail_shape", 0))),
		"mo" + str(int(g.get("mouth_orientation", 0))),
		"pt" + str(int(g.get("pattern_type", 0))),
		"be" + ("1" if bool(g.get("bar_edged", false)) else "0"),
		"es" + ("1" if bool(g.get("eye_spot", false)) else "0"),
		"vf" + ("1" if bool(g.get("ventral_feelers", false)) else "0"),
		"fn" + str(int(round(clampf(float(g.get("finnage", 1.0)), 1.0, 2.2) * 2.0))),
		"b" + ("1" if bool(g.get("has_barbels", false)) else "0"),
		"a" + ("1" if bool(g.get("armor_plates", false)) else "0"),
		"sp" + ("1" if bool(g.get("snail_predator", false)) else "0"),
		"hp" + ("1" if bool(g.get("shrimp_predator", false)) else "0"),
		"ad" + ("1" if bool(g.get("adipose_fin", false)) else "0"),
		"e" + str(int(round(clampf(float(g.get("body_elongation", 1.0)), 0.5, 2.0) * 2.0))),
		"d" + str(int(round(clampf(float(g.get("body_depth_factor", 1.0)), 0.5, 2.0) * 2.0))),
		"h" + str(int(round(clampf(float(g.get("head_proportion", 1.0)), 0.5, 2.0) * 2.0))),
		"jc" + str(int(round(clampf(float(g.get("jaw_claw_size", 0.0)), 0.0, 1.2) * 6.0))),
		"gp" + str(int(round(clampf(float(g.get("size_potential", 1.0)), 0.6, 2.4) * 4.0))),
	]
	return "::".join(parts)


func _species_key_shrimp(g: Dictionary) -> String:
	var parts: Array = [
		"shrimp",
		String(g.get("species", "shrimp")),
		_color_to_hex(g.get("base_color", Color.WHITE)),
		_color_to_hex(g.get("accent_color", Color.GRAY)),
		"s" + str(int(round(clampf(float(g.get("adult_voxel_scale", 0.1)), 0.06, 0.30) * 30.0))),
		"c" + ("1" if bool(g.get("is_cleaner", false)) else "0"),
		"sp" + str(int(round(clampf(float(g.get("defense_spines", 0.0)), 0.0, 1.0) * 5.0))),
		"tx" + str(int(round(clampf(float(g.get("toxin_level", 0.0)), 0.0, 1.0) * 5.0))),
		"cl" + str(int(round(clampf(float(g.get("claw_size", 0.25)), 0.0, 1.2) * 5.0))),
		"lf" + str(int(round(clampf(float(g.get("body_length_factor", 1.0)), 0.75, 1.7) * 4.0))),
	]
	return "::".join(parts)


func _species_key_snail(g: Dictionary) -> String:
	var parts: Array = [
		"snail",
		_color_to_hex(g.get("shell_color", Color.WHITE)),
		"sz" + str(int(round(clampf(float(g.get("shell_size", 1.0)), 0.5, 1.6) * 4.0))),
		String(g.get("shell_shape", "turbo")),
		"sp" + str(int(round(clampf(float(g.get("shell_spines", 0.0)), 0.0, 1.0) * 5.0))),
		"tx" + str(int(round(clampf(float(g.get("toxin_level", 0.0)), 0.0, 1.0) * 5.0))),
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
				var ss: String = String(genome.get("subspecies_id", ""))
				if ss != "" and ss != String(genome.get("species", "")):
					var parts: PackedStringArray = ss.split(".")
					var tail: String = parts[parts.size() - 1] if parts.size() > 0 else ss
					return "%s · %s" % [fn, tail.right(4)]
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
		"base_color", "accent_color", "tail_color", "marking_color", "shell_color",
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
