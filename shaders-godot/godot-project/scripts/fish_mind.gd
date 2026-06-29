extends RefCounted

# Sentient-fish cognition layer (SENTIENT_FISH_IDEAS.md).
# fish.gd owns state; this module holds perception, affect, deliberation, learning.

const CreatureNaming = preload("res://scripts/creature_naming.gd")
const MindLexicon = preload("res://scripts/mind_lexicon.gd")
const MindWorldModel = preload("res://scripts/mind_world_model.gd")
const CognitiveSchema = preload("res://scripts/cognitive_schema.gd")

static var _convo_script: GDScript = null


static func _mind_conversation() -> GDScript:
	if _convo_script == null:
		_convo_script = load("res://scripts/mind_conversation.gd") as GDScript
	return _convo_script

const VIEW_DOT_THRESHOLD: float = -0.4   # ~115° forward cone (matches boids)
const DELIB_MARGIN: float = 0.12
const COMMIT_DWELL: float = 0.35
const COMMIT_HYSTERESIS: float = 0.08
# Drift-diffusion (#31 Vol II): evidence integrates with noise to a threshold.
const DDM_DRIFT: float = 1.35
const DDM_NOISE: float = 0.22
const DDM_THRESHOLD_BASE: float = 1.05

const FOOD_SUB_KEYS: Array = ["flake", "pellet", "worm", "wafer"]
const FishMindScience = preload("res://scripts/fish_mind_science.gd")
const FishBinding = preload("res://scripts/fish_binding.gd")
const SALIENT_MAX: int = 12
const VOICED_FAMILIARITY: float = 0.62
const TD_ALPHA: float = 0.12
const TD_GAMMA: float = 0.88
const MIND_SCHEMA_VERSION: int = 3
const SimRngScript = preload("res://scripts/sim_rng.gd")
const EpisodicMemory = preload("res://scripts/episodic_memory.gd")


# ---- Perception (#1) ----

static func in_vision_cone(f: Fish, target_pos: Vector3) -> bool:
	var to_t: Vector3 = target_pos - f.position
	if to_t.length_squared() < 1e-4:
		return true
	return f.heading.dot(to_t.normalized()) >= VIEW_DOT_THRESHOLD


static func perceives_pos(f: Fish, target_pos: Vector3, max_dist: float, sim: Node = null) -> bool:
	var scale: float = 1.0
	if sim != null and sim.has_method("daylight"):
		scale = lerpf(0.45, 1.0, clampf(float(sim.daylight()) / 0.35, 0.0, 1.0))
	var eff_dist: float = max_dist * scale
	var to_t: Vector3 = target_pos - f.position
	if to_t.length_squared() > eff_dist * eff_dist:
		return false
	var thresh: float = VIEW_DOT_THRESHOLD
	if sim != null and sim.has_method("daylight") and float(sim.daylight()) < 0.28:
		thresh = -0.15
	var to_n: Vector3 = to_t.normalized() if to_t.length_squared() > 1e-4 else Vector3.FORWARD
	return f.heading.dot(to_n) >= thresh


# ---- Affect (#26, #27, #32) ----

static func tick_affect(f: Fish, dt: float) -> void:
	var arousal_target: float = f.stress * 0.55 + f.spooked * 0.45 + f.hunger * 0.25
	arousal_target += clampf(f.mood, 0.0, 1.0) * 0.15
	if f.burst_remaining > 0.0 or f._startle_remaining > 0.0:
		arousal_target += 0.35
	if f.current_mode == Fish.Mode.COURT or f.current_mode == Fish.Mode.SPAWN:
		arousal_target += 0.3
	if f._asleep:
		arousal_target *= 0.2
	else:
		arousal_target += clampf(f.speed * 0.035, 0.0, 0.2)
	f.arousal = lerpf(f.arousal, clampf(arousal_target, 0.0, 1.0), clampf(dt * 0.5, 0.0, 1.0))
	if f.spooked > 0.35:
		f.vigilance = clampf(f.vigilance + dt * 0.8, 0.0, 1.0)
	else:
		f.vigilance = maxf(0.0, f.vigilance - dt * 0.25)
	f._contentment = clampf((f.mood + 1.0) * 0.5 * (1.0 - f.arousal) * (1.0 - f.stress), 0.0, 1.0)


static func emotional_state(f: Fish) -> String:
	var v: float = f.mood
	var a: float = f.arousal
	if f._asleep:
		if f._dreaming:
			return "dreaming"
		return "cozy"
	if f.vigilance > 0.55:
		return "anxious"
	if f._contentment > 0.65 and a < 0.35:
		return "content"
	if a > 0.65 and v > 0.2:
		return "excited"
	if a > 0.55 and v < 0.0:
		return "anxious"
	if f.curiosity_drive > 0.55 and a > 0.4:
		return "playful"
	if f.curiosity_drive > 0.65 and a < 0.35:
		return "bored"
	if v < -0.35 and a < 0.4:
		return "sulking"
	if v > 0.15 and a < 0.45:
		return "content"
	return "calm"


