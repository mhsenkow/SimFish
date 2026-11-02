extends SceneTree

# CREATURE_MOTION_700 leftover ease/arcs (#258–#273, #277–#287, #289/#294/#295).


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_motion_ease_arcs2")
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
	f.id = "ease2_smoke"
	f.init_genome(g)
	f.sim = sim
	f.heading = Vector3.FORWARD
	f.global_position = Vector3(0, 3, 0)
	f.speed = 0.4
	f._spawn_settle_remaining = 0.0

	# #258: fear recover eases fins open.
	f._fear_phase = 5
	f.spooked = 0.6
	var fear0: Dictionary = FishEaseArcs.fear_recover_weights(f, 0.05)
	for i in 80:
		fear0 = FishEaseArcs.fear_recover_weights(f, 0.05)
		f.spooked = maxf(0.0, f.spooked - 0.02)
	t.check(float(fear0.get("fin", 1.0)) < 0.35, "fear fin carriage re-opens")

	# #259: hover depth damps.
	f._hover_depth = 3.0
	f.set_meta("_ease_hover_y", 3.0)
	var hy: float = FishEaseArcs.ease_hover_depth(f, 4.0, 0.05)
	t.check(hy < 3.9, "hover depth eases toward target")

	# #269: saccade uses burst profile (motion_gaze contract via MotionEase.burst).
	t.check(MotionEase.burst(0.2, 0.35, 5.0) > MotionEase.burst(0.05, 0.35, 5.0),
		"saccade attack rises fast")
	t.check(MotionEase.burst(0.9, 0.35, 5.0) < 1.01, "saccade settles to hold")

	# #270: park reverse-scull near arrival.
	var park: Vector3 = FishEaseArcs.park_adjust(f, Vector3(0.2, 0, 0), 0.05)
	t.check(park.length() < 0.2, "park scull is tiny near the spot")

	# #272: music dance blend damps slowly (source contract).
	var mc_src: String = FileAccess.get_file_as_string("res://scripts/music_context.gd")
	t.check(mc_src.contains("MotionEase.damp(_dance_blend"), "dance blend eases over a bar")

	# #273: frustum blend rises from 0 on enter.
	f.set_meta("_ease_was_vis", false)
	f.set_meta("_frustum_blend", 0.0)
	var fw: float = FishEaseArcs.frustum_enter_blend(f, true, 0.02)
	t.check(fw < 0.5, "frustum blend starts low on enter")
	for i in 20:
		fw = FishEaseArcs.frustum_enter_blend(f, true, 0.02)
	t.check(fw > 0.85, "frustum blend settles in ~0.1 s")

	# #277: meander changes smoothly.
	f.set_meta("_wander_kappa", 0.0)
	var m0: Vector3 = FishEaseArcs.wander_meander(f, 0.05, 0.15, 0.5)
	var m1: Vector3 = FishEaseArcs.wander_meander(f, 0.05, 0.15, 0.5)
	t.check(m0.distance_to(m1) < 0.25, "meander steps are continuous")

	# #278: porpoise pitch follows vertical velocity with S-curve.
	t.check(FishEaseArcs.porpoise_pitch(f, 0.8) > 0.1, "rise pitches nose up")
	t.check(FishEaseArcs.porpoise_pitch(f, -0.8) < -0.1, "dive pitches nose down")
	t.check(absf(FishEaseArcs.porpoise_pitch(f, 0.05)) < 0.05, "level swim stays flat")

	# #285 / #286: wall arcs fire near the glass.
	var inward := Vector3(1, 0, 0)
	t.check(FishEaseArcs.corner_arc_steer(f, inward, 0.2, 0.4).length() > 0.05,
		"corner arc steers near wall")
	f.heading = Vector3(-1, 0, 0)
	t.check(FishEaseArcs.glass_parallel_steer(f, inward, 0.3, 0.4).length() > 0.05,
		"glass approach turns parallel")

	# #287: rounded snap is continuous through zero.
	t.check(absf(FishEaseArcs.rounded_snap(0.01)) < 0.2, "snap is soft at zero")
	t.check(FishEaseArcs.rounded_snap(1.2) > 0.9, "snap saturates at peaks")

	# #289 / #295.
	t.check(FishEaseArcs.dying_rock_offset(f, 0.2, 0.05).length() > 0.0, "dying rock is alive")
	t.check(FishEaseArcs.shuffle_hop_arc(f, 0.15, 0.3).y > 0.05, "shuffle hop heaves mid-arc")

	# #271: bottom land eases down.
	f.global_position.y = 0.4
	f.velocity = Vector3(0, -0.1, 0)
	var ly: float = FishEaseArcs.bottom_land_y(f, 0.0, 0.05)
	t.check(ly < 0.4 and ly > 0.0, "bottom land glides toward the bed")

	for i in 30:
		f._motion_substep(1.0 / 60.0, 1.0 / 60.0)
	t.check(f.global_position.is_finite() and f.heading.is_finite(),
		"ease2 hooks keep motion finite")

	f.queue_free()
	host.queue_free()
	await process_frame
	quit(t.finish())
