extends SceneTree

func _initialize() -> void:
	var failed: Array[String] = []
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/foliage_mm.gdshader")
	VoxelMat.register_foliage_mm(mat)
	VoxelMat.set_shader_perf_tier(0)
	VoxelMat.update_foliage_golden_hour(0.8, Vector3(1, -1, 0), false)
	_assert(failed, is_equal_approx(float(mat.get_shader_parameter("golden_hour")), 0.8),
		"full tier receives dawn/dusk rim")
	VoxelMat.update_foliage_golden_hour(0.8, Vector3(1, -1, 0), true)
	_assert(failed, float(mat.get_shader_parameter("golden_hour")) < 0.35,
		"reduced setting restrains rim")
	VoxelMat.set_shader_perf_tier(2)
	VoxelMat.update_foliage_golden_hour(0.8, Vector3(1, -1, 0), false)
	_assert(failed, is_zero_approx(float(mat.get_shader_parameter("golden_hour"))),
		"lowest tier disables rim")
	for path in ["res://shaders/foliage.gdshader", "res://shaders/foliage_mm.gdshader"]:
		var source := FileAccess.get_file_as_string(path)
		_assert(failed, source.contains("sun_edge") and source.contains("foliage_light_dir"),
			"%s has restrained directional rim" % path)
	if failed.is_empty(): print("SMOKE_PLANT_VISUAL_13_OK"); quit(0); return
	for message in failed: push_error(message)
	quit(1)

func _assert(failed: Array[String], condition: bool, message: String) -> void:
	if not condition: failed.append(message)
