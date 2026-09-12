extends SceneTree

# PLANT_SYSTEMS_50 #17 — measured far-foliage consolidation and clean fallback.

const PlantScript := preload("res://scripts/plant.gd")
const FarBatchScript := preload("res://scripts/plant_far_foliage_batch.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	var host := Node3D.new()
	root.add_child(host)
	var camera := Camera3D.new()
	camera.position = Vector3.ZERO
	host.add_child(camera)
	var plants: Array[Plant] = []
	var fixture_handles: Array[VoxelBatch.Handle] = []
	for pi in FarBatchScript.MIN_FAR_PLANTS:
		var plant: Plant = PlantScript.new()
		host.add_child(plant)
		plant.init(0, {"leaf_form": "column", "max_height": 1})
		plant.position = Vector3(50.0 + pi, 0.0, 0.0)
		var batch: VoxelBatch = plant._ensure_foliage_batch()
		for vi in int(ceil(float(FarBatchScript.MIN_INSTANCES)
				/ float(FarBatchScript.MIN_FAR_PLANTS))):
			fixture_handles.append(batch.add(Transform3D(Basis().scaled(Vector3.ONE * 0.08),
				Vector3(float(vi % 10) * 0.1, float(vi / 10) * 0.1, 0.0)),
				Color.GREEN))
		batch.flush()
		plants.append(plant)

	var far_batch: Node3D = FarBatchScript.new()
	host.add_child(far_batch)
	far_batch.update_far_batch(plants, camera, FarBatchScript.REBUILD_INTERVAL_S)
	TestSupport.check(failed, far_batch.last_instance_count >= FarBatchScript.MIN_INSTANCES,
		"population gate measures dense far foliage")
	TestSupport.check(failed, far_batch.last_saved_draws >= FarBatchScript.MIN_FAR_PLANTS - 1,
		"gate records draw calls consolidated")
	if far_batch.last_rebuild_usec <= FarBatchScript.MAX_REBUILD_USEC:
		TestSupport.check(failed, far_batch.enabled_by_profile,
			"measured profitable mirror enables global batch")
		TestSupport.check(failed, not plants[0]._foliage_batch.mmi.visible,
			"private batch hides only after successful mirror")
	var measured_instances: int = far_batch.last_instance_count
	var measured_saved_draws: int = far_batch.last_saved_draws
	var measured_usec: int = far_batch.last_rebuild_usec
	var measured_gate: bool = far_batch.enabled_by_profile

	far_batch.update_far_batch([], camera, FarBatchScript.REBUILD_INTERVAL_S)
	TestSupport.check(failed, not far_batch.enabled_by_profile, "small population falls back")
	TestSupport.check(failed, plants[0]._foliage_batch.mmi.visible,
		"fallback restores private render batches")

	for plant in plants:
		plant.free()
	far_batch.free()
	host.free()
	await process_frame
	quit(TestSupport.report("smoke_plant_far_batch", failed))
