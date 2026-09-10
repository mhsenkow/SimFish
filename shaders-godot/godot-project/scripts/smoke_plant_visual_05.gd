extends SceneTree

func _initialize() -> void:
	var failed: Array[String] = []
	var plant := Plant.new()
	plant.asymmetry_seed = 77
	var a: float = plant._stable_leaf_phase(Vector3(1.0, 2.0, 3.0), 4)
	var b: float = plant._stable_leaf_phase(Vector3(1.0, 2.0, 3.0), 4)
	var c: float = plant._stable_leaf_phase(Vector3(1.0, 2.0, 3.0), 5)
	_assert(failed, a >= 0.0 and a < 1.0 and is_equal_approx(a, b),
		"leaf phase is stable and normalized")
	_assert(failed, not is_equal_approx(a, c), "neighbor leaves desynchronize")
	var source := FileAccess.get_file_as_string("res://shaders/foliage_mm.gdshader")
	_assert(failed, source.contains("INSTANCE_CUSTOM.g") and source.contains("v_leaf_phase"),
		"shader reads packed per-leaf phase")
	_assert(failed, VoxelMat._foliage_mat_cache.size() <= VoxelMat._CACHE_MAX,
		"phase adds no material variants")
	plant.free()
	if failed.is_empty(): print("SMOKE_PLANT_VISUAL_05_OK"); quit(0)
	for message in failed: push_error(message)
	quit(1)

func _assert(failed: Array[String], condition: bool, message: String) -> void:
	if not condition: failed.append(message)
