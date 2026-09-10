extends SceneTree

const SeedMoteDynamics = preload("res://scripts/seed_mote_dynamics.gd")


func _init() -> void:
	var failed: Array[String] = []
	var state := SeedMoteDynamics.make_state(
		Vector3(0, 2.0, 0), {"species_id": "cattail"}, {}, 1.0, true, 0.18)
	var finished := false
	for _i in 20:
		finished = SeedMoteDynamics.integrate(
			state, 0.1, Vector3(0.4, 0, 0.1), 0.1, 2.0,
			func(x: float, z: float) -> Vector2: return Vector2(x, z))
		if finished:
			break
	_assert(failed, finished, "surface mote lifetime is bounded")
	_assert(failed, is_equal_approx(state.position.y, 1.96),
		"puff remains on water surface")
	_assert(failed, state.position.x > 0.05, "puff rides surface flow")
	_assert(failed, is_equal_approx(float(state.quantity), 0.18),
		"puff carries bounded seed quantity")
	if failed.is_empty():
		print("[smoke_plant_reproduction_44] PASS")
		quit(0)
	else:
		for message in failed:
			push_error("[smoke_plant_reproduction_44] " + message)
		quit(1)


func _assert(failed: Array[String], condition: bool, label: String) -> void:
	if not condition:
		failed.append(label)
