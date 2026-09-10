extends SceneTree

# PLANT_SYSTEMS_50 #2 — leaf thickness is packed in MultiMesh custom R and
# attenuates the fake transmission path without allocating leaf materials.


func _initialize() -> void:
	var failed: Array[String] = []
	var host := Node3D.new()
	root.add_child(host)
	await process_frame
	var plant := Plant.new()
	host.add_child(plant)
	plant.init(8, {"max_height": 14, "leaf_form": "paddle", "asymmetry_seed": 202})
	var batch: VoxelBatch = plant._foliage_batch
	_assert(failed, batch != null and batch._mm.use_custom_data,
		"foliage batch enables custom data")
	var min_t: float = 1.0
	var max_t: float = 0.0
	if batch != null:
		for custom in batch._customs:
			min_t = minf(min_t, custom.r)
			max_t = maxf(max_t, custom.r)
	_assert(failed, min_t >= 0.0 and max_t <= 1.0 and max_t > min_t,
		"baked leaf thickness is normalized and varies")
	var shader_source := FileAccess.get_file_as_string(
		"res://shaders/foliage_mm.gdshader")
	_assert(failed, shader_source.contains("INSTANCE_CUSTOM.r"),
		"shader reads thickness from custom R")
	_assert(failed, shader_source.contains("thin_transmission"),
		"thickness attenuates fake SSS and backlight")
	host.queue_free()
	if failed.is_empty():
		print("SMOKE_PLANT_VISUAL_02_OK")
		quit(0)
		return
	for message in failed:
		push_error(message)
	quit(1)


func _assert(failed: Array[String], condition: bool, message: String) -> void:
	if not condition:
		failed.append(message)
