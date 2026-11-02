extends SceneTree
const Batches = preload("res://scripts/fauna_species_batch.gd")

# Covers BOTH species-batch animation paths:
#  - GPU bone palette (default): instances static in bone-local space, one
#    palette row per bone per frame, slot in floor(custom.g). The palette row
#    must compose the exact world transform the legacy path wrote.
#  - Legacy per-voxel CPU path (rollback flag): the original contract — every
#    voxel's mirror transform is bone * local after sync_all().

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_fauna_render_lifecycle")
	await _run_skinned(t)
	await _run_legacy(t)
	Batches.reset_for_test()
	quit(t.finish())


func _run_skinned(t: TestSupport.Suite) -> void:
	Batches.reset_for_test()
	Batches.set_active(true)
	t.check(Batches.gpu_skin_enabled(), "species batches default to the GPU bone palette")
	var tank := Node3D.new()
	root.add_child(tank)
	tank.position = Vector3(5, 2, 1)
	tank.rotation.y = 0.4
	var pivot := Node3D.new()
	tank.add_child(pivot)
	pivot.position = Vector3(1, 0, 0)
	var local := Transform3D(Basis.from_scale(Vector3(0.2, 0.3, 0.4)), Vector3(0, 0.5, 0))
	var h: VoxelBatch.Handle = Batches.register_instance(tank, "guppy", Transform3D.IDENTITY, Color.CORAL)
	h.set_custom_data(Color(0.3, 0.25, 0.1, 0.4))
	Batches.track_sync(pivot, local, h)
	Batches.sync_all()
	t.check(h.transform.is_equal_approx(local), "skinned instances stay static in bone-local space")
	var slot: int = int(floorf(h.custom_data.g))
	t.check(slot >= 1, "tracked bone takes a non-identity palette slot")
	t.approx(h.custom_data.g - floorf(h.custom_data.g), 0.25,
		"belly-flash fraction survives the slot stamp", 1e-4)
	var skin: Batches.SkinPalette = Batches.skin_for_batch(h.batch)
	t.check(skin != null, "skinned batch owns a bone palette")
	var batch_root: Node3D = h.batch.mmi.get_parent() as Node3D
	var root_g: Transform3D = batch_root.global_transform
	t.check(_skin_world(skin, slot, root_g, local).is_equal_approx(
		root_g * pivot.transform * local),
		"palette row composes the exact world transform the CPU path wrote")
	t.check(skin.bone_transform(0).is_equal_approx(Transform3D.IDENTITY),
		"palette slot 0 is pinned to identity")
	_check_bounds(t, h, pivot.transform * local, "initial bone")
	Batches.set_active(false)
	pivot.position.x = 3.0
	await process_frame
	await process_frame
	t.check(_skin_world(skin, slot, root_g, local).is_equal_approx(
		root_g * pivot.transform * local),
		"render frames keep the palette row current after admission is disabled")
	t.equals(Batches.sync_slot_count(), 1, "threshold change retains existing animation slots")
	var second: VoxelBatch.Handle = Batches.register_instance(tank, "guppy", Transform3D.IDENTITY, Color.BLUE)
	var other_local := Transform3D(Basis.IDENTITY, Vector3(0.2, -0.4, 0.1))
	Batches.track_sync(pivot, other_local, second)
	Batches.sync_all()
	t.equals(int(floorf(second.custom_data.g)), slot, "voxels of one bone share its palette slot")
	t.check(second.transform.is_equal_approx(other_local), "grouped voxels retain distinct static locals")
	pivot.scale = Vector3(1.8, 0.7, 1.3)
	pivot.rotation = Vector3(0.3, 0.6, 0.2)
	Batches.sync_all()
	t.check(_skin_world(skin, slot, root_g, local).is_equal_approx(
		root_g * pivot.transform * local),
		"palette row tracks rotation and non-uniform scale")
	_check_bounds(t, h, pivot.transform * local, "rotated scaled bone")
	_check_bounds(t, second, pivot.transform * other_local, "new sibling voxel")
	# The public registration API also supports static, untracked geometry.
	var static_voxel: VoxelBatch.Handle = Batches.register_instance(tank, "guppy",
		Transform3D(Basis.IDENTITY, Vector3(-12, 1, 0)), Color.GREEN)
	Batches.sync_all()
	t.equals(int(floorf(static_voxel.custom_data.g)), 0, "untracked geometry rides identity slot 0")
	_check_bounds(t, static_voxel, static_voxel.transform,
		"untracked static voxel merged into skinned bounds")
	_check_bounds(t, second, pivot.transform * other_local,
		"tracked voxel stays covered after the mirror merge")
	h.hide()
	t.check(h.batch == null or not h.alive, "retired voxel is immediately detached")
	Batches.maintain_parent(0.0, tank.get_instance_id())
	t.equals(Batches.sync_slot_count(), 1,
		"maintenance reclaims the dead handle without dropping its live bone sibling")
	pivot.rotation.z = 0.3
	Batches.sync_all()
	t.check(_skin_world(skin, slot, root_g, other_local).is_equal_approx(
		root_g * pivot.transform * other_local),
		"surviving voxel follows its bone after group compaction")
	_check_bounds(t, second, pivot.transform * other_local, "surviving rotated voxel")
	pivot.free()
	Batches.sync_all()
	t.check(not second.alive, "deleted creature cannot leave visible ghost geometry")
	t.equals(Batches.sync_slot_count(), 0, "deleted creature sync slot is reclaimed")
	t.check(skin.free_slots.has(slot), "released bone slot returns to the palette free list")
	tank.free()
	t.equals(Batches.batch_count(), 0, "closing tank releases shared batches")
	var next_tank := Node3D.new()
	root.add_child(next_tank)
	var next_handle: VoxelBatch.Handle = Batches.register_instance(next_tank, "guppy", Transform3D.IDENTITY, Color.BLUE)
	t.check(next_handle.alive and is_instance_valid(next_handle.batch.mmi), "next tank gets live replacement geometry")
	next_tank.free()


