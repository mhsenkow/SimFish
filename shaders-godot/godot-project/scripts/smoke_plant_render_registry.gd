extends SceneTree

# PLANT_SYSTEMS_50 #26 — every living foliage material receives global updates,
# including populations beyond the retired 96-material hard cap.


func _initialize() -> void:
	var host := Node3D.new()
	root.add_child(host)
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
