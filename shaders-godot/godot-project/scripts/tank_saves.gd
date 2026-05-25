# Tank slots manager.
#
# Owns the user://tanks/ directory tree. Each "tank" is a numbered slot
# (1, 2, 3, ...) holding:
#   tanks/<slot>/config.cfg     - the TankConfig fields for this tank
#   tanks/<slot>/meta.cfg       - name, accumulated_runtime_s, created_unix, last_opened_unix
#   tanks/<slot>/state.json     - full SimDriver snapshot (fish/plants/substrate/...)
#   tanks/<slot>/state.json.bak - previous good state, kept around for corruption recovery
#   tanks/<slot>/thumbnail.png  - last-save screenshot, shown on the menu card
#
# tanks/index.cfg lists known slots and the last-opened one so the menu can
# default-select the tank the player was just in.
#
# Registered as an Autoload so any scene can call TankSaves.list_tanks() etc.

extends Node

const TANKS_DIR := "user://tanks"
const INDEX_PATH := "user://tanks/index.cfg"
const LEGACY_CONFIG_PATH := "user://tank_config.cfg"
const STATE_VERSION := 1

# The slot the menu chose; main.tscn reads this on _ready to know which
# state.json to load. Defaults to 1 so a fresh install always has something.
var active_slot: int = 1


func _ready() -> void:
	_ensure_dir(TANKS_DIR)
	_migrate_legacy_if_needed()
	_load_index()


# ---- Public API ----

# Returns Array[Dictionary], one per tank, sorted by last_opened_unix desc.
# Each dict has: { "slot": int, "name": String, "runtime_s": int,
# "created_unix": int, "last_opened_unix": int, "thumbnail_path": String }.
func list_tanks() -> Array:
	var out: Array = []
	var d := DirAccess.open(TANKS_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	while true:
		var name: String = d.get_next()
		if name == "":
			break
		if not d.current_is_dir():
			continue
		if not name.is_valid_int():
			continue
		var slot: int = int(name)
		var meta: Dictionary = _read_meta(slot)
		if meta.is_empty():
			continue
		meta["slot"] = slot
		meta["thumbnail_path"] = TANKS_DIR + "/" + str(slot) + "/thumbnail.png"
		out.append(meta)
	d.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary):
		return int(a.get("last_opened_unix", 0)) > int(b.get("last_opened_unix", 0)))
	return out


# Create an empty new slot. Caller is expected to immediately set TankConfig
# fields (the menu's "+ New tank" flow does this) and then save it.
# Returns the new slot id.
func new_tank(name: String = "New tank") -> int:
	var slot: int = _next_free_slot()
	var dir: String = _slot_dir(slot)
	_ensure_dir(dir)
	var now: int = int(Time.get_unix_time_from_system())
	_write_meta(slot, {
		"name": name,
		"runtime_s": 0,
		"created_unix": now,
		"last_opened_unix": now,
	})
	active_slot = slot
	_save_index()
	return slot


# Duplicate slot's config + meta (but not its state — a clone starts fresh
# with the same parameters but a new seed/spawn). Returns the new slot id.
func duplicate_tank(src_slot: int, new_name: String = "") -> int:
	var src_dir: String = _slot_dir(src_slot)
	var src_meta: Dictionary = _read_meta(src_slot)
	var new_slot: int = _next_free_slot()
	var new_dir: String = _slot_dir(new_slot)
	_ensure_dir(new_dir)
	# Copy config.cfg (so the new tank starts with the same params).
	var cfg_src: String = src_dir + "/config.cfg"
	if FileAccess.file_exists(cfg_src):
		_copy_file(cfg_src, new_dir + "/config.cfg")
	var now: int = int(Time.get_unix_time_from_system())
	var label: String = new_name if new_name != "" else String(src_meta.get("name", "Tank")) + " (copy)"
	_write_meta(new_slot, {
		"name": label,
		"runtime_s": 0,
		"created_unix": now,
		"last_opened_unix": now,
	})
	active_slot = new_slot
	_save_index()
	return new_slot


# Remove a tank slot from disk. Irreversible — caller should confirm.
func delete_tank(slot: int) -> void:
	var dir: String = _slot_dir(slot)
	var d := DirAccess.open(dir)
	if d != null:
		d.list_dir_begin()
		while true:
			var name: String = d.get_next()
			if name == "":
				break
			if d.current_is_dir():
				continue
			d.remove(name)
		d.list_dir_end()
	DirAccess.remove_absolute(dir)
	if active_slot == slot:
		# Fall back to whatever the most-recent remaining tank is, or 1 if
		# nothing's left (a fresh blank slot will be created on next save).
		var rest: Array = list_tanks()
		active_slot = int(rest[0]["slot"]) if rest.size() > 0 else 1
	_save_index()


