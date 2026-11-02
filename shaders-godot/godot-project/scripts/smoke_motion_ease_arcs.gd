extends SceneTree

# CREATURE_MOTION_700 §I / §J — slow-in/out + arcs helpers.


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_motion_ease_arcs")
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true
	var host: Node3D = load("res://scripts/motion_world_test_stub.gd").new()
	root.add_child(host)
	var sim: Node = load("res://scripts/motion_visibility_test_stub.gd").new()
	sim.creature_visible = true
	host.add_child(sim)

	var f := Fish.new()
	host.add_child(f)
	f.set_process(false)
	var g: Dictionary = cfg.SPECIES_LIBRARY["guppy"]["genome"].duplicate(true)
	f.id = "ease_arcs_smoke"
	f.init_genome(g)
	f.sim = sim
	f.heading = Vector3.FORWARD
	f.global_position = Vector3(0, 3, 0)
	f.speed = 0.5
	f.max_speed = 1.2
	f._spawn_settle_remaining = 0.0

	# #253: critically damped target doesn't jump to raw in one step.
	var raw := Vector3(1.0, 0.0, 0.0)
	var step1: Vector3 = FishEaseArcs.smooth_target_velocity(f, raw, 0.05)
	t.check(step1.distance_to(raw) > 0.05, "steering spring lags the raw target")
	for i in 40:
		step1 = FishEaseArcs.smooth_target_velocity(f, raw, 0.05)
	t.check(step1.distance_to(raw) < 0.08, "steering spring settles on the target")

	# #255: early burst frames amplify thrust.
	f.burst_remaining = 0.4
	f.set_meta("_burst_age", 0.05)
	t.check(FishEaseArcs.explosive_burst_thrust(f, 1.0) > 1.4, "burst impulse early")
	f.set_meta("_burst_age", 0.5)
	t.approx(FishEaseArcs.explosive_burst_thrust(f, 1.0), 1.0, "burst impulse settles", 0.01)

	# #256: yaw decelerates with a cap.
	var limited: float = FishEaseArcs.limit_yaw_decel(2.0, 0.0, 4.0, 0.05)
	t.check(limited > 1.5, "yaw shed is rate-limited (%.3f)" % limited)

	# #257: hover drift is tiny and non-zero when nearly still.
	f.speed = 0.05
	f.burst_remaining = 0.0
	var drift: Vector3 = FishEaseArcs.hover_drift(f, 0.1)
	t.check(drift.length() < 0.05, "hover drift stays small")
	t.check(drift.length() > 0.0, "hover drift is alive")

	# #260 / #261 / #262 damp helpers converge.
	var pec: float = FishEaseArcs.damp_pec_amp(f, 0.5, 0.05)
	for i in 30:
		pec = FishEaseArcs.damp_pec_amp(f, 0.1, 0.05)
	t.check(absf(pec - 0.1) < 0.05, "pec amp damps toward target")
	var wag: float = 2.0
	for i in 40:
		wag = FishEaseArcs.damp_wag_freq(f, 1.0, 0.05)
	t.check(absf(wag - 1.0) < 0.08, "wag freq damps with τ≈0.15")
	var mood: float = 1.5
	for i in 40:
		mood = FishEaseArcs.damp_mood_tempo(f, 0.7, 0.05)
	t.check(absf(mood - 0.7) < 0.1, "mood tempo eases over ≥0.5 s")

	# #275: turn radius grows with speed and length.
	f.adult_voxel_scale = 1.0
	f.locomotion_type = "subcarangiform"
	var r_slow: float = FishEaseArcs.turn_radius(f, 0.2)
	var r_fast: float = FishEaseArcs.turn_radius(f, 1.2)
	t.check(r_fast > r_slow, "faster fish turn wider")
	f.locomotion_type = "anguilliform"
	t.check(FishEaseArcs.turn_radius(f, 0.5) < r_slow * 1.05, "eels turn tighter")

	# #281: far approach bends; near strike straightens.
	var far: Vector3 = FishEaseArcs.curve_approach(f, Vector3(2, 0, 0), 0.55)
	var near: Vector3 = FishEaseArcs.curve_approach(f, Vector3(0.3, 0, 0), 0.55)
	t.check(absf(far.normalized().dot(Vector3.RIGHT)) < 0.999,
		"far approach has lateral bend")
	t.check(near.normalized().dot(Vector3.RIGHT) > 0.99, "near strike is straight")

	# #282: escape is sharp early, then curves.
	f.set_meta("_burst_age", 0.05)
	var early: Vector3 = FishEaseArcs.escape_then_curve(f, Vector3(0, 0, -1))
	f.set_meta("_burst_age", 0.3)
	var late: Vector3 = FishEaseArcs.escape_then_curve(f, Vector3(0, 0, -1))
	t.check(early.normalized().dot(Vector3(0, 0, -1)) > 0.99, "early escape is sharp")
	t.check(late.normalized().dot(Vector3(0, 0, -1)) < 0.99, "late escape curves")

	# Living path stays finite with the new hooks.
	f.burst_remaining = 0.35
	f.speed = 0.6
	f.target_velocity = Vector3(0.8, 0.0, -0.2)
	for i in 45:
		f._motion_substep(1.0 / 60.0, 1.0 / 60.0)
	t.check(f.heading.is_finite() and f.global_position.is_finite(),
		"ease/arcs motion stays finite")
	t.check(f._tail_pivot != null and f._tail_pivot.transform.is_finite(),
		"figure-eight caudal heave stays finite")

	# #266 / #254 surface contracts (FACING_TURN_RATE capped in snail.gd).
	t.check(MotionEase.expo_out(0.2) > MotionEase.expo_out(0.05),
		"drag-shaped ease rises fast then tails")
	var snail_src: String = FileAccess.get_file_as_string("res://scripts/snail.gd")
	t.check(snail_src.contains("FACING_TURN_RATE: float = 0.6"),
		"snails turn at ~0.6 rad/s (#266)")
	var trumpet_src: String = FileAccess.get_file_as_string("res://scripts/trumpet_snail.gd")
	t.check(trumpet_src.contains("_drift_target"),
		"trumpet snails ease drift (#267)")

	f.queue_free()
	host.queue_free()
	await process_frame
	quit(t.finish())