static func animation_modifiers(f: Fish) -> Dictionary:
	var v: float = f.mood
	var a: float = f.arousal
	var content: float = clampf(v, 0.0, 1.0)
	var distress: float = clampf(-v, 0.0, 1.0)
	var out: Dictionary = {
		"wag_freq": a * 0.22 - (1.0 - a) * content * 0.10,
		"pec_spread": content * 0.10 + a * 0.12 - distress * 0.06,
		"fin_amp": a * 0.08 - distress * 0.05,
		"breath_calm": (1.0 - a) * content * 0.12,
		"color_flare": a * 0.08,
		"color_pallor": distress * (1.0 - a) * 0.08,
	}
	var st: String = emotional_state(f)
	match st:
		"playful":
			out["wag_freq"] = float(out["wag_freq"]) + 0.08
		"bored":
			out["wag_freq"] = float(out["wag_freq"]) - 0.12
			out["fin_amp"] = float(out["fin_amp"]) - 0.06
		"cozy":
			out["breath_calm"] = float(out["breath_calm"]) + 0.08
			out["wag_freq"] = float(out["wag_freq"]) - 0.06
	var indec: Dictionary = indecision_modifiers(f)
	for k in indec:
		out[k] = indec[k]
	return out


static func nudge_arousal(f: Fish, amount: float) -> void:
	f.arousal = clampf(f.arousal + amount, 0.0, 1.0)


# ---- Deliberation (#10–12) ----

static func personality_commit_speed(f: Fish) -> float:
	return lerpf(0.55, 1.45, f._trait("boldness"))


static func ddm_threshold(f: Fish) -> float:
	# Scared fish decide faster (lower threshold) — Vol II #32.
	# Low self-model confidence → higher threshold (hesitate) — META #6.
	var fear: float = clampf(f.spooked * 0.55 + f.stress * 0.45 + f.vigilance * 0.35, 0.0, 1.0)
	var thr: float = lerpf(DDM_THRESHOLD_BASE, DDM_THRESHOLD_BASE * 0.55, fear)
	var conf: float = 1.0
	if f._mind_self_model is Dictionary and not f._mind_self_model.is_empty():
		conf = float(f._mind_self_model.get("confidence", 1.0))
	return lerpf(thr, thr * 1.38, clampf(1.0 - conf, 0.0, 0.9))


static func update_conflict(f: Fish, approach: float, avoid: float,
		toward_pos: Vector3, away_from_pos: Vector3) -> void:
	f._delib_approach_pos = toward_pos
	f._delib_avoid_pos = away_from_pos
	f._delib_approach_s = approach
	f._delib_avoid_s = avoid
	var tied: bool = absf(approach - avoid) < DELIB_MARGIN \
		and minf(approach, avoid) > 0.32
	var was_active: bool = f._delib_active
	f._delib_active = tied
	if tied and not was_active:
		f._delib_ev_approach = 0.0
		f._delib_ev_avoid = 0.0
		f._delib_decided = false
		f._delib_phase = 0.0
	if not tied:
		f._delib_phase = 0.0
		f._delib_decided = false


static func tick_ddm(f: Fish, dt: float, approach: float, avoid: float, sim: Node = null) -> void:
	if not f._delib_active or f._delib_decided:
		return
	var thr: float = ddm_threshold(f)
	var cog: RandomNumberGenerator = MindRng.for_fish(f)
	var noise_a: float = (cog.randf() - 0.5) * DDM_NOISE
	var noise_b: float = (cog.randf() - 0.5) * DDM_NOISE
	f._delib_ev_approach += (approach * DDM_DRIFT + noise_a) * dt
	f._delib_ev_avoid += (avoid * DDM_DRIFT + noise_b) * dt
	f._delib_phase += dt
	if f._delib_phase > 1.5 and not f._delib_decided:
		var rich: bool = f.is_guardian or f.fish_name != "" or f.familiarity > 0.35
		if rich and deliberation_tie_break(f, sim) != 0:
			return
	if f._delib_ev_approach >= thr:
		f._delib_decided = true
		f._delib_choice = 1
	elif f._delib_ev_avoid >= thr:
		f._delib_decided = true
		f._delib_choice = 2


