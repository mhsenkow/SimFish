extends SceneTree

func _initialize() -> void:
	await process_frame
	var host := Node3D.new()
	root.add_child(host)
	var batch := VoxelBatch.new(host, StandardMaterial3D.new())
	var handles: Array[VoxelBatch.Handle] = []
	for i in 5000:
		handles.append(batch.add(Transform3D(Basis.from_scale(Vector3.ONE * 0.1), Vector3(i * 0.01, 0, 0)), Color.GREEN))
	var measurements: Array[float] = []
	for _repeat in 7:
		var start: int = Time.get_ticks_usec()
		for _tick in 500:
			batch.consider_compaction(0.1)
		measurements.append(float(Time.get_ticks_usec() - start) / 500.0)
	measurements.sort()
	var result: Dictionary = {"voxels": handles.size(), "maintenance_us_per_tick": measurements[3]}
	print(JSON.stringify(result))
	var path: String = OS.get_environment("COMPACTION_PROBE_OUT")
	if not path.is_empty():
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "\t"))
	batch.dispose()
	host.free()
	quit()
