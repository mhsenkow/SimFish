extends SceneTree



func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_epiphyte_manual_placement")
	var world: Node3D = load("res://scripts/epiphyte_placement_test_stub.gd").new()
	root.add_child(world)
	world.sim = SimDriver.new()
	world.fauna_root = Node3D.new()
	var genome: Dictionary = {"is_epiphyte": true, "plant_name": "Test fern", "max_height": 8}
	t.check(not world.spawn_library_entry(genome, "plant"), "hostless epiphyte is refused")
	t.check(not world.last_spawn_failure.is_empty(), "hostless placement supplies a keeper-facing reason")
	t.check(world.spawned_config.is_empty(), "refusal does not plant a substrate substitute")
	t.equals(genome.is_epiphyte, true, "input plant identity remains unchanged")
	world.sync_build_epiphyte_anchors([Vector3(8.0, 2.0, 0.0)])
	t.equals(world._find_nearest_hardscape_anchor(Vector3(-8.0, 2.0, 0.0)), Vector3.ZERO,
		"autonomous search still has its local distance limit")
	t.check(world.spawn_library_entry(genome, "plant"), "manual placement finds a distant host")
	t.check(world.spawned_config.is_epiphyte, "placed fern retains epiphyte traits")
	t.check(world.spawned_at.distance_to(Vector3(8.0, 2.25, 0.0)) < 0.0001,
		"placed fern attaches to the actual host")
	t.equals(world.last_spawn_failure, "", "successful placement clears previous reason")
	world.spawned_config.clear()
	world.sync_build_epiphyte_anchors([])
	t.check(world.spawn_library_entry({"is_epiphyte": false}, "plant"),
		"ordinary rooted plants remain placeable without hardscape")
	world.sim.free()
	world.fauna_root.free()
	world.free()
	quit(t.finish())
