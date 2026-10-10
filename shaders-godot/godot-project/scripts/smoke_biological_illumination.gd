extends SceneTree

const Illumination = preload("res://scripts/tank_illumination.gd")


class NightClock extends Node:
	var bloom_intensity: float = 0.0
	var water_chemistry: Variant = null
	var substrate: Variant = null


	func daylight() -> float:
		return 0.0


	func irradiance() -> float:
		return 1.0


class LocalLampWorld extends Node3D:
	var aim: Vector3 = Vector3.DOWN


	func irradiance_at(pos: Vector3) -> float:
		return LightingRig.beam_coverage(pos, Vector3(0.0, 8.0, 0.0),
			Vector3.ZERO, aim, LightingRig.cone_params(20.0, 20.0, 1.0))


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_biological_illumination")
	_test_source_response(t)
	var cfg: Node = root.get_node("TankConfig")
	_test_sim_and_chemistry(t, cfg)
	_test_stored_carbon(t)
	_test_local_plant_light(t)
	_test_floater_light(t)
	await process_frame
	quit(t.finish())


func _test_source_response(t: TestSupport.Suite) -> void:
	t.approx(Illumination.normalized_irradiance(1.0, 0.5, 0.0, 1.0),
		1.0, "default lamp and noon preserve tuned photosynthesis")
	t.approx(Illumination.normalized_irradiance(1.0, 0.5, 0.0, 0.0),
		1.0, "noon sun still supplies light with the fixture off")
	t.approx(Illumination.normalized_irradiance(0.0, 0.5, 0.0, 1.0),
		1.0, "manual nighttime lamp supplies useful light")
	t.approx(Illumination.normalized_irradiance(1.0, 0.5, 1.0, 0.0),
		0.0, "black room without a fixture has no photosynthetic exposure")
	t.approx(Illumination.normalized_irradiance(1.0, 0.5, 1.0, 1.0),
		1.0, "dark room leaves the working fixture useful")
	t.approx(Illumination.normalized_irradiance(1.0, 1.0, 0.0, 2.0, false),
		0.0, "master blackout wins over every source")
	t.approx(Illumination.normalized_irradiance(1.0, 0.0, 0.0, 0.0),
		0.0, "zero energy does not invent sunlight")
	t.approx(Illumination.normalized_irradiance(NAN, INF, NAN, NAN),
		0.0, "invalid artistic controls cannot poison chemistry")
	var prev: float = -1.0
	for i in 31:
		var output: float = Illumination.normalized_irradiance(
			0.0, 0.0, 0.0, float(i) / 20.0)
		t.check(output >= prev, "dimming never raises relative exposure %d" % i)
		t.in_range(output, 0.0, 1.5, "relative light remains bounded %d" % i)
		prev = output


func _test_sim_and_chemistry(t: TestSupport.Suite, cfg: Node) -> void:
	cfg.global_intensity = 0.5
	cfg.room_darkness = 0.0
	cfg.tank_fixture_intensity = 0.5
	cfg.tank_fixture_color = Color.WHITE
	cfg.tank_lights_on = true
	cfg.light_master_enabled = true
	cfg.fixture_follow_day_cycle = true
	var sim := SimDriver.new()
	sim.day_phase = 0.25
	t.approx(SimGate.irradiance(sim), 1.0, "SimGate publishes effective noon light")
	var original_clock: float = sim.daylight()
	cfg.light_master_enabled = false
	_resample(sim)
	t.approx(sim.irradiance(), 0.0, "render master switch reaches real biology")
	t.approx(sim.daylight(), original_clock, "blackout preserves the circadian clock")
	cfg.light_master_enabled = true
	sim.day_phase = 0.75
	_resample(sim)
	t.approx(sim.irradiance(), 0.0, "automatic fixture gives plants a dark rest")
	cfg.fixture_follow_day_cycle = false
	_resample(sim)
	t.approx(sim.irradiance(), 1.0, "manual nighttime fixture reaches biology")
	t.approx(sim.daylight(), 0.0, "manual lamp does not move an animal's clock")
	cfg.tank_fixture_color = Color.BLACK
	_resample(sim)
	t.approx(sim.irradiance(), 0.0, "black emitter color supplies no useful light")
	cfg.tank_fixture_color = Color(0.25, 0.25, 0.25)
	_resample(sim)
	t.check(sim.irradiance() > 0.0 and sim.irradiance() < 1.0,
		"muted emitter color produces less than white")
	cfg.tank_fixture_color = Color.WHITE
	cfg.tank_lights_on = false
	_resample(sim)
	t.approx(sim.irradiance(), 0.0, "fixture off at night stops photosynthesis")
	cfg.tank_lights_on = true
	sim.total_plant_biomass = 400
	sim.total_photosynthetic_biomass = 400.0
	sim.o2_test_fish_count = 8
	sim.aeration_air_rate = 0.0
	sim.aeration_flow_rate = 0.0
	sim.dissolved_o2 = 0.6
	_resample(sim)
	sim._tick_dissolved_o2(1.0)
	var lit_o2: float = sim.dissolved_o2
	cfg.light_master_enabled = false
	sim.dissolved_o2 = 0.6
	_resample(sim)
	sim._tick_dissolved_o2(1.0)
	t.check(lit_o2 > sim.dissolved_o2,
		"at the same clock time a working lamp produces more O2 than blackout")
	var dark_water := WaterChemistry.new()
	dark_water.dissolved_co2 = 0.42
	dark_water._tick_carbonate(10.0, sim, 400)
	cfg.light_master_enabled = true
	_resample(sim)
	var lit_water := WaterChemistry.new()
	lit_water.dissolved_co2 = 0.42
	lit_water._tick_carbonate(10.0, sim, 400)
	t.check(lit_water.dissolved_co2 < dark_water.dissolved_co2,
		"real carbonate chemistry draws CO2 under the nighttime lamp")
	t.check(lit_water.ph > dark_water.ph,
		"photosynthetic CO2 draw raises pH relative to dark respiration")
	cfg.tank_lights_on = false
	sim.day_phase = 0.25
	cfg.room_darkness = 1.0
	_resample(sim)
	t.approx(sim.irradiance(), 0.0, "room blackout removes solar photosynthesis at noon")
	sim.free()


