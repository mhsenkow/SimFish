# Controlled rendering of the actual fauna shader at tiny lighting changes.
# Run with scripts/dev_run.sh --script res://dev/fauna_reflection_probe.gd.
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true
	cfg.guardian_voice_enabled = false
	var out_dir: String = OS.get_environment("FAUNA_REFLECTION_OUT")
	if out_dir.is_empty():
		out_dir = "user://fauna_reflection_probe"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var vp := SubViewport.new()
	vp.size = Vector2i(128, 128)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var scene := Node3D.new()
	vp.add_child(scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color.BLACK
	scene.add_child(env)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.0
	scene.add_child(camera)
	camera.position = Vector3(0, 3, 0)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	var material := ShaderMaterial.new()
	var legacy: bool = OS.get_environment("FAUNA_REFLECTION_LEGACY") == "1"
	material.shader = load("res://shaders/voxel.gdshader" if legacy \
		else "res://shaders/voxel_fauna_mm.gdshader")
	if legacy:
		material.set_shader_parameter("albedo", Color(0.35, 0.30, 0.24))
		material.set_shader_parameter("palette_category", 1)
	material.set_shader_parameter("fauna_vertex_bend", 0.0)
	material.set_shader_parameter("color_vibrancy", 1.0)
	var batch := VoxelBatch.new(scene, material, 1, true)
	batch.add(Transform3D(Basis.from_scale(Vector3(1, 0.02, 1)), Vector3(0, -0.01, 0)),
		Color(0.35, 0.30, 0.24))
	batch.flush()
	RenderingServer.global_shader_parameter_set("iaq_beam_origin", Vector3(0, 3, 0))
	RenderingServer.global_shader_parameter_set("iaq_beam_dir", Vector3.DOWN)
	RenderingServer.global_shader_parameter_set("iaq_beam_cone", Vector4(0.6, 0.9, 8, 1))
	RenderingServer.global_shader_parameter_set("iaq_beam_tint", Vector4(1, 0.94, 0.82, 0.45))
	RenderingServer.global_shader_parameter_set("iaq_beam_axis", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_room_light", 1.0)
	RenderingServer.global_shader_parameter_set("iaq_water_absorb", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_backlight", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_palette_fauna", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_occluder_info", Vector4(1, 0.62, 0, 0))
	var occ := Image.create(16, 1, false, Image.FORMAT_RGBAF)
	var tex := ImageTexture.create_from_image(occ)
	RenderingServer.global_shader_parameter_set("iaq_occluder_tex", tex)
	# Pixel centre, not the corner between four pixels. Position the diagnostic
	# sphere exactly one radius above the fragment and move it by a micrometre.
	var pixel := Vector2i(64, 64)
	var ray_origin: Vector3 = camera.project_ray_origin(Vector2(pixel) + Vector2(0.5, 0.5))
	var fragment_pos := Vector3(ray_origin.x, 0, ray_origin.z)
	var rows: Array[Dictionary] = []
	for offset: float in [-0.000001, 0.000001, 0.01, 0.10, 0.25, 0.50]:
		var centre: Vector3 = fragment_pos + Vector3.UP * (0.5 + offset)
		occ.set_pixel(0, 0, Color(centre.x, centre.y, centre.z, 0.5))
		tex.update(occ)
		await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = vp.get_texture().get_image()
		var color: Color = img.get_pixelv(pixel)
		rows.append({"offset": offset, "rgb": [color.r, color.g, color.b],
			"luma": color.get_luminance()})
		img.save_png(out_dir.path_join("shadow_%d.png" % rows.size()))
	var file := FileAccess.open(out_dir.path_join("measurements.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	file.close()
	print("[fauna_reflection_probe] ", JSON.stringify(rows))
	var tests := TestSupport.Suite.new("fauna_reflection_probe")
	var jump: float = absf(float(rows[1]["luma"]) - float(rows[0]["luma"]))
	tests.check(jump < 0.01, "crossing the self-shadow boundary cannot flash a fish surface")
	tests.check(float(rows[1]["luma"]) - float(rows[4]["luma"]) > 0.08,
		"the probe exercises an actual cast shadow, not disabled lighting")
	tests.check(float(rows[0]["luma"]) < 0.80,
		"a brown fish surface keeps a restrained reflected highlight")
	for row: Dictionary in rows:
		tests.in_range(float(row["luma"]), 0.0, 1.0, "rendered reflection stays finite and bounded")
	var result: int = tests.finish()
	batch.queue_free()
	scene.queue_free()
	vp.queue_free()
	await process_frame
	quit(result)