# Mark a slot active and persist that choice in the index.
func set_active(slot: int) -> void:
	active_slot = slot
	# Touch last_opened so the menu sorts this one to the top next time.
	var meta: Dictionary = _read_meta(slot)
	meta["last_opened_unix"] = int(Time.get_unix_time_from_system())
	_write_meta(slot, meta)
	_save_index()


# ---- File-layout helpers (also used by TankConfig + main.gd) ----

func slot_dir(slot: int) -> String:
	return _slot_dir(slot)


func config_path(slot: int) -> String:
	return _slot_dir(slot) + "/config.cfg"


func state_path(slot: int) -> String:
	return _slot_dir(slot) + "/state.json"


func state_backup_path(slot: int) -> String:
	return _slot_dir(slot) + "/state.json.bak"


func thumbnail_path(slot: int) -> String:
	return _slot_dir(slot) + "/thumbnail.png"


# True if the active slot has a saved state.json on disk that can be
# restored. Used by world.gd to know whether to skip _spawn_initial_*.
func has_state_for_active_slot() -> bool:
	return FileAccess.file_exists(state_path(active_slot))


# Read just enough of the active slot's state.json to extract the saved
# substrate_type. Returns "" if no save exists or it's malformed. Used by
# world.gd to detect a substrate-type change between sessions (e.g. user
# switched a freshwater tank to ocean_sand via Settings) — when that
# happens, the saved freshwater plants don't make sense in the new tank
# and we want to discard them and respawn from scratch.
func peek_saved_substrate_type() -> String:
	var path: String = state_path(active_slot)
	if not FileAccess.file_exists(path):
		return ""
	var d: Dictionary = read_json(path)
	var sim_d: Dictionary = d.get("sim", {})
	return String(sim_d.get("substrate_type", ""))


# Same as peek_saved_substrate_type, but for tank_preset. Returns "" if the
# save predates the preset-in-header change (in which case the preset check
# in is_active_save_compatible is skipped — we don't want to invalidate
# legacy saves that just don't carry the field yet).
func peek_saved_preset() -> String:
	var path: String = state_path(active_slot)
	if not FileAccess.file_exists(path):
		return ""
	var d: Dictionary = read_json(path)
	var sim_d: Dictionary = d.get("sim", {})
	return String(sim_d.get("tank_preset", ""))


# True when state.json exists AND it's safe to restore into the current
# TankConfig. False when there's no save, the save is malformed, or it
# conflicts with the active tank in a way that would produce nonsense
# (substrate mismatch, preset mismatch, or ecology mismatch). World.gd
# uses this to decide between "skip initial spawn + load_state" vs
# "do initial spawn".
func is_active_save_compatible() -> bool:
	if not has_state_for_active_slot():
		return false
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return true  # can't validate, assume OK
	# Substrate mismatch — the original compatibility check. Saltwater corals
	# in a freshwater tank (or vice versa) make no ecological sense.
	var cur: String = String(cfg.substrate_type)
	var saved: String = peek_saved_substrate_type()
	if saved != "" and saved != cur:
		return false
	# Preset mismatch — if the player switched stocking presets (e.g.
	# Community → Tetra School) the saved fish list is stale. Without this
	# check, hitting Apply after a preset change reloaded the OLD fish and
	# the new preset's stocking never spawned, which read as "the preset
	# dropdown doesn't change anything". Empty saved_preset means a legacy
	# save predating this field — skip the check rather than invalidate it.
	var cur_preset: String = String(cfg.tank_preset)
	var saved_preset: String = peek_saved_preset()
	if saved_preset != "" and saved_preset != cur_preset:
		return false
	# Ecological fallback (catches legacy saves that don't have substrate_type
	# in the file header). If the current substrate is saltwater but the
	# saved plants contain no corals, the save is from a freshwater spawn
	# that doesn't make sense in this tank. Same in reverse.
	var cur_is_salt: bool = _substrate_is_saltwater(cur)
	var save_has_coral: bool = _peek_saved_has_coral()
	var save_has_freshwater_plant: bool = _peek_saved_has_freshwater_plant()
	if cur_is_salt and not save_has_coral and save_has_freshwater_plant:
		return false
	if not cur_is_salt and save_has_coral and not save_has_freshwater_plant:
		return false
	return true


func _substrate_is_saltwater(sub_type: String) -> bool:
	# Currently only ocean_sand is saltwater. If new saltwater substrates are
	# added to tank_config.gd, list them here.
	return sub_type == "ocean_sand"


# Cheap peek: reads state.json and reports whether ANY saved plant is a coral.
# Used by the compatibility heuristic above. Returns false if no save exists
# or it can't be parsed (caller treats those as "no coral").
func _peek_saved_has_coral() -> bool:
	var d: Dictionary = read_json(state_path(active_slot))
	for p in d.get("plants", []):
		if p is Dictionary and String(p.get("subclass", "")) == "coral":
			return true
	return false


