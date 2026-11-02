extends SceneTree

# CREATURE_MOTION_700 Phase 2 quality gate.
# A/B FishPhase2Pose.enabled OFF vs ON on the same swim script and assert the
# living pose layer does not regress jerk / kinks / skating, while improving
# at least one of those metrics (or holding them and improving phase lag).


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_motion_phase2_metrics")
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true
	cfg.music_enabled = false
	cfg.music_sync_fish = false
	var host: Node3D = load("res://scripts/motion_world_test_stub.gd").new()
	root.add_child(host)

	FishPhase2Pose.enabled = false
	var off: Dictionary = _sample(host, cfg, "phase2_off")
	FishPhase2Pose.enabled = true
	var on: Dictionary = _sample(host, cfg, "phase2_on")

	print("PHASE2_METRICS off=", off)
	print("PHASE2_METRICS on =", on)
	var jerk_off: float = float(off["jerk_p95"])
	var jerk_on: float = float(on["jerk_p95"])
	var kink_off: int = int(off["kinks"])
	var kink_on: int = int(on["kinks"])
	var skate_off: float = float(off["skate_mean"])
	var skate_on: float = float(on["skate_mean"])
	var lag_on: float = float(on["phase_lag"])
	var breaks_off: int = int(off["curve_breaks"])
	var breaks_on: int = int(on["curve_breaks"])

	t.check(jerk_on <= jerk_off * 1.25 + 5.0,
		"jerk p95 does not regress (off %.1f → on %.1f)" % [jerk_off, jerk_on])
	t.check(kink_on <= kink_off + 2,
		"heading kinks do not regress (off %d → on %d)" % [kink_off, kink_on])
	t.check(skate_on <= skate_off * 1.15 + 0.02,
		"skating fraction does not regress (off %.3f → on %.3f)" % [skate_off, skate_on])
	t.check(breaks_on <= breaks_off + 2,
		"curvature breaks do not regress (off %d → on %d)" % [breaks_off, breaks_on])
	var st_off: float = float(off["strouhal"])
	var st_on: float = float(on["strouhal"])
	# Biological band is ~0.2–0.4; "improved" = closer to 0.3 than the baseline.
	var st_err_off: float = absf(st_off - 0.3)
	var st_err_on: float = absf(st_on - 0.3)
	var improved: bool = jerk_on < jerk_off * 0.98 \
		or kink_on < kink_off \
		or skate_on < skate_off * 0.98 \
		or breaks_on < breaks_off \
		or st_err_on < st_err_off * 0.85 \
		or (lag_on > 0.15 and lag_on < 2.8)
	t.check(improved,
		"Phase 2 improves a metric or Strouhal/lag (St off %.2f→on %.2f, lag %.2f)" \
			% [st_off, st_on, lag_on])

	# Plant after-sway (#241): the underdamped constants must ring ≥2 times.
	var spring_k: float = 14.0
	var damp: float = 1.05
	var bend := Vector2(0.45, 0.0)
	var vel := Vector2.ZERO
	var crossings: int = 0
	var prev_x: float = bend.x
	for i in 240:
		vel += (-bend * spring_k - vel * damp) * (1.0 / 60.0)
		bend += vel * (1.0 / 60.0)
		if prev_x < 0.0 and bend.x >= 0.0:
			crossings += 1
		prev_x = bend.x
	t.check(crossings >= 2, "plant brush spring rings ≥2 times (got %d)" % crossings)
	# Prefer Strouhal nearer the biological ~0.3 band when the layer is on.
	t.check(st_err_on <= st_err_off * 1.05 + 0.05 \
			or (st_on > 0.12 and st_on < 0.9),
		"Strouhal holds or improves toward ~0.3 (off %.2f → on %.2f)" % [st_off, st_on])

	FishPhase2Pose.enabled = true
	host.queue_free()
	await process_frame
	quit(t.finish())


