extends SceneTree


func _init() -> void:
	var failed: Array[String] = []
	var grid := SubstrateGrid.new()
	root.add_child(grid)
	grid.init(2.0, 2.0, 1.0)
	var p := Vector3.ZERO
	grid.add_seed_lot_at(p, {
		"species_id": "pioneer",
		"succession_stage": 0.0,
		"disturbance_affinity": 1.0,
	}, 0.35)
	grid.add_seed_lot_at(p, {
		"species_id": "climax",
		"succession_stage": 1.0,
		"disturbance_affinity": 0.0,
	}, 0.35)
	grid.add_seed_lot_at(p, {
		"species_id": "dormant",
		"succession_stage": 0.0,
		"disturbance_affinity": 1.0,
	}, 0.25, {"min_age_s": 100.0})
	grid.note_disturbance_at(p, 0.9)
	var blocked: Dictionary = grid.take_eligible_seed_lot_at(
		p, 0.1, {"daylight": 1.0, "nutrient_ok": false})
	_assert(failed, blocked.is_empty(), "bias never overrides environment")
	var chosen: Dictionary = grid.take_eligible_seed_lot_at(
		p, 0.1, {"daylight": 1.0, "nutrient_ok": true})
	_assert(failed, chosen.get("genome", {}).get("species_id", "") == "pioneer",
		"disturbed young cell favors eligible pioneer")
	_assert(failed, chosen.get("genome", {}).get("species_id", "") != "dormant",
		"dormancy remains a hard eligibility gate")

	var saved_grid: Dictionary = grid.to_save_dict()
	var restored_grid := SubstrateGrid.new()
	root.add_child(restored_grid)
	restored_grid.init(2.0, 2.0, 1.0)
	restored_grid.apply_save_dict(saved_grid)
	_assert(failed, is_equal_approx(restored_grid.get_cell_maturity_at(p),
		grid.get_cell_maturity_at(p)), "cell maturity roundtrip")
	_assert(failed, is_equal_approx(restored_grid.get_cell_disturbance_at(p),
		grid.get_cell_disturbance_at(p)), "cell disturbance roundtrip")

	var registry := PlantLineageRegistry.new()
	var genome := {"species_id": "pioneer", "generation": 2}
	var lid: String = registry.record_germination(genome, "2:2")
	registry.register_genome(genome, 77)
	registry.record_establishment(77, "2:2")
	registry.unregister_plant(77)
	var entry: Dictionary = registry.get_entry(lid)
	_assert(failed, int(entry.get("germinations", 0)) == 1,
		"germination recorded")
	_assert(failed, int(entry.get("establishments", 0)) == 1,
		"establishment recorded")
	_assert(failed, int(entry.get("extinctions", 0)) == 1,
		"local extinction recorded")
	for i in 300:
		registry.record_germination({
			"species_id": "s%d" % i,
			"generation": i,
		}, "%d:0" % i)
	_assert(failed, registry.event_history().size() == 256,
		"event history capped")
	var saved_registry: Dictionary = registry.to_save_dict()
	var restored_registry := PlantLineageRegistry.new()
	restored_registry.from_save_dict(saved_registry)
	_assert(failed, restored_registry.event_history().size() == 256,
		"ledger roundtrip retains capped history")

	if failed.is_empty():
		print("[smoke_plant_succession_ledger] PASS")
		quit(0)
	else:
		for msg in failed:
			push_error("[smoke_plant_succession_ledger] " + msg)
		quit(1)


func _assert(failed: Array[String], condition: bool, label: String) -> void:
	if not condition:
		failed.append(label)