func _peek_saved_has_freshwater_plant() -> bool:
	var d: Dictionary = read_json(state_path(active_slot))
	for p in d.get("plants", []):
		if not (p is Dictionary):
			continue
		var sub: String = String(p.get("subclass", ""))
		if sub == "plant" or sub == "spiral_plant" or sub == "branch_plant":
			return true
	return false


# Delete the active slot's state.json (and its .bak). Used when we detect
# an incompatible save: the user just changed substrate to a type that
# can't host the previous plants/creatures.
func clear_active_state() -> void:
	var sp: String = state_path(active_slot)
	if FileAccess.file_exists(sp):
		DirAccess.remove_absolute(sp)
	var bp: String = state_backup_path(active_slot)
	if FileAccess.file_exists(bp):
		DirAccess.remove_absolute(bp)


# Atomic write: write to .tmp then rename. Prevents half-written files if
# the OS kills the process mid-save.
func write_text_atomic(path: String, text: String) -> Error:
	_ensure_dir(path.get_base_dir())
	var tmp: String = path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	# Best-effort backup of the previous file before clobbering it. Used by
	# the corruption-recovery flow.
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
	var err: Error = DirAccess.rename_absolute(tmp, path)
	return err


# Read JSON dict from disk. Returns empty dict on parse error.
func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}


# ---- Meta (per-slot small config) ----

func get_tank_meta(slot: int) -> Dictionary:
	return _read_meta(slot)


func update_tank_meta(slot: int, patch: Dictionary) -> void:
	var m: Dictionary = _read_meta(slot)
	for k in patch.keys():
		m[k] = patch[k]
	_write_meta(slot, m)


func _read_meta(slot: int) -> Dictionary:
	var path: String = _slot_dir(slot) + "/meta.cfg"
	if not FileAccess.file_exists(path):
		return {}
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return {}
	return {
		"name": cf.get_value("tank", "name", "Tank %d" % slot),
		"runtime_s": int(cf.get_value("tank", "runtime_s", 0)),
		"created_unix": int(cf.get_value("tank", "created_unix", 0)),
		"last_opened_unix": int(cf.get_value("tank", "last_opened_unix", 0)),
	}


func _write_meta(slot: int, meta: Dictionary) -> void:
	_ensure_dir(_slot_dir(slot))
	var cf := ConfigFile.new()
	cf.set_value("tank", "name", meta.get("name", "Tank %d" % slot))
	cf.set_value("tank", "runtime_s", int(meta.get("runtime_s", 0)))
	cf.set_value("tank", "created_unix", int(meta.get("created_unix", 0)))
	cf.set_value("tank", "last_opened_unix", int(meta.get("last_opened_unix", 0)))
	cf.save(_slot_dir(slot) + "/meta.cfg")


# ---- Internals ----

func _slot_dir(slot: int) -> String:
	return TANKS_DIR + "/" + str(slot)


func _next_free_slot() -> int:
	# Smallest positive integer not already a slot directory.
	var n: int = 1
	while DirAccess.dir_exists_absolute(_slot_dir(n)):
		n += 1
	return n


func _ensure_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)


func _copy_file(src: String, dst: String) -> void:
	DirAccess.copy_absolute(src, dst)


func _load_index() -> void:
	var cf := ConfigFile.new()
	if cf.load(INDEX_PATH) != OK:
		# First launch (after migration). Pick the most-recently-opened tank,
		# or slot 1 if there's nothing.
		var tanks: Array = list_tanks()
		active_slot = int(tanks[0]["slot"]) if tanks.size() > 0 else 1
		return
	active_slot = int(cf.get_value("session", "active_slot", 1))


func _save_index() -> void:
	var cf := ConfigFile.new()
	cf.set_value("session", "active_slot", active_slot)
	cf.save(INDEX_PATH)


# One-shot migration: if the legacy user://tank_config.cfg exists but no
# tanks/1/ has been set up yet, move the legacy file in as slot 1 and write
# its meta. Preserves the player's existing tank across the upgrade.
func _migrate_legacy_if_needed() -> void:
	if not FileAccess.file_exists(LEGACY_CONFIG_PATH):
		return
	if DirAccess.dir_exists_absolute(_slot_dir(1)):
		return
	_ensure_dir(_slot_dir(1))
	_copy_file(LEGACY_CONFIG_PATH, _slot_dir(1) + "/config.cfg")
	var now: int = int(Time.get_unix_time_from_system())
	_write_meta(1, {
		"name": "My tank",
		"runtime_s": 0,
		"created_unix": now,
		"last_opened_unix": now,
	})
	active_slot = 1
	_save_index()
	print_verbose("[tank_saves] migrated legacy tank_config.cfg → tanks/1/")
