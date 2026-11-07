class_name FishPoseRuntime
extends RefCounted

# CREATURE_MOTION_700 §G — pose-to-pose layer on top of straight-ahead physics.
# Selects a named pose from MotionPoseLibrary, blends through the transition
# graph (#213), keeps a moving-hold (#214), and maps continuous affect (#215).


const HOLD_FLICKER: float = 0.04
const _META_OFFS: StringName = &"_pose_offs"
const _ZERO_OFFS: PackedFloat32Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

static var enabled: bool = true

# Per-fish state lives on Fish metas / fields to avoid allocating drivers.
#   _pose_name: String
#   _pose_blend: MotionPoseLibrary.Blend
#   _pose_channels: Dictionary (resolved mixed channels)
#   _pose_end: String (post-action pose, e.g. glide after dart)


static func _meta_f(f: Fish, key: String, fallback: float) -> float:
	if f.has_meta(key):
		return float(f.get_meta(key))
	return fallback


static func ensure(f: Fish) -> void:
	if f.has_meta("_pose_blend") and f.get_meta("_pose_blend") is MotionPoseLibrary.Blend:
		return
	var b := MotionPoseLibrary.Blend.new(0.5, 0.6, "sine")
	b.weight = 1.0
	b.target = 1.0
	f.set_meta("_pose_blend", b)
	f.set_meta("_pose_name", "cruise")
	f.set_meta("_pose_channels", MotionPoseLibrary.get_pose(f.species, "cruise"))
	f.set_meta("_pose_hold_t", 0.0)


static func force_pose(f: Fish, pose_name: String) -> void:
	# Motion-lab pose editor (#218): lock selection so sliders preview one shape.
	if f == null:
		return
	ensure(f)
	f.set_meta("_pose_force", pose_name)
	f.set_meta("_pose_name", pose_name)
	var blend: MotionPoseLibrary.Blend = f.get_meta("_pose_blend")
	blend.weight = 1.0
	blend.target = 1.0
	blend._t = 1.0
	f.set_meta("_pose_channels", MotionPoseLibrary.get_pose(f.species, pose_name))


static func clear_force_pose(f: Fish) -> void:
	if f == null:
		return
	if f.has_meta("_pose_force"):
		f.remove_meta("_pose_force")
	if f.has_meta("_pose_edit_channels"):
		f.remove_meta("_pose_edit_channels")


static func set_edit_channels(f: Fish, channels: Dictionary) -> void:
	if f == null:
		return
	ensure(f)
	f.set_meta("_pose_edit_channels", channels.duplicate(true))
	f.set_meta("_pose_channels", channels.duplicate(true))


