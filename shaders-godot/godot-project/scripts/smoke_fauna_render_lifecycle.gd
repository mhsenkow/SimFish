extends SceneTree
const Batches = preload("res://scripts/fauna_species_batch.gd")

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_fauna_render_lifecycle")
	Batches.reset_for_test()
	Batches.set_active(true)
	var tank := Node3D.new()
	root.add_child(tank)
	tank.position = Vector3(5, 2, 1)
	tank.rotation.y = 0.4
	var pivot := Node3D.new()
	tank.add_child(pivot)
	pivot.position = Vector3(1, 0, 0)
	var local := Transform3D(Basis.from_scale(Vector3(0.2, 0.3, 0.4)), Vector3(0, 0.5, 0))
	var h: VoxelBatch.Handle = Batches.register_instance(tank, "guppy", Transform3D.IDENTITY, Color.CORAL)
	Batches.track_sync(pivot, local, h)
	Batches.sync_all()
	t.check(h.transform.is_equal_approx(pivot.transform * local), "shared geometry uses tank-local coordinates")
	_check_bounds(t, h, "initial bone")
	Batches.set_active(false)
	pivot.position.x = 3.0
	await process_frame
	await process_frame
	t.check(h.transform.is_equal_approx(pivot.transform * local), "render frames update shared fish after admission is disabled")
	t.equals(Batches.sync_slot_count(), 1, "threshold change retains existing animation slots")
	var second: VoxelBatch.Handle = Batches.register_instance(tank, "guppy", Transform3D.IDENTITY, Color.BLUE)
	var other_local := Transform3D(Basis.IDENTITY, Vector3(0.2, -0.4, 0.1))
	Batches.track_sync(pivot, other_local, second)
	Batches.sync_all()
	t.check(second.transform.is_equal_approx(pivot.transform * other_local), "grouped voxels retain distinct local transforms")
	pivot.scale = Vector3(1.8, 0.7, 1.3)
	pivot.rotation = Vector3(0.3, 0.6, 0.2)
	Batches.sync_all()
	_check_bounds(t, h, "rotated scaled bone")
	_check_bounds(t, second, "new sibling voxel")
	# The public registration API also supports static, untracked geometry.
	var static_voxel: VoxelBatch.Handle = Batches.register_instance(tank, "guppy",
		Transform3D(Basis.IDENTITY, Vector3(-12, 1, 0)), Color.GREEN)
	Batches.sync_all()
	_check_bounds(t, static_voxel, "untracked static voxel keeps exact fallback")
	h.hide()
	pivot.rotation.z = 0.3
	Batches.sync_all()
	t.equals(Batches.sync_slot_count(), 1, "dead handle is removed without dropping its live bone sibling")
	t.check(second.transform.is_equal_approx(pivot.transform * other_local), "surviving voxel follows bone after group compaction")
	_check_bounds(t, second, "surviving rotated voxel")
	pivot.free()
	Batches.sync_all()
	t.check(not second.alive, "deleted creature cannot leave visible ghost geometry")
	t.equals(Batches.sync_slot_count(), 0, "deleted creature sync slot is reclaimed")
	tank.free()
	t.equals(Batches.batch_count(), 0, "closing tank releases shared batches")
	var next_tank := Node3D.new()
	root.add_child(next_tank)
	var next_handle: VoxelBatch.Handle = Batches.register_instance(next_tank, "guppy", Transform3D.IDENTITY, Color.BLUE)
	t.check(next_handle.alive and is_instance_valid(next_handle.batch.mmi), "next tank gets live replacement geometry")
	next_tank.free()
	Batches.reset_for_test()
	quit(t.finish())

func _check_bounds(t: TestSupport.Suite, handle: VoxelBatch.Handle, context: String) -> void:
	var bounds: AABB = handle.batch.mmi.custom_aabb
	for x in [-0.5, 0.5]:
		for y in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				t.check(bounds.has_point(handle.transform * Vector3(x, y, z)),
					"conservative bounds include every box corner: " + context)
