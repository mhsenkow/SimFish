class_name FishEaseArcs
extends RefCounted

# CREATURE_MOTION_700 §I / §J — slow-in/out + arcs helpers for living fish.
# Critically-damped steering, drag-shaped coast, turn-exit easing, hover drift,
# turn-radius law, curved approaches.


static var enabled: bool = true


static func _meta_v3(f: Fish, key: String, fallback: Vector3) -> Vector3:
	if f.has_meta(key):
		return f.get_meta(key) as Vector3
	return fallback


static func _meta_f(f: Fish, key: String, fallback: float) -> float:
	if f.has_meta(key):
		return float(f.get_meta(key))
	return fallback


static func smooth_target_velocity(f: Fish, raw: Vector3, dt: float) -> Vector3:
	# #253: brain sets desired at 10 Hz; critically damp the written target.
	# Analytical critically-damped step (unconditionally stable for any dt;
	# explicit Euler at ω=9, dt=0.1 had 1−2ωdt = −0.8 and rang at 10 Hz).
	if not enabled or f == null or dt <= 0.0:
		return raw
	var cur: Vector3 = _meta_v3(f, "_ease_target_v", f.target_velocity)
	var vel: Vector3 = _meta_v3(f, "_ease_target_acc", Vector3.ZERO)
	if not cur.is_finite() or not vel.is_finite():
		cur = raw
		vel = Vector3.ZERO
	var omega: float = 7.5
	var odt: float = clampf(omega * dt, 0.0, 6.0)
	var e: float = exp(-odt)
	var diff: Vector3 = cur - raw
	var next_cur: Vector3 = raw + (diff * (1.0 + odt) + vel * dt) * e
	var next_vel: Vector3 = (vel * (1.0 - odt) - diff * (omega * odt)) * e
	f.set_meta("_ease_target_v", next_cur)
	f.set_meta("_ease_target_acc", next_vel)
	return next_cur


static func explosive_burst_thrust(f: Fish, stroke_push: float) -> float:
	# #255: early burst frames get an impulse so peak speed arrives in ~2–4 beats.
	if not enabled or f == null or f.burst_remaining <= 0.05:
		return stroke_push
	var age: float = _meta_f(f, "_burst_age", 0.0)
	if age < 0.14:
		return stroke_push * lerpf(2.4, 1.0, age / 0.14)
	return stroke_push


static func tick_burst_age(f: Fish, dt: float) -> void:
	if f.burst_remaining > 0.05:
		f.set_meta("_burst_age", _meta_f(f, "_burst_age", 0.0) + dt)
	else:
		f.set_meta("_burst_age", 0.0)


static func limit_yaw_decel(prev_rate: float, new_rate: float, max_decel: float, dt: float) -> float:
	# #256: angular deceleration capped so aligned fish don't shed yaw in one frame.
	if not enabled or dt <= 0.0:
		return new_rate
	# Slowing toward zero (or any smaller |rate|) is rate-limited.
	if absf(new_rate) < absf(prev_rate) - 1e-6:
		var max_drop: float = max_decel * dt
		var drop: float = absf(prev_rate) - absf(new_rate)
		if drop > max_drop:
			return signf(prev_rate) * (absf(prev_rate) - max_drop)
	return new_rate


static func hover_drift(f: Fish, dt: float) -> Vector3:
	# #257: ±0.02 u ease in/out while hovering.
	if not enabled or f == null:
		return Vector3.ZERO
	if f.burst_remaining > 0.05:
		return Vector3.ZERO
	var t: float = _meta_f(f, "_hover_drift_t", 0.0) + dt
	f.set_meta("_hover_drift_t", t)
	# Velocity amplitude ≈ 0.02 u/s, eased so it reads as a moving hold.
	var amp: float = 0.02 * (0.35 + 0.65 * MotionEase.sine_in_out(fposmod(t * 0.35, 1.0)))
	var side: Vector3 = Vector3(-f.heading.z, 0.0, f.heading.x)
	if side.length_squared() < 1e-6:
		side = Vector3.RIGHT
	return (f.heading * sin(t * 1.1) + side.normalized() * cos(t * 0.85)) * amp