static func deliberation_tie_break(f: Fish, _sim: Node) -> int:
	if not f._delib_active or f._delib_decided:
		return 0
	var total: float = maxf(f._delib_ev_approach + f._delib_ev_avoid, 0.01)
	var conflict: float = 1.0 - absf(f._delib_ev_approach - f._delib_ev_avoid) / total
	if conflict < 0.72:
		return 0
	var ctx: Dictionary = {
		"feel": emotional_state(f),
		"delib_conflict": conflict,
	}
	var op: Dictionary = CognitiveSchema.template_op(ctx)
	op["choice"] = "approach" if f._delib_ev_approach >= f._delib_ev_avoid else "avoid"
	f._last_cog_op = op.duplicate(true)
	f._last_cog_validation = "delib_tie"
	if str(op.get("choice", "")) == "approach":
		f._delib_decided = true
		f._delib_choice = 1
		return 1
	f._delib_decided = true
	f._delib_choice = 2
	return 2


static func stream_tense_tag(f: Fish) -> String:
	if f._asleep and f._dreaming:
		return "imagining"
	if f.get("_episodic_retrieval_hint") is Dictionary:
		return "remembering"
	return "now"


static func autobiography_dict(f: Fish) -> Dictionary:
	return {
		"origin": "hatched here" if f.generation <= 1 else "lineage %d" % f.generation,
		"defining": str(f._self_summary).substr(0, 80) if f.get("_self_summary") else "",
		"arc": str(f.get("_life_stance") if f.get("_life_stance") != null else ""),
		"stance": str(f.get("_life_stance") if f.get("_life_stance") != null else "steadfast"),
	}


static func deliberation_steer(f: Fish, _dt: float, effective_max: float) -> Vector3:
	if not f._delib_active:
		return Vector3.ZERO
	var to_approach: Vector3 = f._delib_approach_pos - f.position
	var to_retreat: Vector3 = f.position - f._delib_avoid_pos
	if to_approach.length_squared() < 0.04:
		to_approach = f.heading
	if to_retreat.length_squared() < 0.04:
		to_retreat = -f.heading
	to_approach.y *= 0.35
	to_retreat.y *= 0.35
	if f._delib_decided:
		var chosen: Vector3 = to_approach if f._delib_choice == 1 else to_retreat
		if chosen.length_squared() < 1e-4:
			return Vector3.ZERO
		return chosen.normalized() * effective_max * 0.65
	# Undecided: lean toward leading evidence with visible hesitation.
	var lead: float = f._delib_ev_approach - f._delib_ev_avoid
	var lean: Vector3 = to_approach.normalized() * maxf(lead, 0.0) \
		+ to_retreat.normalized() * maxf(-lead, 0.0)
	if lean.length_squared() < 1e-4:
		lean = f.heading * sin(f._delib_phase * 3.0)
	return lean.normalized() * effective_max * 0.38


static func tick_commitment(f: Fish, dt: float, proposed_mode: int) -> bool:
	var dwell_need: float = COMMIT_DWELL / personality_commit_speed(f)
	if f.stress > 0.65 or f.spooked > 0.45:
		dwell_need *= 0.42
	if proposed_mode == f._commit_mode:
		f._commit_dwell += dt
		return f._commit_dwell >= dwell_need
	var beat: float = COMMIT_HYSTERESIS / personality_commit_speed(f)
	if f._commit_mode >= 0 and f._commit_dwell < beat:
		return false
	f._commit_mode = proposed_mode
	f._commit_dwell = dt
	return false


static func indecision_modifiers(f: Fish) -> Dictionary:
	if not f._delib_active or f._delib_decided:
		return {}
	var total: float = maxf(f._delib_ev_approach + f._delib_ev_avoid, 0.01)
	var conflict: float = 1.0 - absf(f._delib_ev_approach - f._delib_ev_avoid) / total
	var swing: float = sin(f._delib_phase * (1.5 + conflict))
	return {
		"gaze_split": swing * (0.28 + conflict * 0.22),
		"speed_mult": lerpf(0.62, 0.42, conflict),
		"fin_twitch": conflict * 0.16,
		"wag_freq": conflict * 0.07,
	}


static func aim_before_burst(f: Fish) -> void:
	if f._aim_remaining <= 0.0:
		f._aim_remaining = lerpf(0.12, 0.22, 1.0 - f._trait("boldness"))


static func maybe_double_take(f: Fish, curiosity: float) -> void:
	if f._double_take_remaining > 0.0:
		return
	if curiosity > 0.45 and MindRng.for_fish(f).randf() < 0.22:
		var cog: RandomNumberGenerator = MindRng.for_fish(f)
		f._double_take_remaining = cog.randf_range(0.35, 0.7)


# ---- Memory & learning (#14, #18, #22–25) ----

static func memory_decay_mult(kind: String) -> float:
	match kind:
		"startled", "bullied":
			return 0.55
		"fed", "saw_player":
			return 1.0
		"bred":
			return 0.35
		_:
			return 1.0


static func habituation_decay_rate(f: Fish) -> float:
	# High curiosity → novelty returns slower (stay interested longer).
	return lerpf(1.4, 0.55, f._trait("curiosity"))


