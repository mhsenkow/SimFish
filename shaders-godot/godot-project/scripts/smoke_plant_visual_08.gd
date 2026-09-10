extends SceneTree

func _initialize() -> void:
	var failed: Array[String] = []
	var plant := Plant.new()
	var first := plant._apply_baked_self_occlusion(Color.WHITE, Vector3.ZERO)
	var crowded := first
	for i in 16:
		crowded = plant._apply_baked_self_occlusion(Color.WHITE,
			Vector3(float(i % 2) * 0.05, 0.0, 0.0))
	_assert(failed, crowded.get_luminance() < first.get_luminance(),
		"crowded interior voxels darken at bake time")
	for i in 700:
		plant._apply_baked_self_occlusion(Color.WHITE, Vector3(float(i), 0, 0))
	_assert(failed, plant._crown_density_cells.size() <= Plant.CROWN_DENSITY_CELL_CAP,
		"density cache is capped")
	var source := FileAccess.get_file_as_string("res://scripts/plant.gd")
	_assert(failed, not source.contains("self_occlusion_strength"),
		"self occlusion adds no shader/material state")
	plant.free()
	if failed.is_empty(): print("SMOKE_PLANT_VISUAL_08_OK"); quit(0); return
	for message in failed: push_error(message)
	quit(1)

func _assert(failed: Array[String], condition: bool, message: String) -> void:
	if not condition: failed.append(message)