static func damp_pec_amp(f: Fish, pec_amp: float, dt: float) -> float:
	# #260
	var prev: float = _meta_f(f, "_ease_pec_amp", pec_amp)
	var next: float = MotionEase.damp(prev, pec_amp, 10.0, dt)
	f.set_meta("_ease_pec_amp", next)
	return next


static func damp_wag_freq(f: Fish, wag_freq: float, dt: float) -> float:
	# #261 τ ≈ 0.15 s → λ ≈ 6.7
	var prev: float = _meta_f(f, "_ease_wag_freq", wag_freq)
	var next: float = MotionEase.damp(prev, wag_freq, 6.7, dt)
	f.set_meta("_ease_wag_freq", next)
	return next


static func damp_mood_tempo(f: Fish, mult: float, dt: float) -> float:
	# #262 over ≥0.5 s
	var prev: float = _meta_f(f, "_ease_mood_tempo", mult)
	var next: float = MotionEase.damp(prev, mult, 2.2, dt)
	f.set_meta("_ease_mood_tempo", next)
	return next


static func dance_freeze_amp(f: Fish, freeze: float, dt: float) -> float:
	# #263: ease amp toward zero with a last flick; breath stays alive.
	var prev: float = _meta_f(f, "_ease_dance_freeze", 0.0)
	var next: float = MotionEase.damp(prev, freeze, 5.0, dt)
	f.set_meta("_ease_dance_freeze", next)
	if next > 0.05 and prev < next:
		# Small flick on rising freeze edge.
		return next
	return next


static func carry_blend(f: Fish, carried: float, dt: float) -> float:
	# #268
	var prev: float = _meta_f(f, "_ease_carried", carried)
	var next: float = MotionEase.damp(prev, carried, 2.0, dt)
	f.set_meta("_ease_carried", next)
	return next


static func turn_radius(f: Fish, speed: float) -> float:
	# #275: r_min = k · L · (1 + U/U_ref). L ≈ body length in tank units.
	var L: float = maxf(f.adult_voxel_scale * 4.5, 0.25)
	var k: float = 0.55
	match f.locomotion_type:
		"anguilliform": k = 0.35
		"thunniform": k = 0.75
		"ostraciiform": k = 0.85
		"labriform": k = 0.4
	var U_ref: float = maxf(f.max_speed, 0.2)
	return k * L * (1.0 + speed / U_ref)


static func max_yaw_from_radius(f: Fish, speed: float) -> float:
	var r: float = turn_radius(f, speed)
	if r <= 1e-4:
		return 4.0
	# Floor keeps mid-water fish responsive; ceiling caps spin.
	return clampf(speed / r, 0.55, 5.5)


static func curve_approach(_f: Fish, to_goal: Vector3, strike_dist: float = 0.55) -> Vector3:
	# #281: curve while far, straighten into the strike.
	if to_goal.length_squared() < 1e-6:
		return to_goal
	var dist: float = to_goal.length()
	if dist < strike_dist:
		return to_goal.normalized()
	var side: Vector3 = to_goal.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		return to_goal.normalized()
	side = side.normalized()
	var bend: float = clampf((dist - strike_dist) / maxf(dist, 0.1), 0.0, 0.55)
	return (to_goal.normalized() + side * bend * 0.35).normalized()


static func park_adjust(f: Fish, to_spot: Vector3, dt: float) -> Vector3:
	# #270: final glide + tiny reverse-scull at rest arrival.
	if to_spot.length() > 0.55:
		return to_spot.normalized() * 0.35
	var t: float = _meta_f(f, "_park_t", 0.0) + dt
	f.set_meta("_park_t", t)
	var scull: float = sin(t * 6.0) * 0.08
	return -to_spot.normalized() * scull


static func escape_then_curve(f: Fish, flee_dir: Vector3) -> Vector3:
	# #282: sharp escape heading early, then curve.
	if flee_dir.length_squared() < 1e-6:
		return flee_dir
	var age: float = _meta_f(f, "_burst_age", 0.0)
	if age < 0.12:
		return flee_dir.normalized()
	var side: Vector3 = flee_dir.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		return flee_dir.normalized()
	return (flee_dir.normalized() + side.normalized() * 0.25).normalized()


