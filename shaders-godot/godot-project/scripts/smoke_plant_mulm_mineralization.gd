extends SceneTree


func _init() -> void:
	var failed: Array[String] = []
	var grid := SubstrateGrid.new()
	root.add_child(grid)
	grid.init(2.0, 2.0, 1.0)
	var p := Vector3.ZERO
	var nutrient_before: float = grid.get_at(p)
	var accepted: float = grid.deposit_litter_at(p, 20.0)
	TestSupport.check(failed, is_equal_approx(accepted, SubstrateGrid.MULM_MAX),
		"mulm accepts only bounded mass")
	TestSupport.check(failed, is_equal_approx(grid.get_at(p), nutrient_before),
		"litter is not instantly mineralized")
	grid.tick(10.0)
	var remaining: float = grid.get_mulm_at(p)
	var released: float = grid.get_at(p) - nutrient_before
	TestSupport.check(failed, remaining < accepted and released > 0.0,
		"mulm mineralizes gradually")
	TestSupport.check(failed, released <= accepted - remaining + 0.0001,
		"mineralization conserves mass")

	var saved: Dictionary = grid.to_save_dict()
	var restored := SubstrateGrid.new()
	root.add_child(restored)
	restored.init(2.0, 2.0, 1.0)
	restored.apply_save_dict(saved)
	TestSupport.check(failed, is_equal_approx(restored.get_mulm_at(p), remaining),
		"mulm roundtrip")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("mulm_flat")
	var migrated := SubstrateGrid.new()
	root.add_child(migrated)
	migrated.init(2.0, 2.0, 1.0)
	migrated.apply_save_dict(legacy)
	TestSupport.check(failed, is_zero_approx(migrated.get_mulm_at(p)),
		"legacy save does not duplicate realized nutrients")

	quit(TestSupport.report("smoke_plant_mulm_mineralization", failed))
