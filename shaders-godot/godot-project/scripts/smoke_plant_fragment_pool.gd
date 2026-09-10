extends SceneTree

# PLANT_SYSTEMS_50 #18 — instrument first, then bound/reset only the fragment
# node type demonstrated to churn during trim/die-off bursts.


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	var host := Node3D.new()
	root.add_child(host)
	var sim := SimDriver.new()
	host.add_child(sim)
	var fragment_root := Node3D.new()
	host.add_child(fragment_root)
	sim.plants_root = fragment_root

	for i in SimDriver.PLANT_FRAGMENT_POOL_CHURN_GATE:
		sim.spawn_plant_fragment(Vector3(i, 2, 0), {"plant_name": "cut"},
			[Color.GREEN, Color.GREEN, Color.GREEN], 3, Vector3.ONE)
		var frag: PlantFragment = sim.plant_fragments.back()
		sim._on_plant_fragment_finished(frag)
	var stats: Dictionary = sim.plant_fragment_pool_stats()
	_assert(failed, bool(stats.enabled), "measured churn enables fragment pool")
	_assert(failed, int(stats.finishes) == SimDriver.PLANT_FRAGMENT_POOL_CHURN_GATE,
		"finish instrumentation reaches gate")
	_assert(failed, int(stats.pooled) == 1,
		"only post-gate compatible fragment is retained")
	var pooled: PlantFragment = sim._plant_fragment_pool.back()
	_assert(failed, pooled.genome.is_empty() and pooled.ramp_override.is_empty()
		and pooled.biomass_units == 2 and pooled._age == 0.0
		and pooled._velocity == Vector3.ZERO and not pooled.visible,
		"pooled fragment resets every mutable field")

	var allocations_before: int = int(stats.allocations)
	sim.spawn_plant_fragment(Vector3.ZERO, {}, [], 2, Vector3.ZERO)
	_assert(failed, int(sim.plant_fragment_pool_stats().allocations) == allocations_before,
		"enabled pool reuses without allocation")
	var reused: PlantFragment = sim.plant_fragments.back()
	sim._on_plant_fragment_finished(reused)

	for i in SimDriver.PLANT_FRAGMENT_POOL_CAP + 5:
		var frag := PlantFragment.new()
		fragment_root.add_child(frag)
		sim._on_plant_fragment_finished(frag)
	_assert(failed, sim._plant_fragment_pool.size() == SimDriver.PLANT_FRAGMENT_POOL_CAP,
		"pool is capped and oversized burst falls back to queue_free")

	host.free()
	await process_frame
	if failed.is_empty():
		print("[smoke] plant_fragment_pool OK gate=%d cap=%d allocations=%d"
			% [SimDriver.PLANT_FRAGMENT_POOL_CHURN_GATE,
				SimDriver.PLANT_FRAGMENT_POOL_CAP, allocations_before])
		quit(0)
	else:
		for message in failed:
			push_error("[smoke] FAIL: %s" % message)
		quit(1)


func _assert(failed: Array[String], condition: bool, label: String) -> void:
	if not condition:
		failed.append(label)
