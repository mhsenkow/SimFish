extends SceneTree

const SeedMoteDynamics = preload("res://scripts/seed_mote_dynamics.gd")


func _init() -> void:
	var failed: Array[String] = []
	var state := SeedMoteDynamics.make_state(
		Vector3(0.0, 2.0, 0.0), {"species_id": "flow_seed"}, {}, 8.0)
	var settled := false
	for _i in 80:
		settled = SeedMoteDynamics.integrate(
			state, 0.1, Vector3(0.5, 0.0, 0.2), 0.1, 3.0,
			func(x: float, z: float) -> Vector2:
				return Vector2(clampf(x, -0.6, 0.6), clampf(z, -0.6, 0.6)))
		if settled:
			break
	TestSupport.check(failed, settled, "mote settles within bounded lifetime")
	TestSupport.check(failed, state.position.x > 0.1, "flow changes final landing")
	TestSupport.check(failed, absf(state.position.x) <= 0.601 and absf(state.position.z) <= 0.601,
		"landing clamps inside tank")
	TestSupport.check(failed, is_equal_approx(state.position.y, 0.1), "landing clamps to substrate")
	var fallback := SeedMoteDynamics.make_state(Vector3(0, 0.5, 0), {}, {}, 2.0)
	for _i in 30:
		if SeedMoteDynamics.integrate(fallback, 0.1, Vector3.ZERO, 0.1, 3.0,
				func(x: float, z: float) -> Vector2: return Vector2(x, z)):
			break
	TestSupport.check(failed, fallback.position.y <= 0.11, "zero-flow fallback settles")
	quit(TestSupport.report("smoke_plant_reproduction_39", failed))