static func select_pose(f: Fish) -> String:
	# Priority: death → illness → sleep → gulp/gasp → display/threat → forage poses → hover/cruise.
	if f.has_meta("_pose_force"):
		return str(f.get_meta("_pose_force"))
	if f._dying or (f.maturity == Fish.MATURITY_SENESCENT and f.energy < 0.05):
		return "dead"
	if f.stress > 0.88 and f.energy < 0.25 and f.speed < 0.1 and f.mood < -0.35:
		return "listing"
	if f._asleep:
		if f._sleep_have_nook and f._sleep_nook.distance_squared_to(f.global_position) < 1.0:
			return "wedged"
		return "sleep"
	if float(f.get_meta("_ant_pre_gulp", 0.0)) > 0.2 or (f._aerial_timer > 0.0 and f.labyrinth_breather):
		if f.sim != null and f.sim.get("dissolved_o2") != null and float(f.sim.dissolved_o2) < 0.28:
			return "gasping"
		return "gulp"
	if f._mouthbrood_progress > 0.05:
		return "mouthbrood"
	if f.brooding_remaining > 0.05 and f._fidget_kind == 1 and f._fidget_remaining > 0.05:
		return "fanning"
	if f._courtship_sync or (f._courtship_flare and f.court_timer > Fish.COURT_DURATION * 0.75):
		return "spawn_clasp"
	if float(f.get_meta("_ant_threat", 0.0)) > 0.35 or (f.is_territorial and f._territory_chase_t > 0.05 \
			and f._territory_chase_t < 0.85):
		return "threat"
	if f._courtship_flare or f.current_mode == Fish.Mode.COURT:
		return "display"
	if f.stress > 0.72 or f.spooked > 0.55 or float(f.get_meta("_ant_freeze", 0.0)) > 0.4:
		if f.rank_within_species < 0.35 and f.stress > 0.55:
			return "submission"
		return "clamped"
	if f._sift_timer > 0.05:
		return "sifting"
	if f.ventral_sucker and f.speed < 0.2 and f.global_position.y < f._water_surface_y() - 1.5:
		# Attached when slow near glass/wood — approximate with low speed + sucker.
		if absf(f.global_position.x) > 5.5 or f.speed < 0.08:
			return "attached"
	if f.current_mode == Fish.Mode.FORAGE and f.hunger > 0.45 and f.velocity.y < -0.05:
		return "picking"
	if f._mouth_gape > 0.55 and f.current_mode == Fish.Mode.FORAGE:
		return "chew"
	if f.burst_remaining <= 0.05 and f.speed > f.max_speed * 0.55 \
			and f._motion_target_spd < f.speed * 0.7:
		return "glide"
	if f.swim_pattern == "sit" and f.speed < 0.14 and f.global_position.y < 1.2:
		return "bed_rest"
	if f.stress > 0.4 or f.spooked > 0.25 or f.arousal > 0.55:
		return "alert"
	if f.speed < f.max_speed * 0.18 and f.burst_remaining <= 0.0:
		return "hover"
	var end_pose: String = str(f.get_meta("_pose_end", ""))
	if end_pose != "" and float(f.get_meta("_pose_end_t", 0.0)) > 0.0:
		return end_pose
	return "cruise"


static func transition_seconds(species: String, from_pose: String, to_pose: String) -> float:
	if not MotionPoseLibrary._loaded:
		MotionPoseLibrary.reload_data()
	var graph: Variant = MotionPoseLibrary._data.get("_transitions", {})
	if graph is Dictionary:
		var row: Variant = (graph as Dictionary).get(from_pose, {})
		if row is Dictionary and (row as Dictionary).has(to_pose):
			return float((row as Dictionary)[to_pose])
	var times: Vector2 = MotionPoseLibrary.blend_times(species, to_pose)
	return times.x


