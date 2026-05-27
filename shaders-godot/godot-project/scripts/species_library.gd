# Species Library autoload.
#
# Tracks every distinct fish genotype the player has encountered. Two scopes:
#   - tank_entries: discoveries made in the currently-loaded tank. Persisted
#     inside the tank's state.json (saved by SimDriver.save_state, restored by
#     load_state). Cleared when the player switches tanks.
#   - global_entries: cross-tank "pinned" species. Persisted to a single
#     user://species_library_global.json file. Survives tank deletion.
#
# A discovery is keyed by a canonical hash of the genome's visible shape +
# discrete traits (colors, body shape, tail shape, swim pattern, etc.) so
# micro-drift (gen-over-gen body_elongation jitter) does not produce a
# different entry, but a real morph change does. This mirrors the
# perceptual rule that fish.gd's morph_label() uses.
#
# Call SpeciesLibrary.record_discovery(genome, source) anywhere a Fish enters
# the world; the singleton dedupes and emits species_discovered for the HUD
# toast on the FIRST encounter of a given key.

extends Node

signal species_discovered(entry: Dictionary)
signal library_changed

const GLOBAL_PATH := "user://species_library_global.json"
const GLOBAL_VERSION := 1

var tank_entries: Array = []
var global_entries: Array = []

# Suppression flag for bulk load — sim_driver replays saved fish via load_state,
# which calls register_fish for every restored individual. We don't want to
# fire "discovered!" toasts for all of them. set_tank_entries() sets this,
# and the next batch of register_fish calls is treated as silent re-discovery
# (they all already exist).
var _loading: bool = false


func _ready() -> void:
	_load_global()


# ============================================================================
# Discovery
# ============================================================================

# Record a discovery. Returns true iff this is a NEW species_key in tank scope
# (i.e. worth flashing a toast). Idempotent — repeated calls with the same
# genome just bump count_seen.
func record_discovery(genome: Dictionary, source: String) -> bool:
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
	if not _loading:
		species_discovered.emit(entry)
	return true


# Snapshot helpers — caller gets stable copies, mutating them won't reach in.
func get_tank_entries() -> Array:
	return tank_entries.duplicate(true)


func get_global_entries() -> Array:
	return global_entries.duplicate(true)


# Lookup by canonical key. Returns {} if not present.
func find_in_tank(key: String) -> Dictionary:
	return _find_by_key(tank_entries, key)


func find_in_global(key: String) -> Dictionary:
	return _find_by_key(global_entries, key)


func is_pinned(key: String) -> bool:
	return not _find_by_key(global_entries, key).is_empty()


# Promote an entry from tank scope to global. Idempotent.
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


# Bulk restore from a saved state.json. Each element is the same dict shape
# that record_discovery emits. Silences species_discovered for the load.
func set_tank_entries(entries: Array) -> void:
	_loading = true
	tank_entries = entries.duplicate(true)
	_loading = false
	library_changed.emit()


# ============================================================================
# Genome → canonical key
# ============================================================================

# Stable string id for a genome. Only includes fields that meaningfully
# change the perceived species: colors, skeleton discrete traits, body
# shape coarse buckets, swim pattern. Continuous params are coarsely
# bucketed so generation-to-generation drift folds into the same key.
func species_key(g: Dictionary) -> String:
	var parts: Array = [
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
		# Coarse buckets on continuous body params — 4 buckets each.
		"e" + str(int(round(clampf(float(g.get("body_elongation", 1.0)), 0.5, 2.0) * 2.0))),
		"d" + str(int(round(clampf(float(g.get("body_depth_factor", 1.0)), 0.5, 2.0) * 2.0))),
		"h" + str(int(round(clampf(float(g.get("head_proportion", 1.0)), 0.5, 2.0) * 2.0))),
	]
	return "::".join(parts)


# ============================================================================
# Internal
# ============================================================================

func _make_entry(genome: Dictionary, key: String, source: String) -> Dictionary:
	var display: String = String(genome.get("fish_name", ""))
	if display == "":
		display = String(genome.get("_display_name", ""))
	if display == "":
		display = String(genome.get("species", "fish"))
	return {
		"species_key": key,
		"display_name": display,
		"species": String(genome.get("species", "")),
		"genome": _genome_to_serialisable(genome),
		"source": source,
		"first_seen_unix": int(Time.get_unix_time_from_system()),
		"count_seen": 1,
		"generation": int(genome.get("generation", 0)),
	}


func _find_by_key(arr: Array, key: String) -> Dictionary:
	for e in arr:
		if e is Dictionary and String(e.get("species_key", "")) == key:
			return e
	return {}


# Colors are not JSON-serialisable directly. Convert to [r,g,b] arrays so the
# entry can be round-tripped through state.json without losing the tint.
func _genome_to_serialisable(g: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in g.keys():
		var v: Variant = g[k]
		if v is Color:
			out[k] = [v.r, v.g, v.b, v.a]
		else:
			out[k] = v
	return out


# Inverse of _genome_to_serialisable. Used when restoring from JSON.
static func genome_from_serialisable(g: Dictionary) -> Dictionary:
	const COLOR_KEYS: Array[String] = ["base_color", "accent_color", "tail_color"]
	var out: Dictionary = {}
	for k in g.keys():
		var v: Variant = g[k]
		if (k in COLOR_KEYS) and v is Array and (v as Array).size() >= 3:
			var arr: Array = v
			out[k] = Color(
				float(arr[0]), float(arr[1]), float(arr[2]),
				float(arr[3]) if arr.size() >= 4 else 1.0)
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


# ---- Global persistence -----------------------------------------------------

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
