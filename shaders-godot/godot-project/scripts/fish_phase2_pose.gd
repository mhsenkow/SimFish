class_name FishPhase2Pose
extends RefCounted

# CREATURE_MOTION_700 Phase 2 leftovers that layer on the living fish pose.
# Called from Fish._motion_substep so the 10k-line fish script stays readable.
# Each public method owns a cluster of idea numbers (cited in comments).
#
# `enabled` lets smokes A/B the helper (smoke_motion_phase2_metrics) so we can
# measure jerk / kinks / skating with the Phase 2 pose layer off vs on.

static var enabled: bool = true


static func tick(f: Fish, dt: float) -> void:
	if not enabled or f == null or not (dt > 0.0):
		return
	# Birth deflation (#126): snap then recoil when gestation clears.
	if f.get_meta("_p2_was_gestating", false) and f._gestation_progress <= 0.0:
		f.set_meta("_p2_birth_recoil", 1.0)
	f.set_meta("_p2_was_gestating", f._gestation_progress > 0.05)
	var birth: float = float(f.get_meta("_p2_birth_recoil", 0.0))
	if birth > 0.0:
		f.set_meta("_p2_birth_recoil", maxf(0.0, birth - dt * 2.5))
	# Burst / strike edges.
	var prev_burst: float = float(f.get_meta("_p2_prev_burst", 0.0))
	if f.burst_remaining > 0.05 and prev_burst <= 0.05:
		f.set_meta("_p2_strike_stretch", 1.0)
		f.set_meta("_p2_effort_girth", 1.0)
		f.set_meta("_p2_fin_reopen", 0.0)
	if f.burst_remaining <= 0.05 and prev_burst > 0.05:
		f.set_meta("_p2_fin_reopen", 1.2)
	f.set_meta("_p2_prev_burst", f.burst_remaining)
	# Startle → C-start coil then staged fin reopen (#122, #246).
	var prev_startle: float = float(f.get_meta("_p2_prev_startle", 0.0))
	if f._startle_remaining > 0.1 and prev_startle <= 0.1:
		f.set_meta("_p2_c_start", 1.0)
	if f._startle_remaining <= 0.05 and prev_startle > 0.05:
		f.set_meta("_p2_fin_reopen", maxf(float(f.get_meta("_p2_fin_reopen", 0.0)), 1.5))
	f.set_meta("_p2_prev_startle", f._startle_remaining)
	_decay_meta(f, "_p2_strike_stretch", dt * 8.0)
	_decay_meta(f, "_p2_effort_girth", dt * 3.5)
	_decay_meta(f, "_p2_c_start", dt * 5.0)
	_decay_meta(f, "_p2_fin_reopen", dt * 0.85)
	_decay_meta(f, "_p2_hop_stretch", dt * 6.0)
	_decay_meta(f, "_p2_land_squash", dt * 7.0)
	_decay_meta(f, "_p2_chew", dt * 1.8)
	_decay_meta(f, "_p2_puffer", dt * 0.12)
	# Shuffle hop rising edge (#132).
	var hop: float = f._shuffle_hop_t
	var prev_hop: float = float(f.get_meta("_p2_prev_hop", 0.0))
	if hop > 0.05 and prev_hop <= 0.05:
		f.set_meta("_p2_hop_stretch", 1.0)
	f.set_meta("_p2_prev_hop", hop)
	# Landing when a bottom fish's settle/speed collapses near the bed (#131, #249).
	if _is_bottom(f) and f.speed < 0.12 and f.global_position.y < _bed_y(f) + 0.55:
		var was_up: bool = bool(f.get_meta("_p2_was_airborne", false))
		if was_up:
			f.set_meta("_p2_land_squash", 1.0)
		f.set_meta("_p2_was_airborne", false)
	elif _is_bottom(f) and f.speed > 0.35:
		# #166: telegraph take-off the frame the bottom fish leaves the bed.
		if not bool(f.get_meta("_p2_was_airborne", false)):
			FishAnticipation.note_bottom_takeoff(f)
		f.set_meta("_p2_was_airborne", true)


