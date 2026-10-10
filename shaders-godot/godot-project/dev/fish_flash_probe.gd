# Consecutive shipped frames plus unquantized frames and per-fish state.
# Run only through scripts/dev_run.sh. Set VISUAL_CAPTURE_SEQUENCE_FRAMES.
extends "res://dev/visual_capture.gd"

var _flash_trace: Array[Dictionary] = []
var _flash_previous_us: int = 0


func _apply_scenario(cfg: Node, scenario_id: String) -> void:
	var snapshot: String = OS.get_environment("FISH_FLASH_SLOT_DIR")
	if snapshot.is_empty():
		super._apply_scenario(cfg, scenario_id)
		return
	var sandbox: String = OS.get_environment("GODOT_DEV_SCRATCH_NAME")
	if sandbox.is_empty() or not OS.get_user_data_dir().ends_with(sandbox):
		push_error("[fish_flash_probe] saved-tank capture requires verified dev isolation")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tanks/1"))
	for name_s: String in ["config.cfg", "state.json", "meta.cfg"]:
		var source := FileAccess.open(snapshot.path_join(name_s), FileAccess.READ)
		if source == null:
			push_error("[fish_flash_probe] missing snapshot file: " + name_s)
			get_tree().quit(1)
			return
		var dest := FileAccess.open("user://tanks/1/" + name_s, FileAccess.WRITE)
		dest.store_buffer(source.get_buffer(source.get_length()))
		dest.close()
	get_node("/root/TankSaves").active_slot = 1
	cfg.load_from_disk()
	# SaveManager may restore and save this COPY, never the player's slot.
	cfg.capture_mode = false
	cfg.guardian_voice_enabled = false
	print("[fish_flash_probe] copied saved tank into verified sandbox")


func _process(dt: float) -> void:
	super._process(dt)
	if _main == null or not _world_ready:
		return
	var disable: PackedStringArray = _env("FISH_FLASH_DISABLE", "").split(",", false)
	if disable.is_empty():
		return
	var sim: Node = _main.get("_sim") as Node
	for fish: Fish in sim.fish:
		Fish._walk_fauna_material_nodes(fish, func(_mi: Node, mat: ShaderMaterial) -> void:
			for key: String in disable:
				if mat.get_shader_parameter(key) != null:
					mat.set_shader_parameter(key, 0.0))
		if disable.has("bioluminescence"):
			fish._apply_bioluminescence_uniform(0.0)
		if disable.has("irid_strength"):
			for handle: VoxelBatch.Handle in fish._voxel_builder.handles:
				var custom: Color = handle.custom_data
				custom.a = 0.0
				handle.set_custom_data(custom)
	var post: ShaderMaterial = _quantize_material()
	for key: String in disable:
		if post != null and post.get_shader_parameter(key) != null:
			post.set_shader_parameter(key, 0.0)


func _shoot(angle: Dictionary) -> void:
	var shot_name: String = String(angle["name"])
	var vp: SubViewport = _main.get("sub_viewport") as SubViewport
	var raw: Image = vp.get_texture().get_image()
	var post_vp: SubViewport = _main.get("_post_viewport") as SubViewport
	var final: Image = post_vp.get_texture().get_image() if post_vp != null \
		else get_viewport().get_texture().get_image()
	raw.save_png(OUT_DIR.path_join(shot_name + "_raw.png"))
	final.save_png(OUT_DIR.path_join(shot_name + ".png"))
	var camera: Camera3D = vp.get_camera_3d()
	var sim: Node = _main.get("_sim") as Node
	var states: Array[Dictionary] = []
	for fish: Fish in sim.fish:
		if not is_instance_valid(fish) or camera.is_position_behind(fish.global_position):
			continue
		var pixel: Vector2 = camera.unproject_position(fish.global_position)
		var pigment: Color = Color.BLACK
		var original: Color = Color.BLACK
		var distance: float = INF
		for handle: VoxelBatch.Handle in fish._voxel_builder.handles:
			var source: Color = handle.get_meta("orig_color", handle.base_color)
			if source.a < 0.98:
				continue
			var error: float = Vector3(source.r - fish.base_color.r,
				source.g - fish.base_color.g, source.b - fish.base_color.b).length_squared()
			if error < distance:
				distance = error
				original = source
				pigment = handle.batch._colors[handle.index]
		states.append({"id": fish.get_instance_id(), "species": fish.species,
			"age": fish.age, "maturity": fish._color_maturity, "stress": fish.stress,
			"pallor": fish.spooked, "mood": fish.mood, "dying": fish._dying,
			"pigment": [pigment.r, pigment.g, pigment.b],
			"original": [original.r, original.g, original.b],
			"pixel": [pixel.x, pixel.y], "yaw": fish.rotation.y,
			"position": [fish.global_position.x, fish.global_position.y, fish.global_position.z],
			"bank": fish._bank, "belly": fish._fauna_inst_custom.g,
			"biolum": fish._fauna_inst_custom.r, "display": fish._fauna_inst_custom.b,
			"metallic": fish.metallic_scales})
	var now: int = Time.get_ticks_usec()
	_flash_trace.append({"frame": shot_name, "time_us": now,
		"interval_us": 0 if _flash_previous_us == 0 else now - _flash_previous_us,
		"size": [vp.size.x, vp.size.y], "fish": states})
	_flash_previous_us = now
	if _flash_trace.size() % 20 == 0:
		print("[fish_flash_probe] captured ", _flash_trace.size(), " frames")


func _finish() -> void:
	var file := FileAccess.open(OUT_DIR.path_join("fish_trace.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_flash_trace))
	file.close()
	print("[fish_flash_probe] frames=", _flash_trace.size(), " -> ", OUT_DIR)
	super._finish()
