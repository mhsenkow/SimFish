extends SceneTree

# PLANT_SYSTEMS_50 #3 — measurement found the dormant stem path had zero
# callers and would add one material per stem plant; batched stems stay on the
# registered foliage material instead.


func _initialize() -> void:
	var failed: Array[String] = []
	_assert(failed, not ResourceLoader.exists(
		"res://shaders/stem_subsurface.gdshader"),
		"dead standalone stem shader is removed")
	var factory := FileAccess.get_file_as_string("res://scripts/voxel_mat.gd")
	_assert(failed, not factory.contains("make_stem("),
		"dead per-call stem material factory is removed")
	var plant_source := FileAccess.get_file_as_string("res://scripts/plant.gd")
	_assert(failed, plant_source.contains(
		"_stem_mat.shader = load(\"res://shaders/foliage_mm.gdshader\")"),
		"batched stems reuse foliage shader")
	_assert(failed, plant_source.contains("register_foliage_mm(_stem_mat)"),
		"stem material remains in bounded uniform registry")
	if failed.is_empty():
		print("SMOKE_PLANT_VISUAL_03_OK")
		quit(0)
		return
	for message in failed:
		push_error(message)
	quit(1)


func _assert(failed: Array[String], condition: bool, message: String) -> void:
	if not condition:
		failed.append(message)