static func tick_personality_conditioning(f: Fish, dt: float) -> void:
	if f.personality.is_empty():
		return
	if f.familiarity > 0.35 and f._cached_glance_strength > 0.2:
		f.personality["boldness"] = clampf(
			float(f.personality.get("boldness", 0.5)) + dt * 0.004, 0.05, 1.0)
		f.personality["sociability"] = clampf(
			float(f.personality.get("sociability", 0.5)) + dt * 0.003, 0.05, 1.0)
	if f.spooked > 0.45 or f.stress > 0.75:
		f.personality["boldness"] = clampf(
			float(f.personality.get("boldness", 0.5)) - dt * 0.006, 0.05, 1.0)
		f.personality["calm"] = clampf(
			float(f.personality.get("calm", 0.5)) - dt * 0.004, 0.05, 1.0)
	if f.curiosity_drive > 0.55 and f.stress < 0.35:
		f.personality["curiosity"] = clampf(
			float(f.personality.get("curiosity", 0.5)) + dt * 0.002, 0.05, 1.0)


# Needs hierarchy (#31 Vol I): safety > food > social > rest > play > explore.
static func dominant_need(f: Fish) -> String:
	if f.spooked > 0.4 or f.stress > 0.7 or f._startle_remaining > 0.0:
		return "safety"
	if f.hunger > 0.55:
		return "food"
	if f.partner != null or f.brooding_remaining > 0.0:
		return "social"
	if f._asleep:
		return "rest"
	if f.curiosity_drive > 0.5 and f.stress < 0.45:
		return "explore"
	if f.curiosity_drive > 0.35:
		return "play"
	return "calm"


static func dominant_wants(f: Fish) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	match dominant_need(f):
		"safety":
			out.append("stay safe")
		"food":
			out.append("eat")
		"social":
			out.append("be near others")
		"rest":
			out.append("rest")
		"explore":
			out.append("investigate")
		"play":
			out.append("play")
		_:
			out.append("drift")
	if f.hunger > 0.45 and dominant_need(f) != "food":
		out.append("snack soon")
	return out


static func need_blocks_action(f: Fish, action: String) -> bool:
	var need: String = dominant_need(f)
	match action:
		"play", "explore":
			return need in ["safety", "food"]
		"social":
			return need == "safety"
	return false


static func tick_mood_disposition(f: Fish, dt: float, satisfaction: float) -> void:
	# Leaky reward integral — Vol II #26 / Vol I #35.
	var rpe: float = satisfaction - f.mood_disposition
	f.mood_disposition = clampf(
		f.mood_disposition + rpe * clampf(dt * 0.08, 0.0, 0.12), -0.35, 0.45)


static func mood_baseline(f: Fish) -> float:
	return lerpf(-0.1, 0.4, (f._trait("calm") + f._trait("boldness")) * 0.5) \
		+ f.mood_disposition


static func tick_prediction_surprise(f: Fish, sim: Node, dt: float) -> void:
	f.surprise = maxf(0.0, f.surprise - dt * 0.35)
	var predicted_feed: bool = false
	if sim != null and sim.has_method("feed_anticipation_active"):
		predicted_feed = sim.feed_anticipation_active()
	if predicted_feed and not f._predicted_feed_last:
		f._predicted_feed_last = true
	elif f._predicted_feed_last and not predicted_feed and f.hunger > 0.35:
		f.surprise = clampf(f.surprise + 0.45, 0.0, 1.0)
		f._predicted_feed_last = false
	if f._reaction_remaining > 0.0:
		f.surprise = clampf(f.surprise + dt * 0.8, 0.0, 1.0)


static func tick_attention(f: Fish, _sim: Node) -> void:
	var best: String = ""
	var best_s: float = 0.0
	if f.spooked > 0.35 or f._startle_remaining > 0.0:
		best = "threat"
		best_s = f.spooked + 0.4
	elif f.hunger > 0.5:
		best = "food"
		best_s = f.hunger
	elif f._cached_glance_strength > 0.25:
		best = "player"
		best_s = f._cached_glance_strength
	elif f.partner != null and is_instance_valid(f.partner):
		best = "mate"
		best_s = 0.55
	elif f.curiosity_drive > 0.45:
		best = "novelty"
		best_s = f.curiosity_drive * 0.7
	f.attention_focus = best if best_s > 0.28 else ""


static func update_intention(f: Fish) -> void:
	if f._delib_active and not f._delib_decided:
		f.current_intention = "weighing options"
		return
	if f._aim_remaining > 0.0:
		f.current_intention = "about to dart"
		return
	match f.current_mode:
		Fish.Mode.FLEE:
			f.current_intention = "fleeing"
		Fish.Mode.FORAGE:
			f.current_intention = "foraging"
		Fish.Mode.COURT:
			f.current_intention = "courting"
		Fish.Mode.SPAWN:
			f.current_intention = "spawning"
		_:
			match dominant_need(f):
				"food":
					f.current_intention = "seeking food"
				"safety":
					f.current_intention = "staying wary"
				"rest":
					f.current_intention = "resting"
				"explore":
					f.current_intention = "exploring"
				_:
					f.current_intention = "cruising"


