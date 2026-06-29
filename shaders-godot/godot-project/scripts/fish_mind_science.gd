extends RefCounted

# Extended procedural mind mechanics (SENTIENCE_DEEP_SCIENCE Vol II).
# Lite, deterministic, always inspectable — never a black box.

const FishMind = preload("res://scripts/fish_mind.gd")
const EpisodicMemory = preload("res://scripts/episodic_memory.gd")
const SimRngScript = preload("res://scripts/sim_rng.gd")


# Panksepp primary-process read (#21).
static func primary_process(f: Fish) -> String:
	if f._mate_grief > 0.35:
		return "PANIC/GRIEF"
	if f.spooked > 0.45 or f.vigilance > 0.55:
		return "FEAR"
	if f.grudges.size() > 0 and f.stress > 0.4:
		return "RAGE"
	if f.partner != null or f.brooding_remaining > 0.0:
		return "CARE"
	if f.current_mode == Fish.Mode.COURT:
		return "LUST"
	if f.curiosity_drive > 0.55 and f.stress < 0.4:
		return "PLAY" if f.maturity == Fish.MATURITY_FRY else "SEEKING"
	if f.hunger > 0.45:
		return "SEEKING"
	return "SEEKING"


static func tick_neuromodulators(f: Fish, dt: float, satisfaction: float,
		surprise: float) -> void:
	var rpe: float = satisfaction - f.mood_disposition
	f.dopamine = clampf(f.dopamine + rpe * dt * 0.35, 0.0, 1.0)
	f.dopamine = maxf(0.0, f.dopamine - dt * 0.06)
	f.serotonin = clampf(f.serotonin + satisfaction * dt * 0.08 - f.stress * dt * 0.05, 0.0, 1.0)
	f.noradrenaline = clampf(f.arousal * 0.7 + f.vigilance * 0.5, 0.0, 1.0)
	f.cortisol = clampf(f.cortisol + f.stress * dt * 0.04 - (1.0 - f.stress) * dt * 0.02, 0.0, 1.0)
	var plasticity: float = 1.0 + surprise * 0.6 + f.dopamine * 0.25
	f._learning_rate_mult = clampf(plasticity * (1.0 - f.cortisol * 0.35), 0.35, 1.8)


static func appraisal_emotion(f: Fish) -> String:
	var pe: float = f.surprise
	var ctrl: float = 1.0 - clampf(f.stress + f.spooked, 0.0, 1.0)
	var val: float = f.mood
	if pe > 0.5 and val > 0.1:
		return "delight"
	if pe > 0.5 and val < 0.0:
		return "dread"
	if pe > 0.35 and ctrl > 0.5:
		return "relief"
	if pe > 0.35 and ctrl < 0.35:
		return "frustration"
	return FishMind.emotional_state(f)


static func tick_boredom_flow(f: Fish, enrichment: float, dt: float) -> void:
	var barren: float = clampf(1.0 - enrichment, 0.0, 1.0)
	if barren > 0.55 and f.stress < 0.4 and f.hunger < 0.45:
		f.curiosity_drive = clampf(f.curiosity_drive + dt * barren * 0.04, 0.0, 1.0)
		f.mood = clampf(f.mood - dt * barren * 0.02, -1.0, 1.0)
	elif enrichment > 0.45 and f.curiosity_drive > 0.3:
		f.mood = clampf(f.mood + dt * 0.015, -1.0, 1.0)


static func tick_hypothesis(f: Fish, region_idx: int, outcome: String) -> void:
	if region_idx < 0:
		return
	var key: String = str(region_idx)
	if not f._hypotheses.has(key):
		f._hypotheses[key] = {"guess": "unknown", "trials": 0}
	var h: Dictionary = f._hypotheses[key]
	h["trials"] = int(h.get("trials", 0)) + 1
	if outcome in ["food", "threat", "nothing"]:
		h["guess"] = outcome
	f._hypotheses[key] = h


static func tick_theory_of_mind(f: Fish, neighbors: Array) -> void:
	f.inferred_states.clear()
	for n in neighbors:
		if not (n is Fish) or n == f:
			continue
		var other: Fish = n
		var oid: String = String(other.id)
		if oid == "":
			continue
		var label: String = "neutral"
		if f.grudges.has(oid):
			label = "threat"
		elif f.bonds.has(oid) and float(f.bonds[oid]) > 0.3:
			label = "friend"
		elif other.spooked > 0.45:
			label = "scared"
		elif other.lead_score > 0.55:
			label = "dominant"
		f.inferred_states[oid] = label
	# Keeper theory-of-mind (#35).
	var kp: Variant = f.get("_keeper_pending")
	if kp is Dictionary and not (kp as Dictionary).is_empty():
		var felt: String = str((kp as Dictionary).get("keeper_felt", "neutral"))
		if felt == "scold":
			f.inferred_states["keeper"] = "angry"
		elif felt in ["comfort", "greeting"]:
			f.inferred_states["keeper"] = "gentle"
		elif felt == "question":
			f.inferred_states["keeper"] = "curious"
		else:
			f.inferred_states["keeper"] = "present"


