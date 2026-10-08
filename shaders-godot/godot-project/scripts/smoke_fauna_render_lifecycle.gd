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
	Batches.set_active(false)
	pivot.position.x = 3.0
	await process_frame
	await process_frame
	t.check(h.transform.is_equal_approx(pivot.transform * local), "render frames update shared fish after admission is disabled")
	t.equals(Batches.sync_slot_count(), 1, "threshold change retains existing animation slots")
	pivot.free()
	Batches.sync_all()
	t.check(not h.alive, "deleted creature cannot leave visible ghost geometry")
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
