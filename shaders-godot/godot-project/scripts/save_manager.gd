# Tank save/load orchestration extracted from main.gd.
class_name SaveManager
extends RefCounted

static func try_load(host: Node, sim: Node, world: Node, aquascape: AquascapeController,
		save_restored_flag: StringName) -> void:
	if host.get(save_restored_flag):
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
	var saves := host.get_node_or_null("/root/TankSaves")
	if saves == null:
		return pending_time_scale
	var live_ts: float = float(sim.time_scale)
	if live_ts > 0.0:
		pending_time_scale = live_ts
	sim.set_save_mind_delta(skip_thumbnail)
	var state_d: Dictionary = sim.save_state()
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
	var path: String = saves.state_path(int(saves.active_slot))
	var payload: Variant = SaveHelpers.sanitize_for_json(state_d)
	WorkerThreadPool.add_task(_async_serialize_and_write.bind(path, payload))
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


static func _async_serialize_and_write(path: String, payload: Variant) -> void:
	_async_write_save(path, JSON.stringify(payload, "  "))


static func _async_write_save(path: String, json_text: String) -> void:
	# Worker thread — no scene tree access; mirror TankSaves.write_text_atomic.
	var base_dir: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)
	var tmp: String = path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
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
