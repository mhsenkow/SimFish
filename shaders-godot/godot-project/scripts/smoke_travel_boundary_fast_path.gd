extends SceneTree



func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_travel_boundary_fast_path")
	var world: Node3D = load("res://scripts/travel_boundary_test_stub.gd").new()
	root.add_child(world)
	var sim := SimDriver.new()
	world.add_child(sim)
	sim.set_physics_process(false)
	var fish := Fish.new()
	world.add_child(fish)
	fish.set_process(false)
	fish.sim = sim
	for shape in ["box", "triangle", "hex", "cylinder", "sphere"]:
		world.TANK_SHAPE = shape
		world._footprint_cache = null
		var origin := Vector3(0.0, world.SUBSTRATE_DEPTH + 0.8, 0.0)
		world.clamp_calls = 0
		t.approx(fish._max_inside_travel(origin, Vector3.RIGHT, 0.1, 0.25, 0.12),
			0.1, "%s accepts the full unobstructed step" % shape)
		t.equals(world.clamp_calls, 1, "%s interior step uses one clamp" % shape)
		for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.UP, Vector3.DOWN]:
			var expected: float = _reference(world, origin, direction, 30.0, 0.25, 0.12)
			var actual: float = fish._max_inside_travel(origin, direction, 30.0, 0.25, 0.12)
			t.approx(actual, expected, "%s boundary travel matches conservative search" % shape, 0.002)
			t.check((origin + direction * actual).distance_squared_to(
				world.clamp_xyz_in_tank(origin + direction * actual, 0.25, 0.12)) < 0.000001,
				"%s travel endpoint respects body clearance" % shape)
		# World permits emergent plants above water. Fish must still stop
		# at the submerged ceiling even when that far endpoint fits glass.
		var emergent_length: float = world.WATER_HEIGHT + 0.125 - origin.y
		var submerged: float = fish._max_inside_travel(origin, Vector3.UP,
			emergent_length, 0.1, 0.02)
		t.approx(submerged, _reference(world, origin, Vector3.UP,
			emergent_length, 0.1, 0.02), "%s emergent endpoint retains conservative search" % shape)
		t.check(origin.y + submerged <= world.WATER_HEIGHT - 0.12 + 0.001,
			"%s fish cannot shortcut the water surface" % shape)
	t.approx(fish._max_inside_travel(Vector3.ZERO, Vector3.ZERO, 1.0, 0.25, 0.12),
		0.0, "zero direction is rejected")
	t.approx(fish._max_inside_travel(Vector3.ZERO, Vector3.RIGHT, -1.0, 0.25, 0.12),
		0.0, "negative travel is rejected")
	world.free()
	quit(t.finish())


func _reference(world: Node, origin: Vector3, direction: Vector3, length: float,
		margin: float, radius: float) -> float:
	var lo: float = 0.0
	var hi: float = length
	for i in 14:
		var mid: float = (lo + hi) * 0.5
		var probe: Vector3 = origin + direction * mid
		if probe.distance_squared_to(world.clamp_xyz_in_tank(probe, margin, radius)) < 1e-10:
			lo = mid
		else:
			hi = mid
	return lo
