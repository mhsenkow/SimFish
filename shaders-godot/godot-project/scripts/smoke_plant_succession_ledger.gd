extends SceneTree

class LineageWorld extends Node3D:
	var plant_lineages := PlantLineageRegistry.new()


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
	TestSupport.check(failed, blocked.is_empty(), "bias never overrides environment")
	var chosen: Dictionary = grid.take_eligible_seed_lot_at(
		p, 0.1, {"daylight": 1.0, "nutrient_ok": true})
	TestSupport.check(failed, chosen.get("genome", {}).get("species_id", "") == "pioneer",
		"disturbed young cell favors eligible pioneer")
	TestSupport.check(failed, chosen.get("genome", {}).get("species_id", "") != "dormant",
		"dormancy remains a hard eligibility gate")

	var saved_grid: Dictionary = grid.to_save_dict()
	var restored_grid := SubstrateGrid.new()
	root.add_child(restored_grid)
	restored_grid.init(2.0, 2.0, 1.0)
	restored_grid.apply_save_dict(saved_grid)
	TestSupport.check(failed, is_equal_approx(restored_grid.get_cell_maturity_at(p),
		grid.get_cell_maturity_at(p)), "cell maturity roundtrip")
	TestSupport.check(failed, is_equal_approx(restored_grid.get_cell_disturbance_at(p),
		grid.get_cell_disturbance_at(p)), "cell disturbance roundtrip")

	var registry := PlantLineageRegistry.new()
	var genome := {"species_id": "pioneer", "generation": 2}
	var lid: String = registry.record_germination(genome, "2:2")
	registry.register_genome(genome, 77)
	registry.record_establishment(77, "2:2")
	registry.unregister_plant(77)
	var entry: Dictionary = registry.get_entry(lid)
	TestSupport.check(failed, int(entry.get("germinations", 0)) == 1,
		"germination recorded")
	TestSupport.check(failed, int(entry.get("establishments", 0)) == 1,
		"establishment recorded")
	TestSupport.check(failed, int(entry.get("extinctions", 0)) == 1,
		"local extinction recorded")

	# Production-shaped ownership: World -> Plants -> Plant. Initialization,
	# establishment, and death must resolve the registry through the container.
	var world := LineageWorld.new()
	root.add_child(world)
	var plants := Node3D.new()
	plants.name = "Plants"
	world.add_child(plants)
	var live := Plant.new()
	live.plant_name = "Ledger Plant"
	plants.add_child(live)
	var live_genome := {
		"plant_name": "Ledger Plant",
		"species_id": "production_shape",
		"is_epiphyte": true,
		"from_seed_bank": true,
		"lineage_cell": "3:4",
	}
	world.plant_lineages.record_germination(live_genome, "3:4")
	live.init(0, live_genome)
	live.init(0, live_genome) # spawn/load retries remain idempotent
	var live_lid: String = PlantLineageRegistry.lineage_id_for(live_genome)
	var live_entry: Dictionary = world.plant_lineages.get_entry(live_lid)
	TestSupport.check(failed, int(live_entry.get("count", 0)) == 1,
		"nested production plant registers exactly once")
	TestSupport.check(failed, int(live_entry.get("establishments", 0)) == 1,
		"nested production plant establishes exactly once")
	live._on_death()
	live._on_death()
	live_entry = world.plant_lineages.get_entry(live_lid)
	TestSupport.check(failed, int(live_entry.get("count", 0)) == 0
			and int(live_entry.get("extinctions", 0)) == 1,
		"nested production plant unregisters with one extinction")
	world.free()

	for i in 300:
		registry.record_germination({
			"species_id": "s%d" % i,
			"generation": i,
		}, "%d:0" % i)
	TestSupport.check(failed, registry.event_history().size() == 256,
		"event history capped")
	var saved_registry: Dictionary = registry.to_save_dict()
	var restored_registry := PlantLineageRegistry.new()
	restored_registry.from_save_dict(saved_registry)
	TestSupport.check(failed, restored_registry.event_history().size() == 256,
		"ledger roundtrip retains capped history")

	quit(TestSupport.report("smoke_plant_succession_ledger", failed))
