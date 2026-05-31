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
	if sim != null and sim.has_method("load_state"):
		sim.load_state(d)
	if d.has("terrain") and world != null and world.has_method("terrain_apply_save_dict") \
			and not bool(TankConfig.rebuild_terrain_on_load):
		world.terrain_apply_save_dict(d["terrain"])
	if TankConfig.rebuild_terrain_on_load:
		TankConfig.rebuild_terrain_on_load = false
		TankConfig.save_to_disk()
	if d.has("aquascape") and aquascape != null:
		aquascape.restore_from_save(d["aquascape"])
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
	var state_d: Dictionary = sim.save_state()
	state_d["sim"]["time_scale"] = pending_time_scale
	if aquascape != null:
		state_d["aquascape"] = aquascape.to_save_arr()
	if world != null and world.has_method("terrain_to_save_dict"):
		var terrain_d: Dictionary = world.terrain_to_save_dict()
		if not terrain_d.is_empty():
			state_d["terrain"] = terrain_d
	var path: String = saves.state_path(int(saves.active_slot))
	var err: int = saves.write_text_atomic(path, JSON.stringify(state_d, "  "))
	if err != OK:
		push_warning("[walstad_loom] save failed at %s: err %d" % [path, err])
		return pending_time_scale
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
	meta["last_opened_unix"] = int(Time.get_unix_time_from_system())
	saves.update_tank_meta(int(saves.active_slot), meta)
	return pending_time_scale