static func apply_body_scale(f: Fish, _dt: float, rest_factor: float) -> void:
	if not enabled or f == null or f._body_mid_pivot == null:
		return
	var s: Vector3 = f._body_mid_pivot.scale
	# Global caps (#134).
	var strike: float = float(f.get_meta("_p2_strike_stretch", 0.0))
	if strike > 0.0:
		var st: float = sin(strike * PI) * 0.05
		s.z *= 1.0 + st
		s.y *= 1.0 - st * 0.4
	var effort: float = float(f.get_meta("_p2_effort_girth", 0.0))
	if effort > 0.0:
		s.x *= 1.0 - sin(effort * PI) * 0.04  # #140 peduncle tuck at burst start
	var coil: float = float(f.get_meta("_p2_c_start", 0.0))
	if coil > 0.0:
		# #122: chord shortens, girth rises.
		var c: float = sin(coil * PI)
		s.z *= 1.0 - c * 0.08
		s.x *= 1.0 + c * 0.04
		s.y *= 1.0 + c * 0.04
	var hop: float = float(f.get_meta("_p2_hop_stretch", 0.0))
	if hop > 0.0:
		s.z *= 1.0 + sin(hop * PI) * 0.04
	var land: float = float(f.get_meta("_p2_land_squash", 0.0))
	if land > 0.0:
		var l: float = sin(land * PI)
		s.y *= 1.0 - l * 0.03
		s.x *= 1.0 + l * 0.02
	var birth: float = float(f.get_meta("_p2_birth_recoil", 0.0))
	if birth > 0.0:
		# Fast deflate with a small rebound (#126).
		var b: float = birth
		var deflate: float = 1.0 - sin((1.0 - b) * PI * 0.5) * 0.22
		if b < 0.25:
			deflate += sin(b / 0.25 * PI) * 0.04
		s.y *= deflate
		s.x *= lerpf(1.0, deflate, 0.5)
	# Belly slosh (#238): gravid / full belly lags the bank a little via shear.
	var slosh: float = 0.0
	if f._gestation_progress > 0.2:
		slosh = f._gestation_progress * 0.04
	else:
		slosh = clampf(1.0 - f.hunger, 0.0, 1.0) * 0.015
	s.x *= 1.0 + sin(f._swim_phase) * slosh * (1.0 - rest_factor)
	# Puffer inflation (#127): rare, costly, globiform only.
	var puff: float = float(f.get_meta("_p2_puffer", 0.0))
	if f.body_shape == "globiform" and f._startle_remaining > 0.2 and puff <= 0.0 \
			and f.stress > 0.55 and f._behavior_rng().randf() < _dt * 0.35:
		f.set_meta("_p2_puffer", 1.0)
		f.stress = clampf(f.stress + 0.25, 0.0, 1.0)
		puff = 1.0
	if puff > 0.0:
		# Inflate over the first ~15%, hold, then slow deflate. Skip #134 caps.
		var inflate: float = 1.0
		if puff > 0.85:
			inflate = lerpf(1.0, 1.7, (1.0 - puff) / 0.15)
		else:
			inflate = lerpf(1.0, 1.7, puff / 0.85)
		f._body_mid_pivot.scale = s * inflate
		return
	# Concertina (#139): anguilliform reversing / burrowing shortens the wave.
	if f.locomotion_type == "anguilliform" and f.speed < 0.2 \
			and f._motion_target_spd < 0.15:
		s.z *= 0.94
		s.x *= 1.03
	s = _cap_scale(s, f)
	f._body_mid_pivot.scale = s


