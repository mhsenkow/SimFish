extends SceneTree

const Batches = preload("res://scripts/fauna_species_batch.gd")

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_retired_voxel_slots")
	var host := Node3D.new()
	root.add_child(host)
	var batch := VoxelBatch.new(host, StandardMaterial3D.new(), 64, true, true)
	var first: VoxelBatch.Handle = batch.add(Transform3D.IDENTITY, Color.RED)
	first.set_custom_data(Color(0.2, 0.4, 0.6, 0.8))
	first.hide()
	first.hide()
	var second: VoxelBatch.Handle = batch.add(Transform3D(Basis.IDENTITY, Vector3(7, 2, 3)), Color.BLUE)
	batch.flush()
	t.equals(batch._count, 1, "retired slot is reused once despite repeated hide")
	t.equals(first.batch, null, "old handle is detached before its slot is reused")
	t.equals(first.index, -1, "retired handle no longer addresses a live animal")
	first.set_color(Color.WHITE)
	first.set_transform(Transform3D.IDENTITY)
	t.equals(batch._colors[second.index], Color.BLUE, "stale handle cannot recolor its replacement")
	t.equals(batch._customs[second.index], Color(0, 0, 0, 1), "replacement resets old custom attributes")
	if DisplayServer.get_name() != "headless":
		t.check(batch._mm.get_instance_transform(second.index).is_equal_approx(second.transform), "reused pose reaches renderer")
		t.check(batch._mm.get_instance_color(second.index).is_equal_approx(Color.BLUE), "reused pigment reaches renderer")
		t.equals(batch._mm.get_instance_custom_data(second.index), Color(0, 0, 0, 1), "reused custom data reaches renderer")
	second.set_visible(false)
	var third: VoxelBatch.Handle = batch.add(Transform3D.IDENTITY, Color.GREEN)
	t.equals(batch._count, 2, "temporary visibility is not a reusable slot")
	second.set_visible(true)
	t.equals(batch._xforms[second.index].origin, Vector3(7, 2, 3), "temporarily hidden animal restores its own pose")
	third.hide()
	var deferred: VoxelBatch.Handle = batch.add_deferred(Transform3D.IDENTITY, Color.YELLOW)
	t.equals(deferred.index, 2, "deferred bakes keep append-only reservation")
	batch.flush()
	t.equals(batch._mm.visible_instance_count, 1, "deferred reservation does not reveal unwritten geometry")
	batch.process_deferred_writes(1)
	t.equals(batch._mm.visible_instance_count, 3, "deferred geometry commits after upload")
	batch.clear()
	t.equals(batch._retired_indices.size(), 0, "clear invalidates reusable indices")
	batch.dispose()
	Batches.reset_for_test()
	# Repeated fauna lifetimes stay at peak live size, then shrink after a lull.
	for generation in 12:
		var pivot := Node3D.new()
		host.add_child(pivot)
		for i in 300:
			var pose := Transform3D(Basis.from_scale(Vector3.ONE * 0.1), Vector3(i * 0.01, 0, 0))
			var h: VoxelBatch.Handle = Batches.register_instance(host, "churn", pose, Color.CORAL)
			Batches.track_sync(pivot, pose, h)
		Batches.sync_all()
		var live_batch: VoxelBatch = Batches.batches_for("churn")[0]
		t.equals(live_batch._count, 300, "fauna slots stay bounded at the live population peak")
		pivot.free()
		Batches.sync_all()
		t.equals(Batches.sync_slot_count(), 0, "dead pivots release every sync handle")
	Batches.maintain_parent(5.1, host.get_instance_id())
	var compacted: VoxelBatch = Batches.batches_for("churn")[0]
	t.equals(compacted._count, 0, "idle shared batch releases retired CPU arrays")
	t.equals(compacted._mm.instance_count, 64, "idle shared batch releases historical GPU capacity")
	# Legacy callers can register static geometry without retaining a handle.
	for _i in 300:
		Batches.register_instance(host, "untracked", Transform3D.IDENTITY, Color.CYAN)
	Batches.maintain_parent(10.0, host.get_instance_id())
	t.equals((Batches.batches_for("untracked")[0] as VoxelBatch)._count, 300, "maintenance preserves untracked static geometry")
	host.free()
	Batches.reset_for_test()
	await process_frame
	quit(t.finish())
