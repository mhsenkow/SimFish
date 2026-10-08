extends SceneTree
const Scripts = preload("res://scripts/plant_seed_scripts.gd")
const Bank = preload("res://scripts/substrate_seed_bank.gd")

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_seed_resource_integrity")
	root.get_node("TankConfig").capture_mode = true
	var coral_script: Script = load("res://scripts/coral.gd")
	var debug_path: String = "(res://scripts/coral.gd):<GDScript#-9223371980634233312>"
	for value in [coral_script, coral_script.resource_path, debug_path]:
		t.equals(Scripts.path_for(value), "res://scripts/coral.gd", "resource identity survives %s" % typeof(value))
		t.check(Scripts.resolve(value) == coral_script, "coral seed resolves to its actual subclass")
	for bad in ["res://scripts/no_such_plant.gd", "invalid", "res://scripts/fish.gd", "res://assets/not_a_script.png"]:
		t.check(Scripts.resolve(bad) == null, "missing and non-plant resources fail safely")
	var bank = Bank.new()
	bank.init(2, 2)
	bank.add_lot(Vector2i.ZERO, {"script": coral_script, "species_id": "coral",
		"coral_form": "plate", "tip_color": Color(0.2, 0.4, 0.6)}, 0.2)
	var saved: Array = JSON.parse_string(JSON.stringify(bank.to_sparse_save()))
	t.equals(saved[0].lots[0].genome.script, coral_script.resource_path, "bank JSON stores a stable script path")
	t.check(saved[0].lots[0].genome.tip_color is Array, "seed colors are JSON values")
	var restored = Bank.new()
	restored.init(2, 2)
	restored.apply_sparse_save(saved)
	t.check(Scripts.resolve(restored.lots_at(Vector2i.ZERO)[0].genome.script) == coral_script,
		"restored seed retains coral identity")
	bank.add_lot(Vector2i(1, 0), {"species_id": "stem", "plant_name": "", "parent_lineage": "A"}, 0.2)
	bank.add_lot(Vector2i(1, 0), {"species_id": "stem", "plant_name": "", "parent_lineage": "B"}, 0.2)
	t.equals(bank.lots_at(Vector2i(1, 0)).size(), 2, "unnamed offspring keep distinct parent lineages")
	var duplicates: Array = [{"x": 0, "z": 0, "lots": [
		{"genome": {"species_id": "a"}, "quantity": 0.2, "age_s": 10, "viability": 0.8},
		{"genome": {"species_id": "b"}, "quantity": 0.2, "age_s": 20, "viability": 0.6},
		{"genome": {"species_id": "a"}, "quantity": 0.1, "age_s": 30, "viability": 0.4}]}]
	restored.apply_sparse_save(duplicates)
	var lots: Array = restored.lots_at(Vector2i.ZERO)
	t.equals(lots.size(), 3, "reload preserves separate age cohorts")
	t.approx(lots[1].age_s, 20.0, "loading another cohort cannot overwrite a different family age")
	t.approx(lots[1].viability, 0.6, "loading another cohort cannot overwrite a different family viability")
	restored.apply_sparse_save(duplicates)
	t.approx(restored.total_at(Vector2i.ZERO), 0.5, "reapplying a save replaces rather than duplicates seeds")
	t.approx(bank.add_lot(Vector2i(-1, 0), {}, 0.2), 0.0, "invalid cells cannot accept seed mass")
	t.approx(bank.total_at(Vector2i(20, 20)), 0.0, "invalid cells are safe to query")
	t.approx(bank.add_lot(Vector2i.ZERO, {}, NAN), 0.0, "nonfinite seed quantities are rejected")
	t.check(bank.consume(Vector2i.ZERO, 0.0).is_empty(), "zero consumption does not produce an invented encounter")
	var grid := SubstrateGrid.new()
	grid.init(1.0, 1.0)
	var empty_save: Dictionary = grid.to_save_dict()
	grid._seed_lots.add_lot(Vector2i.ZERO, {}, 0.4)
	grid.apply_save_dict(empty_save)
	t.approx(grid._seed_lots.total_at(Vector2i.ZERO), 0.0, "empty structured save clears previous dormant seeds")
	var legacy_save: Dictionary = empty_save.duplicate(true)
	legacy_save.erase("seed_lots")
	legacy_save.seed_bank_flat[0] = 0.3
	grid.apply_save_dict(legacy_save)
	grid.apply_save_dict(legacy_save)
	t.approx(grid._seed_lots.total_at(Vector2i.ZERO), 0.3, "repeated legacy restore cannot multiply dormant seeds")
	grid.free()
	var world: Node3D = load("res://scripts/seedling_world_test_stub.gd").new()
	root.add_child(world)
	world.plants_root = Node3D.new()
	world.add_child(world.plants_root)
	world.sim = SimDriver.new()
	world.sim.name = "SimDriver"
	world.add_child(world.sim)
	world.sim.set_physics_process(false)
	world.sim.set_process(false)
	var cfg: Dictionary = {"script": debug_path, "coral_form": "plate", "no_mutate": true,
		"tip_color": [0.2, 0.4, 0.6, 1.0], "max_height": 3, "spawn_initial_height": 1}
	world.spawn_seedling(Vector3(1, 0, 0), [], 2, cfg)
	var coral: Plant = world.plants_root.get_child(0)
	t.check(coral is Coral, "real seedling spawn repairs the screenshot's broken path")
	t.equals(coral.get("coral_form"), "plate", "coral seedling retains its parent's form")
	t.check((coral.get("tip_color") as Color).is_equal_approx(Color(0.2, 0.4, 0.6)), "coral tip color survives JSON")
	world.relocate = true
	world.spawn_seedling(Vector3(1, 0, 0), [], 0, {"no_mutate": true})
	var moved: Plant = world.plants_root.get_child(1)
	t.approx(moved.global_position.y, 1.2, "relocated seedlings use the destination terrain height")
	world.full = true
	world.spawn_seedling(Vector3.ZERO, [], 0, {"from_seed_bank": true})
	t.equals(world.plants_root.get_child_count(), 2, "seed-bank reproduction respects plant capacity")
	world.spawn_seedling(Vector3.ZERO, [], 0, {"no_mutate": true})
	t.equals(world.plants_root.get_child_count(), 3, "deliberate planting remains possible at capacity")
	t.check((coral.get_seed_config().script) is String, "live seed production uses stable resource paths")
	world.queue_free()
	await process_frame
	quit(t.finish())