static func seed_quirks(f: Fish) -> void:
	if not f.quirks.is_empty():
		return
	var h: int = 0
	for i in String(f.id).length():
		h = (h * 31 + String(f.id).unicode_at(i)) & 0x7fffffff
	var pool: Array = [
		"rests in the left corner", "avoids the filter current",
		"greets at the same rock", "patrols the surface at dusk",
		"shies from bright light", "naps behind plants",
	]
	f.quirks.append(pool[h % pool.size()])
	f.quirks.append(pool[(h * 7 + 3) % pool.size()])
	if f.quirks[0] == f.quirks[1]:
		f.quirks[1] = pool[(h * 13 + 1) % pool.size()]


static func record_salient(f: Fish, kind: String, text: String, intensity: float = 0.5,
		pos: Vector3 = Vector3.INF) -> void:
	var weight: float = clampf(intensity, 0.1, 1.0)
	if f.surprise > 0.35:
		weight = clampf(weight + f.surprise * 0.25, 0.0, 1.0)
	var entry: Dictionary = {
		"kind": kind,
		"text": text,
		"weight": weight,
		"age": 0.0,
	}
	if not f.salient_memories.is_empty():
		var prev: Dictionary = f.salient_memories[-1]
		if String(prev.get("text", "")) == text and String(prev.get("kind", "")) == kind:
			return
	if pos.is_finite() and not is_inf(pos.x):
		entry["pos"] = pos
	f.salient_memories.append(entry)
	while f.salient_memories.size() > SALIENT_MAX:
		f.salient_memories.pop_front()


static func tick_salient_decay(f: Fish, dt: float) -> void:
	var keep: Array = []
	for e in f.salient_memories:
		var w: float = float(e.get("weight", 0.5))
		var mult: float = memory_decay_mult(String(e.get("kind", "")))
		w = maxf(0.0, w - dt * 0.004 * mult)
		if w > 0.08:
			e["weight"] = w
			e["age"] = float(e.get("age", 0.0)) + dt
			keep.append(e)
	f.salient_memories = keep


static func top_salient_memories(f: Fish, n: int = 3) -> PackedStringArray:
	var sorted: Array = f.salient_memories.duplicate()
	sorted.sort_custom(func(a, b): return float(a.get("weight", 0.0)) > float(b.get("weight", 0.0)))
	var out: PackedStringArray = PackedStringArray()
	for i in range(mini(n, sorted.size())):
		var txt: String = String(sorted[i].get("text", ""))
		var w: float = float(sorted[i].get("weight", 0.5))
		if w < 0.25:
			out.append("a dim memory of %s" % txt)
		else:
			out.append(txt)
	return out


static func salient_avoid_steer(f: Fish, at_pos: Vector3) -> Vector3:
	var push: Vector3 = Vector3.ZERO
	for e in f.salient_memories:
		if String(e.get("kind", "")) != "startled":
			continue
		if float(e.get("weight", 0.0)) < 0.42:
			continue
		var p: Variant = e.get("pos", null)
		if not (p is Vector3):
			continue
		var sp: Vector3 = p as Vector3
		var d2: float = at_pos.distance_squared_to(sp)
		if d2 > 6.25 or d2 < 0.04:
			continue
		var away: Vector3 = at_pos - sp
		push += away.normalized() * (1.0 - sqrt(d2) / 2.5) * float(e.get("weight", 0.5))
	if push.length_squared() < 1e-4:
		return Vector3.ZERO
	return push.normalized()


static func bond_seek_steer(f: Fish, neighbors: Array, dist2: Array, count: int) -> Vector3:
	var best: Vector3 = Vector3.ZERO
	var best_w: float = 0.0
	for i in count:
		var nf: Fish = neighbors[i]
		if nf == f or nf.id == "":
			continue
		var oid: String = String(nf.id)
		var w: float = 0.0
		if oid == f._mate_id:
			w = 1.0
		elif f.bonds.has(oid):
			w = float(f.bonds[oid])
		if w < 0.28:
			continue
		var d2: float = dist2[i]
		if d2 < 1.0:
			continue
		if d2 > 36.0:
			w *= 0.55
		var dir: Vector3 = nf.position - f.position
		if dir.length_squared() < 1e-4:
			continue
		var score: float = w * clampf(1.0 - sqrt(d2) / 6.0, 0.1, 1.0)
		if score > best_w:
			best_w = score
			best = dir.normalized()
	return best