func _run_legacy(t: TestSupport.Suite) -> void:
	Batches.reset_for_test()
	Batches.set_gpu_skin_enabled(false)
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
	t.check(Batches.skin_for_batch(h.batch) == null, "legacy flag builds an unskinned batch")
	t.check(h.transform.is_equal_approx(pivot.transform * local), "legacy geometry uses tank-local coordinates")
	_check_bounds(t, h, h.transform, "legacy initial bone")
	Batches.set_active(false)
	pivot.position.x = 3.0
	await process_frame
	await process_frame
	t.check(h.transform.is_equal_approx(pivot.transform * local), "legacy render frames update shared fish after admission is disabled")
	t.equals(Batches.sync_slot_count(), 1, "legacy threshold change retains existing animation slots")
	var second: VoxelBatch.Handle = Batches.register_instance(tank, "guppy", Transform3D.IDENTITY, Color.BLUE)
	var other_local := Transform3D(Basis.IDENTITY, Vector3(0.2, -0.4, 0.1))
	Batches.track_sync(pivot, other_local, second)
	Batches.sync_all()
	t.check(second.transform.is_equal_approx(pivot.transform * other_local), "legacy grouped voxels retain distinct local transforms")
	pivot.scale = Vector3(1.8, 0.7, 1.3)
	pivot.rotation = Vector3(0.3, 0.6, 0.2)
	Batches.sync_all()
	_check_bounds(t, h, h.transform, "legacy rotated scaled bone")
	_check_bounds(t, second, second.transform, "legacy new sibling voxel")
	h.hide()
	pivot.rotation.z = 0.3
	Batches.sync_all()
	t.equals(Batches.sync_slot_count(), 1, "legacy dead handle is removed without dropping its live bone sibling")
	t.check(second.transform.is_equal_approx(pivot.transform * other_local), "legacy surviving voxel follows bone after group compaction")
	pivot.free()
	Batches.sync_all()
	t.check(not second.alive, "legacy deleted creature cannot leave visible ghost geometry")
	t.equals(Batches.sync_slot_count(), 0, "legacy deleted creature sync slot is reclaimed")
	tank.free()
	t.equals(Batches.batch_count(), 0, "legacy closing tank releases shared batches")


# World transform the GPU composes for a voxel: palette row * root * local.
func _skin_world(skin: Batches.SkinPalette, slot: int, root_g: Transform3D,
		local: Transform3D) -> Transform3D:
	return skin.bone_transform(slot) * root_g * local


# `composed` is the voxel's live root-local transform (bone * local); the
# batch's custom_aabb must cover all eight of its corners.
func _check_bounds(t: TestSupport.Suite, handle: VoxelBatch.Handle,
		composed: Transform3D, context: String) -> void:
	var bounds: AABB = handle.batch.mmi.custom_aabb
	for x in [-0.5, 0.5]:
		for y in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				t.check(bounds.has_point(composed * Vector3(x, y, z)),
					"conservative bounds include every box corner: " + context)