static func apply_head_face(f: Fish, dt: float, rest_factor: float, breath_wave: float) -> void:
	if not enabled or f == null or f._head_pivot == null:
		return
	# Jaw protrusion (#137): mouth voxels push forward during gape.
	if f._jaw_pivot != null:
		var rest_z: float = float(f.get_meta("_p2_jaw_rest_z", INF))
		if not is_finite(rest_z):
			rest_z = f._jaw_pivot.position.z
			f.set_meta("_p2_jaw_rest_z", rest_z)
		var protrude: float = clampf(f._mouth_gape, 0.0, 1.0) * f.adult_voxel_scale * 0.3
		f._jaw_pivot.position.z = lerpf(f._jaw_pivot.position.z, rest_z - protrude,
			1.0 - exp(-dt * 10.0))
	# Chewing (#330).
	var chew: float = float(f.get_meta("_p2_chew", 0.0))
	if chew > 0.0:
		f._mouth_gape = maxf(f._mouth_gape, absf(sin(chew * TAU * 4.0)) * 0.55)
	# Labyrinth gulp (#133): pitch via meta (settled once at end of pose pass);
	# never scale the skull — that mashed faces into pug wedges.
	if f.labyrinth_breather and f._aerial_timer > 0.0:
		f.set_meta("_head_pitch_gulp", -0.28)
		if f._operculum_left != null:
			f._operculum_left.rotation.y = minf(f._operculum_left.rotation.y, -0.25)
		if f._operculum_right != null:
			f._operculum_right.rotation.y = maxf(f._operculum_right.rotation.y, 0.25)
	else:
		f.set_meta("_head_pitch_gulp", 0.0)
	# Heavy-headed stop (#243).
	if f._brake_pose > 0.2 and _is_bottom(f):
		f.set_meta("_head_pitch_brake", 0.22 * f._brake_pose)
	else:
		f.set_meta("_head_pitch_brake", 0.0)
	# Corydoras wink (#317): one eye dips at rest.
	if f.swim_pattern == "shuffle" and rest_factor > 0.6 and f._eye_left_pivot != null \
			and f._behavior_rng().randf() < dt * 0.08:
		f.set_meta("_p2_wink", 1.0 if f._behavior_rng().randf() < 0.5 else -1.0)
		f.set_meta("_p2_wink_t", 0.35)
	var wink_t: float = float(f.get_meta("_p2_wink_t", 0.0))
	if wink_t > 0.0:
		wink_t = maxf(0.0, wink_t - dt)
		f.set_meta("_p2_wink_t", wink_t)
		var side: float = float(f.get_meta("_p2_wink", 1.0))
		var dip: float = sin((0.35 - wink_t) / 0.35 * PI) * 0.45
		if side > 0.0 and f._eye_left_pivot != null:
			f._eye_left_pivot.rotation.x = dip
		elif f._eye_right_pivot != null:
			f._eye_right_pivot.rotation.x = dip
	# Breath bob already elsewhere; keep girth tied (#313 companion).
	f._breath_girth = lerpf(f._breath_girth, 1.0 + breath_wave * 0.01 * rest_factor,
		1.0 - exp(-dt * 6.0))


