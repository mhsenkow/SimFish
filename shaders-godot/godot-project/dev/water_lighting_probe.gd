# Controlled GPU readback of the shipped water shader, without a live tank.
# Run via scripts/dev_run.sh --script res://dev/water_lighting_probe.gd.
extends SceneTree

var _viewport: SubViewport
var _material: ShaderMaterial
var _camera: Camera3D
var _output: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true
	cfg.guardian_voice_enabled = false
	_output = OS.get_environment("WATER_LIGHTING_OUT")
	if _output.is_empty():
		_output = "user://water_lighting_probe"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(128, 128)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var scene := Node3D.new()
	_viewport.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	scene.add_child(environment)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 1.0
	scene.add_child(_camera)
	_set_view(false)
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/water.gdshader")
	for key: String in ["wave_amplitude", "wave2_amplitude", "wave_speed", "surface_ripple_slope",
			"surface_film", "protein_film", "turbidity_haze", "aerial_haze", "caustic_intensity",
			"surface_spec_gain", "under_reflect", "floor_bounce", "surface_reflection"]:
		_material.set_shader_parameter(key, 0.0)
	_material.set_shader_parameter("aquatic_detail", 3)
	_material.set_shader_parameter("water_surface_y", 0.0)
	_material.set_shader_parameter("water_floor_y", -2.0)
	_material.set_shader_parameter("shallow_color", Color(0.32, 0.46, 0.48, 0.30))
	_material.set_shader_parameter("fixture_world_pos", Vector3(0, 4, 0))
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	mesh.mesh = plane
	mesh.material_override = _material
	scene.add_child(mesh)
	RenderingServer.global_shader_parameter_set("iaq_beam_origin", Vector3(0, 4, 0))
	RenderingServer.global_shader_parameter_set("iaq_beam_dir", Vector3.DOWN)
	RenderingServer.global_shader_parameter_set("iaq_beam_axis", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_beam_tint", Vector4(1, 0.94, 0.82, 0))
	RenderingServer.global_shader_parameter_set("iaq_room_light", 1.0)
	RenderingServer.global_shader_parameter_set("iaq_backlight", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_accent1", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_accent2", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_water_absorb", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_sun_light", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_moon_light", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_sun_tint", Vector4(1, 1, 1, 0))
	RenderingServer.global_shader_parameter_set("iaq_moon_tint", Vector4(0.56, 0.70, 1, 0))
	var suite := TestSupport.Suite.new("water_lighting_probe")
	var rows: Array[Dictionary] = []
	var previous: float = -1.0
	for energy: float in [0.0, 0.00001, 0.05, 0.15, 0.30, 0.50]:
		_set_fixture(energy)
		var row: Dictionary = await _sample("fixture_%.5f" % energy)
		rows.append(row)
		var luminance: float = row["luma"]
		suite.check(luminance >= previous - 0.005,
			"water brightness rises continuously with fixture energy %.5f" % energy)
		suite.in_range(luminance, 0.0, 1.0, "finite water light at %.5f" % energy)
		previous = luminance
	suite.check(float(rows[0]["luma"]) < 0.01, "no source produces no artificial water glow")
	suite.check(absf(float(rows[1]["luma"]) - float(rows[0]["luma"])) < 0.01,
		"an almost-off fixture cannot switch on a full luminous surface")
	suite.check(float(rows[-1]["luma"]) > float(rows[2]["luma"]) + 0.08,
		"the test exercises actual continuous fixture brightness")
	_material.set_shader_parameter("surface_spec_gain", 1.0)
	var reflected: Dictionary = await _sample("top_reflection")
	rows.append(reflected)
	suite.check(float(reflected["luma"]) > float(rows[5]["luma"]) + 0.08,
		"a top-down camera sees the actual surface reflection")
	_set_fixture(0.0)
	var off_reflection: Dictionary = await _sample("top_reflection_off")
	rows.append(off_reflection)
	suite.check(float(off_reflection["luma"]) < 0.01,
		"turning the fixture off removes its specular and specular opacity")
	RenderingServer.global_shader_parameter_set("iaq_beam_tint", Vector4(1, 0.02, 0.02, 0))
	_set_fixture(0.5)
	var red_reflection: Dictionary = await _sample("red_reflection")
	rows.append(red_reflection)
	suite.check(float(red_reflection["rgb"][0]) > float(red_reflection["rgb"][2]) + 0.25,
		"a red source creates a red reflection without an added white spectrum")
	RenderingServer.global_shader_parameter_set("iaq_beam_tint", Vector4(1, 0.94, 0.82, 0))
	_set_fixture(0.0)
	_material.set_shader_parameter("surface_spec_gain", 0.0)
	RenderingServer.global_shader_parameter_set("iaq_sun_light", Vector4(0, 1, 0, 0.65))
	var sunlight: Dictionary = await _sample("sun_only")
	rows.append(sunlight)
	suite.check(float(sunlight["luma"]) > 0.05, "sun alone lights the water")
	RenderingServer.global_shader_parameter_set("iaq_sun_light", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_moon_light", Vector4(0, 1, 0, 0.35))
	var moonlight: Dictionary = await _sample("moon_only")
	rows.append(moonlight)
	suite.check(float(moonlight["luma"]) > 0.025, "moon alone lights the water")
	RenderingServer.global_shader_parameter_set("iaq_moon_light", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_accent1_tint", Vector4(1, 0.02, 0.02, 1))
	RenderingServer.global_shader_parameter_set("iaq_accent1", Vector4(0, 1, 0, 1))
	var accent_near: Dictionary = await _sample("accent1_red_near")
	rows.append(accent_near)
	suite.check(float(accent_near["rgb"][0]) > float(accent_near["rgb"][2]) + 0.06,
		"red accent alone colors the water")
	RenderingServer.global_shader_parameter_set("iaq_accent1", Vector4(0, 4, 0, 1))
	var accent_far: Dictionary = await _sample("accent1_red_far")
	rows.append(accent_far)
	suite.check(float(accent_near["luma"]) > float(accent_far["luma"]) + 0.01,
		"accent illumination attenuates with source distance")
	RenderingServer.global_shader_parameter_set("iaq_accent1", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_accent2_tint", Vector4(0.02, 0.1, 1, 1))
	RenderingServer.global_shader_parameter_set("iaq_accent2", Vector4(0, 1, 0, 1))
	var accent_blue: Dictionary = await _sample("accent2_blue")
	rows.append(accent_blue)
	suite.check(float(accent_blue["rgb"][2]) > float(accent_blue["rgb"][0]) + 0.06,
		"blue accent alone colors the water")
	RenderingServer.global_shader_parameter_set("iaq_accent2", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_beam_tint", Vector4(0, 0, 0, 0))
	_set_fixture(1.0)
	var black: Dictionary = await _sample("black_fixture")
	rows.append(black)
	suite.check(float(black["luma"]) < 0.01, "black fixture RGB does not create white light")
	RenderingServer.global_shader_parameter_set("iaq_beam_tint", Vector4(1, 0.94, 0.82, 0))
	_set_view(true)
	_set_fixture(0.5)
	var underside: Dictionary = await _sample("underside_on")
	rows.append(underside)
	# VIEW and incoming light are exactly opposite here. Their Blinn half
	# vector has zero length and must remain finite even with specular enabled.
	_material.set_shader_parameter("surface_spec_gain", 1.0)
	var opposed: Dictionary = await _sample("underside_opposed_half_vector")
	rows.append(opposed)
	suite.approx(float(opposed["luma"]), float(underside["luma"]),
		"an opposed view/light half vector does not corrupt the underside", 0.015)
	_material.set_shader_parameter("surface_spec_gain", 0.0)
	_set_fixture(0.0)
	var underside_off: Dictionary = await _sample("underside_off")
	rows.append(underside_off)
	suite.check(float(underside["luma"]) > float(underside_off["luma"]) + 0.10,
		"the underside mirror follows real fixture power")
	suite.check(float(underside_off["luma"]) < 0.01,
		"an unlit water ceiling no longer emits a bright silver sheet")
	var file := FileAccess.open(_output.path_join("measurements.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	file.close()
	print("[water_lighting_probe] ", JSON.stringify(rows))
	var result: int = suite.finish()
	_viewport.queue_free()
	await process_frame
	quit(result)


func _set_fixture(energy: float) -> void:
	RenderingServer.global_shader_parameter_set("iaq_beam_cone", Vector4(0.5, 0.9, 20, energy))


func _set_view(under: bool) -> void:
	_camera.position = Vector3(0, -3 if under else 3, 0)
	_camera.look_at(Vector3.ZERO, Vector3.FORWARD)


func _sample(label_text: String) -> Dictionary:
	await process_frame
	await RenderingServer.frame_post_draw
	var image_data: Image = _viewport.get_texture().get_image()
	var rgb := Color(0, 0, 0, 1)
	for y in range(62, 66):
		for x in range(62, 66):
			var color: Color = image_data.get_pixel(x, y)
			rgb.r += color.r / 16.0
			rgb.g += color.g / 16.0
			rgb.b += color.b / 16.0
	image_data.save_png(_output.path_join(label_text + ".png"))
	return {"label": label_text, "rgb": [rgb.r, rgb.g, rgb.b], "luma": rgb.get_luminance()}