static func fear_recover_weights(f: Fish, dt: float) -> Dictionary:
	# #258: after flight, fin carriage re-opens and breath slows over 3–10 s.
	if not enabled or f == null:
		return {"fin": 0.0, "breath": 1.0}
	var phase: int = int(f.get("_fear_phase")) if f.get("_fear_phase") != null else 0
	var want_clamp: float = 0.0
	if phase >= 1 and phase <= 3:  # freeze/flee/hide
		want_clamp = 1.0
	elif phase == 4 or phase == 5:  # peek/recover
		want_clamp = 0.45 if phase == 4 else 0.2
	elif f.spooked > 0.25:
		want_clamp = clampf(f.spooked, 0.0, 0.7)
	# λ ≈ 0.35 → ~3 s to reopen; spooked keeps a longer tail up to ~10 s.
	var lam: float = lerpf(0.35, 0.12, clampf(f.spooked, 0.0, 1.0))
	var fin: float = MotionEase.damp(_meta_f(f, "_fear_fin", 0.0), want_clamp, lam, dt)
	f.set_meta("_fear_fin", fin)
	var breath_tgt: float = lerpf(1.0, 1.7, fin)
	var breath: float = MotionEase.damp(_meta_f(f, "_fear_breath", 1.0), breath_tgt, lam, dt)
	f.set_meta("_fear_breath", breath)
	return {"fin": fin, "breath": breath}


static func ease_hover_depth(f: Fish, raw_hover: float, dt: float) -> float:
	# #259: depth targets ease in/out (bettas keep a slight bounce).
	if not enabled or f == null:
		return raw_hover
	var prev: float = _meta_f(f, "_ease_hover_y", raw_hover)
	# Only engage the spring when the target actually moved; otherwise return
	# the raw value so steady cruise stays frame-rate identical (#72).
	if absf(raw_hover - prev) < 1e-5:
		f.set_meta("_ease_hover_y", raw_hover)
		return raw_hover
	var bounce: bool = f.species == "betta" or f.labyrinth_breather
	var lam: float = 2.4 if bounce else 3.6
	var next: float = MotionEase.damp(prev, raw_hover, lam, dt)
	if bounce and absf(raw_hover - prev) > 0.08:
		next += sin(_meta_f(f, "_hover_drift_t", 0.0) * 5.0) * 0.012
	f.set_meta("_ease_hover_y", next)
	return next


static func porpoise_pitch(f: Fish, vy: float) -> float:
	# #278: pitch follows vertical velocity on an S-curve.
	if not enabled:
		return 0.0
	var n: float = clampf(vy / maxf(f.max_speed * 0.45, 0.15), -1.0, 1.0)
	# Smoothstep S-curve keeps starts/ends soft.
	var s: float = MotionEase.smooth(absf(n)) * signf(n)
	return s * 0.42


static func wander_meander(f: Fish, dt: float, y_wander: float, amp: float) -> Vector3:
	# #277: Ornstein–Uhlenbeck walk on path curvature → smooth meanders.
	# `amp` is the travel-bias magnitude (same units as the old discrete
	# heading_offset refresh). Shrinking it further left fish thrashing in
	# place: body clocks kept beating while the steer sum cancelled to ~0.
	# Use a slow dedicated meander clock (never `_motor_phase`, which runs at
	# ~25 rad/s and aliases into a 10 Hz jitter when sampled at brain ticks).
	if not enabled or f == null:
		return f.heading_offset
	var travel: float = maxf(amp, 0.28)
	var wt: float = _meta_f(f, "_wander_clock", float(f.get_instance_id() & 63) * 0.37) + dt
	f.set_meta("_wander_clock", wt)
	var kappa: float = _meta_f(f, "_wander_kappa", 0.0)
	var theta: float = 0.55  # mean-reversion
	var sigma: float = 0.7 * travel
	var noise: float = sin(wt * 0.55) * 0.65 + cos(wt * 0.23 + 1.1) * 0.35
	kappa += (-theta * kappa + sigma * noise) * dt
	kappa = clampf(kappa, -1.1, 1.1)
	f.set_meta("_wander_kappa", kappa)
	var yaw: float = _meta_f(f, "_wander_yaw", atan2(f.heading.x, -f.heading.z))
	yaw += kappa * dt * 1.15
	f.set_meta("_wander_yaw", yaw)
	var y: float = sin(wt * 0.38) * y_wander
	var target_off := Vector3(sin(yaw) * travel, y, -cos(yaw) * travel)
	# Blend direction smoothly but keep magnitude near `travel` so cruise
	# still relocates between home-pull / mill contributions.
	var blended: Vector3 = f.heading_offset.lerp(target_off, 1.0 - exp(-dt * 3.2))
	var flat := Vector3(blended.x, 0.0, blended.z)
	if flat.length_squared() > 1e-6:
		flat = flat.normalized() * travel
		blended = Vector3(flat.x, blended.y, flat.z)
	return blended


