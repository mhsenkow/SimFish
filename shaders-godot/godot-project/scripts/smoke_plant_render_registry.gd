extends SceneTree

# PLANT_SYSTEMS_50 #26 — every living foliage material receives global updates,
# including populations beyond the retired 96-material hard cap.

const PlantTickStub := preload("res://scripts/plant_tick_test_stub.gd")


func _initialize() -> void:
	var host := Node3D.new()
	root.add_child(host)
	await process_frame
	var mats: Array[ShaderMaterial] = []
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
uniform float daylight = 0.0;
uniform float canopy_shade = 0.0;
uniform float water_surface_y = 0.0;
uniform vec3 flow_dir = vec3(0.0);
uniform float flow_strength = 0.0;
"""
	for i in 128:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mats.append(mat)
		VoxelMat.register_foliage_mm(mat)
	VoxelMat.update_foliage_uniforms(0.37, 12.0, 0.73)
	VoxelMat.update_foliage_flow(Vector3(1.0, 0.0, 0.0), 0.42)
	var failed: Array[String] = []
	for i in mats.size():
		var mat: ShaderMaterial = mats[i]
		_assert(failed, is_equal_approx(float(mat.get_shader_parameter("daylight")), 0.73),
			"material %d missed daylight update" % i)
		_assert(failed, is_equal_approx(float(mat.get_shader_parameter("flow_strength")), 0.42),
			"material %d missed flow update" % i)
	_assert(failed, VoxelMat._live_foliage_mm_mats().size() >= 128,
		"registry retains all living materials")
	mats.resize(2)
	# Weak entries must not keep discarded materials alive.
	VoxelMat._live_foliage_mm_mats()
	_assert(failed, VoxelMat._foliage_mm_mats.size() < 128,
		"registry evicts released materials")
	# #21: bounds fit live transforms plus the configured shader-sway margin.
	var batch := VoxelBatch.new(host, StandardMaterial3D.new(), 4)
	batch.set_bounds_margin(Vector3(1.0, 0.5, 1.0))
	batch.add(Transform3D(Basis().scaled(Vector3(2.0, 4.0, 2.0)),
		Vector3(-3.0, 2.0, 1.0)), Color.GREEN)
	batch.add(Transform3D(Basis().scaled(Vector3.ONE),
		Vector3(5.0, 7.0, -2.0)), Color.GREEN)
	batch.flush()
	var bounds: AABB = batch.mmi.custom_aabb
	_assert(failed, bounds.position.x <= -5.0 and bounds.end.x >= 6.5,
		"dynamic bounds enclose transformed voxels and margin")
	_assert(failed, bounds.size.x < 20.0 and bounds.size.y < 20.0,
		"dynamic bounds replace oversized legacy AABB")
	batch.clear()
	_assert(failed, batch.mmi.custom_aabb.size.x <= 2.01,
		"empty batch resets to margin bounds")
	# #14: rooted plant geometry receives a nonzero, height-scaled fade range.
	var plant := Plant.new()
	host.add_child(plant)
	plant.init(3, {"max_height": 18, "leaf_form": "spade"})
	var plant_range: float = plant._plant_visibility_range()
	_assert(failed, plant_range > Plant.PLANT_LOD_BASE_RANGE,
		"plant visibility range scales with mature height")
	var ranged_geometry: int = 0
	var stack: Array[Node] = [plant]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			if child is GeometryInstance3D:
				var geometry := child as GeometryInstance3D
				ranged_geometry += 1
				_assert(failed, is_equal_approx(geometry.visibility_range_end, plant_range),
					"rooted geometry receives plant visibility range")
			if child.get_child_count() > 0:
				stack.append(child)
	_assert(failed, ranged_geometry > 0, "plant smoke built ranged geometry")
	# #16: rooted structural stems share a second per-plant MultiMesh while
	# retaining stable biological handles for removal and biomass.
	var stem_plant := Plant.new()
	host.add_child(stem_plant)
	stem_plant.init(6, {"max_height": 12, "leaf_form": "column",
		"asymmetry_seed": 4242})
	_assert(failed, stem_plant._stem_batch != null
			and stem_plant._stem_batch.mmi != null,
		"multi-voxel rooted plant creates a stem batch")
	_assert(failed, stem_plant.voxels.size() == 6,
		"stem registry retains one stable handle per voxel")
	var all_batched: bool = true
	for h in stem_plant.voxels:
		all_batched = all_batched and h != null and h.alive \
			and h.batch == stem_plant._stem_batch
	_assert(failed, all_batched, "every structural stem points at the shared batch")
	_assert(failed, is_equal_approx(
			stem_plant._stem_batch.mmi.visibility_range_end,
			stem_plant._plant_visibility_range()),
		"stem batch receives rooted visibility range")
	var stem_bounds: AABB = stem_plant._stem_batch.mmi.custom_aabb
	_assert(failed, stem_bounds.size.y > Plant.VOXEL_SIZE * 4.0
			and stem_bounds.size.y < Plant.VOXEL_SIZE * 9.0,
		"stem batch uses live dynamic bounds")
	var removed_handle: VoxelBatch.Handle = stem_plant.voxels.back()
	var biomass_before: int = stem_plant.biomass()
	var eaten: int = stem_plant.nibble(1)
	_assert(failed, eaten == 1 and not removed_handle.alive,
		"grazing hides the removed stable stem handle")
	_assert(failed, stem_plant.biomass() == stem_plant.current_height
			and stem_plant.biomass() < biomass_before,
		"stem removal updates biological biomass")
	# #24: far calm plants tick every fourth phase but receive all accumulated dt.
	var sim := SimDriver.new()
	host.add_child(sim)
	var camera := Camera3D.new()
	host.add_child(camera)
	camera.global_position = Vector3.ZERO
	var far_plant: Plant = PlantTickStub.new()
	host.add_child(far_plant)
	far_plant.global_position = Vector3(60.0, 0.0, 0.0)
	for _step in 4:
		sim._plant_tick_index += 1
		sim._tick_plant_distance_bucketed(far_plant, 0.1, camera)
	_assert(failed, int(far_plant.get("tick_calls")) == 1,
		"far calm plant runs one of four deterministic tick phases")
	var pending_dt: float = float(sim._plant_tick_accum.get(
		far_plant.get_instance_id(), 0.0))
	_assert(failed, is_equal_approx(
			float(far_plant.get("integrated_dt")) + pending_dt, 0.4),
		"integrated plus pending far-plant time preserves complete elapsed time")
	far_plant.health = 0.5
	_assert(failed, sim._plant_tick_divisor(far_plant, camera) == 1,
		"stressed far plant returns to full tick rate")
	host.queue_free()
	if failed.is_empty():
		print("SMOKE_PLANT_RENDER_REGISTRY_OK")
		quit(0)
	else:
		for message in failed:
			push_error(message)
		quit(1)


func _assert(failed: Array[String], condition: bool, message: String) -> void:
	if not condition:
		failed.append(message)