static func dominance_hint(f: Fish) -> String:
	if f.lead_score > 0.62:
		return "leads the shoal"
	if f.lead_score < 0.28 and f.rank_within_species > 0.65:
		return "defers to others"
	return ""


static func grudge_voice_hints(f: Fish, sim: Node) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if f.grudges.is_empty() or sim == null or sim.get("fish") == null:
		return out
	for oid in f.grudges.keys():
		if float(f.grudges[oid]) <= 0.0:
			continue
		for ff in sim.fish:
			if is_instance_valid(ff) and String(ff.id) == String(oid):
				var nm: String = ff.fish_name if ff.fish_name != "" else ff.species
				out.append("keeps distance from %s" % nm)
				break
	return out


static func society_snapshot(sim: Node) -> Dictionary:
	var leaders: PackedStringArray = PackedStringArray()
	var bonds_n: int = 0
	if sim == null or sim.get("fish") == null:
		return {"leaders": leaders, "bond_pairs": 0}
	for ff in sim.fish:
		if not is_instance_valid(ff):
			continue
		if float(ff.lead_score) > 0.58:
			var nm: String = ff.fish_name if ff.fish_name != "" else ff.species.capitalize()
			if nm != "" and not leaders.has(nm):
				leaders.append(nm)
		for oid in ff.bonds:
			if float(ff.bonds[oid]) > 0.35:
				bonds_n += 1
	return {"leaders": leaders, "bond_pairs": bonds_n >> 1}


static func salient_relevant_for_situation(f: Fish, situation: String, n: int = 2) -> PackedStringArray:
	var tag: String = situation.strip_edges().to_lower()
	var hits: Array = []
	for e in f.salient_memories:
		var kind: String = String(e.get("kind", ""))
		var w: float = float(e.get("weight", 0.0))
		if w < 0.2:
			continue
		if tag == "" or kind == tag or (tag == "inspect" and w > 0.4):
			hits.append(e)
	hits.sort_custom(func(a, b): return float(a.get("weight", 0.0)) > float(b.get("weight", 0.0)))
	var out: PackedStringArray = PackedStringArray()
	for i in range(mini(n, hits.size())):
		out.append(String(hits[i].get("text", "")))
	if out.is_empty():
		return top_salient_memories(f, n)
	return out


static func td_update_heatmap(f: Fish, cell_idx: int, reward: float) -> void:
	if cell_idx < 0 or cell_idx >= f.feed_heatmap.size():
		return
	var old: float = float(f.feed_heatmap[cell_idx])
	var best_next: float = 0.0
	for ix in range(Fish.FEED_HEATMAP_SIZE):
		for iy in range(Fish.FEED_HEATMAP_SIZE):
			for iz in range(Fish.FEED_HEATMAP_SIZE):
				var j: int = ix + iy * Fish.FEED_HEATMAP_SIZE \
					+ iz * Fish.FEED_HEATMAP_SIZE * Fish.FEED_HEATMAP_SIZE
				if j != cell_idx:
					best_next = maxf(best_next, float(f.feed_heatmap[j]))
	var target: float = reward + TD_GAMMA * best_next
	# Eligibility trace (#28): credit assignment across recent path
	var trace: float = float(f.get("_td_eligibility_peak") if f.get("_td_eligibility_peak") != null else 0.0)
	trace = trace * 0.88 + 1.0
	f._td_eligibility_peak = trace
	var delta: float = target - old
	f.feed_heatmap[cell_idx] = clampf(old + TD_ALPHA * delta * trace, 0.0, 8.0)


static func heatmap_cell_at(f: Fish, pos: Vector3) -> int:
	var w: Node = f._world_node()
	if w == null:
		return -1
	var hw: float = float(w.get("TANK_HALF_W") if w.get("TANK_HALF_W") != null else 8.0)
	var hd: float = float(w.get("TANK_HALF_D") if w.get("TANK_HALF_D") != null else 4.0)
	var hh: float = float(w.get("TANK_HEIGHT") if w.get("TANK_HEIGHT") != null else 7.0)
	var sz: int = Fish.FEED_HEATMAP_SIZE
	var ix: int = clampi(int((pos.x + hw) / (hw * 2.0) * sz), 0, sz - 1)
	var iy: int = clampi(int(pos.y / hh * sz), 0, sz - 1)
	var iz: int = clampi(int((pos.z + hd) / (hd * 2.0) * sz), 0, sz - 1)
	return ix + iy * sz + iz * sz * sz


static func tick_bond_arcs(f: Fish, dt: float) -> void:
	for oid in f.bonds.keys():
		var aff: float = float(f.bonds[oid])
		f.bonds[oid] = clampf(aff - dt * 0.002, -1.0, 1.0)
		if aff > 0.2 and f.familiarity > 0.3:
			f.bonds[oid] = clampf(float(f.bonds[oid]) + dt * 0.0015, -1.0, 1.0)
	for gid in f.grudges.keys():
		var g: float = float(f.grudges[gid])
		f.grudges[gid] = maxf(0.0, g - dt * 0.004)