static func tick(f: Fish, dt: float) -> Dictionary:
	if not enabled or f == null or not (dt > 0.0):
		return {}
	ensure(f)
	var want: String = select_pose(f)
	var cur: String = str(f.get_meta("_pose_name") if f.has_meta("_pose_name") else "cruise")
	var blend: MotionPoseLibrary.Blend = f.get_meta("_pose_blend")
	if want != cur:
		var secs: float = transition_seconds(f.species, cur, want)
		blend.in_s = maxf(secs, 0.05)
		blend.out_s = maxf(secs * 0.85, 0.05)
		var pose_meta: Dictionary = MotionPoseLibrary.get_pose(f.species, want)
		blend.curve = str(pose_meta.get("_ease", "smooth"))
		# Crossfade: drop old weight, rise into new.
		blend.weight = 0.0
		blend.set_on(true)
		f.set_meta("_pose_name", want)
		cur = want
	blend.step(dt)
	var end_t: float = float(f.get_meta("_pose_end_t") if f.has_meta("_pose_end_t") else 0.0)
	if end_t > 0.0:
		f.set_meta("_pose_end_t", maxf(0.0, end_t - dt))
		if end_t - dt <= 0.0:
			f.set_meta("_pose_end", "")
	# Lab edit override (#218): slider channels win while force-previewing.
	if f.has_meta("_pose_edit_channels"):
		var edited: Dictionary = f.get_meta("_pose_edit_channels") as Dictionary
		f.set_meta("_pose_channels", edited)
		return edited
	# Continuous affect (#215): valence/arousal soft-mix relaxed/alert/clamped.
	# Resolved poses are cached and shared (read-only); mix_channels returns a
	# fresh dictionary, so `mixed` below is ours to edit.
	var base: Dictionary = MotionPoseLibrary.resolved_channels(f.species, cur)
	var affect_w: float = clampf(float(f.arousal) * 0.55 + maxf(float(f.stress) - 0.35, 0.0) * 0.5, 0.0, 1.0)
	var valence: float = clampf((float(f.mood) + 1.0) * 0.5, 0.0, 1.0)
	var alert_p: Dictionary = MotionPoseLibrary.resolved_channels(f.species, "alert")
	var mixed: Dictionary = MotionPoseLibrary.mix_channels(base, alert_p, affect_w * valence * 0.35)
	if float(f.stress) > 0.5:
		var clamp_p: Dictionary = MotionPoseLibrary.resolved_channels(f.species, "clamped")
		mixed = MotionPoseLibrary.mix_channels(mixed, clamp_p, clampf((float(f.stress) - 0.5) * 0.7, 0.0, 0.55))
	# Moving hold (#214): breath / fin flicker / tiny drift never freeze.
	var hold_t: float = float(f.get_meta("_pose_hold_t") if f.has_meta("_pose_hold_t") else 0.0) + dt
	f.set_meta("_pose_hold_t", hold_t)
	var flicker: float = sin(hold_t * 7.3 + float(f.get_instance_id() & 31)) * HOLD_FLICKER
	mixed["fin_carriage"] = float(mixed.get("fin_carriage", 0.0)) + flicker
	mixed["pec_spread"] = float(mixed.get("pec_spread", 0.0)) + flicker * 0.6
	# Breath hold stays on the pose's base rate — oscillating it here fed
	# breath_hover_offset and broke 30↔120 Hz path parity in smoke_motion_phase1.

	# Weight the mix by blend progress so transitions don't pop.
	var w: float = blend.weight
	var rest: Dictionary = MotionPoseLibrary.resolved_channels(f.species, "rest")
	var out: Dictionary = MotionPoseLibrary.mix_channels(rest, mixed, w)
	f.set_meta("_pose_channels", out)
	return out


static func note_action_end(f: Fish, pose: String, hold_s: float = 0.55) -> void:
	# #216: dart → glide, strike → chew, etc.
	if f == null:
		return
	f.set_meta("_pose_end", pose)
	f.set_meta("_pose_end_t", hold_s)


