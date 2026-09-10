extends SceneTree

func _initialize() -> void:
	var failed: Array[String] = []
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/foliage_mm.gdshader")
	VoxelMat.register_foliage_mm(mat)
	VoxelMat.update_foliage_gust(Vector3(2, 1, 3), 20.0, 9.0, Vector3.RIGHT, 4.0)
	var wave: Vector4 = mat.get_shader_parameter("gust_wave")
	_assert(failed, is_equal_approx(wave.w, 8.0), "gust radius is capped")
	_assert(failed, is_equal_approx(float(mat.get_shader_parameter("gust_age")), 3.0),
		"gust age is capped")
	_assert(failed, is_equal_approx(float(mat.get_shader_parameter("gust_strength")), 1.0),
		"gust strength is capped")
	var source := FileAccess.get_file_as_string("res://shaders/foliage_mm.gdshader")
	_assert(failed, source.contains("gust_front") and source.contains("gust_fade"),
		"shader contains bounded propagating front")
	var world_source := FileAccess.get_file_as_string("res://scripts/world.gd")
	_assert(failed, world_source.contains("reduced_motion_enabled()"),
		"CPU gust respects reduced motion")
	if failed.is_empty(): print("SMOKE_PLANT_VISUAL_06_OK"); quit(0)
	for message in failed: push_error(message)
	quit(1)

func _assert(failed: Array[String], condition: bool, message: String) -> void:
	if not condition: failed.append(message)
