# Tank save/load orchestration extracted from main.gd.
class_name SaveManager
extends RefCounted

static var _writes_in_flight: int = 0
static var _pending_write_path: String = ""
static var _pending_write_payload: Variant = null


static func writes_in_flight() -> int:
	return _writes_in_flight


static func reset_for_test() -> void:
	_writes_in_flight = 0
	_pending_write_path = ""
	_pending_write_payload = null

# AppLog is an autoload, so it is absent in headless --script runs and in any
# static context before the tree exists. Never assume it is there.
# True while dev/visual_capture.gd is driving the app. Reads through the
# autoload rather than a static of its own so there is exactly one switch.
static func _capture_mode(host: Node) -> bool:
	if host == null:
		return false
	var cfg := host.get_node_or_null("/root/TankConfig")
	return cfg != null and bool(cfg.get("capture_mode"))


static func _log() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("AppLog")
	return null


static func try_load(host: Node, sim: Node, world: Node, aquascape: AquascapeController,
		save_restored_flag: StringName) -> void:
	if host.get(save_restored_flag):
		return
	# VISUAL_DIRECTIONS #20 — a capture run builds its tank from a named
	# scenario so the frame is comparable between commits. Restoring the
	# player's saved state would make every capture a different picture.
	if _capture_mode(host):
		host.set(save_restored_flag, true)
		return
	host.set(save_restored_flag, true)
	var saves := host.get_node_or_null("/root/TankSaves")
	if saves == null:
		return
	if not saves.is_active_save_compatible():
		return
	var path: String = saves.state_path(int(saves.active_slot))
	if not FileAccess.file_exists(path):
		return
	var d: Dictionary = saves.read_json(path)
	if d.is_empty():
		if host.has_method("_show_corrupt_save_prompt"):
			host.call("_show_corrupt_save_prompt", path)
		return
	# Schema gate (BROAD_DIRECTIONS #4). A save from a newer build is refused
	# outright rather than loaded with its new fields silently dropped — the
	# next autosave would otherwise write that loss back over the player's
	# tank. This runs before SaveRepair so a refused save is never mutated.
	var mig: Dictionary = SaveMigrations.migrate(d)
	var lg: Node = _log()
	if not bool(mig.get("ok", false)):
		var msg: String = "refusing save at %s: %s (format %d, this build %d)" % [
			path, String(mig.get("reason", "")), int(mig.get("from", -1)),
			SaveMigrations.CURRENT_VERSION,
		]
		if lg != null:
			lg.error("save", msg)
		else:
			push_error("[walstad_loom] %s" % msg)
		if host.has_method("_show_incompatible_save_prompt"):
			host.call("_show_incompatible_save_prompt", path, mig)
		return
	if int(mig.get("from", 0)) != int(mig.get("to", 0)):
		var mmsg: String = "migrated save %s: format %d -> %d" % [
			path, int(mig.get("from", 0)), int(mig.get("to", 0)),
		]
		if lg != null:
			lg.info("save", mmsg)
		else:
			print("[walstad_loom] %s" % mmsg)
	d = mig.get("dict", d)
	d = SaveRepair.sanitize(d)
	if sim != null and sim.has_method("load_state"):
		sim.load_state(d)
	if d.has("terrain") and world != null and world.has_method("terrain_apply_save_dict") \
			and not TankConfig.rebuild_terrain_on_load:
		world.terrain_apply_save_dict(d["terrain"])
		# Terrain sculpt changes surface Y; re-anchor ground plants after overlay.
		if sim != null and sim.has_method("_clamp_loaded_entities"):
			sim.call("_clamp_loaded_entities")
	if TankConfig.rebuild_terrain_on_load:
		TankConfig.rebuild_terrain_on_load = false
		TankConfig.save_to_disk()
	if d.has("aquascape") and aquascape != null:
		aquascape.restore_from_save(d["aquascape"])
	# Re-follow the creature the player was watching (creatures are spawned now).
	if host.has_method("restore_follow_from_save"):
		host.call("restore_follow_from_save", d)
	print_verbose("[walstad_loom] restored save from ", path)