static func tick_mate_grief(f: Fish, dt: float, mate_alive: bool) -> void:
	if f._mate_id == "":
		f._mate_grief = maxf(0.0, f._mate_grief - dt * 0.05)
		return
	if not mate_alive and f._mate_grief < 1.0:
		var prev: float = f._mate_grief
		f._mate_grief = clampf(f._mate_grief + dt * 0.25, 0.0, 1.0)
		f.mood = clampf(f.mood - dt * 0.08, -1.0, 1.0)
		f.arousal = clampf(f.arousal + dt * 0.05, 0.0, 1.0)
		if prev < 0.35 and f._mate_grief >= 0.35:
			f._longing_residue = clampf(float(f.get("_longing_residue") if f.get("_longing_residue") != null else 0.0) + 0.35, 0.0, 1.0)
			FishMind.record_salient(f, "loss", "the bond is gone", 0.62, f.position)
	else:
		f._mate_grief = maxf(0.0, f._mate_grief - dt * 0.04)


static func tick_sleep_replay(f: Fish) -> void:
	if not f._asleep or f.salient_memories.is_empty():
		return
	var replayed: bool = false
	for e in f.salient_memories:
		var kind: String = String(e.get("kind", ""))
		if kind in ["fed", "food", "dream", "keeper", "startled", "loss"]:
			var cell: int = FishMind.heatmap_cell_at(f, f.position)
			if cell >= 0:
				var boost: float = 0.12 if kind != "startled" else 0.06
				FishMind.td_update_heatmap(f, cell, boost)
				replayed = true
			if f._dreaming and kind == "startled" and MindRng.for_fish(f).randf() < 0.08:
				f._sleep_twitch_t = 0.18
	if replayed and f._dreaming:
		f._replay_glow = maxf(float(f.get("_replay_glow") if f.get("_replay_glow") != null else 0.0), 0.35)
		if f._dream_wisp == "":
			for e in f.salient_memories:
				var t: String = String(e.get("text", ""))
				if t != "":
					f._dream_wisp = t.substr(0, mini(t.length(), 40))
					break


static func reconsolidate_memory(f: Fish, kind: String, safer: bool) -> void:
	for e in f.salient_memories:
		if String(e.get("kind", "")) != kind:
			continue
		var w: float = float(e.get("weight", 0.5))
		if safer:
			e["weight"] = clampf(w - 0.06, 0.0, 1.0)
		else:
			e["weight"] = maxf(0.0, w - 0.05)
	var store: Array = EpisodicMemory.ensure_store(f)
	for e in store:
		if String(e.get("kind", "")) != kind:
			continue
		var w2: float = float(e.get("weight", 0.5))
		if safer:
			e["weight"] = clampf(w2 - 0.05, 0.0, 1.0)


static func push_prospective(f: Fish, intent: String, pos: Vector3, ttl: float) -> void:
	f._prospective = {"intent": intent, "pos": pos, "t": ttl}


static func tick_prospective(f: Fish, dt: float) -> void:
	if f._prospective.is_empty():
		return
	var t: float = float(f._prospective.get("t", 0.0)) - dt
	if t <= 0.0:
		f._prospective.clear()
	else:
		f._prospective["t"] = t


static func inherit_disposition(f: Fish, parent_pers: Dictionary) -> Dictionary:
	var g: RandomNumberGenerator = MindRng.for_fish(f, SimRngScript.STREAM_GENETICS)
	var out: Dictionary = {}
	for k in ["boldness", "curiosity", "sociability", "calm"]:
		var base: float = float(parent_pers.get(k, 0.5))
		out[k] = clampf(base + g.randf_range(-0.08, 0.08), 0.05, 1.0)
	return out


static func prospect_value(reward: float, risk: float, boldness: float) -> float:
	var loss_weight: float = lerpf(1.6, 1.0, boldness)
	return reward - risk * loss_weight


static func hyperbolic_discount(reward: float, delay_s: float, impulsivity: float) -> float:
	var k: float = lerpf(0.002, 0.012, impulsivity)
	return reward / (1.0 + k * delay_s)


static func mvt_leave_patch(patch_yield: float, habitat_avg: float) -> bool:
	if habitat_avg <= 0.001:
		return false
	return patch_yield < habitat_avg * 0.85


static func tank_enrichment(sim: Node) -> float:
	if sim == null:
		return 0.5
	var plants: float = 0.0
	if sim.get("total_plant_biomass") != null:
		plants = clampf(float(sim.total_plant_biomass) / 80.0, 0.0, 1.0)
	var o2: float = 0.5
	if sim.get("dissolved_o2") != null:
		o2 = clampf(float(sim.dissolved_o2), 0.0, 1.0)
	return clampf(plants * 0.55 + o2 * 0.45, 0.0, 1.0)


static func novelty_cell_key(f: Fish) -> String:
	var w: Node = f._world_node()
	if w == null:
		return "-1"
	var hw: float = float(w.get("TANK_HALF_W") if w.get("TANK_HALF_W") != null else 8.0)
	var hd: float = float(w.get("TANK_HALF_D") if w.get("TANK_HALF_D") != null else 4.0)
	var hh: float = float(w.get("TANK_HEIGHT") if w.get("TANK_HEIGHT") != null else 7.0)
	var g: int = Fish.NOVELTY_GRID
	var rx: float = clampf((f.position.x + hw) / (hw * 2.0), 0.0, 0.999)
	var ry: float = clampf(f.position.y / hh, 0.0, 0.999)
	var rz: float = clampf((f.position.z + hd) / (hd * 2.0), 0.0, 0.999)
	var idx: int = int(rx * g) + int(ry * g) * g + int(rz * g) * g * g
	return str(idx)


static func hypothesis_line(f: Fish) -> String:
	var key: String = novelty_cell_key(f)
	if not f._hypotheses.has(key):
		return ""
	match String(f._hypotheses[key].get("guess", "")):
		"food":
			return "might be food here"
		"threat":
			return "something felt wrong here"
		"nothing":
			return "nothing much here"
		_:
			return "what is this place?"