func _test_stored_carbon(t: TestSupport.Suite) -> void:
	var lit := Plant.new()
	var dark := Plant.new()
	var shade := Plant.new()
	for p in [lit, dark, shade]:
		p._starch = 0.3
		p._light_avg = 0.5
	lit._tick_light_resources(5.0, 1.0, 1.0)
	dark._tick_light_resources(5.0, 1.0, 0.0)
	shade._shade_mult = 0.2
	shade._tick_light_resources(5.0, 1.0, 1.0)
	t.check(lit._starch > 0.3, "working lamp builds stored carbon")
	t.check(dark._starch < 0.3, "dark plant spends stored carbon")
	t.check(dark._starch > 0.0, "short darkness retains reserves for gradual growth")
	t.check(shade._starch < lit._starch, "canopy shade diminishes carbon production")
	t.check(dark._light_avg < lit._light_avg, "acclimation follows actual illumination")
	dark._tick_light_resources(120.0, 1.0, 0.0)
	t.in_range(dark._light_avg, 0.0, 0.5,
		"coarse sleeping-plant update cannot overshoot light acclimation")
	t.approx(dark._starch, 0.0, "prolonged darkness exhausts stored carbon")
	for p in [lit, dark, shade]:
		p.free()


func _resample(sim: SimDriver) -> void:
	# Tests deliberately turn several controls within one frame. Gameplay
	# invalidates once per fixed tick; this hook emulates that tick boundary.
	sim._irradiance_sample_frame = -1


func _test_local_plant_light(t: TestSupport.Suite) -> void:
	var world := LocalLampWorld.new()
	root.add_child(world)
	var sim := NightClock.new()
	sim.name = "SimDriver"
	world.add_child(sim)
	var under := Plant.new()
	world.add_child(under)
	under._world_pos = Vector3(0.0, 2.0, 0.0)
	under._starch = 0.3
	var corner := Plant.new()
	world.add_child(corner)
	corner._world_pos = Vector3(6.0, 2.0, 0.0)
	corner._starch = 0.3
	var lit: float = under._photosynthetic_exposure(sim)
	var unlit: float = corner._photosynthetic_exposure(sim)
	t.check(lit > 0.9 and unlit < 0.01,
		"real narrow CPU cone reaches the plant below and excludes the far corner")
	under._tick_light_resources(5.0, 1.0, lit)
	corner._tick_light_resources(5.0, 1.0, unlit)
	t.check(under._starch > corner._starch,
		"local illumination changes actual plant carbon accumulation")
	under._leaf_states = [{"light_dose": 0.0, "dose_visual": -1.0}]
	under._leaf_groups = [[]]
	under.red_potential = 0.8
	under._tick_leaf_light_dose(45.0, sim)
	t.approx(float(under._leaf_states[0].light_dose), 1.0,
		"red leaf light dose samples the real aimed cone")
	under._tick_nyctinasty(sim)
	var fold: float = under.rotation.x
	world.aim = Vector3.RIGHT
	t.approx(under._photosynthetic_exposure(sim), 0.0,
		"aiming the lamp away removes useful light at the same plant")
	under._tick_leaf_light_dose(45.0, sim)
	t.approx(float(under._leaf_states[0].light_dose), 0.0,
		"leaf light dose follows aim change rather than the day clock")
	under._tick_nyctinasty(sim)
	t.approx(under.rotation.x, fold,
		"photoperiod-driven leaf folding is independent of manual lamp aim")
	world.free()


func _test_floater_light(t: TestSupport.Suite) -> void:
	var world := LocalLampWorld.new()
	root.add_child(world)
	var sim := NightClock.new()
	world.add_child(sim)
	var lit := FloatingPlant.new()
	var dark := FloatingPlant.new()
	for floater in [lit, dark]:
		world.add_child(floater)
		floater.vitality = 0.55
		floater._visual_dirty = false
		floater._light_exposure_avg = 1.0
	lit.global_position = Vector3(0.0, 2.0, 0.0)
	dark.global_position = Vector3(6.0, 2.0, 0.0)
	lit.tick(5.0, world, sim)
	dark.tick(5.0, world, sim)
	t.check(lit.vitality > dark.vitality,
		"actual nighttime lamp feeds surface plants inside its cone")
	t.check(lit.bud_timer > dark.bud_timer,
		"floater budding requires actual local light rather than the clock")
	t.check(dark._light_exposure_avg > 0.8,
		"brief darkness preserves red-root pigmentation memory")
	t.check(lit.flower_stage == FloatingPlant.FlowerStage.NONE,
		"manual nighttime lamp does not force photoperiod flowers open")
	var saved: Dictionary = dark.to_state()
	t.approx(float(saved.light_exposure_avg), dark._light_exposure_avg,
		"floater light acclimation is retained in saved state")
	var restored := FloatingPlant.new()
	world.add_child(restored)
	restored.init_genome(saved)
	t.approx(restored._light_exposure_avg, dark._light_exposure_avg,
		"floater light acclimation restores without a pigment jump")
	world.aim = Vector3.RIGHT
	lit.tick(5.0, world, sim)
	t.check(lit._light_exposure_avg < 1.0 and lit._light_exposure_avg > 0.8,
		"moving the fixture softens surface-pigment response over time")
	world.free()
