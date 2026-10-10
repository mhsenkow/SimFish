extends SceneTree

# Fixed bone/voxel workload, same full poses and uploads as living fauna.
const Batches = preload("res://scripts/fauna_species_batch.gd")

func _initialize() -> void:
	await process_frame
	Batches.reset_for_test()
	var tank := Node3D.new()
	root.add_child(tank)
	var bones: Array[Node3D] = []
	for fish in 80:
		for bone in 5:
			var pivot := Node3D.new()
			tank.add_child(pivot)
			bones.append(pivot)
			pivot.position = Vector3(float(fish % 20) * 0.6, 1.0 + floor(float(fish) / 20.0) * 0.5, bone * 0.1)
			for voxel in 24:
				var local := Transform3D(Basis.from_scale(Vector3(0.1, 0.08, 0.1)),
					Vector3(float(voxel % 6) * 0.08, floor(float(voxel) / 6.0) * 0.06, 0))
				var handle: VoxelBatch.Handle = Batches.register_instance(
					tank, "probe", Transform3D.IDENTITY, Color.CORAL)
				Batches.track_sync(pivot, local, handle)
	var times: Array[float] = []
	for step in 20:
		for i in bones.size():
			bones[i].rotation.y = sin(float(step) * 0.13 + i * 0.4) * 0.3
			bones[i].position.x += 0.002
		var start: int = Time.get_ticks_usec()
		Batches.sync_all()
		if step >= 8:
			times.append(float(Time.get_ticks_usec() - start) / 1000.0)
	times.sort()
	var report: Dictionary = {"bones": bones.size(), "voxels": Batches.sync_slot_count(),
		"median_ms": times[6], "p95_ms": times[11]}
	print(JSON.stringify(report))
	var path: String = OS.get_environment("FAUNA_SYNC_PROBE_OUT")
	if not path.is_empty():
		var out := FileAccess.open(path, FileAccess.WRITE)
		out.store_string(JSON.stringify(report, "\t"))
	tank.free()
	Batches.reset_for_test()
	quit()
