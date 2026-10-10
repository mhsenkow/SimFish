# GPU check that fresh lighting is transported through water after shading.
# scripts/dev_run.sh --script res://dev/water_extinction_probe.gd
extends SceneTree

var _viewport: SubViewport
var _output: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("TankConfig").capture_mode = true
	_output = OS.get_environment("WATER_EXTINCTION_OUT")
	if _output.is_empty():
		_output = "user://water_extinction_probe"
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
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.0
	scene.add_child(camera)
	camera.position = Vector3(0, 3, 0)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	RenderingServer.global_shader_parameter_set("iaq_beam_origin", Vector3(0, 3, 0))
	RenderingServer.global_shader_parameter_set("iaq_beam_dir", Vector3.DOWN)
	RenderingServer.global_shader_parameter_set("iaq_beam_axis", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_beam_cone", Vector4(0.6, 0.9, 12, 0.5))
	RenderingServer.global_shader_parameter_set("iaq_beam_tint", Vector4(1, 1, 1, 0))
	RenderingServer.global_shader_parameter_set("iaq_room_light", 1.0)
	RenderingServer.global_shader_parameter_set("iaq_sun_light", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_moon_light", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_accent1", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_accent2", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_backlight", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_occluder_info", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_water_body", Vector4(0, 0, 0, 2))
	RenderingServer.global_shader_parameter_set("iaq_water_depth", Vector4(1, 1, 2, 2))
	var tests := TestSupport.Suite.new("water_extinction_probe")
	var rows: Array[Dictionary] = []
	for shader_name: String in ["voxel_mm", "foliage", "foliage_mm", "floater_roots"]:
		var host := Node3D.new()
		scene.add_child(host)
		var material := ShaderMaterial.new()
		material.shader = load("res://shaders/%s.gdshader" % shader_name)
		material.set_shader_parameter("albedo", Color(0.35, 0.30, 0.24))
		for key: String in ["sway_amplitude", "flutter_amplitude", "sway_amount", "sway_speed",
				"flow_strength", "wet_sheen_strength", "sss_strength", "aquatic_caustic_intensity"]:
			material.set_shader_parameter(key, 0.0)
		var batch: VoxelBatch = null
		if shader_name == "floater_roots":
			var roots := MeshInstance3D.new()
			roots.mesh = _root_patch()
			roots.material_override = material
			host.add_child(roots)
		else:
			batch = VoxelBatch.new(host, material, 1, true)
			batch.add(Transform3D(Basis.from_scale(Vector3(1, 0.02, 1)), Vector3(0, -0.01, 0)),
				Color(0.35, 0.30, 0.24))
			batch.flush()
		RenderingServer.global_shader_parameter_set("iaq_water_absorb", Vector4.ZERO)
		var clear: Color = await _sample(shader_name + "_clear")
		# Deliberately strong diagnostic coefficients make bypassing the water
		# visible. They are test stimuli, not shipped aquarium coefficients.
		RenderingServer.global_shader_parameter_set("iaq_water_absorb", Vector4(0.8, 0.1, 0.05, 1))
		var absorbed: Color = await _sample(shader_name + "_absorbed")
		tests.check(clear.get_luminance() > 0.1, "%s has actual direct light to transport" % shader_name)
		tests.check(absorbed.r < clear.r * 0.65,
			"%s newly reflected highlights do not bypass red extinction" % shader_name)
		tests.check(absorbed.b / maxf(clear.b, 0.001) > absorbed.r / maxf(clear.r, 0.001) + 0.15,
			"%s transports different wavelengths by different amounts" % shader_name)
		rows.append({"shader": shader_name, "clear": [clear.r, clear.g, clear.b],
			"absorbed": [absorbed.r, absorbed.g, absorbed.b]})
		if batch != null:
			batch.queue_free()
		host.queue_free()
		await process_frame
	var file := FileAccess.open(_output.path_join("measurements.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	file.close()
	print("[water_extinction_probe] ", JSON.stringify(rows))
	var result: int = tests.finish()
	_viewport.queue_free()
	await process_frame
	quit(result)


func _root_patch() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(-1, 0), Vector2(1, 0), Vector2(1, 1), Vector2(-1, 1)])
	arrays[Mesh.ARRAY_TEX_UV2] = PackedVector2Array([Vector2(0, 1), Vector2(0, 1), Vector2(0, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([
		Color(0.35, 0.30, 0.24), Color(0.35, 0.30, 0.24), Color(0.35, 0.30, 0.24), Color(0.35, 0.30, 0.24)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _sample(label_text: String) -> Color:
	await process_frame
	await RenderingServer.frame_post_draw
	var pixels: Image = _viewport.get_texture().get_image()
	pixels.save_png(_output.path_join(label_text + ".png"))
	return pixels.get_pixel(64, 64)