static func apply(f: Fish, pec_amp: float, pec_spread: float, dt: float) -> Dictionary:
	var ch: Dictionary = tick(f, dt)
	if ch.is_empty():
		return {"pec_amp": pec_amp, "pec_spread": pec_spread}
	# Additive channels only — never replace the living bank/pitch springs or
	# write scales (those fight hydro / framerate path parity).
	var carriage: float = float(ch.get("fin_carriage", 0.0))
	pec_spread += carriage * 0.28 + float(ch.get("pec_spread", 0.0)) * 0.45
	pec_amp += maxf(float(ch.get("pec_forward", 0.0)), 0.0) * 0.35
	f.set_meta("_pose_caudal_spread", float(ch.get("caudal_spread", 1.0)))
	# Expressive poses only. Never += every frame (that integrates unbound and
	# breaks 30↔120 Hz path parity). Soft-damp a stored offset, then add once.
	var d_raise: float = float(ch.get("dorsal_raise", 0.0))
	var a_raise: float = float(ch.get("anal_raise", 0.0))
	var pitch: float = float(ch.get("head_pitch", 0.0))
	var roll: float = float(ch.get("roll", 0.0))
	var arch: float = float(ch.get("body_arch", 0.0))
	var op: float = float(ch.get("opercula", 0.0))
	var jaw: float = float(ch.get("jaw", 0.0))
	var want_d: float = d_raise if absf(d_raise) > 0.2 else 0.0
	var want_a: float = a_raise if absf(a_raise) > 0.2 else 0.0
	var want_p: float = pitch if absf(pitch) > 0.2 else 0.0
	var want_r: float = roll if absf(roll) > 0.2 and absf(roll) < PI * 0.5 else 0.0
	var want_arch: float = arch if absf(arch) > 0.15 else 0.0
	var want_op: float = op if absf(op) > 0.15 else 0.0
	var want_jaw: float = jaw if absf(jaw) > 0.15 else 0.0
	# The seven damped offsets live in one packed meta (d, a, p, r, arch, op,
	# jaw): fourteen meta reads/writes per fish per frame were a measurable
	# share of the pose pass.
	var offs: PackedFloat32Array = f.get_meta(_META_OFFS, _ZERO_OFFS)
	var off_d: float = MotionEase.damp(offs[0], want_d, 6.0, dt)
	var off_a: float = MotionEase.damp(offs[1], want_a, 6.0, dt)
	var off_p: float = MotionEase.damp(offs[2], want_p, 5.0, dt)
	var off_r: float = MotionEase.damp(offs[3], want_r, 4.0, dt)
	var off_arch: float = MotionEase.damp(offs[4], want_arch, 5.0, dt)
	var off_op: float = MotionEase.damp(offs[5], want_op, 6.0, dt)
	var off_jaw: float = MotionEase.damp(offs[6], want_jaw, 8.0, dt)
	f.set_meta(_META_OFFS, PackedFloat32Array([off_d, off_a, off_p, off_r, off_arch, off_op, off_jaw]))
	if f._dorsal_pivot != null:
		f._dorsal_pivot.rotation.x += off_d * 0.35
	if f._anal_pivot != null:
		f._anal_pivot.rotation.x += -off_a * 0.35
	if f._bank_pivot != null and f._sift_timer <= 0.0 and f._aerial_timer <= 0.0:
		f._bank_pivot.rotation.x = clampf(f._bank_pivot.rotation.x + off_p * 0.35, -0.55, 0.6)
		f._bank_pivot.rotation.z = clampf(f._bank_pivot.rotation.z + off_r * 0.3, -0.8, 0.8)
	if f._body_mid_pivot != null:
		f._body_mid_pivot.rotation.x = off_arch * 0.28
	if f._operculum_left != null:
		f._operculum_left.rotation.y = clampf(f._operculum_left.rotation.y + off_op * 0.35, -0.55, 0.25)
		if f._operculum_right != null:
			f._operculum_right.rotation.y = clampf(f._operculum_right.rotation.y - off_op * 0.35, -0.25, 0.55)
	if f._jaw_pivot != null:
		f._jaw_pivot.rotation.x = clampf(f._jaw_pivot.rotation.x + off_jaw * 0.25, 0.0, 0.85)
	# Pose breath / colour stay visual-only. Writing `_breath_load` here made
	# frustum-culled fish diverge from seen fish on Y (breath_hover_offset),
	# which fails smoke_motion_phase1's culled↔seen path check.
	f.set_meta("_pose_breath", float(ch.get("breath", 1.0)))
	var col: float = float(ch.get("colour", 0.5))
	if col > 0.7:
		f.set_meta("_pose_flush", (col - 0.7) * 0.8)
	return {"pec_amp": pec_amp, "pec_spread": pec_spread, "channels": ch}


static func required_poses() -> PackedStringArray:
	return PackedStringArray([
		"cruise", "hover", "alert", "clamped", "display", "threat", "submission",
		"picking", "attached", "bed_rest", "sleep", "wedged", "gulp", "sifting",
		"spawn_clasp", "mouthbrood", "fanning", "listing", "gasping", "glide",
		"chew", "dead",
	])
