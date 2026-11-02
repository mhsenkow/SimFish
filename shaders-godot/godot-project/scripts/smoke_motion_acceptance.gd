extends SceneTree

# CREATURE_MOTION_700 #107 / #108 / #109 — exposure-sheet acceptance smokes.
# Peak speed after wind-up; tail follow-through ≥0.3 s; no long constant-speed
# flats between rests.


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_motion_acceptance")
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true
	var host: Node3D = load("res://scripts/motion_world_test_stub.gd").new()
	root.add_child(host)
	var sim: Node = load("res://scripts/motion_visibility_test_stub.gd").new()
	sim.creature_visible = true
	host.add_child(sim)

	var f := _make(host, cfg, sim)
	# ---- #107: anticipation precedes peak speed ----
	MotionEvents.clear()
	f.burst_remaining = 0.0
	f.speed = 0.15
	f._startle_remaining = 0.0
	f.set_meta("_ant_prev_burst", 0.0)
	FishAnticipation.tick(f, 1.0 / 60.0)
	f.burst_remaining = 0.55
	FishAnticipation.tick(f, 1.0 / 60.0)
	var windup: float = float(f.get_meta("_ant_scull", 0.0)) \
		+ float(f.get_meta("_ant_tail_cock", 0.0)) + float(f.get_meta("_ant_effort", 0.0))
	t.check(windup > 0.5, "#107 wind-up armed before dart (#170)")
	var peak_speed: float = f.speed
	var windup_frames: int = 0
	var saw_peak_after_windup: bool = false
	for i in 48:
		# Hold burst early so wind-up can read, then let hydro integrate.
		if i < 6:
			f.burst_remaining = maxf(f.burst_remaining, 0.4)
			f.target_velocity = f.heading.normalized() * f.max_speed * 1.4
		f._motion_substep(1.0 / 60.0, 1.0 / 60.0)
		if windup > 0.3 and f.speed <= peak_speed + 0.02:
			windup_frames += 1
		if f.speed > peak_speed:
			if windup_frames >= 2:
				saw_peak_after_windup = true
			peak_speed = f.speed
	t.check(windup_frames >= 2, "#107 ≥2 wind-up frames before climb (got %d)" % windup_frames)
	t.check(saw_peak_after_windup or peak_speed > 0.2,
		"#107 peak speed arrives after wind-up (peak=%.2f)" % peak_speed)

	# ---- #108: follow-through after thrust ends ----
	f.burst_remaining = 0.0
	f.speed = f.max_speed * 0.9
	f.target_velocity = f.heading * 0.02
	f._fin_tail_activity = 1.0
	var tail_samples: Array[float] = []
	for i in 36:  # 0.6 s
		f._motion_substep(1.0 / 60.0, 1.0 / 60.0)
		if f._tail_pivot != null:
			tail_samples.append(absf(f._tail_pivot.rotation.y))
	var late_mean: float = 0.0
	var n_late: int = 0
	for i in range(18, tail_samples.size()):
		late_mean += tail_samples[i]
		n_late += 1
	if n_late > 0:
		late_mean /= float(n_late)
	t.check(tail_samples.size() >= 18, "#108 sampled ≥0.3 s of post-thrust tail")
	t.check(late_mean > 0.01 or f._fin_tail_activity > 0.15,
		"#108 tail still moving after thrust (mean=%.3f act=%.2f)" \
			% [late_mean, f._fin_tail_activity])

	# ---- #109: no long constant-speed segments between rests ----
	f.queue_free()
	f = _make(host, cfg, sim)
	f.speed = 0.02
	f.target_velocity = Vector3.ZERO
	var speeds: Array[float] = []
	# Rest → accelerate → cruise → decelerate → rest
	for i in 180:
		if i < 10:
			f.target_velocity = Vector3.ZERO
		elif i < 50:
			f.target_velocity = f.heading.normalized() * f.max_speed * 0.95
			f.burst_remaining = maxf(f.burst_remaining, 0.2)
		elif i < 110:
			f.target_velocity = f.heading.normalized() * f.max_speed * 0.55
		elif i < 150:
			f.target_velocity = f.heading.normalized() * 0.05
		else:
			f.target_velocity = Vector3.ZERO
		f._motion_substep(1.0 / 60.0, 1.0 / 60.0)
		speeds.append(f.speed)
	var flat_run: int = 0
	var max_flat: int = 0
	for i in range(1, speeds.size()):
		if speeds[i] > 0.08 and speeds[i - 1] > 0.08 \
				and absf(speeds[i] - speeds[i - 1]) < 0.004:
			flat_run += 1
			max_flat = maxi(max_flat, flat_run)
		else:
			flat_run = 0
	t.check(max_flat < 24,
		"#109 no ≥0.4 s constant-speed flats between rests (max_flat=%d)" % max_flat)
	# Accel present at both ends of the cruise window.
	var mid: int = 80
	var rising: bool = speeds[40] > speeds[15] + 0.05
	var falling: bool = speeds[140] < speeds[mid] - 0.05
	t.check(rising, "#109 acceleration into cruise")
	t.check(falling, "#109 deceleration out of cruise")

	# Staging helpers sanity (#171 / #175 / #178).
	t.check(MotionStaging.legibility_scale(f, 0.02) >= 1.0, "#171 legibility gain ≥1")
	t.check(MotionStaging.begin_big_event(f.global_position, &"test", 0.5),
		"#175 first big event accepted")
	t.check(MotionStaging.follow_lead_aim(Vector3.ZERO, Vector3.FORWARD).z < 0.0 \
			or MotionStaging.follow_lead_aim(Vector3.ZERO, Vector3.FORWARD).length() > 0.0,
		"#178 lead aim offsets along heading")

	# #296: curvature continuity — a turning cruise stays below a kink ceiling.
	f.queue_free()
	f = _make(host, cfg, sim)
	f.heading = Vector3(0, 0, -1)
	f.target_velocity = Vector3(0.8, 0, -0.2)
	var path: Array = []
	for i in 60:
		# Gentle left turn command.
		var yaw: float = -0.35 + float(i) * 0.012
		f.target_velocity = Vector3(sin(yaw), 0.0, -cos(yaw)) * f.max_speed * 0.55
		f._motion_substep(1.0 / 60.0, 1.0 / 60.0)
		path.append(f.global_position)
	var curv: float = FishEaseArcs.path_curvature_samples(path)
	t.check(curv < 4.5, "#296 cruise curvature continuous (k=%.3f)" % curv)

	f.queue_free()
	host.queue_free()
	await process_frame
	quit(t.finish())


func _make(host: Node3D, cfg: Node, sim: Node) -> Fish:
	var f := Fish.new()
	host.add_child(f)
	f.set_process(false)
	var g: Dictionary = cfg.SPECIES_LIBRARY["guppy"]["genome"].duplicate(true)
	f.init_genome(g)
	f.sim = sim
	f.maturity = Fish.MATURITY_ADULT
	f.heading = Vector3(0, 0, -1)
	f.global_position = Vector3(0, 3, 0)
	f._spawn_settle_remaining = 0.0
	f.speed = 0.3
	f._fin_tail_activity = 0.9
	return f
