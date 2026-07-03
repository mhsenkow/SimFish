class_name MotionWave
extends RefCounted

# LIVING_MOTION §B — scale-free correlation through topological links.
# Agitation and turn intent propagate fish-to-fish instead of tank broadcasts.

const AGITATION_DECAY_DEFAULT: float = 2.6
const MANOEUVRE_WAVE_SPEED_DEFAULT: float = 5.2

static var agitation_decay: float = AGITATION_DECAY_DEFAULT
static var manoeuvre_wave_speed: float = MANOEUVRE_WAVE_SPEED_DEFAULT
const PROPAGATION_BLEND_DEFAULT: float = 0.44
const REFRACTORY_DURATION: float = 0.55
const REFRACTORY_DAMP: float = 0.62
const TURN_INTENT_BLEND: float = 0.38
const TURN_INTENT_DECAY: float = 4.5
const CASCADE_FLOOR: float = 0.04
const CASCADE_HYST: float = 0.03

static var propagation_blend: float = PROPAGATION_BLEND_DEFAULT

static var _music_sweep_prev: float = 0.0


static func reset_for_test() -> void:
	_music_sweep_prev = 0.0
	agitation_decay = AGITATION_DECAY_DEFAULT
	manoeuvre_wave_speed = MANOEUVRE_WAVE_SPEED_DEFAULT
	propagation_blend = PROPAGATION_BLEND_DEFAULT


static func sync_tuning(cfg: Node) -> void:
	if cfg == null:
		return
	agitation_decay = clampf(float(cfg.get("motion_agitation_decay") if cfg.get("motion_agitation_decay") != null else agitation_decay),
		0.8, 6.0)
	manoeuvre_wave_speed = clampf(float(cfg.get("motion_wave_speed") if cfg.get("motion_wave_speed") != null else manoeuvre_wave_speed),
		2.0, 12.0)
	propagation_blend = clampf(float(cfg.get("motion_propagation_blend") if cfg.get("motion_propagation_blend") != null else propagation_blend),
		0.15, 0.85)


static func uses_wave(f: Node) -> bool:
	if f == null:
		return false
	var sp: String = str(f.get("swim_pattern") if f.get("swim_pattern") != null else "")
	var sch: float = float(f.get("schooling_strength") if f.get("schooling_strength") != null else 0.0)
	return (sp == "school" or sp == "shoal") and sch > 0.4


static func tick(fish_arr: Array, dt: float) -> void:
	if fish_arr.is_empty():
		return
	for f_v in fish_arr:
		if is_instance_valid(f_v) and uses_wave(f_v):
			f_v.motion_agitation_snap = float(f_v.motion_agitation)
	var hop: float = clampf(manoeuvre_wave_speed * dt, 0.0, 1.0)
	for f_v in fish_arr:
		if not is_instance_valid(f_v) or f_v.get("_dying") == true:
			continue
		if not uses_wave(f_v):
			continue
		f_v.motion_agitation = maxf(0.0, float(f_v.motion_agitation) * exp(-agitation_decay * dt))
		f_v.motion_refractory = maxf(0.0, float(f_v.motion_refractory) - dt)
		f_v.motion_turn_intent = (f_v.motion_turn_intent as Vector3) \
				* maxf(0.0, 1.0 - TURN_INTENT_DECAY * dt)

	if MindBoidsBuffer.backend == "none":
		return

	for f_v in fish_arr:
		if not is_instance_valid(f_v) or f_v.get("_dying") == true:
			continue
		if not uses_wave(f_v):
			continue
		var idx: int = MindBoidsBuffer.index_for(f_v)
		if idx < 0:
			continue
		var best_agit: float = float(f_v.motion_agitation)
		var best_intent: Vector3 = f_v.motion_turn_intent as Vector3
		for t in MindBoidsBuffer.N_TOPO:
			var ni: int = MindBoidsBuffer.topo_neighbor_at(idx, t)
			if ni < 0:
				continue
			var nf: Node = MindBoidsBuffer.fish_refs[ni]
			if not is_instance_valid(nf):
				continue
			if float(nf.motion_agitation) > best_agit:
				best_agit = float(nf.motion_agitation)
			var nf_intent: Vector3 = nf.motion_turn_intent as Vector3
			if nf_intent.length_squared() > best_intent.length_squared():
				best_intent = nf_intent

		var refr: float = clampf(float(f_v.motion_refractory) / REFRACTORY_DURATION, 0.0, 1.0)
		var blend: float = propagation_blend * hop * (1.0 - refr * REFRACTORY_DAMP)
		var gf: float = float(f_v.get("growth_factor") if f_v.get("growth_factor") != null else 1.0)
		blend *= lerpf(1.0, 0.62, clampf((gf - 0.85) / 0.55, 0.0, 1.0))
		var wave_jitter: float = 1.0
		if f_v.has_method("_behavior_rng"):
			wave_jitter = lerpf(0.88, 1.12, f_v._behavior_rng().randf())
		blend *= wave_jitter
		if best_agit > float(f_v.motion_agitation) + CASCADE_FLOOR + CASCADE_HYST:
			f_v.motion_agitation = lerpf(float(f_v.motion_agitation), best_agit, blend)
		if best_intent.length_squared() > 1e-5:
			f_v.motion_turn_intent = (f_v.motion_turn_intent as Vector3).lerp(best_intent, blend * TURN_INTENT_BLEND)