static func apply_fins(f: Fish, dt: float, _speed_frac: float, fold: float, pec_spread: float,
		pec_amp: float) -> Dictionary:
	# Returns adjusted fold / pec_spread / pec_amp for staged reopen (#240, #246).
	if not enabled:
		return {"fold": fold, "pec_spread": pec_spread, "pec_amp": pec_amp}
	var reopen: float = float(f.get_meta("_p2_fin_reopen", 0.0))
	if reopen > 0.0:
		# Pec first, then dorsal (fold), then caudal settles via springs already.
		var pec_gate: float = clampf((1.2 - reopen) / 0.35, 0.0, 1.0)
		var dors_gate: float = clampf((0.85 - reopen) / 0.4, 0.0, 1.0)
		fold = lerpf(fold, 0.0, dors_gate * 0.85)
		pec_spread = lerpf(pec_spread, pec_spread + 0.18, pec_gate)
		pec_amp = lerpf(pec_amp, pec_amp + 0.1, pec_gate)
	# Landing settle (#249): splay pecs/pelvics.
	var land: float = float(f.get_meta("_p2_land_squash", 0.0))
	if land > 0.0:
		pec_spread += sin(land * PI) * 0.2
		if f._pelvic_left_pivot != null:
			f._pelvic_left_pivot.rotation.x = lerpf(f._pelvic_left_pivot.rotation.x, 0.55, 0.4)
		if f._pelvic_right_pivot != null:
			f._pelvic_right_pivot.rotation.x = lerpf(f._pelvic_right_pivot.rotation.x, 0.55, 0.4)
	# Reversal swing (#248): hover back-paddle overshoots the tail.
	if f.speed < f.max_speed * 0.2 and f._motion_target_spd < 0.0 \
			and f._tail_pivot != null:
		f._tail_pivot.rotation.y += sin(f._swim_phase) * 0.12
	# Independent caudal lobes (#245): fork tails get asymmetric tip scale.
	if int(f.get("tail_shape")) == 0 and f._tail_pivot != null:
		f._tail_pivot.scale.x = 1.0 + 0.04 * sin(f._swim_phase * 2.0)
	# Gonopodium (#325): male livebearer anal swings on display.
	if f.is_livebearer and f.sex == 0 and f._anal_pivot != null and f._lb_sigmoid > 0.05:
		f._anal_pivot.rotation.z = lerpf(f._anal_pivot.rotation.z, f._lb_side * 0.35 * f._lb_sigmoid,
			1.0 - exp(-dt * 5.0))
	# Spacing corrections (#326): crowded schools twitch pecs.
	if f._boids_neighbor_count >= 3:
		pec_amp += 0.06
		pec_spread += 0.04
	# Rheotaxis pose (#388): pec spread only. A constant head pitch on every
	# slow fish (station fires whenever speed < 0.22) mashed faces into a
	# concerned-pug tip — keep the skull level unless gulp/bite/takeoff asks.
	var station: float = float(f._fin_effort_cache.get("station", 0.0)) if f._fin_effort_cache else 0.0
	if station > 0.55:
		pec_spread += 0.12
	f.set_meta("_head_pitch_station", 0.0)
	# Flinch dorsal (#324).
	if f.motion_freeze_t > 0.05 and f._dorsal_flick_t <= 0.0:
		f._dorsal_flick_t = 0.25
	# Single tail flick to reorient (#328): hovering labriform.
	if f.locomotion_type == "labriform" and f.speed < f.max_speed * 0.15 \
			and absf(f._last_yaw_rate) > 0.8 and f._tail_pivot != null:
		f._tail_pivot.rotation.y += signf(f._last_yaw_rate) * 0.18
	# Ripple long median fins (#224): soft dorsal trails with a longer phase.
	if f.fin_length_factor > 1.2 and f._dorsal2_pivot != null:
		f._dorsal2_pivot.rotation.x += sin(f._swim_phase * 0.7 + 1.1) * 0.05
	# Fin rays out of step (#235): soft dorsal leads adipose / lags primary.
	if f._dorsal2_pivot != null and f._dorsal_pivot != null:
		f._dorsal2_pivot.rotation.z = lerpf(f._dorsal2_pivot.rotation.z,
			f._dorsal_pivot.rotation.z * 0.6 + sin(f._swim_phase * 1.7) * 0.03,
			1.0 - exp(-dt * 4.0))
	# Puffer uses median fins as rudders (#239).
	if f.body_shape == "globiform" and f._dorsal_pivot != null and f._anal_pivot != null:
		var rudder: float = clampf(f._last_yaw_rate * 0.12, -0.35, 0.35)
		f._dorsal_pivot.rotation.z = lerpf(f._dorsal_pivot.rotation.z, rudder, 0.35)
		f._anal_pivot.rotation.z = lerpf(f._anal_pivot.rotation.z, -rudder, 0.35)
	return {"fold": fold, "pec_spread": pec_spread, "pec_amp": pec_amp}


static func apply_bottom_contact(f: Fish, dt: float, world: Node = null) -> void:
	# #380 contact at rest + #393 align to slopes for bottom fish.
	if not enabled or not _is_bottom(f) or f._bank_pivot == null:
		return
	var bed: float = _bed_y(f)
	var near_bed: bool = f.global_position.y < bed + 0.65
	if near_bed and f.speed < 0.18:
		# Settle onto the bed rather than floating a voxel above it.
		var target_y: float = bed + f.adult_voxel_scale * 0.55
		f.global_position.y = lerpf(f.global_position.y, target_y, 1.0 - exp(-dt * 3.0))
		var slope: Vector3 = Vector3.UP
		if world != null and world.has_method("sample_substrate_normal"):
			slope = world.sample_substrate_normal(f.global_position)
		elif world != null and world.has_method("substrate_normal_at"):
			slope = world.substrate_normal_at(f.global_position)
		if slope.length_squared() > 0.25 and slope.y > 0.2:
			var pitch: float = clampf(atan2(slope.z, slope.y), -0.35, 0.35)
			var roll: float = clampf(atan2(-slope.x, slope.y), -0.35, 0.35)
			f._bank_pivot.rotation.x = lerpf(f._bank_pivot.rotation.x, pitch, 1.0 - exp(-dt * 2.5))
			f._bank_pivot.rotation.z = lerpf(f._bank_pivot.rotation.z, roll, 1.0 - exp(-dt * 2.5))
		# #381: adherent grazers keep the belly to the surface they grip.
		if f.ventral_sucker:
			f._bank_pivot.rotation.x = lerpf(f._bank_pivot.rotation.x, 0.22, 1.0 - exp(-dt * 3.0))
		# #320: gentle caudal fan while parked on the bed.
		if f._tail_pivot != null and (f.ventral_sucker or f.swim_pattern == "shuffle"):
			f._tail_pivot.rotation.y += sin(f._swim_phase * 0.55) * 0.04


