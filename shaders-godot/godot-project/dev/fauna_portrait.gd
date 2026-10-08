# Close-up visual audit using the game's actual Life Library renderer.
# Run through scripts/dev_run.sh; FAUNA_PORTRAIT_OUT sets the output directory.
extends Node

func _ready() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var cfg := get_node("/root/TankConfig")
	cfg.set("capture_mode", true)
	cfg.call("reset_to_defaults")
	var script: GDScript = load("res://scripts/library_panel.gd")
	var library: PanelContainer = script.new()
	add_child(library)
	library.set_process(false)
	library.call("_resume_preview_rendering")
	var vp: SubViewport = library.get("_preview_viewport")
	vp.size = Vector2i(768, 512)
	var camera: Camera3D = library.get("_preview_cam")
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.35
	camera.position = Vector3(0.9, 0.65, -2.0)
	camera.look_at(Vector3(0, 0.15, 0), Vector3.UP)
	var out: String = OS.get_environment("FAUNA_PORTRAIT_OUT")
	if out == "":
		out = "user://fauna_portraits"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var fish_genome: Dictionary = (cfg.get("SPECIES_LIBRARY") as Dictionary)["guppy"]["genome"].duplicate(true)
	fish_genome["sex"] = 0
	fish_genome["mixed_morphs"] = false
	var cases: Array[Dictionary] = [
		{"id": "fish_guppy", "type": "fish", "g": fish_genome},
		{"id": "shrimp_long", "type": "shrimp", "g": {"body_length_factor": 2.0, "adult_voxel_scale": 0.12, "base_color": Color8(215, 66, 42)}},
		{"id": "shrimp_crab", "type": "shrimp", "g": {"body_shape": "crab", "adult_voxel_scale": 0.12, "eye_stalk_length": 0.7}},
		{"id": "snail_ramshorn", "type": "snail", "g": {"shell_shape": "ramshorn", "shell_color": Color8(210, 72, 45), "shell_size": 1.4}},
		{"id": "snail_tower", "type": "snail", "g": {"shell_shape": "tower", "shell_color": Color8(191, 143, 75), "shell_size": 0.9, "whorl_count": 7}},
	]
	for entry in cases:
		library.call("_load_preview_creature", entry["g"], entry["type"])
		var tower: bool = entry["id"] == "snail_tower"
		camera.size = 1.85 if tower else 1.35
		camera.look_at(Vector3(0, 0.35 if tower else 0.15, 0), Vector3.UP)
		for i in 8:
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path: String = out.path_join(String(entry["id"]) + ".png")
		vp.get_texture().get_image().save_png(path)
		print("[fauna_portrait] ", path)
		if entry["id"] == "fish_guppy":
			camera.position = Vector3(2.0, 0.65, -0.7)
			camera.look_at(Vector3(0, 0.15, 0), Vector3.UP)
			for i in 8:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png(out.path_join("fish_guppy_side.png"))
			camera.position = Vector3(0.9, 0.65, -2.0)
	library.queue_free()
	await get_tree().process_frame
	get_tree().quit()