static func apply_arousal_contagion(f: Fish, neighbor_arousal: float, dt: float) -> void:
	if neighbor_arousal < 0.35:
		return
	f.arousal = clampf(f.arousal + neighbor_arousal * dt * 0.08 * f.schooling_strength, 0.0, 1.0)


static func inspect_mind_summary(f: Fish) -> Dictionary:
	return {
		"feel": emotional_state(f),
		"wants": dominant_wants(f),
		"intention": str(f.current_intention),
		"attention": str(f.attention_focus),
		"memories": top_salient_memories(f, 2),
		"surprise": snappedf(f.surprise, 0.01),
		"voiced": f.is_voiced_individual(),
	}


static func record_food_preference(f: Fish, subtype: int, satisfaction: float) -> void:
	var key: String = FOOD_SUB_KEYS[clampi(subtype, 0, FOOD_SUB_KEYS.size() - 1)]
	var prev: float = float(f.food_preferences.get(key, 0.5))
	f.food_preferences[key] = clampf(prev + satisfaction * 0.08, 0.0, 1.0)


static func food_preference_mult(f: Fish, subtype: int) -> float:
	var key: String = FOOD_SUB_KEYS[clampi(subtype, 0, FOOD_SUB_KEYS.size() - 1)]
	var pref: float = float(f.food_preferences.get(key, 0.5))
	return lerpf(1.15, 0.82, pref)


static func refresh_patrol_from_heatmap(f: Fish) -> void:
	if f.feed_heatmap.is_empty() or f.maturity != Fish.MATURITY_ADULT:
		return
	var best: Array = []
	var w: Node = f._world_node()
	if w == null:
		return
	var hw: float = float(w.get("TANK_HALF_W") if w.get("TANK_HALF_W") != null else 8.0)
	var hd: float = float(w.get("TANK_HALF_D") if w.get("TANK_HALF_D") != null else 4.0)
	var hh: float = float(w.get("TANK_HEIGHT") if w.get("TANK_HEIGHT") != null else 7.0)
	var sz: int = Fish.FEED_HEATMAP_SIZE
	for ix in range(sz):
		for iy in range(sz):
			for iz in range(sz):
				var idx: int = ix + iy * sz + iz * sz * sz
				var heat: float = float(f.feed_heatmap[idx])
				if heat < 0.18:
					continue
				var pos: Vector3 = Vector3(
					(ix + 0.5) / float(sz) * hw * 2.0 - hw,
					(iy + 0.5) / float(sz) * hh,
					(iz + 0.5) / float(sz) * hd * 2.0 - hd)
				if w.has_method("clamp_xyz_in_tank"):
					pos = w.clamp_xyz_in_tank(pos, 0.5, f._body_tank_margin())
				best.append({"heat": heat, "pos": pos})
	best.sort_custom(func(a, b): return float(a["heat"]) > float(b["heat"]))
	f.patrol_anchors.clear()
	for i in range(mini(3, best.size())):
		f.patrol_anchors.append(best[i]["pos"])


static func tick_home_confidence(f: Fish, dt: float) -> void:
	if f.visited_regions.is_empty():
		return
	var visited: int = 0
	for v in f.visited_regions:
		if int(v) > 0:
			visited += 1
	var explore_frac: float = float(visited) / float(f.visited_regions.size())
	f.home_confidence = lerpf(f.home_confidence, clampf(explore_frac * 1.2, 0.0, 1.0),
		clampf(dt * 0.08, 0.0, 1.0))


