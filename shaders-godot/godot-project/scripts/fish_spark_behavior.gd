extends RefCounted

# SENTIENCE_THE_SPARK §B/C — close loops + wire dark hooks into motor behavior.

const FishGenerativeSelf = preload("res://scripts/fish_generative_self.gd")
const FishVolition = preload("res://scripts/fish_volition.gd")
const MindDaring = preload("res://scripts/mind_daring.gd")
const MindWorldModel = preload("res://scripts/mind_world_model.gd")
const EpisodicMemory = preload("res://scripts/episodic_memory.gd")
const FishMind = preload("res://scripts/fish_mind.gd")
const FishProtoself = preload("res://scripts/fish_protoself.gd")
const FeltSelfLayer = preload("res://scripts/felt_self_layer.gd")


static func enabled() -> bool:
	return FeltSelfLayer.layer_enabled()


static func habituate(f: Fish, key: String, amount: float = 0.12) -> void:
	if key == "":
		return
	var cur: float = float(f.habituated.get(key, 1.0))
	f.habituated[key] = clampf(cur - amount, 0.0, 1.0)


static func encounter_novelty(f: Fish, key: String) -> float:
	var nov: float = MindWorldModel.stimulus_novelty(f, key) if key != "" else 1.0
	if nov > 0.35:
		habituate(f, key, 0.08 + nov * 0.06)
	return nov


static func glass_tap_habituation(f: Fish, tap_strength: float) -> void:
	var nov: float = encounter_novelty(f, "player")
	if nov < 0.25:
		f.stress = clampf(f.stress + tap_strength * 0.04 * (1.0 - nov), 0.0, 1.0)


static func tick_dark_room_guard(f: Fish, sim: Node, dt: float) -> void:
	if not enabled() or f == null or sim == null:
		return
	var hiding: bool = f.stress > 0.35 and f.speed < 0.25
	if hiding:
		f._hide_timer = float(f._hide_timer) + dt
	else:
		f._hide_timer = maxf(0.0, float(f._hide_timer) - dt * 0.5)
	if float(f._hide_timer) > 45.0:
		f.curiosity_drive = clampf(f.curiosity_drive + dt * 0.035, 0.0, 1.0)


static func tick_longing_linger(f: Fish, _dt: float) -> Vector3:
	var lr: float = float(f._longing_residue if f._longing_residue != null else 0.0)
	if lr <= 0.05:
		return Vector3.ZERO
	if f.get("_longing_linger_pos") == null:
		f._longing_linger_pos = f.position
	var target: Vector3 = f._longing_linger_pos as Vector3
	var to: Vector3 = target - f.position
	to.y *= 0.35
	if to.length_squared() > 0.04:
		return to.normalized() * lerpf(0.0, 0.35, lr)
	return Vector3.ZERO


static func signal_reaction_delay(f: Fish, caller: Fish, base: float) -> float:
	if caller == null or not enabled():
		return base
	var rel: float = FishSignals.interpret(f, "alarm")
	if rel < 0.75:
		return base * lerpf(2.2, 1.0, rel / 0.75)
	return base


static func affordance_motor_scale(_f: Fish, affordance: String) -> float:
	match affordance:
		"edible":
			return 1.05
		"hide_from":
			return 1.35
		"mate_with":
			return 0.82
		"manufacture_goal":
			return 0.95
	return 1.0


static func winning_affordance(f: Fish) -> String:
	if f.get("_last_winning_affordance") != null:
		return str(f._last_winning_affordance)
	return ""


static func schema_spatial_pull(f: Fish) -> Vector3:
	if not enabled():
		return Vector3.ZERO
	var hint: Dictionary = f._episodic_retrieval_hint if f.get("_episodic_retrieval_hint") is Dictionary else {}
	if hint.is_empty() or not hint.has("pos"):
		return Vector3.ZERO
	var pos: Vector3 = hint["pos"] as Vector3
	var val: float = float(hint.get("valence", 0.0))
	var to: Vector3 = pos - f.position
	to.y *= 0.25
	if to.length_squared() < 0.01:
		return Vector3.ZERO
	var dir: Vector3 = to.normalized()
	if val < -0.2:
		return -dir * clampf(absf(val), 0.0, 1.0) * 0.4
	if val > 0.15:
		return dir * clampf(val, 0.0, 1.0) * 0.35
	return Vector3.ZERO


