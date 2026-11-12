class_name FishAnticipation
extends RefCounted

# CREATURE_MOTION_700 anticipation (143–170): every action is telegraphed.
# Called from Fish so the wind-up reads before the move.
# Gated with FishPhase2Pose.enabled so A/B metrics stay honest.


static func enabled() -> bool:
	return FishPhase2Pose.enabled


static func tick(f: Fish, dt: float) -> void:
	if not enabled() or f == null or not (dt > 0.0):
		return
	# #339: big fish hold envelopes longer (L^(1/3)).
	var size_s: float = FishTiming.size_reaction_scale(
		f.adult_voxel_scale * 5.5 * f.body_elongation * maxf(f.scale.x, 0.1))
	var sdt: float = dt / maxf(size_s, 0.7)
	_decay(f, "_ant_scull", sdt * 4.5)
	_decay(f, "_ant_tail_cock", sdt * 5.5)
	_decay(f, "_ant_fixate", sdt * 3.2)
	_decay(f, "_ant_freeze", sdt * 5.0)
	_decay(f, "_ant_head_lead", sdt * 2.8)
	_decay(f, "_ant_bank_lead", sdt * 3.5)
	_decay(f, "_ant_effort", sdt * 2.2)
	_decay(f, "_ant_s_stage", sdt * 6.0)
	_decay(f, "_ant_court", sdt * 2.4)
	_decay(f, "_ant_threat", sdt * 1.8)
	_decay(f, "_ant_takeoff", sdt * 8.0)
	_decay(f, "_ant_pre_gulp", sdt * 3.0)
	_decay(f, "_ant_reverse", sdt * 4.0)
	_decay(f, "_ant_stalk", sdt * 1.2)
	_decay(f, "_ant_hesitate", sdt * 2.0)
	_decay(f, "_ant_inspect", sdt * 0.55)
	_tick_c_start_sheet(f, sdt)
	# Rising edges.
	var prev_burst: float = float(f.get_meta("_ant_prev_burst", 0.0))
	if f.burst_remaining > 0.05 and prev_burst <= 0.05:
		# #159: urgency scales wind-up length (startle short, voluntary long).
		var urg: float = urgency_for(f)
		# #365: record pre-action hold envelope for pose/fin scull — never
		# stamp `motion_freeze_t` on every voluntary burst (that made fish
		# stutter-stop for 0.2 s before every routine dart).
		if float(f.get_meta("_ant_pre_hold", 0.0)) <= 0.0:
			f.set_meta("_ant_pre_hold", FishExaggeration.pre_action_hold_seconds())
		if f._startle_remaining <= 0.05:
			# #147 / #148: voluntary darts scull then cock the tail.
			f.set_meta("_ant_scull", urg)
			f.set_meta("_ant_tail_cock", urg)
			f.set_meta("_ant_effort", urg)
			# #146 / #168: stalkers S-coil instead of plain cock.
			if _is_stalker(f) and float(f.get_meta("_ant_stalk", 0.0)) > 0.2:
				f.set_meta("_ant_s_stage", urg)
			# Staging is a *visual* budget (#175/#366). Always emit audio so a
			# busy region does not go silent while fish still dart.
			var dart_staged: bool = MotionStaging.begin_big_event(
				f.global_position, &"dart", 0.9)
			MotionEvents.emit(&"dart_started", f, f.global_position,
				(0.7 if dart_staged else 0.35) * urg)
			if dart_staged:
				MotionStaging.light_actor(f, 0.7)
			else:
				f.burst_remaining = minf(f.burst_remaining, 0.12)
		else:
			# #145 / #342: C-start exposure sheet (stage1 → stage2 → glide).
			_begin_c_start_sheet(f)
			var startle_staged: bool = MotionStaging.begin_big_event(
				f.global_position, &"startle", 1.0)
			MotionEvents.emit(&"startled", f, f.global_position,
				1.0 if startle_staged else 0.45)
			if startle_staged:
				MotionStaging.light_actor(f, 0.85)
				# #370: one adult smear ghost on the C-start.
				f.call("_spawn_adult_action_smear")
	_decay(f, "_ant_pre_hold", sdt * 5.0)
	f.set_meta("_ant_prev_burst", f.burst_remaining)
	# #153: visible freeze while motion_freeze / fear freeze is live.
	if f.motion_freeze_t > 0.05:
		f.set_meta("_ant_freeze", maxf(float(f.get_meta("_ant_freeze", 0.0)), 0.85))
	# #165: reverse intent — heading vs desired oppose.
	var want: Vector3 = f.target_velocity
	if want.length_squared() > 0.04 and f.heading.length_squared() > 0.04:
		var flat_h: Vector3 = Vector3(f.heading.x, 0.0, f.heading.z)
		var flat_w: Vector3 = Vector3(want.x, 0.0, want.z)
		if flat_h.length_squared() > 1e-6 and flat_w.length_squared() > 1e-6:
			if flat_h.normalized().dot(flat_w.normalized()) < -0.35 \
					and f.speed < f.max_speed * 0.35:
				f.set_meta("_ant_reverse", maxf(float(f.get_meta("_ant_reverse", 0.0)), 0.9))
				f.set_meta("_ant_scull", maxf(float(f.get_meta("_ant_scull", 0.0)), 0.8))


