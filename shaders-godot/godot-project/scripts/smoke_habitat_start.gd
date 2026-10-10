extends SceneTree

class ClockFixture extends SimDriver:
	var tick_count: int = 0
	func _tick(_dt: float) -> void:
		tick_count += 1


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_habitat_start")
	var sim := ClockFixture.new()
	sim.begin_habitat_build()
	root.add_child(sim)
	sim.set_physics_process(false)
	var starting_phase: float = sim.day_phase
	var starting_o2: float = sim.dissolved_o2
	sim.tank_age_s = 400.0
	sim._physics_process(5.0)
	t.equals(sim.tick_count, 0, "partial habitat never ticks ecology")
	t.approx(sim.day_phase, starting_phase, "construction does not advance daylight")
	t.approx(sim.elapsed_runtime_s, 0.0, "construction does not count as keeper time")
	t.approx(sim._cap_smooth, -1.0, "unfinished planting never primes capacity")
	var plant := Plant.new()
	plant.current_height = 360
	plant._health_smooth = 0.75
	sim.plants.append(plant)
	sim.surface_plant_biomass = 20.0
	sim.finish_habitat_build()
	t.equals(sim.total_plant_biomass, 380, "founding canopy includes floating plants")
	t.approx(sim.total_photosynthetic_biomass, 290.0, "founding canopy respects plant health")
	t.equals(sim.fish_carrying_capacity_smoothed(), sim.fish_carrying_capacity(),
		"first carrying capacity uses the finished planting")
	t.check(sim.fish_carrying_capacity_smoothed() > SimDriver.CARRYING_CAPACITY_MIN,
		"a grown planted habitat does not inherit bare-tank capacity")
	t.approx(sim.tank_age_s, 400.0, "ready gate preserves restored tank age")
	t.approx(sim.dissolved_o2, starting_o2, "ready gate preserves restored oxygen")
	sim._physics_process(0.1)
	t.equals(sim.tick_count, 1, "finished habitat starts without construction debt")
	sim.plants.clear()
	sim.total_plant_biomass = 0
	var capacity: float = sim._cap_smooth
	sim._tick_carrying_capacity(0.1)
	t.check(sim._cap_smooth < capacity and sim._cap_smooth > SimDriver.CARRYING_CAPACITY_MIN,
		"later plant loss retains the gradual carrying-capacity response")
	sim.aeration_fixture = "disk"
	sim.water_chemistry.bacteria_colony = 0.06
	var bare_fresh: int = sim.fish_carrying_capacity()
	sim.water_chemistry.apply_established_start()
	t.check(sim.fish_carrying_capacity() > bare_fresh,
		"established bacterial support helps sparse scapes without extra plants")
	sim.aeration_fixture = "none"
	t.equals(sim.fish_carrying_capacity(), SimDriver.CARRYING_CAPACITY_MIN,
		"unfiltered bare tanks still have limited capacity")
	plant.free()
	sim.free()
	quit(t.finish())
