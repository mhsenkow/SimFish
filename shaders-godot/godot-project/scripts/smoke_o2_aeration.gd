extends SceneTree

# Holistic O₂ / aeration: TankConfig drives sim rates; floors match stress band;
# overstocking erodes the equipment guarantee; tick loop reaches steady state.


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	var cfg := get_root().get_node_or_null("TankConfig")
	if cfg == null:
		failed.append("TankConfig autoload missing")
		_report(failed)
		return

	_test_profiles(cfg, failed)
	_test_sync_and_heal(cfg, failed)
	_test_steady_state(cfg, failed)
	_test_overstock_floor(cfg, failed)
	_report(failed)


func _test_profiles(cfg: Node, failed: Array[String]) -> void:
	cfg.aeration_type = "stick"
	cfg.aeration_strength = 1.0
	var rates: Dictionary = SimDriver.compute_aeration_rates(cfg)
	if float(rates.get("air_rate", 0.0)) < 0.65:
		failed.append("stick@1.0 air_rate expected ~0.7 got %.3f" % float(rates["air_rate"]))
	for key in ["none", "disk", "stick", "filter"]:
		cfg.aeration_type = key
		cfg.aeration_strength = 1.0
		var r: Dictionary = SimDriver.compute_aeration_rates(cfg)
		if String(r.get("fixture", "")) != key:
			failed.append("profile %s fixture mismatch" % key)


func _test_sync_and_heal(cfg: Node, failed: Array[String]) -> void:
	cfg.aeration_type = "stick"
	cfg.aeration_strength = 1.0
	var sim: SimDriver = SimDriver.new()
	sim.name = "SmokeO2Sim"
	sim.aeration_air_rate = 0.0
	sim.aeration_fixture = "none"
	sim.dissolved_o2 = 0.0
	sim.sync_aeration_from_config(true)
	if sim.aeration_air_rate < 0.65:
		failed.append("sync should set air_rate from config")
	if sim.dissolved_o2 < 0.45:
		failed.append("sync should heal O2 above stress band (got %.3f)" % sim.dissolved_o2)
	var o2_floor: float = sim._o2_equipment_floor()
	if o2_floor < O2_floor_target("stick", 1.0):
		failed.append("stick@1.0 floor too low: %.3f" % o2_floor)
	cfg.aeration_type = "disk"
	cfg.aeration_strength = 1.0
	sim.sync_aeration_from_config(true)
	if sim._o2_equipment_floor() < O2_floor_target("disk", 1.0):
		failed.append("disk@1.0 floor below stress band: %.3f" % sim._o2_equipment_floor())
	sim.queue_free()


func _test_steady_state(cfg: Node, failed: Array[String]) -> void:
	cfg.aeration_type = "disk"
	cfg.aeration_strength = 0.85
	var sim: SimDriver = _make_tick_sim(cfg, 12, 280)
	sim.day_phase = 0.25
	for _i in 120:
		sim._tick_dissolved_o2(1.0)
	if sim.dissolved_o2 < 0.55:
		failed.append("disk@0.85 + 12 fish day steady O2 low: %.3f" % sim.dissolved_o2)
	sim.day_phase = 0.82
	for _j in 180:
		sim._tick_dissolved_o2(1.0)
	if sim.dissolved_o2 < 0.48:
		failed.append("disk@0.85 + 12 fish night steady O2 low: %.3f" % sim.dissolved_o2)
	sim.queue_free()


func _test_overstock_floor(cfg: Node, failed: Array[String]) -> void:
	cfg.aeration_type = "disk"
	cfg.aeration_strength = 1.0
	var sim: SimDriver = _make_tick_sim(cfg, 48, 40)
	sim.total_plant_biomass = 40
	sim.sync_aeration_from_config(false)
	var equip: float = sim._o2_equipment_floor()
	var effective: float = sim._o2_effective_floor()
	if effective >= equip * 0.85:
		failed.append("overstock should erode O2 floor (equip %.3f eff %.3f)" % [equip, effective])
	cfg.aeration_type = "none"
	cfg.aeration_strength = 1.0
	sim.sync_aeration_from_config(false)
	sim.dissolved_o2 = 0.55
	sim.day_phase = 0.85
	for _k in 300:
		sim._tick_dissolved_o2(1.0)
	if sim.dissolved_o2 > 0.36:
		failed.append("48 fish / no aeration should crash O2 at night (got %.3f)" % sim.dissolved_o2)
	sim.queue_free()


func _make_tick_sim(cfg: Node, n_fish: int, plant_bm: int) -> SimDriver:
	var sim: SimDriver = SimDriver.new()
	sim.name = "SmokeO2Tick"
	sim.total_plant_biomass = plant_bm
	sim.total_photosynthetic_biomass = float(plant_bm) * 0.92
	sim.o2_test_fish_count = n_fish
	sim.sync_aeration_from_config(false)
	sim.dissolved_o2 = 0.82
	sim._tick_carrying_capacity(0.0)
	return sim


static func O2_floor_target(fixture: String, strength: float) -> float:
	var air: float = 0.0
	var flow: float = 0.0
	match fixture:
		"disk":
			air = 1.0 * strength
			flow = 0.15 * strength
		"stick":
			air = 0.7 * strength
			flow = 0.10 * strength
		"filter":
			air = 0.55 * strength
			flow = 1.0 * strength
	return 0.32 + air * 0.28 + flow * 0.10


func _report(failed: Array[String]) -> void:
	if failed.is_empty():
		print("[smoke] o2_aeration OK")
		quit(0)
	else:
		for f in failed:
			push_error("[smoke] " + f)
		quit(1)