static func corner_arc_steer(f: Fish, inward: Vector3, clearance: float, body_m: float) -> Vector3:
	# #285: start perimeter turns early at the turn-radius distance.
	if not enabled or inward.length_squared() < 1e-6:
		return Vector3.ZERO
	var r: float = turn_radius(f, f.speed)
	var start: float = r + body_m * 1.2
	if clearance > start:
		return Vector3.ZERO
	var t: float = 1.0 - clampf(clearance / maxf(start, 0.1), 0.0, 1.0)
	# Turn parallel to the wall: blend heading toward tangent (perp to inward).
	var tangent: Vector3 = Vector3(-inward.z, 0.0, inward.x)
	if tangent.dot(f.heading) < 0.0:
		tangent = -tangent
	return (tangent.normalized() * t + inward.normalized() * t * 0.35) * f.max_speed * 0.55


static func glass_parallel_steer(f: Fish, inward: Vector3, clearance: float, body_m: float) -> Vector3:
	# #286: approaching the glass turns parallel before arrival.
	if not enabled or inward.length_squared() < 1e-6:
		return Vector3.ZERO
	var approach: float = body_m * 3.2 + 0.8
	if clearance > approach:
		return Vector3.ZERO
	# Only when heading into the glass.
	if f.heading.dot(-inward) < 0.25:
		return Vector3.ZERO
	var t: float = 1.0 - clampf(clearance / approach, 0.0, 1.0)
	var tangent: Vector3 = Vector3(-inward.z, 0.0, inward.x)
	if tangent.dot(f.heading) < 0.0:
		tangent = -tangent
	return tangent.normalized() * t * f.max_speed * 0.7


static func rounded_snap(phase: float) -> float:
	# #287: keep the dart-courtship snap but round each corner over ~2 frames.
	var s: float = sin(phase)
	# Soft clip through zero instead of sign().
	return clampf(s * 4.0, -1.0, 1.0)


static func dying_rock_offset(f: Fish, progress: float, dt: float) -> Vector3:
	# #289: sinking corpses rock like a falling leaf.
	if not enabled or f == null:
		return Vector3.ZERO
	var t: float = _meta_f(f, "_die_rock_t", 0.0) + dt
	f.set_meta("_die_rock_t", t)
	var amp: float = 0.12 * (1.0 - progress * 0.55)
	return Vector3(sin(t * 2.4) * amp, 0.0, cos(t * 1.7) * amp * 0.7)


static func shuffle_hop_arc(_f: Fish, hop_t: float, hop_dur: float) -> Vector3:
	# #295: low parabolic hop with a vertical heave.
	if not enabled or hop_dur <= 1e-4:
		return Vector3.ZERO
	var u: float = 1.0 - clampf(hop_t / hop_dur, 0.0, 1.0)
	var heave: float = 4.0 * u * (1.0 - u)  # parabola peaking at mid
	return Vector3(0.0, heave * 0.22, 0.0)


