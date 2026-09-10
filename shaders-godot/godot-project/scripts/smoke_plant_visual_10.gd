extends SceneTree

func _initialize() -> void:
	var failed: Array[String] = []
	var plant := Plant.new()
	root.add_child(plant)
	await process_frame
	var primary := VoxelBatch.new(plant, StandardMaterial3D.new(), 4, true)
	var old := primary.add(Transform3D(Basis().scaled(Vector3(0.2, 0.1, 0.3)),
		Vector3(0.0, 1.0, 0.0)), Color(0.5, 0.7, 0.3))
	old.set_custom_data(Color(0.4, 0.3, 0.7, 1.0))
	plant._leaf_groups = [[old]]
	plant._migrate_senescent_leaf(0)
	var replacement: VoxelBatch.Handle = plant._leaf_groups[0][0]
	_assert(failed, not old.alive and replacement.alive,
		"migration swaps stable lifecycle handle")
	_assert(failed, replacement.batch == plant._senescence_batch,
		"late leaf uses secondary shared batch")
	_assert(failed, replacement.custom_data == Color(0.4, 0.3, 0.7, 1.0),
		"migration preserves per-leaf custom data")
	_assert(failed, plant._senescence_batch._count == 1,
		"one batch serves migrated leaf voxels")
	plant.queue_free()
	if failed.is_empty(): print("SMOKE_PLANT_VISUAL_10_OK"); quit(0)
	for message in failed: push_error(message)
	quit(1)

func _assert(failed: Array[String], condition: bool, message: String) -> void:
	if not condition: failed.append(message)