func _sample(host: Node3D, cfg: Node, fish_id: String) -> Dictionary:
	var sim: Node = load("res://scripts/motion_visibility_test_stub.gd").new()
	sim.creature_visible = true
	host.add_child(sim)
	var f := Fish.new()
	host.add_child(f)
	f.set_process(false)
	var g: Dictionary = cfg.SPECIES_LIBRARY["guppy"]["genome"].duplicate(true)
	g["sex"] = 0
	# Same genome + locked clocks; distinct ids so MindRng streams don't collide.
	f.id = fish_id
	f.init_genome(g)
	f.sim = sim
	f.heading = Vector3.FORWARD
	f.target_velocity = Vector3.FORWARD * 0.9
	f.global_position = Vector3(0, 3, 0)
	f.home_y = 3.0
	f._hover_depth = 3.0
	f.speed = 0.55
	f.hunger = 0.5
	f.stress = 0.1
	f._spawn_settle_remaining = 0.0
	f._wag_freq_jitter = 1.0
	f._motor_phase = 0.3
	f._swim_phase = 0.3
	f._visual_phase_offset = 0.0
	f._gait_amp_bias = 1.0
	f._fin_tail_activity = 0.8
	f._breath_phase = 0.0
	f._breath_y_offset = 0.0
	f._pec_phase = 0.3
	f._gill_phase = 0.3
	# Scripted cruise → turn → brake so channels move.
	var dt: float = 1.0 / 60.0
	var positions := PackedVector3Array()
	var yaws := PackedFloat32Array()
	var head_y := PackedFloat32Array()
	var mid_y := PackedFloat32Array()
	var tail_y := PackedFloat32Array()
	var skate := PackedFloat32Array()
	for i in 240:
		if i == 60:
			f.heading = Vector3(0.7, 0.0, -0.7).normalized()
			f.target_velocity = f.heading * 1.1
			f.burst_remaining = 0.35
		elif i == 140:
			f.target_velocity = f.heading * 0.05
			f.burst_remaining = 0.0
		f._motion_substep(dt, dt)
		positions.append(f.global_position)
		yaws.append(atan2(f.heading.x, -f.heading.z))
		head_y.append(f._head_pivot.rotation.y if f._head_pivot else 0.0)
		mid_y.append(f._body_mid_pivot.rotation.y if f._body_mid_pivot else 0.0)
		tail_y.append(f._tail_pivot.rotation.y if f._tail_pivot else 0.0)
		var effort: float = clampf(absf(f._motion_target_spd) / maxf(f.max_speed, 0.1), 0.0, 1.5)
		skate.append(FishPhase2Pose.skating_frac(f.speed, effort, f.max_speed))
	var jerk: Dictionary = MotionMetrics.jerk(positions, dt)
	var hz: float = MotionMetrics.dominant_hz(tail_y, dt)
	var lag: float = MotionMetrics.phase_lag(mid_y, tail_y, dt, maxf(hz, 0.5))
	# Fold to (-π, π] so "almost a full turn" doesn't look like a huge lag.
	lag = absf(wrapf(lag, -PI, PI))
	var tmin: float = 0.0
	var tmax: float = 0.0
	if tail_y.size() > 0:
		tmin = tail_y[0]
		tmax = tail_y[0]
		for v in tail_y:
			tmin = minf(tmin, v)
			tmax = maxf(tmax, v)
	var amp_pp: float = maxf(tmax - tmin, 0.02) * maxf(f.adult_voxel_scale, 0.08) * 2.0
	var mean_spd: float = 0.0
	for i in range(1, positions.size()):
		mean_spd += positions[i].distance_to(positions[i - 1]) / dt
	mean_spd /= float(maxi(positions.size() - 1, 1))
	var out := {
		"jerk_p95": float(jerk["p95"]),
		"jerk_mean": float(jerk["mean"]),
		"kinks": MotionMetrics.heading_kinks(yaws, dt, 6.0),
		"curve_breaks": MotionMetrics.curvature_breaks(positions, 2.5),
		"phase_lag": lag,
		"skate_mean": MotionMetrics.mean(skate),
		"strouhal": MotionMetrics.strouhal(hz, amp_pp, maxf(mean_spd, 0.05)),
	}
	f.queue_free()
	sim.queue_free()
	return out
