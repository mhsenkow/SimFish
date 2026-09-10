extends SceneTree

# PLANT_SYSTEMS_50 #15 — reversible, transition-only leaf instance LOD.

const PlantScript := preload("res://scripts/plant.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	var host := Node3D.new()
	root.add_child(host)
	var plant: Plant = PlantScript.new()
	host.add_child(plant)
	plant.init(0, {"leaf_form": "pinnate", "leaf_length": 7,
		"max_height": 8, "asymmetry_seed": 15015})
	for i in 4:
		plant._grow_one()
	while plant._foliage_batch != null and plant._foliage_batch.has_deferred_writes():
		plant._foliage_batch.process_deferred_writes(Plant.LEAF_BAKE_CHUNK_SIZE)
	var biomass_before: int = plant.biomass()
	var alive_before: int = _alive_count(plant)
	var damaged: VoxelBatch.Handle = plant._leaf_groups[0][0]
	damaged.set_visible(false)

	plant.set_leaf_lod_reduced(true)
	_assert(failed, not plant._leaf_lod_hidden.is_empty(),
		"far LOD hides stable interior instances")
	_assert(failed, plant.biomass() == biomass_before
		and _alive_count(plant) == alive_before,
		"LOD changes neither biomass nor alive handles")
	var hidden_indices: Array[int] = []
	for h in plant._leaf_lod_hidden:
		hidden_indices.append(h.index)
	plant.set_leaf_lod_reduced(true)
	var unchanged: Array[int] = []
	for h in plant._leaf_lod_hidden:
		unchanged.append(h.index)
	_assert(failed, hidden_indices == unchanged,
		"unchanged far state performs no rebuild")

	plant.set_leaf_lod_reduced(false)
	_assert(failed, plant._leaf_lod_hidden.is_empty(), "near LOD restores subset")
	_assert(failed, not damaged.visible and damaged.lod_visible,
		"LOD restoration does not revive biological damage")
	for group in plant._leaf_groups:
		for value in group:
			var h: VoxelBatch.Handle = value
			if h.alive and h.visible:
				_assert(failed, h.lod_visible, "all healthy leaves restore near")

	plant.free()
	host.free()
	await process_frame
	if failed.is_empty():
		print("[smoke] plant_leaf_lod OK alive=%d hidden=%d"
			% [alive_before, hidden_indices.size()])
		quit(0)
	else:
		for message in failed:
			push_error("[smoke] FAIL: %s" % message)
		quit(1)


func _alive_count(plant: Plant) -> int:
	var total: int = 0
	for group in plant._leaf_groups:
		for value in group:
			var h: VoxelBatch.Handle = value
			if h != null and h.alive:
				total += 1
	return total


func _assert(failed: Array[String], condition: bool, label: String) -> void:
	if not condition:
		failed.append(label)
