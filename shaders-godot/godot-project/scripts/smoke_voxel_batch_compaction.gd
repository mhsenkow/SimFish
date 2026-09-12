extends SceneTree

# PLANT_SYSTEMS_50 #19 — sparse buffers shrink only after a sustained interval,
# atomically remap surviving handles, and defer compaction during active writes.


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	var host := Node3D.new()
	root.add_child(host)
	var batch := VoxelBatch.new(host, StandardMaterial3D.new(), 256)
	var handles: Array[VoxelBatch.Handle] = []
	for i in 80:
		handles.append(batch.add(Transform3D(
			Basis().scaled(Vector3.ONE * 0.1), Vector3(i, 0, 0)), Color.WHITE))
	batch.flush()
	for i in 68:
		handles[i].hide()
	var survivors: Array[VoxelBatch.Handle] = handles.slice(68)
	TestSupport.check(failed, not batch.consider_compaction(4.9),
		"sparse buffer does not compact before hold interval")

	var deferred: VoxelBatch.Handle = batch.add_deferred(
		Transform3D(Basis().scaled(Vector3.ONE * 0.1), Vector3(90, 0, 0)), Color.RED)
	TestSupport.check(failed, not batch.consider_compaction(10.0),
		"active writes block compaction")
	batch.process_deferred_writes(1)
	TestSupport.check(failed, not batch.consider_compaction(4.9),
		"blocked write resets sustained interval")
	TestSupport.check(failed, batch.consider_compaction(0.2), "sustained sparse buffer compacts")
	TestSupport.check(failed, batch._mm.instance_count == VoxelBatch.MIN_CAPACITY,
		"capacity shrinks to bounded floor")

	var expected_index: int = 0
	for h in survivors + [deferred]:
		TestSupport.check(failed, h.alive and h.batch == batch and h.index == expected_index,
			"live handle remapped contiguously")
		h.set_color(Color.BLUE)
		TestSupport.check(failed, batch._colors[h.index] == Color.BLUE,
			"remapped handle still addresses its instance")
		expected_index += 1
	TestSupport.check(failed, handles[0].index == -1 and handles[0].batch == null,
		"dead handle is explicitly detached")

	batch.clear()
	handles.clear()
	survivors.clear()
	deferred = null
	host.free()
	batch = null
	await process_frame
	quit(TestSupport.report("smoke_voxel_batch_compaction", failed))