static func apply_soft_chains_flow(f: Fish, flow: Vector3) -> void:
	# #251: bias chain roots downstream.
	if not enabled or f._soft_chains.is_empty() or flow.length_squared() < 0.01:
		return
	var basis: Basis = f.global_transform.basis
	if not basis.is_finite() or absf(basis.determinant()) < 1e-8:
		return
	var local: Vector3 = basis.inverse() * flow
	if not local.is_finite():
		return
	var yaw_bias: float = clampf(atan2(-local.x, maxf(-local.z, 0.05)), -0.35, 0.35)
	for entry in f._soft_chains:
		var pivots: Array = entry["pivots"]
		if pivots.is_empty():
			continue
		var root: Node3D = pivots[0]
		if root == null:
			continue
		var axis: int = int(entry["axis"])
		match axis:
			0:
				root.rotation.x += yaw_bias * 0.15
			1:
				root.rotation.y += yaw_bias * 0.25
			_:
				root.rotation.z += yaw_bias * 0.15


static func apply_sift_barbels(f: Fish, _dt: float) -> void:
	# #318
	if not enabled or f._sift_timer <= 0.0 or not f.has_barbels:
		return
	var t: float = f._sift_timer * 18.0
	for entry in f._soft_chains:
		var pivots: Array = entry["pivots"]
		if pivots.is_empty():
			continue
		var name_s: String = String(pivots[0].name)
		if not name_s.begins_with("Barbel"):
			continue
		pivots[0].rotation.x = sin(t + float(pivots[0].get_instance_id() & 7)) * 0.35


static func note_meal(f: Fish, weight: float = 1.0) -> void:
	# Kick chew / pre-bite protrusion window (#124 foundation, #330).
	if not enabled:
		return
	if weight > 0.6:
		f.set_meta("_p2_chew", 1.2)
	f._mouth_gape = maxf(f._mouth_gape, 0.7)
	# #329: occasionally arm a spit-and-retake after a large bite.
	if weight > 0.9 and f._behavior_rng().randf() < 0.12:
		f.set_meta("_p2_spit_retake", 1.0)


static func body_yaw_overshoot(f: Fish, dt: float, yaw_rate: float) -> float:
	# #231: underdamped body yaw residual on the bank pivot.
	if not enabled:
		return 0.0
	# get_meta(..., null) still errors in Godot when the key is missing — use has_meta.
	var spring: MotionSpring = null
	if f.has_meta("_p2_yaw_spring"):
		spring = f.get_meta("_p2_yaw_spring") as MotionSpring
	if spring == null:
		spring = MotionSpring.new(2.2, 0.55, 0.0)
		f.set_meta("_p2_yaw_spring", spring)
	return spring.step(dt, clampf(yaw_rate * 0.04, -0.2, 0.2))


static func heavy_body_lag(f: Fish) -> float:
	# #237: deeper / larger fish carry more phase lag.
	if not enabled:
		return 0.0
	return clampf((f.body_depth_factor - 1.0) * 0.35 + (f.size_potential - 1.0) * 0.2, 0.0, 0.55)


static func bottom_sink_boost(f: Fish) -> float:
	# #378: little swim-bladder lift → sink when not thrusting.
	if not enabled or not _is_bottom(f):
		return 0.0
	if f.speed > 0.2 or f._motion_target_spd > 0.15:
		return 0.0
	return 0.55