static func urgency_for(f: Fish) -> float:
	# #159: startle ≈1 (short), feeding strike mid, voluntary relocation long.
	if f._startle_remaining > 0.05:
		return 0.55
	if f.current_mode == Fish.Mode.FORAGE and f.hunger > 0.55:
		return 0.85
	return 1.0


static func note_turn_intent(f: Fish, desired_dir: Vector3, dt: float) -> void:
	# #143 / #154: store the intended yaw so head and bank can lead it.
	if not enabled() or desired_dir.length_squared() < 1e-6:
		return
	var want_yaw: float = atan2(desired_dir.x, -desired_dir.z)
	var have_yaw: float = atan2(f.heading.x, -f.heading.z)
	var dyaw: float = wrapf(want_yaw - have_yaw, -PI, PI)
	if absf(dyaw) < 0.08:
		return
	# dt scales how hard the lead commits this frame (leaders pass a larger dt).
	var commit: float = clampf(dt * 18.0, 0.35, 1.0)
	# The head leads a turn the body is about to make. A near-stopped fish
	# barely turns, so a full lead held its head cocked for seconds and read
	# as askew rather than looking; the eyes (gaze below) carry that look.
	commit *= clampf(f.speed / maxf(f.max_speed * 0.35, 0.05), 0.25, 1.0)
	f.set_meta("_ant_head_lead", clampf(dyaw * commit, -0.3, 0.3))
	f.set_meta("_ant_bank_lead", clampf(-dyaw * 0.45 * commit, -0.35, 0.35))
	# Eyes lead the head by ~60 ms (#144): shove gaze toward the turn.
	if f._motion_gaze != null and absf(dyaw) > 0.12:
		var look: Vector3 = f.global_position + desired_dir.normalized() * 2.0
		f._motion_gaze.look_at_point(&"curiosity", look, 0.35 * commit)


static func note_bite_intent(f: Fish) -> void:
	# #149 / #343: fixation before the strike (exposure-sheet hold).
	if not enabled():
		return
	f.set_meta("_ant_fixate", 1.0)
	f.set_meta("_ant_strike_hold", FishTiming.strike_hold_seconds()
		* FishTiming.size_reaction_scale(
			f.adult_voxel_scale * 5.5 * f.body_elongation * maxf(f.scale.x, 0.1)))
	f.set_meta("_ant_scull", maxf(float(f.get_meta("_ant_scull", 0.0)), 0.7))
	# #362: brief body stretch into the bite.
	f.set_meta("_ant_strike_stretch", 1.0)
	if f._motion_gaze != null:
		f._motion_gaze.converge = maxf(f._motion_gaze.converge, 0.85)
	MotionEvents.emit(&"strike", f, f.global_position, 0.55)
	# #370: one smear frame on the strike.
	if MotionStaging.begin_big_event(f.global_position, &"strike_smear", 0.35):
		f.call("_spawn_adult_action_smear")


static func note_court_notice(f: Fish, partner: Node3D) -> void:
	# #157: dorsal lift + head turn + flush before approach.
	if not enabled() or partner == null:
		return
	f.set_meta("_ant_court", 1.0)
	f.set_meta("_ant_head_lead", clampf(
		wrapf(atan2(partner.global_position.x - f.global_position.x,
			-(partner.global_position.z - f.global_position.z))
			- atan2(f.heading.x, -f.heading.z), -PI, PI), -0.3, 0.3))
	f._courtship_flare = true
	f._courtship_intensity = maxf(f._courtship_intensity, 0.35)
	if f._dorsal_pivot != null:
		f._dorsal_pivot.rotation.x = lerpf(f._dorsal_pivot.rotation.x, 0.55, 0.45)


