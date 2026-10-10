extends SceneTree

# Exercise the actual MultiMesh without a repair/full-buffer upload. Dummy
# headless runs validate mirrors and atomic admission; Metal validates readback.
func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_voxel_commit")
	var host := Node3D.new()
	root.add_child(host)
	var batch := VoxelBatch.new(host, StandardMaterial3D.new(), 8, true)
	var handles: Array[VoxelBatch.Handle] = []
	for i in 70:
		var h: VoxelBatch.Handle = batch.add(Transform3D(
			Basis(Vector3(0.2, 0.01, 0.02), Vector3(0.03, 0.3, 0.04), Vector3(0.05, 0.06, 0.4)),
			Vector3(i * 0.3, 1, -i * 0.05)), Color(0.2, 0.4, 0.6, 0.8))
		h.set_custom_data(Color(0.2, 0.3, 0.4, 0.5))
		handles.append(h)
	batch.flush()
	t.equals(batch._mm.visible_instance_count, 70, "capacity growth retains all admitted voxels")
	_readback(t, handles[0], "first voxel survives capacity growth")
	_readback(t, handles[69], "last admitted voxel")
	var moved: VoxelBatch.Handle = handles[20]
	moved.set_transform(Transform3D(Basis.from_euler(Vector3(0.2, 0.6, 0.3)).scaled(Vector3(0.1, 0.3, 0.7)), Vector3(40, 2, 1)))
	moved.set_color(Color(0.7, 0.2, 0.3, 0.6))
	moved.set_custom_data(Color(0.4, 0.8, 0.2, 0.1))
	batch.flush()
	_readback(t, moved, "full pose, pigment and custom changes commit")
	t.check(batch.mmi.custom_aabb.has_point(moved.transform.origin), "moving voxel remains inside culling bounds")
	moved.set_visible(false)
	batch.flush()
	t.equals(batch._xforms[moved.index].basis, Basis.from_scale(Vector3.ZERO), "hidden voxel has zero-scale mirror")
	if DisplayServer.get_name() != "headless":
		t.equals(batch._mm.get_instance_transform(moved.index).basis, Basis.from_scale(Vector3.ZERO), "hidden voxel reaches renderer")
	moved.set_transform(Transform3D(Basis.IDENTITY, Vector3(42, 3, 1)))
	moved.set_visible(true)
	batch.flush()
	_readback(t, moved, "restoring hidden voxel uses latest pose")
	var before: int = batch._mm.visible_instance_count
	var deferred: VoxelBatch.Handle = batch.add_deferred(Transform3D(Basis.IDENTITY, Vector3(-7, 2, 1)), Color.CYAN)
	batch.flush()
	t.equals(batch._mm.visible_instance_count, before, "deferred shape stays uncommitted")
	t.equals(batch.process_deferred_writes(1), 1, "final deferred chunk is written")
	t.equals(batch._mm.visible_instance_count, before + 1, "deferred shape is admitted atomically")
	_readback(t, deferred, "deferred write reaches renderer")
	for i in 65:
		handles[i].hide()
	t.check(batch.consider_compaction(5.1), "sparse moving geometry compacts")
	_readback(t, handles[69], "remapped voxel retains GPU data")
	_readback(t, deferred, "deferred voxel survives remapping")
	batch.clear()
	t.equals(batch._mm.visible_instance_count, 0, "clear hides stale renderer slots")
	host.free()
	batch.dispose()
	await process_frame
	quit(t.finish())

func _readback(t: TestSupport.Suite, handle: VoxelBatch.Handle, label: String) -> void:
	var batch: VoxelBatch = handle.batch
	t.check(batch._xforms[handle.index].is_equal_approx(handle.transform), label + " CPU pose")
	if DisplayServer.get_name() == "headless":
		return
	t.check(batch._mm.get_instance_transform(handle.index).is_equal_approx(handle.transform), label + " GPU pose")
	var pigment: Color = batch._mm.get_instance_color(handle.index)
	t.check(pigment.is_equal_approx(batch._colors[handle.index]), label + " GPU pigment")
	t.check(batch._mm.get_instance_custom_data(handle.index).is_equal_approx(handle.custom_data), label + " GPU custom data")