static func apply_spit_retake(f: Fish, dt: float) -> void:
	# #329: spit a large particle then re-gape as if taking it again.
	if not enabled:
		return
	var spit: float = float(f.get_meta("_p2_spit_retake", 0.0))
	if spit <= 0.0:
		return
	spit = maxf(0.0, spit - dt * 1.4)
	f.set_meta("_p2_spit_retake", spit)
	if spit > 0.55:
		f._mouth_gape = maxf(f._mouth_gape, 0.9)
	elif spit > 0.25:
		f._mouth_gape = minf(f._mouth_gape, 0.08)
	else:
		f._mouth_gape = maxf(f._mouth_gape, 0.7)


static func apply_feeler_probe(f: Fish, dt: float, neighbors: Array = []) -> void:
	# #321: gourami feelers reach toward nearby interest.
	if not enabled or not f.ventral_feelers or f._soft_chains.is_empty():
		return
	var aim := Vector3.ZERO
	var best_d2: float = 2.2 * 2.2
	for n in neighbors:
		if not (n is Node3D) or n == f:
			continue
		var d: Vector3 = (n as Node3D).global_position - f.global_position
		var d2: float = d.length_squared()
		if d2 < best_d2 and d2 > 0.04:
			best_d2 = d2
			aim = d
	if aim.length_squared() < 0.04:
		return
	var basis: Basis = f.global_transform.basis
	if not basis.is_finite() or absf(basis.determinant()) < 1e-8:
		return
	var local: Vector3 = basis.inverse() * aim.normalized()
	if not local.is_finite():
		return
	var yaw: float = clampf(atan2(-local.x, maxf(-local.z, 0.05)), -0.55, 0.55)
	var pitch: float = clampf(atan2(local.y, 1.0), -0.4, 0.35)
	for entry in f._soft_chains:
		var pivots: Array = entry["pivots"]
		if pivots.is_empty():
			continue
		var name_s: String = String(pivots[0].name)
		if not name_s.begins_with("Feeler"):
			continue
		pivots[0].rotation.y = lerpf(pivots[0].rotation.y, yaw, 1.0 - exp(-dt * 3.0))
		pivots[0].rotation.x = lerpf(pivots[0].rotation.x, pitch, 1.0 - exp(-dt * 3.0))


static func apply_channel_order(f: Fish, dt: float) -> void:
	# #234: start = eyes→head→pecs→body→tail; stop = reverse settle.
	# Applied as a soft scale on already-posed angles (never a hard multiply
	# that fights the caudal spring into a jerk).
	if not enabled:
		return
	var starting: bool = f.burst_remaining > 0.05 or f.speed > f.max_speed * 0.55
	var stopping: bool = f._brake_pose > 0.2 or (f.speed < f.max_speed * 0.12 \
		and f._motion_target_spd < f.max_speed * 0.1)
	var gate: float = float(f.get_meta("_p2_order_gate", 1.0))
	var target: float = 1.0
	if starting:
		target = 1.0
	elif stopping:
		target = 0.55
	gate = lerpf(gate, target, 1.0 - exp(-dt * (2.5 if starting else 1.4)))
	f.set_meta("_p2_order_gate", gate)
	if f._tail_pivot != null and gate < 0.95:
		f._tail_pivot.rotation.y = lerpf(f._tail_pivot.rotation.y,
			f._tail_pivot.rotation.y * lerpf(0.7, 1.0, gate), 0.35)
	if f._body_mid_pivot != null and gate < 0.75:
		f._body_mid_pivot.rotation.y = lerpf(f._body_mid_pivot.rotation.y,
			f._body_mid_pivot.rotation.y * lerpf(0.8, 1.0, clampf(gate / 0.75, 0.0, 1.0)), 0.3)


static func apply_sucker_rasp(f: Fish, dt: float) -> void:
	# #319: oral disc rasps at ~2–3 Hz while pressed to glass / bed.
	if not enabled or not f.ventral_sucker:
		return
	var disc: Node3D = f.get_node_or_null("BankPivot/BodyMid/SuckerDisc") as Node3D
	if disc == null and f._body_mid_pivot != null:
		disc = f._body_mid_pivot.get_node_or_null("SuckerDisc") as Node3D
	if disc == null:
		return
	var active: bool = f.speed < 0.25 and f.global_position.y < _bed_y(f) + 0.9
	var phase: float = float(f.get_meta("_p2_rasp_phase", 0.0))
	if active:
		phase += dt * TAU * 2.6
		disc.position.z = sin(phase) * f.adult_voxel_scale * 0.04
		disc.scale.x = 1.0 + sin(phase * 2.0) * 0.06
	else:
		disc.position.z = lerpf(disc.position.z, 0.0, 1.0 - exp(-dt * 6.0))
		disc.scale.x = lerpf(disc.scale.x, 1.0, 1.0 - exp(-dt * 6.0))
	f.set_meta("_p2_rasp_phase", phase)