static func note_threat_display(f: Fish) -> void:
	# #158: head down + opercula flare, hold, then charge.
	if not enabled():
		return
	f.set_meta("_ant_threat", 1.0)
	f.set_meta("_ant_freeze", maxf(float(f.get_meta("_ant_freeze", 0.0)), 0.4))
	f._mouth_gape = maxf(f._mouth_gape, 0.35)


static func note_bottom_takeoff(f: Fish) -> void:
	# #166: head lift + pec splay one frame before leaving substrate.
	if not enabled():
		return
	f.set_meta("_ant_takeoff", 1.0)
	f.set_meta("_ant_scull", maxf(float(f.get_meta("_ant_scull", 0.0)), 0.75))


static func note_pre_gulp(f: Fish) -> void:
	# #167: labyrinth fish hang nose-up before the rise.
	if not enabled() or not f.labyrinth_breather:
		return
	f.set_meta("_ant_pre_gulp", 1.0)


static func note_stalk_stillness(f: Fish) -> void:
	# #168: stalkers drift motionless (fin scull only) before S-start.
	if not enabled() or not _is_stalker(f):
		return
	f.set_meta("_ant_stalk", 1.0)
	f.set_meta("_ant_scull", maxf(float(f.get_meta("_ant_scull", 0.0)), 0.9))
	f.speed = minf(f.speed, f.max_speed * 0.12)


static func note_hesitation(f: Fish) -> void:
	# #160: visible check at a fork — brief scull + head flick.
	if not enabled():
		return
	f.set_meta("_ant_hesitate", 1.0)
	f.set_meta("_ant_scull", maxf(float(f.get_meta("_ant_scull", 0.0)), 0.55))


static func note_predator_inspect(f: Fish, threat: Node3D) -> void:
	# #161: cautious stop-start approach toward a large stranger, then retreat.
	if not enabled() or threat == null:
		return
	f.set_meta("_ant_inspect", 1.0)
	f.set_meta("_ant_scull", maxf(float(f.get_meta("_ant_scull", 0.0)), 0.7))
	note_turn_intent(f, threat.global_position - f.global_position, 0.05)


static func inspect_steer(f: Fish, threat: Node3D, effective_max: float) -> Vector3:
	# Returns a desired nudge: approach while inspect > 0.45, retreat below.
	if not enabled() or threat == null:
		return Vector3.ZERO
	var ins: float = float(f.get_meta("_ant_inspect", 0.0))
	if ins <= 0.05:
		return Vector3.ZERO
	var to: Vector3 = threat.global_position - f.global_position
	to.y *= 0.25
	if to.length_squared() < 1e-4:
		return Vector3.ZERO
	var dir: Vector3 = to.normalized()
	if ins > 0.45:
		# Stop-start: pulse approach every ~0.4 s of phase.
		var pulse: float = 1.0 if sin(f._motor_phase * 4.0) > 0.15 else 0.15
		return dir * effective_max * 0.35 * pulse
	# Retreat after the look.
	return -dir * effective_max * 0.55


static func head_lead_yaw(f: Fish) -> float:
	if not enabled():
		return 0.0
	return float(f.get_meta("_ant_head_lead", 0.0))


static func bank_lead(f: Fish) -> float:
	# #154: roll into the turn before yaw rate rises.
	if not enabled():
		return 0.0
	return float(f.get_meta("_ant_bank_lead", 0.0))


static func effort_amp(f: Fish) -> float:
	# #155: tail amp steps up one beat before speed.
	if not enabled():
		return 0.0
	return float(f.get_meta("_ant_effort", 0.0)) * 0.22


