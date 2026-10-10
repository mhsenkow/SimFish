extends SceneTree

# Actual template builds, not synthetic populations. Run via dev_run.sh.
const Picker = preload("res://scripts/scenario_picker.gd")

func _initialize() -> void:
	await process_frame
	var cfg: Node = root.get_node("TankConfig")
	var world_script: Script = load("res://scripts/world.gd")
	cfg.capture_mode = true
	var reports: Array = []
	var ids: String = OS.get_environment("TENDING_PROBE_SCENARIOS")
	if ids.is_empty():
		ids = "beginner_sandbox,iwagumi,reef,shrimp_sanctuary"
	var observe: float = maxf(0.0, OS.get_environment("TENDING_PROBE_SECONDS").to_float())
	for id in ids.split(",", false):
		cfg.reset_to_defaults()
		cfg.capture_mode = true
		for scenario in Picker.SCENARIOS:
			if scenario.id == id:
				Picker.apply_scenario(scenario, cfg)
		seed(0xF15C)
		var world: Node3D = world_script.new()
		var start: int = Time.get_ticks_usec()
		root.add_child(world)
		var frames: int = 0
		while not world.build_complete and frames < 3000:
			frames += 1
			await process_frame
		if not world.build_complete:
			push_error("[tending_probe] habitat did not finish: " + id)
			quit(1)
			return
		var sim: SimDriver = world.sim
		var row: Dictionary = {"scenario": id, "build_ms": float(Time.get_ticks_usec() - start) / 1000.0,
			"initial": _sample(sim)}
		var initial_age: float = sim.tank_age_s
		while sim.tank_age_s - initial_age < observe:
			await physics_frame
		row["after_s"] = sim.tank_age_s - initial_age
		row["settled"] = _sample(sim)
		reports.append(row)
		print(JSON.stringify(row))
		MindBrainPool.reset_for_test()
		world.queue_free()
		await process_frame
		await process_frame
	var path: String = OS.get_environment("TENDING_PROBE_OUT")
	if not path.is_empty():
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(reports, "\t"))
	quit()


func _sample(sim: SimDriver) -> Dictionary:
	var hunger: float = 0.0
	var stress: float = 0.0
	var live: int = 0
	var adults: int = 0
	for fish: Fish in sim.fish:
		if not is_instance_valid(fish) or fish._dying:
			continue
		live += 1
		hunger += fish.hunger
		stress += fish.stress
		adults += int(fish.maturity == Fish.MATURITY_ADULT)
	return {"fish": live, "adults": adults, "shrimp": sim.shrimp.size(),
		"plants": sim.plants.size(), "biomass": sim.total_plant_biomass,
		"capacity": sim.fish_carrying_capacity_smoothed(), "stocking_ratio": sim.fish_stocking_ratio(),
		"o2": sim.dissolved_o2, "ammonia": sim.water_chemistry.ammonia,
		"hunger": hunger / maxf(1.0, live), "stress": stress / maxf(1.0, live)}
