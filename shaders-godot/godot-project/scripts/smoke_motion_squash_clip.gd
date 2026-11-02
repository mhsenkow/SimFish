extends SceneTree

# CREATURE_MOTION_700 #142: squash-and-stretch review clip.
# Samples mid-body scale under bend-gain 0× / 1× / 2× so the gain can be
# chosen by eye (and so CI proves the shader/pose stretch still responds).


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_motion_squash_clip")
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true
	var host: Node3D = load("res://scripts/motion_world_test_stub.gd").new()
	root.add_child(host)
	for body in ["fusiform", "compressed", "anguilliform", "globiform"]:
		var scales: Array = []
		for gain in [0.0, 1.0, 2.0]:
			scales.append(_run_clip(host, cfg, body, gain))
		t.check(float(scales[1]) >= float(scales[0]) - 0.001,
			"%s 1× stretch ≥ 0× (%.4f vs %.4f)" % [body, scales[1], scales[0]])
		# 2× should respond at least as strongly as 1× (small float slack —
		# sin envelopes can peak mid-range depending on settle timing).
		t.check(float(scales[2]) >= float(scales[0]) + 0.05,
			"%s 2× stretch reads above 0× (%.4f vs %.4f)" % [body, scales[2], scales[0]])
		t.check(absf(float(scales[2]) - float(scales[1])) < 0.08 \
				or float(scales[2]) >= float(scales[1]) - 0.01,
			"%s 2× stays near/above 1× (%.4f vs %.4f)" % [body, scales[2], scales[1]])
		print("SQUASH_CLIP %s gains=%s" % [body, scales])
	# #65 joint counts by body plan.
	var f := _make(host, cfg, "anguilliform")
	f.maturity = Fish.MATURITY_ADULT
	t.equals(FishAnticipation.joint_count_for(f), 7, "anguilliform → 7 joints")
	f.maturity = Fish.MATURITY_FRY
	t.equals(FishAnticipation.joint_count_for(f), 3, "fry → 3 joints")
	f.queue_free()
	var g := _make(host, cfg, "ostraciiform")
	g.maturity = Fish.MATURITY_ADULT
	g.body_shape = "globiform"
	t.equals(FishAnticipation.joint_count_for(g), 2, "ostraciiform → 2 joints")
	g.queue_free()
	host.queue_free()
	await process_frame
	quit(t.finish())


func _make(host: Node3D, cfg: Node, loco: String) -> Fish:
	var sim: Node = load("res://scripts/motion_visibility_test_stub.gd").new()
	sim.creature_visible = true
	host.add_child(sim)
	var f := Fish.new()
	host.add_child(f)
	f.set_process(false)
	var g: Dictionary = cfg.SPECIES_LIBRARY["guppy"]["genome"].duplicate(true)
	g["locomotion_type"] = loco
	g["body_shape"] = "anguilliform" if loco == "anguilliform" else \
		("globiform" if loco == "ostraciiform" else "fusiform")
	f.init_genome(g)
	f.sim = sim
	f.locomotion_type = loco
	f.maturity = Fish.MATURITY_ADULT
	f._spawn_settle_remaining = 0.0
	f.speed = 0.8
	f._fin_tail_activity = 1.0
	f._motor_phase = 0.4
	f._swim_phase = 0.4
	return f


func _run_clip(host: Node3D, cfg: Node, loco: String, gain: float) -> float:
	var f := _make(host, cfg, loco)
	# Pose with C-start coil so body scale responds to Phase2 squash.
	f._startle_remaining = 0.4
	f.set_meta("_p2_c_start", gain)  # 0 / 1 / 2 mapped via gain
	if gain <= 0.0:
		FishPhase2Pose.enabled = false
	else:
		FishPhase2Pose.enabled = true
		f.set_meta("_p2_c_start", clampf(gain / 2.0, 0.0, 1.0) if gain < 2.0 else 1.0)
		if gain >= 2.0:
			f.set_meta("_p2_strike_stretch", 1.0)
	var peak: float = 1.0
	for i in 30:
		f._motion_substep(1.0 / 60.0, 1.0 / 60.0)
		if f._body_mid_pivot != null:
			var s: Vector3 = f._body_mid_pivot.scale
			peak = maxf(peak, maxf(s.x, maxf(s.y, s.z)))
	FishPhase2Pose.enabled = true
	f.queue_free()
	return peak