static func bottom_land_y(f: Fish, floor_y: float, dt: float) -> float:
	# #271: glide onto the bed instead of snapping.
	if not enabled:
		return f.global_position.y
	var y: float = f.global_position.y
	if y <= floor_y + 0.12:
		return MotionEase.damp(y, floor_y + 0.08, 3.5, dt)
	if y < floor_y + 0.55 and f.velocity.y < 0.05:
		return MotionEase.damp(y, floor_y + 0.08, 2.2, dt)
	return y


static func frustum_enter_blend(f: Fish, now_visible: bool, dt: float) -> float:
	# #273: blend body pose in over 0.1 s when entering the frustum.
	# Steady visible/invisible returns exact 0/1 so culled↔seen path parity
	# (#72 / smoke_motion_phase1) stays intact; damp only across the edge.
	var tgt: float = 1.0 if now_visible else 0.0
	var was: bool = bool(f.get_meta("_ease_was_vis")) if f.has_meta("_ease_was_vis") else now_visible
	var w: float = _meta_f(f, "_frustum_blend", tgt)
	if now_visible and not was:
		w = 0.0
	elif (not now_visible) and was and not f.has_meta("_frustum_blend"):
		w = 1.0
	f.set_meta("_ease_was_vis", now_visible)
	if absf(w - tgt) < 1e-5:
		f.set_meta("_frustum_blend", tgt)
		return tgt
	w = MotionEase.damp(w, tgt, 12.0, dt)
	if absf(w - tgt) < 0.02:
		w = tgt
	f.set_meta("_frustum_blend", w)
	return w


static func curvature_follow(f: Fish, raw: Vector3, _dt: float) -> Vector3:
	# #276: 10 Hz steering targets become arc aims bounded by #275.
	if not enabled or f == null or raw.length_squared() < 1e-8:
		return raw
	var spd: float = raw.length()
	var want: Vector3 = raw / spd
	var flat_w: Vector3 = Vector3(want.x, 0.0, want.z)
	var flat_h: Vector3 = Vector3(f.heading.x, 0.0, f.heading.z)
	if flat_w.length_squared() < 1e-6 or flat_h.length_squared() < 1e-6:
		return raw
	flat_w = flat_w.normalized()
	flat_h = flat_h.normalized()
	var ang: float = flat_h.angle_to(flat_w)
	if ang < 0.12:
		return raw
	var side: float = signf(flat_h.x * flat_w.z - flat_h.z * flat_w.x)
	if is_zero_approx(side):
		side = 1.0
	var mid_ang: float = minf(ang * 0.45, 0.7)
	var aim: Vector3 = flat_h.rotated(Vector3.UP, side * mid_ang)
	var bent: Vector3 = Vector3(aim.x, want.y * 0.28, aim.z)
	if bent.length_squared() < 1e-8:
		return raw
	return bent.normalized().lerp(want, 0.35).normalized() * spd


static func school_turn_centre_steer(f: Fish, school_center: Vector3, align_dir: Vector3,
		slot_r: float) -> Vector3:
	# #288: one shared centre — tangent arcs, outside fish travel farther.
	if not enabled or f == null:
		return Vector3.ZERO
	var flat_ali: Vector3 = Vector3(align_dir.x, 0.0, align_dir.z)
	var flat_h: Vector3 = Vector3(f.heading.x, 0.0, f.heading.z)
	if flat_ali.length_squared() < 1e-6 or flat_h.length_squared() < 1e-6:
		return Vector3.ZERO
	flat_ali = flat_ali.normalized()
	flat_h = flat_h.normalized()
	if flat_h.angle_to(flat_ali) < 0.14:
		return Vector3.ZERO
	var to_c: Vector3 = Vector3(school_center.x - f.global_position.x, 0.0,
		school_center.z - f.global_position.z)
	var r: float = to_c.length()
	if r < 0.25:
		return Vector3.ZERO
	var tangent: Vector3 = Vector3(-to_c.z, 0.0, to_c.x).normalized()
	if tangent.dot(flat_ali) < 0.0:
		tangent = -tangent
	var outside: float = clampf(r / maxf(slot_r, 0.45), 0.55, 1.7)
	var radial: Vector3 = to_c.normalized() * (slot_r - r) * 0.12
	return tangent * 0.55 * outside + radial


