extends SceneTree

# SYSTEMIC #19–21 — potato shader tier smoke.

const VoxelMat = preload("res://scripts/voxel_mat.gd")


func _initialize() -> void:
	if not _run_all():
		quit(1)
		return
	print("[smoke_shader_perf] OK")
	quit(0)


func _fail(msg: String) -> bool:
	push_error(msg)
	return false


func _run_all() -> bool:
	VoxelMat.set_shader_perf_tier(2)
	if VoxelMat.shader_perf_tier() != 2:
		return _fail("set_shader_perf_tier failed")
	var mat: ShaderMaterial = VoxelMat.make_substrate_caustic(Color(0.5, 0.4, 0.3))
	if int(mat.get_shader_parameter("blob_shadow_max")) != 16:
		return _fail("potato tier must cap blob shadows at 16")
	VoxelMat.set_shader_perf_tier(0)
	var mat2: ShaderMaterial = VoxelMat.make_substrate_caustic(Color(0.6, 0.5, 0.4))
	if int(mat2.get_shader_parameter("blob_shadow_max")) != 32:
		return _fail("full tier must use 32 blob shadows")
	return true