static func brake_arrival_scale(f: Fish, dist_to_goal: float, decel: float) -> float:
	# #156: begin braking at speed²/(2·decel). Returns speed scale ≤1.
	if not enabled() or decel <= 1e-4:
		return 1.0
	var stop_d: float = (f.speed * f.speed) / (2.0 * decel)
	if dist_to_goal > stop_d * 1.15:
		return 1.0
	var t: float = clampf(dist_to_goal / maxf(stop_d, 0.05), 0.0, 1.0)
	# Large fish get a deliberate tiny overshoot (#156 + Hydrodynamics.overshoot_bias).
	var over: float = 0.0
	if f.adult_voxel_scale > 0.22:
		over = Hydrodynamics.overshoot_bias(f.speed, f.speed * t, dist_to_goal)
	f._brake_pose = maxf(f._brake_pose, 1.0 - t + over)
	return lerpf(0.18, 1.0, t)


static func apply_pec_scull(f: Fish, pec_amp: float, pec_spread: float) -> Dictionary:
	# #147 / #165: back-scull with the body still.
	if not enabled():
		return {"pec_amp": pec_amp, "pec_spread": pec_spread}
	var scull: float = float(f.get_meta("_ant_scull", 0.0))
	var rev: float = float(f.get_meta("_ant_reverse", 0.0))
	var take: float = float(f.get_meta("_ant_takeoff", 0.0))
	var stalk: float = float(f.get_meta("_ant_stalk", 0.0))
	var blend: float = maxf(scull, maxf(rev, maxf(take, stalk * 0.7)))
	if blend > 0.0:
		pec_amp += blend * 0.55
		pec_spread += blend * 0.28 + take * 0.35
		# Hold speed down while deciding / reversing / stalking.
		if f.burst_remaining <= 0.05:
			f.speed = minf(f.speed, f.max_speed * lerpf(0.22, 0.08, stalk))
	return {"pec_amp": pec_amp, "pec_spread": pec_spread}


static func apply_tail_cock(f: Fish) -> void:
	# #148: first beat starts from a held lateral opposite the power stroke.
	if not enabled() or f._tail_pivot == null:
		return
	var cock: float = float(f.get_meta("_ant_tail_cock", 0.0))
	if cock <= 0.0:
		return
	var side: float = signf(sin(f._swim_phase + PI))
	if is_zero_approx(side):
		side = 1.0
	f._tail_pivot.rotation.y = lerpf(f._tail_pivot.rotation.y, side * 0.42 * cock, 0.55)


static func apply_freeze_pose(f: Fish) -> void:
	# #153: fins clamp, tail centres, covers quiet, eyes fix.
	if not enabled() or f._bank_pivot == null:
		return
	var fr: float = float(f.get_meta("_ant_freeze", 0.0))
	if fr <= 0.0:
		return
	if f._tail_pivot != null:
		f._tail_pivot.rotation.y = lerpf(f._tail_pivot.rotation.y, 0.0, 0.55 * fr)
	if f._pec_left_pivot != null:
		f._pec_left_pivot.rotation.z = lerpf(f._pec_left_pivot.rotation.z, 0.05, 0.5 * fr)
	if f._pec_right_pivot != null:
		f._pec_right_pivot.rotation.z = lerpf(f._pec_right_pivot.rotation.z, -0.05, 0.5 * fr)
	if f._dorsal_pivot != null:
		f._dorsal_pivot.rotation.x = lerpf(f._dorsal_pivot.rotation.x, 0.45, 0.4 * fr)
	if f._motion_gaze != null:
		f._motion_gaze.converge = maxf(f._motion_gaze.converge, 0.6 * fr)


static func apply_c_start(f: Fish) -> void:
	# #145 / #360: stage-1 C coil — keep the real ~90–120° curl (no angle gain).
	if not enabled():
		return
	var c: float = float(f.get_meta("_ant_c_stage", 0.0))
	if c <= 0.0:
		return
	var side: float = signf(f._startle_heading.x) if f._startle_heading.length_squared() > 1e-4 else 1.0
	# Biological curl amplitudes (~0.55+0.75 rad mid/tail ≈ 90–120° together).
	if f._body_mid_pivot != null:
		f._body_mid_pivot.rotation.y = lerpf(f._body_mid_pivot.rotation.y, side * 0.55 * c, 0.7)
	if f._tail_pivot != null:
		f._tail_pivot.rotation.y = lerpf(f._tail_pivot.rotation.y, -side * 0.75 * c, 0.7)
	if f._head_pivot != null:
		f._head_pivot.rotation.y = lerpf(f._head_pivot.rotation.y, side * 0.35 * c, 0.6)


