extends SceneTree

const Picker = preload("res://scripts/scenario_picker.gd")
const Batches = preload("res://scripts/fauna_species_batch.gd")

func _initialize() -> void:
	await process_frame
	var cfg: Node = root.get_node("TankConfig")
	cfg.reset_to_defaults()
	cfg.capture_mode = true
	var scenario: String = OS.get_environment("AGING_PROBE_SCENARIO")
	if scenario.is_empty():
		scenario = "beginner_sandbox"
	for sc in Picker.SCENARIOS:
		if sc.id == scenario:
			Picker.apply_scenario(sc, cfg)
	seed(0xF15C)
	var world: Node3D = load("res://scripts/world.gd").new()
	root.add_child(world)
	while not world.build_complete:
		await process_frame
	var sim: SimDriver = world.sim
	sim.set_physics_process(false)
	sim._tick_profile_enabled = true
	var duration: float = OS.get_environment("AGING_PROBE_SECONDS").to_float()
	if duration <= 0:
		duration = 120.0
	var reports: Array = [_sample(sim, 0.0, [])]
	var timings: Array[float] = []
	for tick in int(duration / SimDriver.SIM_DT):
		var start: int = Time.get_ticks_usec()
		sim._tick(SimDriver.SIM_DT)
		timings.append(float(Time.get_ticks_usec() - start) / 1000.0)
		if (tick + 1) % 100 == 0:
			var row: Dictionary = _sample(sim, (tick + 1) * SimDriver.SIM_DT, timings)
			reports.append(row)
			print(JSON.stringify(row))
			timings.clear()
		if tick % 10 == 0:
			await process_frame
	var file := FileAccess.open(OS.get_environment("AGING_PROBE_OUT"), FileAccess.WRITE)
	file.store_string(JSON.stringify(reports, "	"))
	if OS.get_environment("AGING_PROBE_ORPHANS") == "1":
		Node.print_orphan_nodes()
	MindBrainPool.reset_for_test()
	Batches.reset_for_test()
	world.queue_free()
	await process_frame
	await process_frame
	VoxelMat._live_fauna_mm_mats()
	VoxelMat._live_foliage_mm_mats()
	if OS.get_environment("AGING_PROBE_ORPHANS") == "1":
		Node.print_orphan_nodes()
	quit()

func _sample(sim: SimDriver, elapsed: float, timings: Array[float]) -> Dictionary:
	var episodes: int = 0
	var felt: int = 0
	var salient: int = 0
	for f: Fish in sim.fish:
		if is_instance_valid(f):
			episodes += f._episodic_store.size()
			salient += f.salient_memories.size()
			felt += var_to_bytes(f._felt_self).size()
	var slots: int = 0
	var capacity: int = 0
	for batch: VoxelBatch in Batches._batches.values():
		slots += batch._count
		capacity += batch._mm.instance_count
	timings.sort()
	var stages: Dictionary = {}
	for key in sim.tick_profile:
		var values: Vector2i = sim.tick_profile[key]
		stages[key] = float(values.x) / maxf(1.0, values.y) / 1000.0
	sim.tick_profile.clear()
	return {"elapsed_s": elapsed, "fish": sim.fish.size(), "shrimp": sim.shrimp.size(),
		"plants": sim.plants.size(), "biomass": sim.total_plant_biomass,
		"episodes": episodes, "salient": salient, "felt_bytes": felt,
		"fauna_slots": slots, "fauna_capacity": capacity,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"memory_bytes": OS.get_static_memory_usage(),
		"stages_mean_ms": stages,
		"tick_p50_ms": timings[int(timings.size() / 2.0)] if not timings.is_empty() else 0.0,
		"tick_p95_ms": timings[mini(timings.size() - 1, int(timings.size() * 0.95))] if not timings.is_empty() else 0.0}
