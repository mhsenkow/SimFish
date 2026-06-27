extends SceneTree

# Headless compile+run check for hydrodynamics + flow field (#37).
func _init() -> void:
	var ff := TankFlowField.new()
	ff.configure(8.0, 4.0, 0.5, 6.5, Vector3(0, 6, 0), Vector3(-1, 0, 0), 0.4)
	ff.tick(0.1)
	var sample: Vector3 = ff.sample(Vector3(0.5, 3.0, 0.2))
	ff.deposit(Vector3(0.5, 3.0, 0.2), Vector3(1, 0, 0), 0.2)
	assert(sample.is_finite())
	var prof: Dictionary = Hydrodynamics.profile_for_locomotion("subcarangiform", 0.35)
	var spd: float = Hydrodynamics.integrate_speed(
		0.5, 1.0, Hydrodynamics.stroke_thrust(0.5, prof, 0.5, 1.0, 1.2),
		Hydrodynamics.drag_coeff(0.35, prof), 2.5, 0.05, true)
	assert(spd >= 0.0)
	print("[smoke_hydrodynamics] ok sample=", sample, " spd=", spd)
	quit()