static func mind_to_dict(f: Fish) -> Dictionary:
	var ms = MindState.for_fish(f, true)
	ms.sync_from_fish(f)
	var d: Dictionary = ms.to_dict()
	d.merge({
		"schema_version": MIND_SCHEMA_VERSION,
		"food_preferences": f.food_preferences.duplicate(),
		"home_confidence": f.home_confidence,
		"salient_memories": f.salient_memories.duplicate(true),
		"fish_journal": f.fish_journal.duplicate(true),
		"mate_grief": f._mate_grief,
		"hypotheses": f._hypotheses.duplicate(true),
		"semantic_memory": f.semantic_memory.duplicate(true),
		"voiced_wake": f._voiced_wake,
		"working_memory": f.memory.duplicate(true),
		"quirks": f.quirks.duplicate(),
		"self_summary": str(f.get("_self_summary") if f.get("_self_summary") != null else ""),
		"episodic_store": EpisodicMemory.store_to_dict(f),
		"writeback_log": f._mind_writeback_log.duplicate(true) if f.get("_mind_writeback_log") is Array else [],
		"learned_words": MindLexicon.to_dict(f),
		"word_milestones": f._word_milestones.duplicate(true) if f.get("_word_milestones") is Dictionary else {},
		"world_model": MindWorldModel.to_dict(f),
		"prediction_error": float(f.get("_prediction_error") if f.get("_prediction_error") != null else 0.0),
		"life_stance": str(f.get("_life_stance") if f.get("_life_stance") != null else ""),
		"stance_drift_t": float(f.get("_stance_drift_t") if f.get("_stance_drift_t") != null else 0.0),
		"active_plan": f._active_plan.duplicate(true) if f.get("_active_plan") is Dictionary else {},
		"mend_trust": float(f.get("_mend_trust") if f.get("_mend_trust") != null else 0.0),
		"mend_pending": bool(f.get("_mend_pending")),
		"longing_residue": float(f.get("_longing_residue") if f.get("_longing_residue") != null else 0.0),
		"curiosity_about_keeper": float(f.get("_curiosity_about_keeper") if f.get("_curiosity_about_keeper") != null else 0.0),
		"foraging_commitment": f.foraging_commitment,
		"autobiography": autobiography_dict(f),
		"conversation": _mind_conversation().call("to_dict", f),
		"felt_self": FishBinding.to_dict(f),
	})
	d["schema_version"] = MIND_SCHEMA_VERSION
	return d


static func apply_mind_dict(f: Fish, d: Dictionary) -> void:
	var ms = MindState.new()
	ms.from_dict(d)
	ms.apply_to_fish(f)
	var fp: Variant = d.get("food_preferences", null)
	if fp is Dictionary:
		f.food_preferences = (fp as Dictionary).duplicate()
	f.home_confidence = float(d.get("home_confidence", f.home_confidence))
	var sm: Variant = d.get("salient_memories", null)
	if sm is Array:
		f.salient_memories = (sm as Array).duplicate(true)
	var q: Variant = d.get("quirks", null)
	if q is Array:
		f.quirks = (q as Array).duplicate()
	var wm: Variant = d.get("working_memory", null)
	if wm is Array:
		f.memory = (wm as Array).duplicate(true)
	var fj: Variant = d.get("fish_journal", null)
	if fj is Array:
		f.fish_journal = (fj as Array).duplicate(true)
	f._mate_grief = float(d.get("mate_grief", f._mate_grief))
	var hy: Variant = d.get("hypotheses", null)
	if hy is Dictionary:
		f._hypotheses = (hy as Dictionary).duplicate(true)
	var smem: Variant = d.get("semantic_memory", null)
	if smem is Array:
		f.semantic_memory = (smem as Array).duplicate()
	f._voiced_wake = bool(d.get("voiced_wake", f._voiced_wake))
	f._self_summary = str(d.get("self_summary", f._self_summary))
	EpisodicMemory.apply_store_dict(f, d.get("episodic_store", null))
	var wl: Variant = d.get("writeback_log", null)
	if wl is Array:
		f._mind_writeback_log = (wl as Array).duplicate(true)
	MindLexicon.from_dict(f, d.get("learned_words", null))
	var wms: Variant = d.get("word_milestones", null)
	if wms is Dictionary:
		f._word_milestones = (wms as Dictionary).duplicate(true)
	MindWorldModel.from_dict(f, d.get("world_model", null))
	f._prediction_error = float(d.get("prediction_error", f._prediction_error))
	f._life_stance = str(d.get("life_stance", f._life_stance))
	f._stance_drift_t = float(d.get("stance_drift_t", f._stance_drift_t))
	var ap: Variant = d.get("active_plan", null)
	if ap is Dictionary:
		f._active_plan = (ap as Dictionary).duplicate(true)
	f._mend_trust = float(d.get("mend_trust", f._mend_trust))
	f._mend_pending = bool(d.get("mend_pending", f._mend_pending))
	f._longing_residue = float(d.get("longing_residue", f._longing_residue))
	f._curiosity_about_keeper = float(d.get("curiosity_about_keeper", f._curiosity_about_keeper))
	f.foraging_commitment = float(d.get("foraging_commitment", f.foraging_commitment))
	_mind_conversation().call("from_dict", f, d.get("conversation", null))
	FishBinding.from_dict(f, d.get("felt_self", null))


static func offline_character_bio(f: Fish) -> String:
	var sp: String = f.species.capitalize() if f.species != "" else "fish"
	var ep: String = CreatureNaming.epithet_for_personality(
			f.personality, f.id if f.id != "" else f.fish_name)
	if ep != "":
		return "A %s %s — %s by nature." % [sp, ep, f.swim_pattern]
	if f.generation > 0:
		return "Generation %d %s, still finding its place." % [f.generation, sp]
	return "A %s learning the rhythms of this tank." % sp