static func apply_s_start(f: Fish) -> void:
	# #146: S-coil for predatory lunges (opposite mid/tail sense from C-start).
	if not enabled():
		return
	var s: float = float(f.get_meta("_ant_s_stage", 0.0))
	if s <= 0.0:
		return
	var side: float = signf(sin(f._swim_phase)) 
	if is_zero_approx(side):
		side = 1.0
	if f._body_mid_pivot != null:
		f._body_mid_pivot.rotation.y = lerpf(f._body_mid_pivot.rotation.y, side * 0.4 * s, 0.65)
	if f._tail_pivot != null:
		f._tail_pivot.rotation.y = lerpf(f._tail_pivot.rotation.y, side * 0.55 * s, 0.65)
	if f._head_pivot != null:
		f._head_pivot.rotation.y = lerpf(f._head_pivot.rotation.y, -side * 0.28 * s, 0.55)


static func apply_fixate_hold(f: Fish) -> void:
	# #149: brief gaze converge + strike stretch before the bite.
	# Never clamp `f.speed` here — this runs in the render-rate pose pass and
	# fighting the physics integrator created a 60 Hz speed saw-tooth on approach.
	if not enabled():
		return
	var fix: float = float(f.get_meta("_ant_fixate", 0.0))
	if fix <= 0.0:
		_decay(f, "_ant_strike_stretch", 0.14)
		return
	if f._motion_gaze != null:
		f._motion_gaze.converge = maxf(f._motion_gaze.converge, 0.9 * fix)
	# #362: elongate along the strike axis for one beat (±8%, capped).
	var stretch: float = float(f.get_meta("_ant_strike_stretch", 0.0))
	if stretch > 0.0 and f._body_mid_pivot != null:
		var s: float = 1.0 + 0.08 * stretch
		f._body_mid_pivot.scale.z = f._body_mid_rest_scale.z * s
		f._body_mid_pivot.scale.y = f._body_mid_rest_scale.y / maxf(sqrt(s), 1.0)
		_decay(f, "_ant_strike_stretch", 0.14)


static func apply_court_pose(f: Fish) -> void:
	if not enabled():
		return
	var c: float = float(f.get_meta("_ant_court", 0.0))
	if c <= 0.0:
		return
	if f._dorsal_pivot != null:
		f._dorsal_pivot.rotation.x = lerpf(f._dorsal_pivot.rotation.x, 0.6 * c, 0.4)
	if f._head_pivot != null:
		f._head_pivot.rotation.y = lerpf(f._head_pivot.rotation.y,
			FishAnticipation.head_lead_yaw(f), 0.35)


static func apply_threat_pose(f: Fish) -> void:
	if not enabled() or f._bank_pivot == null:
		return
	var th: float = float(f.get_meta("_ant_threat", 0.0))
	if th <= 0.0:
		return
	f._bank_pivot.rotation.x = lerpf(f._bank_pivot.rotation.x, 0.22 * th, 0.35)
	if f._operculum_left != null:
		f._operculum_left.rotation.y = lerpf(f._operculum_left.rotation.y, -0.38 * th, 0.45)
	if f._operculum_right != null:
		f._operculum_right.rotation.y = lerpf(f._operculum_right.rotation.y, 0.38 * th, 0.45)


static func apply_pre_gulp_pose(f: Fish) -> void:
	if not enabled() or f._bank_pivot == null:
		return
	var g: float = float(f.get_meta("_ant_pre_gulp", 0.0))
	if g <= 0.0:
		return
	f._bank_pivot.rotation.x = lerpf(f._bank_pivot.rotation.x, -0.35 * g, 0.4)


static func apply_takeoff_pose(f: Fish) -> void:
	# Pitch target only — Fish settles Head.rotation.x once at end of pose pass
	# so takeoff / gulp / bite can't leave the skull stuck nose-up forever.
	if not enabled() or f._head_pivot == null:
		return
	var t: float = float(f.get_meta("_ant_takeoff", 0.0))
	f.set_meta("_head_pitch_takeoff", -0.22 * t if t > 0.0 else 0.0)


