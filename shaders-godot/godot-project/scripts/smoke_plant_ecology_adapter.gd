extends SceneTree

const Adapter = preload("res://scripts/plant_ecology_adapter.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed: Array[String] = []
	var grid := SubstrateGrid.new()
	root.add_child(grid)
	grid.init(3.0, 3.0, 1.0)
	var ramp: Array = [
		Color8(20, 60, 30), Color8(40, 95, 50), Color8(60, 130, 70),
		Color8(90, 170, 95), Color8(140, 210, 130),
	]
	var hosts: Array[Node] = []
	var lily := LilyPad.new()
	root.add_child(lily)
	lily.init_at(Vector3.ZERO, -1.0)
	hosts.append(lily)
	var cattail := CattailPlant.new()
	root.add_child(cattail)
	cattail.init_at(Vector3.ZERO, Color.GREEN, Color.BROWN, Color.GREEN)
	hosts.append(cattail)
	var nautilus := NautilusPlant.new()
	root.add_child(nautilus)
	nautilus.init_at(Vector3.ZERO, ramp)
	hosts.append(nautilus)
	var moss := FractalMoss.new()
	root.add_child(moss)
	moss.init_at(Vector3.ZERO, ramp)
	hosts.append(moss)
	var plant := Plant.new()
	root.add_child(plant)
	plant.init(6, {"leaf_form": "lance", "max_height": 12})
	hosts.append(plant)
	var floater := FloatingPlant.new()
	root.add_child(floater)
	floater.init_genome({"morph": "duckweed"})
	hosts.append(floater)

	grid.add_at(Vector3.ZERO, 2.0)
	var nutrient_before: float = grid.get_at(Vector3.ZERO)
	for host in hosts:
		var adapter = Adapter.new(host)
		TestSupport.check(failed, adapter.biomass() > 0.0,
			"%s reports biomass" % host.get_class())
		# Holistic #141 — ecology_biomass matches the adapter budget.
		if host.has_method("ecology_biomass"):
			TestSupport.check(failed,
				absf(adapter.biomass() - float(host.call("ecology_biomass"))) < 0.001,
				"%s ecology_biomass matches adapter" % host.get_class())
		TestSupport.check(failed, adapter.nutrient_demand() > 0.0,
			"%s reports nutrient demand" % host.get_class())
		adapter.tick(2.1, grid)
		TestSupport.check(failed,
			host.has_method("ecology_graze") or host.has_method("nibble"),
			"%s exposes grazing" % host.get_class())
	TestSupport.check(failed, grid.get_at(Vector3.ZERO) < nutrient_before,
		"adapter ecology consumes substrate nutrients")
	# Floater must not debit substrate (water-column path owns that sink).
	var floater_grid := SubstrateGrid.new()
	root.add_child(floater_grid)
	floater_grid.init(3.0, 3.0, 1.0)
	floater_grid.add_at(Vector3.ZERO, 2.0)
	var before_f: float = floater_grid.get_at(Vector3.ZERO)
	var f_adapt = Adapter.new(floater)
	f_adapt.tick(2.1, floater_grid)
	TestSupport.check(failed, absf(floater_grid.get_at(Vector3.ZERO) - before_f) < 0.001,
		"floater ecology does not double-debit substrate")
	var death_adapter = Adapter.new(moss)
	var mulm_before: float = grid.get_mulm_at(Vector3.ZERO)
	death_adapter.die(grid)
	TestSupport.check(failed, grid.get_mulm_at(Vector3.ZERO) > mulm_before,
		"adapter death deposits bounded litter")

	quit(TestSupport.report("smoke_plant_ecology_adapter", failed))
