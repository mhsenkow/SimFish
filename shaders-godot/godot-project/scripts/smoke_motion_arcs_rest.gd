extends SceneTree

# CREATURE_MOTION_700 remaining arcs: #276–#279, #288, #290–#293, #296.


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_motion_arcs_rest")
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
	f.id = "arcs_rest"
	f.init_genome(g)
	f.sim = sim
	f.heading = Vector3.FORWARD
	f.global_position = Vector3(0, 3, 0)
	f.speed = 0.45
	f._spawn_settle_remaining = 0.0

	# #276: curvature follow bends a sharp target into an arc aim.
	f.heading = Vector3(0, 0, -1)
	var sharp: Vector3 = Vector3(1, 0, 0) * f.max_speed
	var bent: Vector3 = FishEaseArcs.curvature_follow(f, sharp, 0.1)
	t.check(bent.normalized().dot(f.heading) > sharp.normalized().dot(f.heading),
		"curvature follow aims inside the turn")

	# #279: air dash phases.
	var rise: Dictionary = FishEaseArcs.air_dash_desired(f, 0.8, 6.0, 1.0, 1.0)
	t.check(str(rise.get("phase")) == "rise" and float(rise.get("target_y")) > 5.0, "air dash rises")
	var gulp: Dictionary = FishEaseArcs.air_dash_desired(f, 0.4, 6.0, 1.0, 1.0)
	t.check(str(gulp.get("phase")) == "gulp" and float(gulp.get("gape")) > 0.5, "air dash gulps")
	var dive: Dictionary = FishEaseArcs.air_dash_desired(f, 0.1, 6.0, 1.0, 1.0)
	t.check(str(dive.get("phase")) == "dive", "air dash dives home")
	t.check((dive.get("desired") as Vector3).y < 0.0, "dive desired points down")

	# #288: school turn centre produces tangent pull.
	f.heading = Vector3(0, 0, -1)
	f.global_position = Vector3(2, 3, 0)
	var turn: Vector3 = FishEaseArcs.school_turn_centre_steer(
		f, Vector3(0, 3, 0), Vector3(1, 0, 0), 1.2)
	t.check(turn.length() > 0.05, "school turn centre steers")

	# #290: shrimp swim arc peaks mid-span.
	var a0: Vector3 = FishEaseArcs.shrimp_swim_arc(Vector3.ZERO, Vector3(2, 0, 0), 0.0)
	var a1: Vector3 = FishEaseArcs.shrimp_swim_arc(Vector3.ZERO, Vector3(2, 0, 0), 0.5)
	var a2: Vector3 = FishEaseArcs.shrimp_swim_arc(Vector3.ZERO, Vector3(2, 0, 0), 1.0)
	t.check(a1.y > a0.y and a1.y > a2.y, "shrimp swim arc peaks mid-flight")

	# #291: flip arcs up early then down late.
	var early: Vector3 = FishEaseArcs.shrimp_flip_arc(Vector3(0, 0, 1), 1.0)
	var late: Vector3 = FishEaseArcs.shrimp_flip_arc(Vector3(0, 0, 1), 0.05)
	t.check(early.y > late.y, "tail flip pitches up then glides")

	# #292: snail fall rocks while descending.
	var s0: Dictionary = FishEaseArcs.snail_fall_step(Vector3(0, 4, 0), 0.8, 0.0, 0.2, 0.05)
	var s1: Dictionary = FishEaseArcs.snail_fall_step(Vector3(0, 4, 0), 0.8, 0.0, 0.9, 0.05)
	t.check(float((s0.get("pos") as Vector3).y) < 4.0, "snail falls")
	t.check(absf(float(s0.get("roll"))) + absf(float(s1.get("roll"))) > 0.01, "snail tumbles")

	# #293: bottom hopper heaves mid-hop.
	t.check(FishEaseArcs.bottom_hopper_arc(0.14, 0.28).y > 0.05, "bottom hopper heaves")

	# #296: smooth arc has lower discrete curvature than a polyline kink.
	var smooth: Array = []
	var kinked: Array = []
	for i in 12:
		var u: float = float(i) / 11.0
		smooth.append(Vector3(sin(u * PI), 0.0, -cos(u * PI)))
		kinked.append(Vector3(u if u < 0.5 else 0.5, 0.0, -u if u < 0.5 else -(1.0 - u)))
	var ks: float = FishEaseArcs.path_curvature_samples(smooth)
	var kk: float = FishEaseArcs.path_curvature_samples(kinked)
	t.check(ks < kk, "smooth arc curvature below kinked path (%.3f < %.3f)" % [ks, kk])

	# Live aerial loop stays finite.
	f.swim_pattern = "shuffle"
	f._aerial_timer = 2.8
	f._aerial_target_y = 6.0
	f._aerial_return_y = 1.2
	f.home_y = 1.2
	for i in 40:
		f._motion_substep(1.0 / 60.0, 1.0 / 60.0)
	t.check(f.global_position.is_finite() and f.heading.is_finite(),
		"air dash loop keeps motion finite")

	f.queue_free()
	host.queue_free()
	await process_frame
	quit(t.finish())