static func air_dash_desired(f: Fish, trip_u: float, surface_y: float, return_y: float,
		effective_max: float) -> Dictionary:
	# #279: one continuous bottom→surface→bottom loop (rise / gulp / curved dive).
	var out := {
		"target_y": return_y,
		"desired": Vector3.ZERO,
		"gape": 0.0,
		"phase": "dive",
	}
	if not enabled or f == null:
		return out
	if trip_u > 0.55:
		out["phase"] = "rise"
		out["target_y"] = surface_y
		var rise: Vector3 = Vector3(
			sin(f._motor_phase * 1.7) * 0.22,
			0.95,
			cos(f._motor_phase * 1.3) * 0.18).normalized()
		out["desired"] = rise * effective_max * 0.95
	elif trip_u > 0.28:
		out["phase"] = "gulp"
		out["target_y"] = surface_y
		out["gape"] = 0.9
		out["desired"] = Vector3.ZERO  # caller damps body motion
	else:
		out["phase"] = "dive"
		out["target_y"] = return_y
		var to_home: Vector3 = Vector3(
			sin(f._motor_phase * 0.9 + float(f.get_instance_id() & 15)) * 0.55,
			return_y - f.global_position.y,
			cos(f._motor_phase * 0.9 + float(f.get_instance_id() & 15)) * 0.55)
		to_home.y = minf(to_home.y, -0.35)
		out["desired"] = curve_approach(f, to_home, 0.4) * effective_max * 0.9
	return out


static func shrimp_swim_arc(from: Vector3, to: Vector3, u: float, lift: float = 0.55) -> Vector3:
	# #290: ballistic-looking perch-to-perch swim (lift, glide, descend).
	var t: float = clampf(u, 0.0, 1.0)
	var p: Vector3 = from.lerp(to, t)
	p.y += 4.0 * t * (1.0 - t) * lift
	return p


static func shrimp_flip_arc(back_dir: Vector3, escape_frac: float) -> Vector3:
	# #291: early flip pitches up; later frames glide down.
	if back_dir.length_squared() < 1e-6:
		return back_dir
	var up: float = clampf(escape_frac, 0.0, 1.0) * 0.55
	var glide: float = -0.18 * (1.0 - clampf(escape_frac, 0.0, 1.0))
	return (back_dir.normalized() + Vector3(0.0, up + glide, 0.0)).normalized()


static func snail_fall_step(pos: Vector3, sink_speed: float, floor_y: float, t: float,
		dt: float) -> Dictionary:
	# #292: tumbling leaf-fall — rock laterally while descending.
	var rock: Vector3 = Vector3(sin(t * 2.6) * 0.11, 0.0, cos(t * 1.9) * 0.08) * sink_speed
	var p: Vector3 = pos + rock * dt
	p.y = maxf(floor_y, p.y - sink_speed * dt)
	var tumble_roll: float = sin(t * 3.1) * 0.55 * clampf((p.y - floor_y) * 0.35, 0.0, 1.0)
	return {"pos": p, "roll": tumble_roll}


static func bottom_hopper_arc(hop_t: float, hop_dur: float) -> Vector3:
	# #293: short parabolic hops for negatively buoyant sitters (gobies etc.).
	if hop_dur <= 1e-4:
		return Vector3.ZERO
	var u: float = 1.0 - clampf(hop_t / hop_dur, 0.0, 1.0)
	var heave: float = 4.0 * u * (1.0 - u)
	return Vector3(0.0, heave * 0.30, 0.0)


static func path_curvature_samples(positions: Array) -> float:
	# #296 / #83: mean absolute discrete curvature along a sampled path.
	if positions.size() < 3:
		return 0.0
	var acc: float = 0.0
	var n: int = 0
	for i in range(1, positions.size() - 1):
		var a: Vector3 = positions[i] - positions[i - 1]
		var b: Vector3 = positions[i + 1] - positions[i]
		if a.length_squared() < 1e-8 or b.length_squared() < 1e-8:
			continue
		var k: float = absf(a.normalized().angle_to(b.normalized())) / maxf(a.length(), 0.02)
		acc += k
		n += 1
	return acc / maxf(float(n), 1.0)
