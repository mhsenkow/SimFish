extends SceneTree


func _init() -> void:
	var failed: Array[String] = []
	var grid := SubstrateGrid.new()
	root.add_child(grid)
	grid.init(2.0, 2.0, 1.0)
	var p := Vector3(0.2, 0.0, -0.2)

	TestSupport.check(failed, is_equal_approx(grid.get_iron_availability_at(p), 0.7),
		"legacy iron default")
	TestSupport.check(failed, is_equal_approx(grid.get_co2_availability_at(p), 0.42),
		"legacy CO2 default")
	grid.exchange_water_availability_at(p, 9.0, 9.0, 100.0)
	TestSupport.check(failed, grid.get_iron_availability_at(p) <= SubstrateGrid.IRON_MAX,
		"iron bounded")
	TestSupport.check(failed, grid.get_co2_availability_at(p) <= SubstrateGrid.CO2_MAX,
		"CO2 bounded")
	var iron_before: float = grid.get_iron_availability_at(p)
	var co2_before: float = grid.get_co2_availability_at(p)
	TestSupport.check(failed, grid.consume_iron_at(p, 0.1) > 0.0 \
		and grid.get_iron_availability_at(p) < iron_before, "roots consume iron")
	TestSupport.check(failed, grid.consume_co2_at(p, 0.1) > 0.0 \
		and grid.get_co2_availability_at(p) < co2_before, "roots consume CO2")

	var saved: Dictionary = grid.to_save_dict()
	var restored := SubstrateGrid.new()
	root.add_child(restored)
	restored.init(2.0, 2.0, 1.0)
	restored.apply_save_dict(saved)
	TestSupport.check(failed, is_equal_approx(restored.get_iron_availability_at(p),
		grid.get_iron_availability_at(p)), "iron roundtrip")
	TestSupport.check(failed, is_equal_approx(restored.get_co2_availability_at(p),
		grid.get_co2_availability_at(p)), "CO2 roundtrip")

	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("iron_availability_flat")
	legacy.erase("co2_availability_flat")
	var migrated := SubstrateGrid.new()
	root.add_child(migrated)
	migrated.init(2.0, 2.0, 1.0)
	migrated.apply_save_dict(legacy)
	TestSupport.check(failed, is_equal_approx(migrated.get_iron_availability_at(p), 0.7),
		"legacy save retains old iron behavior")
	TestSupport.check(failed, is_equal_approx(migrated.get_co2_availability_at(p), 0.42),
		"legacy save retains old CO2 behavior")

	quit(TestSupport.report("smoke_plant_substrate_iron_co2", failed))
