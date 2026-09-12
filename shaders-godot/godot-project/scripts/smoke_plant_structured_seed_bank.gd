extends SceneTree


func _init() -> void:
	var failed: Array[String] = []
	var grid := SubstrateGrid.new()
	root.add_child(grid)
	grid.init(2.0, 2.0, 1.0)
	var p := Vector3.ZERO
	var genome := {
		"species_id": "crypt.test",
		"plant_name": "Copper",
		"generation": 3,
		"dormancy_type": "light",
	}
	grid.add_seed_lot_at(p, genome, 0.4, {"type": "light", "min_age_s": 12.0})
	var lots: Array = grid.get_seed_lots_at(p)
	TestSupport.check(failed, lots.size() == 1, "structured lot created")
	var lot: Dictionary = lots[0]
	TestSupport.check(failed, String(lot.get("genome_id", "")).contains("crypt.test"),
		"genome identity retained")
	TestSupport.check(failed, is_equal_approx(float(lot.get("quantity", 0.0)), 0.4),
		"quantity retained")
	grid.tick_channels(20.0)
	lot = grid.get_seed_lots_at(p)[0]
	TestSupport.check(failed, float(lot.get("age_s", 0.0)) >= 20.0, "age advances")
	TestSupport.check(failed, float(lot.get("viability", 1.0)) < 1.0, "viability decays")
	TestSupport.check(failed, lot.get("dormancy", {}).get("type", "") == "light",
		"dormancy retained")

	var encoded: String = JSON.stringify(grid.to_save_dict())
	var decoded: Variant = JSON.parse_string(encoded)
	var restored := SubstrateGrid.new()
	root.add_child(restored)
	restored.init(2.0, 2.0, 1.0)
	restored.apply_save_dict(decoded)
	var restored_lot: Dictionary = restored.get_seed_lots_at(p)[0]
	TestSupport.check(failed, restored_lot.get("genome", {}).get("species_id", "") == "crypt.test",
		"JSON save roundtrip retains genome")
	TestSupport.check(failed, is_equal_approx(float(restored_lot.get("quantity", 0.0)),
		float(lot.get("quantity", 0.0))), "JSON save roundtrip retains mass")

	var legacy: Dictionary = grid.to_save_dict()
	legacy.erase("seed_lots")
	var migrated := SubstrateGrid.new()
	root.add_child(migrated)
	migrated.init(2.0, 2.0, 1.0)
	migrated.apply_save_dict(legacy)
	var migrated_lots: Array = migrated.get_seed_lots_at(p)
	TestSupport.check(failed, migrated_lots.size() == 1, "scalar save migrates to one lot")
	TestSupport.check(failed, String((migrated_lots[0] as Dictionary).get(
		"genome_id", "")) == "legacy:anonymous", "scalar lot is anonymous")
	TestSupport.check(failed, is_equal_approx(migrated.get_seed_bank_at(p),
		float(legacy.seed_bank_flat[10])), "scalar quantity preserved")

	for i in 20:
		grid.add_seed_lot_at(p, {"species_id": "s%d" % i}, 0.02)
	TestSupport.check(failed, grid.get_seed_lots_at(p).size() <= 8, "lot count bounded")
	TestSupport.check(failed, grid.get_seed_bank_at(p) <= 1.0, "cell quantity bounded")

	quit(TestSupport.report("smoke_plant_structured_seed_bank", failed))
