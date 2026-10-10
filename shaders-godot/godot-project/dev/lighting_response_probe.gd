# Real renderer regression for the shared unshaded lighting path.
# scripts/dev_run.sh --script res://dev/lighting_response_probe.gd
extends SceneTree

var _viewport: SubViewport
var _rows: Array[Dictionary] = []
var _out: String

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("TankConfig").capture_mode = true
	_out = OS.get_environment("LIGHTING_PROBE_OUT")
	if _out.is_empty():
		_out = "user://lighting_response"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(128, 128)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var scene := Node3D.new()
	_viewport.add_child(scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color.BLACK
	scene.add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.0
	scene.add_child(cam)
	cam.position = Vector3(0, 3, 0)
	cam.look_at(Vector3.ZERO, Vector3.FORWARD)
	RenderingServer.global_shader_parameter_set("iaq_beam_origin", Vector3(0, 3, 0))
	RenderingServer.global_shader_parameter_set("iaq_beam_dir", Vector3.DOWN)
	RenderingServer.global_shader_parameter_set("iaq_beam_axis", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_beam_tint", Vector4(1, 0.94, 0.82, 0.45))
	RenderingServer.global_shader_parameter_set("iaq_room_light", 1.0)
	RenderingServer.global_shader_parameter_set("iaq_water_absorb", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_backlight", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_palette_fauna", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_occluder_info", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_beam_falloff", Vector4.ZERO)
	var t := TestSupport.Suite.new("lighting_response_probe")
	for shader_name: String in ["voxel", "voxel_fauna_mm", "foliage_mm", "substrate_opaque"]:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/%s.gdshader" % shader_name)
		mat.set_shader_parameter("albedo", Color(0.32, 0.28, 0.21))
		mat.set_shader_parameter("color_vibrancy", 1.0)
		mat.set_shader_parameter("palette_category", 1)
		mat.set_shader_parameter("fauna_vertex_bend", 0.0)
		mat.set_shader_parameter("sway_strength", 0.0)
		mat.set_shader_parameter("caustic_intensity", 0.0)
		var batch := VoxelBatch.new(scene, mat, 1, true)
		batch.add(Transform3D(Basis.from_scale(Vector3(1, 0.02, 1)), Vector3(0, -0.01, 0)), Color(0.32, 0.28, 0.21))
		batch.flush()
		var in_cone: Array[Color] = []
		var outside: Array[Color] = []
		for energy: float in [0.0, 0.0005, 0.0015, 0.05, 0.25, 0.5, 1.0]:
			RenderingServer.global_shader_parameter_set("iaq_beam_dir", Vector3.DOWN)
			RenderingServer.global_shader_parameter_set("iaq_beam_cone", Vector4(0.6, 0.9, 8, energy))
			in_cone.append(await _sample("%s_in_%.4f" % [shader_name, energy]))
			RenderingServer.global_shader_parameter_set("iaq_beam_dir", Vector3.RIGHT)
			outside.append(await _sample("%s_out_%.4f" % [shader_name, energy]))
		for i in range(1, in_cone.size()):
			t.check(in_cone[i].get_luminance() >= in_cone[i - 1].get_luminance() - 0.01,
				"%s dimmer is monotonic at step %d" % [shader_name, i])
		t.check(absf(in_cone[0].get_luminance() - in_cone[2].get_luminance()) < 0.015,
			"%s zero/faint lamp transition is continuous" % shader_name)
		t.check(absf(outside[0].get_luminance() - outside[5].get_luminance()) < 0.015,
			"%s switching off cannot brighten an unlit corner" % shader_name)
		RenderingServer.global_shader_parameter_set("iaq_beam_dir", Vector3.DOWN)
		RenderingServer.global_shader_parameter_set("iaq_beam_cone", Vector4(0.6, 0.9, 20, 0.5))
		RenderingServer.global_shader_parameter_set("iaq_beam_tint", Vector4(0, 0, 0, 0.45))
		var black_source: Color = await _sample(shader_name + "_black_source")
		t.check(absf(black_source.get_luminance() - outside[0].get_luminance()) < 0.015,
			"%s a black lamp cannot emit grey light" % shader_name)
		RenderingServer.global_shader_parameter_set("iaq_beam_tint", Vector4(1, 0.94, 0.82, 0.45))
		RenderingServer.global_shader_parameter_set("iaq_beam_falloff", Vector4(3, 0.1, 2, 0))
		var near_source: Color = await _sample(shader_name + "_near_source")
		RenderingServer.global_shader_parameter_set("iaq_beam_origin", Vector3(0, 6, 0))
		var far_source: Color = await _sample(shader_name + "_far_source")
		t.check(far_source.get_luminance() < near_source.get_luminance() - 0.01,
			"%s raising a lamp reduces the received flux" % shader_name)
		t.check(far_source.get_luminance() >= outside[0].get_luminance() - 0.01,
			"%s distance falloff preserves room ambient" % shader_name)
		RenderingServer.global_shader_parameter_set("iaq_beam_falloff", Vector4.ZERO)
		RenderingServer.global_shader_parameter_set("iaq_beam_origin", Vector3(0, -3, 0))
		RenderingServer.global_shader_parameter_set("iaq_beam_dir", Vector3.UP)
		var away_face: Color = await _sample(shader_name + "_away_face")
		t.check(away_face.get_luminance() >= outside[0].get_luminance() - 0.01,
			"%s a lamp cannot darken a face pointing away" % shader_name)
		RenderingServer.global_shader_parameter_set("iaq_beam_origin", Vector3(0, 3, 0))
		RenderingServer.global_shader_parameter_set("iaq_beam_cone", Vector4(0.6, 0.9, 8, 0))
		RenderingServer.global_shader_parameter_set("iaq_sun_light", Vector4(0, 1, 0, 1))
		var sun: Color = await _sample(shader_name + "_sun")
		t.check(sun.get_luminance() > outside[0].get_luminance() + 0.005,
			"%s receives real analytic sunlight" % shader_name)
		RenderingServer.global_shader_parameter_set("iaq_sun_light", Vector4.ZERO)
		RenderingServer.global_shader_parameter_set("iaq_moon_light", Vector4(0, 1, 0, 0.8))
		var moon: Color = await _sample(shader_name + "_moon")
		t.check(moon.b > outside[0].b + 0.005, "%s responds to cool moonlight" % shader_name)
		RenderingServer.global_shader_parameter_set("iaq_moon_light", Vector4.ZERO)
		RenderingServer.global_shader_parameter_set("iaq_accent1", Vector4(0, 1, 0, 1))
		RenderingServer.global_shader_parameter_set("iaq_accent1_tint", Vector4(1, 0.1, 0.1, 0.1))
		var accent: Color = await _sample(shader_name + "_accent")
		t.check(accent.r > outside[0].r + 0.01, "%s responds to colored accent light" % shader_name)
		RenderingServer.global_shader_parameter_set("iaq_accent1", Vector4.ZERO)
		RenderingServer.global_shader_parameter_set("iaq_beam_tint", Vector4(1, 1, 1, 0))
		var black: Color = await _sample(shader_name + "_blackout")
		t.check(black.get_luminance() < outside[0].get_luminance() * 0.1,
			"%s master blackout removes ambient light" % shader_name)
		RenderingServer.global_shader_parameter_set("iaq_beam_tint", Vector4(1, 0.94, 0.82, 0.45))
		batch.queue_free()
		await process_frame
	var file := FileAccess.open(_out.path_join("measurements.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_rows, "\t"))
	file.close()
	var status: int = t.finish()
	if OS.get_environment("LIGHTING_PROBE_BASELINE") == "1":
		status = 0
	_viewport.queue_free()
	await process_frame
	quit(status)


func _sample(label: String) -> Color:
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = _viewport.get_texture().get_image()
	var col: Color = img.get_pixel(64, 64)
	_rows.append({"label": label, "rgb": [col.r, col.g, col.b], "luma": col.get_luminance()})
	img.save_png(_out.path_join(label + ".png"))
	return col
