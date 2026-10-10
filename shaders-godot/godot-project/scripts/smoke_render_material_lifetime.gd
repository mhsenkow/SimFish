extends SceneTree

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_render_material_lifetime")
	var materials: Array[ShaderMaterial] = []
	var initial: int = VoxelMat._live_fauna_mm_mats().size()
	for _i in 384:
		materials.append(VoxelMat.make_fauna_mm())
	VoxelMat.update_aquatic_uniforms(0.23, Color.CORAL, 12.0, 0.37, 0.11)
	VoxelMat.update_fixture_glow(0.29, Color.PINK, 12.0, 2.0)
	_verify_uniforms(t, materials)
	t.equals(VoxelMat._live_fauna_mm_mats().size(), initial + 384, "registry covers populations beyond the old cap")
	var released: WeakRef = weakref(materials[200])
	materials.resize(2)
	VoxelMat._live_fauna_mm_mats()
	t.check(released.get_ref() == null, "registry cannot retain departed animal material")
	t.equals(VoxelMat._fauna_mm_mats.size(), initial + 2, "registry prunes dead material bookkeeping")
	var kept: ShaderMaterial = materials[0]
	VoxelMat._apply_palette_to_material(kept, 0.1, 1.2, 0.3, 0.9)
	t.approx(float(kept.get_shader_parameter("palette_saturation")), 1.2, "palette updates remain effective")
	VoxelMat._apply_palette_to_material(kept, 0.1, 1.2, 0.3, 0.9)
	t.approx(float(kept.get_shader_parameter("palette_value")), 0.9, "repeated palette updates retain exact state")
	VoxelMat._clear_palette_overlay(kept)
	VoxelMat._apply_palette_to_material(kept, 0.1, 1.2, 0.3, 0.9)
	t.approx(float(kept.get_shader_parameter("palette_saturation")), 1.2, "clearing overlay invalidates palette memoization")
	kept = null
	materials.clear()
	VoxelMat._live_fauna_mm_mats()
	t.equals(VoxelMat._fauna_mm_mats.size(), initial, "registry returns to its initial live set")
	quit(t.finish())


func _verify_uniforms(t: TestSupport.Suite, materials: Array[ShaderMaterial]) -> void:
	# Loop locals retain their last resource until the function returns.
	for mat in materials:
		t.approx(float(mat.get_shader_parameter("aquatic_caustic_intensity")), 0.23, "all live fauna materials receive water light")
		t.approx(float(mat.get_shader_parameter("tank_fixture_glow")), 0.29, "all live fauna materials receive fixture glow")
