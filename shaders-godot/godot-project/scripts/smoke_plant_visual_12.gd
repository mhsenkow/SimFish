extends SceneTree

func _initialize() -> void:
	var failed: Array[String] = []
	var plant := Plant.new()
	root.add_child(plant)
	await process_frame
	var batch := VoxelBatch.new(plant, StandardMaterial3D.new(), 4, true)
	var mature := batch.add(Transform3D(Basis().scaled(Vector3.ONE * 0.2),
		Vector3(0.4, 1.2, 0.1)), Color(0.3, 0.7, 0.2))
	var young := batch.add(Transform3D(Basis().scaled(Vector3.ONE * 0.2),
		Vector3(0.2, 2.0, 0.0)), Color(0.4, 0.8, 0.3))
	plant._leaf_groups = [[mature], [young]]
	plant._leaf_states = [
		{"phase": Plant.LeafPhase.MATURE},
		{"phase": Plant.LeafPhase.EXPANDING},
	]
	_assert(failed, plant._select_pearling_host() == mature,
		"pearling selects only mature living handles")
	plant._pearling_particles = GPUParticles3D.new()
	plant.add_child(plant._pearling_particles)
	plant._bind_pearling_to_leaf(2.0)
	_assert(failed, plant._pearling_particles.position == mature.local_pos,
		"shared emitter binds to selected leaf")
	_assert(failed, batch._colors[mature.index].get_luminance() > mature.base_color.get_luminance(),
		"host receives brief detach highlight")
	plant._bind_pearling_to_leaf(0.3)
	_assert(failed, batch._colors[mature.index].is_equal_approx(mature.base_color),
		"host highlight restores")
	var source := FileAccess.get_file_as_string("res://scripts/plant.gd")
	_assert(failed, source.contains("claim_pearling_emitter(self)")
		and not source.contains("_pearling_particles.name = \"Pearling\""),
		"pearling uses shared world pool only")
	plant.queue_free()
	if failed.is_empty(): print("SMOKE_PLANT_VISUAL_12_OK"); quit(0); return
	for message in failed: push_error(message)
	quit(1)

func _assert(failed: Array[String], condition: bool, message: String) -> void:
	if not condition: failed.append(message)
