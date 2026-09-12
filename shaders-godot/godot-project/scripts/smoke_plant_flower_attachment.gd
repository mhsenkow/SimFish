extends SceneTree

# Flower motion/attachment regression: the bloom is one rigid tip assembly.

const PlantScript := preload("res://scripts/plant.gd")
const FarBatchScript := preload("res://scripts/plant_far_foliage_batch.gd")


class FootprintHost:
	extends Node3D

	func clamp_xz_in_tank(x: float, z: float, _margin: float) -> Vector2:
		return Vector2(clampf(x, -0.25, 0.25), clampf(z, -0.25, 0.25))

	func clamp_emergent_in_tank(pos: Vector3, _margin: float) -> Vector3:
		return Vector3(clampf(pos.x, -0.25, 0.25), pos.y, clampf(pos.z, -0.25, 0.25))

	func fits_plant_at(x: float, z: float, _reach: float, _margin: float, _y: float) -> bool:
		return absf(x) <= 0.25 and absf(z) <= 0.25


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	var host := FootprintHost.new()
	root.add_child(host)
	var plant: Plant = PlantScript.new()
	host.add_child(plant)
	plant.init(5, {"leaf_form": "column", "max_height": 8, "asymmetry_seed": 4242})
	plant._health_smooth = 1.0
	plant.uses_flowering = true
	plant._begin_flowering()

	# Reclamping moves one parent and never rewrites authored petal locals.
	var locals_before: Array[Transform3D] = []
	for voxel in plant.bloom_voxels:
		locals_before.append((voxel as Node3D).transform)
	plant._flower_node.position.x = 2.0
	for i in 4:
		plant._reclamp_voxels_to_footprint()
	var locals_stable: bool = plant.bloom_voxels.size() == locals_before.size()
	for i in mini(plant.bloom_voxels.size(), locals_before.size()):
		locals_stable = locals_stable \
			and (plant.bloom_voxels[i] as Node3D).transform.is_equal_approx(locals_before[i])
	TestSupport.check(failed, locals_stable, "repeated reclamp preserves every bloom local transform")
	TestSupport.check(failed, absf(plant._flower_node.global_position.x) <= 0.251,
		"reclamp moves the complete flower inside the footprint")

	# Live handle position and layover basis are both inherited by the anchor.
	var tip: VoxelBatch.Handle = plant._live_top_stem_handle()
	var laid_basis := Basis(Vector3.RIGHT, 0.42) * tip.transform.basis
	var laid_xform := tip.transform
	laid_xform.basis = laid_basis
	tip.set_transform(laid_xform)
	plant._stabilize_flower_against_lean()
	var expected_pos: Vector3 = tip.transform.origin \
		+ tip.transform.basis.orthonormalized().y * Plant.FLOWER_TIP_NEST
	TestSupport.check(failed, plant._flower_node.position.distance_to(expected_pos) < 0.0001,
		"flower anchor follows the live top handle without lag")
	TestSupport.check(failed, plant._flower_node.basis.y.normalized().dot(
		tip.transform.basis.orthonormalized().y) > 0.999,
		"flower inherits canopy layover orientation")

	# Flowering stems opt out of shader gust, leaves retain only a soft trace,
	# and the CPU whole-plant lean is tightly bounded under a full gust.
	plant._ensure_stem_batch()
	plant._ensure_foliage_batch()
	plant._apply_sway_personality()
	TestSupport.check(failed, is_zero_approx(float(
		plant._stem_mat.get_shader_parameter("gust_response"))),
		"flowering structural stem has no GPU gust displacement")
	TestSupport.check(failed, float(plant._foliage_mat.get_shader_parameter("gust_response")) <= 0.17,
		"flowering leaves retain strongly attenuated gust")
	plant.apply_gust_tilt(Vector2.RIGHT, 1.0)
	TestSupport.check(failed, plant._gust_tilt.length() <= 0.0551,
		"heavy bloom CPU gust stays bounded")
	plant.rotation.z = plant._gust_tilt.x * 0.65
	plant._stabilize_flower_against_lean()
	var expected_world: Vector3 = plant.global_transform * expected_pos
	TestSupport.check(failed, plant._flower_node.global_position.distance_to(expected_world) < 0.0001,
		"whole-plant gust leaves no structural tip-to-flower gap")

	# Bud is a bridge plus compact cluster, never a lone detached cube.
	TestSupport.check(failed, plant.bloom_voxels.size() >= 5,
		"bud includes pedicel, calyx, and compact multi-voxel head")
	var pedicel: Node3D = plant.bloom_voxels[0]
	var calyx: Node3D = plant.bloom_voxels[1]
	var bud_base: Node3D = plant.bloom_voxels[2]
	TestSupport.check(failed, pedicel.position.y < calyx.position.y
			and bud_base.position.y >= calyx.position.y,
		"bud silhouette forms a connected stem-to-calyx-to-head chain")
	var pedicel_box: BoxMesh = (pedicel as MeshInstance3D).mesh as BoxMesh
	TestSupport.check(failed, pedicel_box != null and pedicel_box.size.x >= Plant.VOXEL_SIZE * 0.34,
		"column pedicel is stem-width, not a wire")
	var bloom_mat: ShaderMaterial = (pedicel as MeshInstance3D).material_override as ShaderMaterial
	TestSupport.check(failed, bloom_mat != null
			and float(bloom_mat.get_shader_parameter("motion_lock")) > 0.5
			and is_zero_approx(float(bloom_mat.get_shader_parameter("sway_amplitude"))),
		"flower material locks out GPU vertex displacement")

	# Far consolidation must reject the whole reproductive plant and restore
	# private draw batches if it had been mirrored on the previous rebuild.
	var far_batch := FarBatchScript.new()
	host.add_child(far_batch)
	await process_frame
	TestSupport.check(failed, not far_batch._eligible_for_mirroring(plant),
		"active flower/seed-pod plant is excluded from far mirroring")
	far_batch._mirrored_plants.append(plant)
	far_batch._set_private_visible(plant, false)
	far_batch.update_far_batch([], null, FarBatchScript.REBUILD_INTERVAL_S)
	TestSupport.check(failed, plant._stem_batch.mmi.visible and plant._foliage_batch.mmi.visible,
		"far-batch fallback restores flowering plant private batches")

	# Save restoration rebuilds stage-specific geometry rather than restoring
	# only the enum and leaving an invisible reproductive state.
	plant.flower_stage = Plant.FlowerStage.SEED_POD
	plant._clear_bloom()
	plant._build_flower_stage_geometry()
	var saved: Dictionary = plant.to_save_dict()
	var restored: Plant = PlantScript.new()
	host.add_child(restored)
	restored.apply_save_dict(saved)
	TestSupport.check(failed, restored.flower_stage == Plant.FlowerStage.SEED_POD,
		"save restores flower stage")
	TestSupport.check(failed, restored._flower_node != null and restored.bloom_voxels.size() >= 4,
		"save restores attached seed-pod geometry")

	host.free()
	await process_frame
	quit(TestSupport.report("smoke_plant_flower_attachment", failed))
