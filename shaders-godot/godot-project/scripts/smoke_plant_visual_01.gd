extends SceneTree

# PLANT_SYSTEMS_50 #1 — foliage reuses the bounded aquatic caustic path and
# the lowest shader tier removes its fragment cost.


func _initialize() -> void:
	var failed: Array[String] = []
	for path in [
		"res://shaders/foliage.gdshader",
		"res://shaders/foliage_mm.gdshader",
	]:
		var source: String = FileAccess.get_file_as_string(path)
		TestSupport.check(failed, source.contains("aquatic_caustic_intensity"),
			"%s exposes caustic intensity" % path)
		TestSupport.check(failed, source.contains("cwave = sin"),
			"%s contains bounded lightweight wave math" % path)
		TestSupport.check(failed, not source.contains("for (int"),
			"%s caustic path adds no fragment loops" % path)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/foliage_mm.gdshader") as Shader
	VoxelMat.register_foliage_mm(mat)
	VoxelMat.set_shader_perf_tier(2)
	VoxelMat.update_aquatic_uniforms(0.8, Color(0.6, 0.8, 1.0), 6.5, 0.2, 0.4)
	TestSupport.check(failed, is_zero_approx(float(
		mat.get_shader_parameter("aquatic_caustic_intensity"))),
		"lowest tier disables foliage caustics")
	VoxelMat.set_shader_perf_tier(0)
	VoxelMat.update_aquatic_uniforms(0.65, Color.WHITE, 6.5, 0.1, 0.2)
	TestSupport.check(failed, is_equal_approx(float(
		mat.get_shader_parameter("aquatic_caustic_intensity")), 0.65),
		"higher tiers receive throttled aquatic uniforms")
	if failed.is_empty():
		print("SMOKE_PLANT_VISUAL_01_OK")
		quit(0)
		return
	for message in failed:
		push_error(message)
	quit(1)
