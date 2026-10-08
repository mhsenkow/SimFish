extends SceneTree

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_root_geometry_batch")
	var plant := Plant.new()
	root.add_child(plant)
	var template := MeshInstance3D.new()
	template.mesh = VoxelMat.get_box(Vector3(0.12, 0.6, 0.24))
	template.material_override = VoxelMat.make_foliage(Color8(70, 50, 30))
	template.position = Vector3(0.2, -0.5, 0.3)
	template.rotation.z = 0.6
	var expected: Transform3D = template.transform
	expected.basis = expected.basis * Basis.from_scale((template.mesh as BoxMesh).size)
	var handle: VoxelBatch.Handle = plant.call("_bake_root_voxel", template)
	t.check(handle.transform.is_equal_approx(expected), "batched hair preserves local rotation, size and position")
	plant.set("_max_roots", 100)
	for i in 100:
		plant.call("_add_root", [Color8(60, 45, 30), Color8(80, 60, 40)])
	var batch: VoxelBatch = plant.get("_root_batch")
	t.check(plant.root_voxels.size() >= 400, "growing roots preserve their logical voxels")
	t.equals(batch.mmi.name, &"RootBatch", "all roots use one render batch")
	var meshes: int = 0
	for child in plant.get_children():
		if child is MeshInstance3D:
			meshes += 1
	t.equals(meshes, 0, "root growth adds no individual mesh nodes")
	t.equals(batch.mmi.multimesh.visible_instance_count, plant.root_voxels.size() + 1, "rendered root count matches live handles")
	plant.free()
	t.check(not handle.alive and handle.batch == null, "freeing a plant releases retained root handles")
	quit(t.finish())
