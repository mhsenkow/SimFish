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
	_assert(failed, settled, "mote settles within bounded lifetime")
	_assert(failed, state.position.x > 0.1, "flow changes final landing")
	_assert(failed, absf(state.position.x) <= 0.601 and absf(state.position.z) <= 0.601,
		"landing clamps inside tank")
	_assert(failed, is_equal_approx(state.position.y, 0.1), "landing clamps to substrate")
	var fallback := SeedMoteDynamics.make_state(Vector3(0, 0.5, 0), {}, {}, 2.0)
	for _i in 30:
		if SeedMoteDynamics.integrate(fallback, 0.1, Vector3.ZERO, 0.1, 3.0,
				func(x: float, z: float) -> Vector2: return Vector2(x, z)):
			break
	_assert(failed, fallback.position.y <= 0.11, "zero-flow fallback settles")
	if failed.is_empty():
		print("[smoke_plant_reproduction_39] PASS")
		quit(0)
	else:
		for message in failed:
			push_error("[smoke_plant_reproduction_39] " + message)
		quit(1)


func _assert(failed: Array[String], condition: bool, label: String) -> void:
	if not condition:
		failed.append(label)