static func apply_fin_edge_thickness(f: Fish) -> void:
	# #390: keep a minimum visible thickness so fins don't vanish edge-on.
	if not enabled:
		return
	const MIN_T: float = 0.55
	for piv in [f._dorsal_pivot, f._anal_pivot, f._tail_pivot,
			f._pec_left_pivot, f._pec_right_pivot]:
		if piv == null:
			continue
		var sx: float = piv.scale.x
		if absf(sx) < MIN_T:
			piv.scale.x = MIN_T if sx >= 0.0 else -MIN_T


static func skating_frac(speed: float, effort: float, max_speed: float) -> float:
	# #395: translation without matching locomotor effort.
	var u: float = speed / maxf(max_speed, 0.1)
	var e: float = clampf(effort, 0.0, 1.5)
	return maxf(0.0, u - e * 1.15)


static func apply_anti_skate(f: Fish, dt: float) -> void:
	# Soften orphaned translation so the fish doesn't skate on residual velocity.
	# Keep this very gentle: aggressive speed pulls show up as jerk p95 spikes
	# in smoke_motion_phase2_metrics (OFF vs ON A/B).
	if not enabled:
		return
	if f.burst_remaining > 0.0 or f._aerial_timer > 0.0 or f._startle_remaining > 0.0:
		return
	if float(f.get_meta("_p2_fin_reopen", 0.0)) > 0.05:
		return
	var effort: float = clampf(absf(f._motion_target_spd) / maxf(f.max_speed, 0.1), 0.0, 1.2)
	effort = maxf(effort, float(f._fin_effort_cache.get("tail_amp", 0.0)) if f._fin_effort_cache else 0.0)
	var skate: float = skating_frac(f.speed, effort, f.max_speed)
	if skate > 0.28:
		f.speed = lerpf(f.speed, f.max_speed * effort, 1.0 - exp(-dt * 0.9))


static func crab_heading_bias(heading: Vector3, flow: Vector3, strength: float = 0.08) -> Vector3:
	# #387: ease into a cross-current (continuous cross product, never signf()
	# which flipped across the flow axis and chattered heading every frame).
	if not enabled or flow.length_squared() < 0.0004 or heading.length_squared() < 1e-6:
		return heading
	var h: Vector3 = heading.normalized()
	var flow_h := Vector3(flow.x, 0.0, flow.z)
	if flow_h.length_squared() < 1e-6:
		return heading
	flow_h = flow_h.normalized()
	var cross: float = h.x * flow_h.z - h.z * flow_h.x
	if absf(cross) < 0.08:
		return heading
	var side_w: float = clampf(cross * 3.0, -1.0, 1.0)
	var into: Vector3 = (h + flow_h * strength * absf(side_w)).normalized()
	return h.lerp(into, 0.025).normalized()


static func _is_bottom(f: Fish) -> bool:
	return f.swim_pattern == "shuffle" or f.locomotion_type == "anguilliform" \
		or f.ventral_sucker or f.body_shape == "depressed"


static func _bed_y(f: Fish) -> float:
	if f.sim != null and f.sim.get("substrate_top_y") != null:
		return float(f.sim.substrate_top_y)
	return 0.5


static func _cap_scale(s: Vector3, f: Fish) -> Vector3:
	# #134 global caps (±8% adults, ±12% fry; puffer handled above).
	var lim: float = 0.12 if f.maturity == Fish.MATURITY_FRY else 0.08
	return Vector3(
		clampf(s.x, 1.0 - lim, 1.0 + lim * 2.0),
		clampf(s.y, 1.0 - lim, 1.0 + lim * 2.0),
		clampf(s.z, 1.0 - lim, 1.0 + lim * 2.0))


static func _decay_meta(f: Fish, key: String, rate: float) -> void:
	var v: float = float(f.get_meta(key, 0.0))
	if v > 0.0:
		f.set_meta(key, maxf(0.0, v - rate))