# SENTIENCE_THE_SPARK #33 — learned danger regions bend patrol routes.
static func schema_patrol_avoidance(f: Fish) -> Vector3:
	if not enabled() or (f._semantic_schemas as Array).is_empty():
		return Vector3.ZERO
	var steer: Vector3 = Vector3.ZERO
	for s in (f._semantic_schemas as Array):
		var c: Variant = s.get("center", null)
		if not (c is Vector3):
			continue
		var center: Vector3 = c as Vector3
		var val: float = float(s.get("valence", 0.0)) * float(s.get("strength", 0.0))
		var to: Vector3 = f.position - center
		to.y *= 0.2
		var d: float = to.length()
		if d < 0.05 or d > EpisodicMemory.SCHEMA_RADIUS * 1.35:
			continue
		var w: float = (1.0 - d / (EpisodicMemory.SCHEMA_RADIUS * 1.35))
		if val < -0.15:
			steer += to.normalized() * w * clampf(-val, 0.0, 1.0)
		elif val > 0.12:
			steer -= to.normalized() * w * clampf(val, 0.0, 1.0) * 0.35
	if steer.length_squared() > 1e-4:
		return steer.normalized() * clampf(steer.length(), 0.0, 1.0)
	return Vector3.ZERO


static func bias_patrol_anchors_from_schemas(f: Fish) -> void:
	if not enabled() or f.patrol_anchors.is_empty():
		return
	for i in f.patrol_anchors.size():
		var pos: Vector3 = f.patrol_anchors[i] as Vector3
		var val: float = EpisodicMemory.schema_valence_at(f, pos)
		if val < -0.35:
			var push: Vector3 = schema_patrol_avoidance(f)
			if push.length_squared() > 1e-4:
				var w: Node = f._world_node()
				var nudged: Vector3 = pos + push * 2.2
				if w != null and w.has_method("clamp_xyz_in_tank"):
					nudged = w.clamp_xyz_in_tank(nudged, 0.5, f._body_tank_margin())
				f.patrol_anchors[i] = nudged


# SENTIENCE_THE_SPARK #38 — cross-species feeding niche soft avoidance.
static func cross_species_feeding_penalty(f: Fish, wpos: Vector3, neighbors: Array) -> float:
	if neighbors.is_empty():
		return 1.0
	var bold: float = f._boldness() if f.has_method("_boldness") else 0.5
	var mult: float = 1.0
	for n in neighbors:
		if not (n is Fish) or n == f:
			continue
		var o: Fish = n
		if o.species == f.species or o.current_mode != Fish.Mode.FORAGE:
			continue
		if o.position.distance_squared_to(wpos) > 2.25:
			continue
		mult *= lerpf(1.85, 1.05, clampf(bold / 1.6, 0.0, 1.0))
		break
	return mult


# SENTIENCE_THE_SPARK #39 — landscape-of-fear range contraction (0..1 threat).
static func landscape_fear_from_neighbors(f: Fish, neighbors: Array) -> float:
	var threat: float = 0.0
	for n in neighbors:
		if not (n is Fish):
			continue
		var pf: Fish = n
		if pf == f or pf.species == f.species:
			continue
		if pf.get("_asleep") == true:
			continue
		if pf.growth_factor * pf.adult_voxel_scale <= f.adult_voxel_scale * 1.25:
			continue
		var pd2: float = pf.position.distance_squared_to(f.position)
		if pd2 < 12.0:
			threat = maxf(threat, 1.0 - sqrt(pd2) / 3.5)
	return threat


static func landscape_range_scale(fear: float) -> float:
	return lerpf(1.0, 0.42, clampf(fear, 0.0, 1.0))


# SENTIENCE_THE_SPARK #78 — rest/hover vertical bob from protoself gill rhythm.
static func breath_hover_offset(f: Fish, dt: float) -> float:
	if not enabled() or f.get("_dying") == true:
		return 0.0
	var resting: bool = f._asleep or f.current_mode == Fish.Mode.REST \
			or (f.speed < 0.32 and f.swim_pattern == "hover")
	if not resting:
		return 0.0
	var ps: Dictionary = FishProtoself.ensure(f)
	var rhythm: float = float(ps.get("gill_rhythm", 1.0))
	f._breath_phase += dt * lerpf(0.55, 1.35, rhythm)
	return sin(f._breath_phase * TAU) * 0.11 * rhythm