static func inject_at(fish_arr: Array, origin: Vector3, amount: float,
		turn_away: Vector3 = Vector3.ZERO, salience: float = 1.0) -> Node:
	var best: Node = null
	var best_d2: float = 1e9
	for f_v in fish_arr:
		if not is_instance_valid(f_v) or f_v.get("_dying") == true:
			continue
		if not uses_wave(f_v):
			continue
		var p: Vector3 = f_v.position as Vector3
		var d2: float = Vector2(p.x - origin.x, p.z - origin.z).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = f_v
	if best == null:
		return null
	var inj: float = clampf(amount * salience, -1.0, 1.0)
	if inj >= 0.0:
		best.motion_agitation = clampf(float(best.motion_agitation) + inj, 0.0, 1.0)
		best.motion_refractory = 0.0
	else:
		best.motion_agitation = clampf(float(best.motion_agitation) + inj, 0.0, 1.0)
	if turn_away.length_squared() > 1e-4:
		var intent: Vector3 = turn_away
		intent.y *= 0.22
		best.motion_turn_intent = intent.normalized() * clampf(absf(inj), 0.2, 1.0)
	return best


static func inject_calm(fish_arr: Array, origin: Vector3, amount: float = 0.35) -> void:
	inject_at(fish_arr, origin, -absf(amount))


static func tick_music_sweep(fish_arr: Array, sweep: float, beat_phase: float) -> void:
	var rising: float = maxf(0.0, sweep - _music_sweep_prev)
	_music_sweep_prev = sweep
	if rising < 0.12 or sweep < 0.15:
		return
	var leader: Node = null
	var best_lead: float = -1.0
	for f_v in fish_arr:
		if not is_instance_valid(f_v) or f_v.get("_dying") == true:
			continue
		if not uses_wave(f_v):
			continue
		var ls: float = float(f_v.get("lead_score") if f_v.get("lead_score") != null else 0.0)
		if ls > best_lead:
			best_lead = ls
			leader = f_v
	if leader == null:
		return
	var sweep_dir: Vector3 = Vector3(cos(beat_phase), 0.0, sin(beat_phase))
	leader.motion_agitation = clampf(float(leader.motion_agitation) + rising * 0.85, 0.0, 1.0)
	leader.motion_turn_intent = sweep_dir.normalized() * rising


static func agitation_turn_boost(agitation: float) -> float:
	return lerpf(1.0, 1.72, clampf(agitation, 0.0, 1.0))


static func turn_intent_steer(f: Node, effective_max: float) -> Vector3:
	if f == null:
		return Vector3.ZERO
	var intent: Vector3 = f.motion_turn_intent as Vector3
	if intent.length_squared() < 1e-5:
		return Vector3.ZERO
	return intent.normalized() * effective_max \
			* clampf(float(f.motion_agitation), 0.15, 1.0) * 0.62


static func startle_salience_for_distance(dist: float, max_r: float = 9.0) -> float:
	return 1.0 - clampf(dist / maxf(max_r, 0.1), 0.0, 1.0)
