extends SceneTree

# PLANT_SYSTEMS_50 #22 — large leaf uploads retain all stable handles while
# GPU writes are consumed in bounded chunks and become visible in one flush.

const PlantScript := preload("res://scripts/plant.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	var host := Node3D.new()
	root.add_child(host)
	var plant: Plant = PlantScript.new()
	host.add_child(plant)
	plant.init(0, {"leaf_form": "column", "max_height": 8})

	var template: Array = LeafShapes.get_leaf_template("pinnate", {
		"length": 7, "quilted": false})
	TestSupport.check(failed, template.size() > Plant.LEAF_BAKE_DEFER_THRESHOLD,
		"fixture exceeds deferred threshold")
	var handles: Array = plant._bake_leaf_template(
		Transform3D.IDENTITY, template, Plant.PLANT_RAMP, 0.0, {})
	TestSupport.check(failed, handles.size() == template.size(),
		"every descriptor receives a biological handle immediately")
	for handle in handles:
		var h: VoxelBatch.Handle = handle
		TestSupport.check(failed, h != null and h.alive and h.index >= 0,
			"reserved handle remains live and indexed")

	var batch: VoxelBatch = plant._foliage_batch
	TestSupport.check(failed, batch.has_deferred_writes(),
		"large bake remains queued after its first chunk")
	TestSupport.check(failed, batch._mm.visible_instance_count == 0,
		"partial leaf is not exposed")
	var passes: int = 1
	while batch.has_deferred_writes() and passes < 20:
		var wrote: int = batch.process_deferred_writes(Plant.LEAF_BAKE_CHUNK_SIZE)
		TestSupport.check(failed, wrote <= Plant.LEAF_BAKE_CHUNK_SIZE,
			"each pass stays within chunk budget")
		passes += 1
	TestSupport.check(failed, not batch.has_deferred_writes(), "queue drains")
	TestSupport.check(failed, batch._mm.visible_instance_count == handles.size(),
		"final drain flushes the complete leaf once")
	TestSupport.check(failed, passes > 1, "upload spans multiple budget passes")

	plant.free()
	host.free()
	quit(TestSupport.report("smoke_plant_amortized_bake", failed))