static func save_active(host: Node, sim: Node, world: Node, aquascape: AquascapeController,
		pending_time_scale: float, skip_thumbnail: bool = false) -> float:
	if sim == null or not sim.has_method("save_state"):
		return pending_time_scale
	# Never let a capture run write its synthetic tank over the player's slot.
	if _capture_mode(host):
		return pending_time_scale
	var saves := host.get_node_or_null("/root/TankSaves")
	if saves == null:
		return pending_time_scale
	var live_ts: float = float(sim.time_scale)
	if live_ts > 0.0:
		pending_time_scale = live_ts
	sim.set_save_mind_delta(skip_thumbnail)
	var snap_t0: int = Time.get_ticks_usec()
	var state_d: Dictionary = sim.save_state()
	PerfGovernor.record_ledger(26, Time.get_ticks_usec(), snap_t0)
	sim.set_save_mind_delta(false)
	state_d["sim"]["time_scale"] = pending_time_scale
	# Persist the followed creature (+ mode/scope) so reopening resumes it.
	# save_state() ran _ensure_ids(), so the followed creature already has an id.
	var ft: Variant = host.get("_follow_target")
	if ft != null and is_instance_valid(ft) and ft.get("id") != null and String(ft.id) != "":
		state_d["sim"]["followed_id"] = String(ft.id)
		state_d["sim"]["follow_mode"] = int(host.get("_follow_mode"))
		state_d["sim"]["cycle_scope"] = int(host.get("_cycle_scope"))
	if aquascape != null:
		state_d["aquascape"] = aquascape.to_save_arr()
	if world != null and world.has_method("terrain_to_save_dict"):
		var terrain_d: Dictionary = world.terrain_to_save_dict()
		if not terrain_d.is_empty():
			state_d["terrain"] = terrain_d
	# Stamp the schema version so this file can be migrated or refused later
	# (BROAD_DIRECTIONS #4). Must happen before sanitize_for_json so the
	# stamp survives into the payload.
	SaveMigrations.stamp(state_d)
	var path: String = saves.state_path(int(saves.active_slot))
	var payload: Variant = SaveHelpers.sanitize_for_json(state_d)
	_enqueue_async_write(path, payload)
	if not skip_thumbnail and host.has_method("_save_thumbnail"):
		host.call("_save_thumbnail", saves.thumbnail_path(int(saves.active_slot)))
	var meta: Dictionary = saves.get_tank_meta(int(saves.active_slot))
	if meta.is_empty():
		meta = {
			"name": "Tank %d" % int(saves.active_slot),
			"runtime_s": 0,
			"created_unix": int(Time.get_unix_time_from_system()),
			"last_opened_unix": int(Time.get_unix_time_from_system()),
		}
	meta["runtime_s"] = int(sim.elapsed_runtime_s) if sim.get("elapsed_runtime_s") != null else int(meta.get("runtime_s", 0))
	if sim.get("tank_age_s") != null:
		meta["tank_age_s"] = float(sim.tank_age_s)
	if sim.get("water_chemistry") != null and sim.water_chemistry != null:
		meta["cycle_label"] = WaterChemistry.phase_label(sim.water_chemistry.cycle_phase)
	if sim.has_method("sim_day_label"):
		meta["sim_day_label"] = sim.sim_day_label()
	if sim.get("tank_vitals") != null and sim.tank_vitals is Dictionary:
		var vitals: Dictionary = sim.tank_vitals
		meta["hud_mode"] = String(vitals.get("hud_mode", ""))
	if world != null:
		if world.get("tannins") != null and float(world.tannins) > 0.28:
			meta["ambient_hint"] = "tannins high"
		elif world.get("biofilm_progress") != null and float(world.biofilm_progress) > 0.42:
			meta["ambient_hint"] = "biofilm maturing"
	meta["last_opened_unix"] = int(Time.get_unix_time_from_system())
	saves.update_tank_meta(int(saves.active_slot), meta)
	return pending_time_scale


static func _enqueue_async_write(path: String, payload: Variant) -> void:
	if _writes_in_flight > 0:
		_pending_write_path = path
		_pending_write_payload = payload
		return
	_writes_in_flight += 1
	WorkerThreadPool.add_task(_async_serialize_and_write.bind(path, payload))


static func _async_serialize_and_write(path: String, payload: Variant) -> void:
	var t0: int = Time.get_ticks_usec()
	var json_text: String = JSON.stringify(payload, "  ")
	_async_write_save(path, json_text)
	PerfGovernor.record_ledger(26, t0 + 1200, t0)
	_writes_in_flight = maxi(0, _writes_in_flight - 1)
	if _writes_in_flight == 0 and _pending_write_path != "":
		var next_path: String = _pending_write_path
		var next_payload: Variant = _pending_write_payload
		_pending_write_path = ""
		_pending_write_payload = null
		_enqueue_async_write(next_path, next_payload)


static func _async_write_save(path: String, json_text: String) -> void:
	# Worker thread — no scene tree access; mirror TankSaves.write_text_atomic.
	var base_dir: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)
	var tmp: String = path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		# Worker thread: push_warning is thread-safe, AppLog's file handle is
		# not, so this path deliberately stays on push_warning.
		push_warning("[walstad_loom] async save open failed at %s: err %d" % [tmp, FileAccess.get_open_error()])
		return
	f.store_string(json_text)
	f.close()
	if FileAccess.file_exists(path):
		var bak: String = path + ".bak"
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.copy_absolute(path, bak)
	var err: Error = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_warning("[walstad_loom] async save rename failed at %s: err %d" % [path, err])