static func feed_anticipation_drift(f: Fish, sim: Node) -> Vector3:
	if f.hunger < 0.35 or sim == null:
		return Vector3.ZERO
	if not sim.has_method("feed_anticipation_active") or not sim.feed_anticipation_active():
		return Vector3.ZERO
	if not sim.has_method("anticipated_feed_surface_pos"):
		return Vector3.ZERO
	var spot: Vector3 = sim.anticipated_feed_surface_pos()
	if spot == Vector3.ZERO:
		return Vector3.ZERO
	var to: Vector3 = spot - f.position
	to.y *= 0.2
	if to.length_squared() < 0.04:
		return Vector3.ZERO
	return to.normalized() * 0.28


static func pulse_feed_contagion_at(sim: Node, pos: Vector3, eater: Node,
		strength: float = 0.55) -> void:
	if not enabled() or sim == null or sim.get("fish") == null:
		return
	const RADIUS: float = 7.0
	const R2: float = RADIUS * RADIUS
	for n in sim.fish:
		if not (n is Fish) or not is_instance_valid(n) or n == eater:
			continue
		var d2: float = n.position.distance_squared_to(pos)
		if d2 > R2:
			continue
		var prox: float = 1.0 - sqrt(d2) / RADIUS
		n.arousal = clampf(float(n.arousal) + strength * prox * 0.42, 0.0, 1.0)
		n.curiosity_drive = clampf(n.curiosity_drive + strength * prox * 0.16, 0.0, 1.0)
		if n.hunger > 0.32:
			n.current_mode = Fish.Mode.FORAGE
		FishMind.nudge_arousal(n, strength * prox * 0.22)


static func tick_feed_contagion(f: Fish, neighbors: Array, dt: float) -> void:
	if not enabled() or neighbors.is_empty():
		return
	for n in neighbors:
		if not (n is Fish):
			continue
		var o: Fish = n
		if o.current_mode == Fish.Mode.FORAGE and o.hunger < 0.5:
			f.arousal = clampf(float(f.arousal) + dt * 0.18, 0.0, 1.0)
			f.curiosity_drive = clampf(f.curiosity_drive + dt * 0.08, 0.0, 1.0)
			break


static func markov_blanket_stress_scale(f) -> float:
	if not enabled() or f.stress < 0.85:
		return 1.0
	return clampf(lerpf(0.58, 0.32, (f.stress - 0.85) / 0.15), 0.28, 0.58)


# Per-label gate — body/interoception stays; world/keeper/social percepts narrow.
static func markov_blanket_percept_scale(f, label: String) -> float:
	if not enabled() or f.stress < 0.85:
		return 1.0
	if label in ["threat", "vibration", "gills", "gut", "interoception", "body", "pain"]:
		return 1.0
	return markov_blanket_stress_scale(f)


static func counterfactual_ddm_nudge(f: Fish) -> float:
	if not enabled() or f.stress < 0.4:
		return 0.0
	var cf: String = FishGenerativeSelf.protention(f)
	if cf.contains("cover") or cf.contains("stay"):
		return 0.08
	if cf.contains("open") or cf.contains("ahead"):
		return -0.06
	return 0.0


static func on_goal_lost(f: Fish, reason: String) -> void:
	MindDaring.on_goal_lost(f, reason)
	if f.get("_longing_linger_pos") == null:
		f._longing_linger_pos = f.position
	else:
		f._longing_linger_pos = f.position


static func tick_rank_boldness_drift(f: Fish, dt: float) -> void:
	if not f.personality.has("boldness"):
		return
	var rank: float = f.rank_within_species
	var target: float = clampf(0.35 + rank * 0.45, 0.05, 1.0)
	var cur: float = float(f.personality["boldness"])
	f.personality["boldness"] = lerpf(cur, target, dt * 0.0008)


static func tick_mourning_stance(f: Fish, sim: Node, dt: float) -> void:
	if sim == null or not sim.has_method("mourning_intensity_for"):
		return
	var mi: float = sim.mourning_intensity_for(f.species, f.position)
	if mi > 0.15 and str(f._life_stance) != "wary":
		f._stance_drift_t = float(f.get("_stance_drift_t") if f.get("_stance_drift_t") != null else 0.0) + dt * mi
