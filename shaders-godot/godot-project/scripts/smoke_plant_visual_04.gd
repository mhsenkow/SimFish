extends SceneTree

func _initialize() -> void:
	var failed: Array[String] = []
	for path in ["res://shaders/foliage.gdshader", "res://shaders/foliage_mm.gdshader"]:
		var source := FileAccess.get_file_as_string(path)
		_assert(failed, source.contains("wet_band") and source.contains("wet_view"),
			"%s has bounded view-dependent waterline sheen" % path)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/foliage_mm.gdshader")
	VoxelMat.register_foliage_mm(mat)
	VoxelMat.set_shader_perf_tier(2)
	_assert(failed, float(mat.get_shader_parameter("wet_sheen_strength")) <= 0.10,
		"lowest tier reduces wet sheen")
	VoxelMat.set_shader_perf_tier(0)
	_assert(failed, float(mat.get_shader_parameter("wet_sheen_strength")) >= 0.30,
		"full tier restores wet sheen")
	if failed.is_empty(): print("SMOKE_PLANT_VISUAL_04_OK"); quit(0)
	for message in failed: push_error(message)
	quit(1)

func _assert(failed: Array[String], condition: bool, message: String) -> void:
	if not condition: failed.append(message)