static func joint_count_for(f: Fish) -> int:
	# #65: segment count by body plan (fry always 3).
	if f.maturity == Fish.MATURITY_FRY:
		return 3
	match f.locomotion_type:
		"anguilliform":
			return 7
		"labriform":
			return 4
		"ostraciiform":
			return 2
		"thunniform":
			return 5
		_:
			if f.body_shape == "globiform":
				return 2
			if f.body_shape == "compressed":
				return 4
			return 5


static func wave_envelope(f: Fish, tip_frac: float, x: float) -> float:
	# A(x)=4·tip·x·(1−x), snapped to the body-plan joint lattice (#65).
	var n: int = joint_count_for(f)
	var xi: float = clampf(x, 0.0, 1.0)
	if n > 1:
		xi = roundf(xi * float(n - 1)) / float(n - 1)
	return 4.0 * tip_frac * xi * (1.0 - xi)


static func sample_wave(f: Fish, swim_phase: float, wave_len: float, tip_frac: float,
		x: float) -> float:
	# θ(x) = A(x)·sin(ωt − 2π·x/λ).
	var n: int = joint_count_for(f)
	var xi: float = clampf(x, 0.0, 1.0)
	if n > 1:
		xi = roundf(xi * float(n - 1)) / float(n - 1)
	return wave_envelope(f, tip_frac, xi) * sin(swim_phase - TAU * xi / maxf(wave_len, 0.25))


static func is_stalker(f: Fish) -> bool:
	var sp: String = String(f.species)
	return sp.contains("gar") or sp.contains("killi") or sp.contains("pike") \
		or (f.locomotion_type == "thunniform" and f.swim_pattern == "sit")


static func _is_stalker(f: Fish) -> bool:
	return is_stalker(f)


# #342: C-start exposure sheet — stage 1 coil, stage 2 propel, glide recovery.
static func _begin_c_start_sheet(f: Fish) -> void:
	var sheet: Vector3 = FishTiming.c_start_stage_seconds()
	var size_s: float = FishTiming.size_reaction_scale(
		f.adult_voxel_scale * 5.5 * f.body_elongation * maxf(f.scale.x, 0.1))
	f.set_meta("_ant_c_sheet", 1)  # 1=stage1, 2=stage2, 3=glide
	f.set_meta("_ant_c_timer", sheet.x * size_s)
	f.set_meta("_ant_c_stage", 1.0)


static func _tick_c_start_sheet(f: Fish, dt: float) -> void:
	var sheet_i: int = int(f.get_meta("_ant_c_sheet", 0))
	if sheet_i <= 0:
		_decay(f, "_ant_c_stage", dt * 8.0)
		var hold: float = float(f.get_meta("_ant_strike_hold", 0.0))
		if hold > 0.0:
			hold = maxf(0.0, hold - dt)
			f.set_meta("_ant_strike_hold", hold)
			if hold > 0.0:
				f.set_meta("_ant_fixate", maxf(float(f.get_meta("_ant_fixate", 0.0)), 0.85))
		return
	var timer: float = float(f.get_meta("_ant_c_timer", 0.0)) - dt
	var sheet: Vector3 = FishTiming.c_start_stage_seconds()
	var size_s: float = FishTiming.size_reaction_scale(
		f.adult_voxel_scale * 5.5 * f.body_elongation * maxf(f.scale.x, 0.1))
	if timer > 0.0:
		f.set_meta("_ant_c_timer", timer)
		match sheet_i:
			1:
				f.set_meta("_ant_c_stage", 1.0)
			2:
				f.set_meta("_ant_c_stage", 0.55)
			_:
				f.set_meta("_ant_c_stage", 0.2)
		return
	match sheet_i:
		1:
			f.set_meta("_ant_c_sheet", 2)
			f.set_meta("_ant_c_timer", sheet.y * size_s)
			f.set_meta("_ant_c_stage", 0.55)
		2:
			f.set_meta("_ant_c_sheet", 3)
			f.set_meta("_ant_c_timer", sheet.z * size_s)
			f.set_meta("_ant_c_stage", 0.2)
		_:
			f.set_meta("_ant_c_sheet", 0)
			f.set_meta("_ant_c_timer", 0.0)
			f.set_meta("_ant_c_stage", 0.0)


static func _decay(f: Fish, key: String, rate: float) -> void:
	var v: float = float(f.get_meta(key, 0.0))
	if v > 0.0:
		f.set_meta(key, maxf(0.0, v - rate))
