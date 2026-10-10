extends SceneTree

const Batches = preload("res://scripts/fauna_species_batch.gd")
const Learned = preload("res://scripts/fish_learned_mind.gd")

func _initialize() -> void:
	await process_frame
	root.get_node("TankConfig").capture_mode = true
	root.get_node("TankConfig").mind_brain_threads = true
	Batches.reset_for_test()
	MindBrainPool.reset_for_test()
	var tank := Node3D.new()
	root.add_child(tank)
	var reports: Array = []
	for generation in 24:
		var actors: Array[Fish] = []
		for i in 12:
			var f := Fish.new()
			f.id = "churn_%d_%d" % [generation, i]
			tank.add_child(f)
			f.set_process(false)
			actors.append(f)
			Learned.tick(f, null, 0.1)
			MindPromptSkeleton.skeleton_for(f, null)
			MindDirtySave.mark(f, "episodic_store")
			MindBrainPool.queue_cognition(f, MindChannel.for_cycle(f), 0.1)
			for voxel in 24:
				var local := Transform3D(Basis.from_scale(Vector3.ONE * 0.1), Vector3(voxel * 0.05, 0, 0))
				var h: VoxelBatch.Handle = Batches.register_instance(tank, "probe", local, Color.CORAL)
				Batches.track_sync(f, local, h)
		Batches.sync_all()
		MindBrainPool.flush_tick()
		MindBrainPool.wait_for_batch()
		var row: Dictionary = _sample(generation, "live")
		for f in actors:
			f.free()
		Batches.sync_all()
		row["after_removal"] = _sample(generation, "removed")
		reports.append(row)
		if generation % 4 == 0 or generation == 23:
			print(JSON.stringify(row))
		await process_frame
	var file := FileAccess.open(OS.get_environment("RETENTION_PROBE_OUT"), FileAccess.WRITE)
	file.store_string(JSON.stringify(reports, "	"))
	tank.free()
	MindBrainPool.reset_for_test()
	Batches.reset_for_test()
	quit()

func _sample(generation: int, phase: String) -> Dictionary:
	var slots: int = 0
	var capacity: int = 0
	for batch: VoxelBatch in Batches.batches_for("probe"):
		slots += batch._count
		capacity += batch._mm.instance_count
	return {"generation": generation, "phase": phase, "slots": slots, "capacity": capacity,
		"sync_handles": Batches.sync_slot_count(), "learned_clocks": Learned._tick_acc.size(),
		"prompt_cache": MindPromptSkeleton._cache.size(), "dirty_cache": MindDirtySave._dirty.size(),
		"brain_results": MindBrainPool._results.size(), "memory_bytes": OS.get_static_memory_usage()}
