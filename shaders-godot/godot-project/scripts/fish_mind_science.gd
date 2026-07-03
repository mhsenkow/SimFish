extends RefCounted

# Extended procedural mind mechanics (SENTIENCE_DEEP_SCIENCE Vol II).
# Lite, deterministic, always inspectable — never a black box.

const FishMind = preload("res://scripts/fish_mind.gd")
const EpisodicMemory = preload("res://scripts/episodic_memory.gd")
const MindSoulPass2 = preload("res://scripts/mind_soul_pass2.gd")
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


const TOM_NEIGHBOR_K: int = 4
const TOM_MODEL_CAP: int = 8
const TOM_HYSTERESIS_S: float = 0.5
const TOM_DELTA_EPS: float = 0.04


static func _tom_nearest(f, neighbors: Array) -> Array:
	var scored: Array = []
	for n in neighbors:
		if not (n is Fish) or n == f:
			continue
		var other: Fish = n as Fish
		if str(other.id) == "":
			continue
		scored.append({"fish": other, "d2": f.position.distance_squared_to(other.position)})
	scored.sort_custom(func(a, b): return float(a.get("d2", 999.0)) < float(b.get("d2", 999.0)))
	var out: Array = []
	for i in range(mini(TOM_NEIGHBOR_K, scored.size())):
		out.append((scored[i] as Dictionary).get("fish"))
	return out


static func _tom_touch_lru(f, oid: String) -> void:
	var order: Array = f._tom_model_ids if f.get("_tom_model_ids") is Array else []
	order.erase(oid)
	order.append(oid)
	while order.size() > TOM_MODEL_CAP:
		var drop: String = str(order[0])
		order.remove_at(0)
		f._tom_pred.erase(drop)
	f._tom_model_ids = order


static func tick_theory_of_mind(f, neighbors: Array) -> void:
	f.inferred_states.clear()
	var best_alert: Dictionary = {}
	var model_set: Array = f._tom_model_ids if f.get("_tom_model_ids") is Array else []
	var nearest: Array = _tom_nearest(f, neighbors)
	var next_ids: Array = []
	for other in nearest:
		if other is Fish:
			next_ids.append(str((other as Fish).id))
	var changed: bool = next_ids.size() != model_set.size()
	if not changed:
		for i in next_ids.size():
			if str(next_ids[i]) != str(model_set[i]):
				changed = true
				break
	if changed:
		f._tom_set_hold = float(f.get("_tom_set_hold") if f.get("_tom_set_hold") != null else 0.0) + 1.0 / 15.0
		if float(f._tom_set_hold) < TOM_HYSTERESIS_S and model_set.size() > 0:
			nearest = []
			for oid in model_set:
				for n in neighbors:
					if n is Fish and str((n as Fish).id) == str(oid):
						nearest.append(n)
						break
		else:
			f._tom_model_ids = next_ids.duplicate()
			f._tom_set_hold = 0.0
	else:
		f._tom_set_hold = 0.0
	for n in nearest:
		if not (n is Fish):
			continue
		var other: Fish = n as Fish
		var oid: String = str(other.id)
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
		var to_me: Vector3 = f.position - other.position
		var d: float = to_me.length()
		var rec: Dictionary = f._tom_pred.get(oid, {"charge": 0.0, "prev_d": d, "hd": other.heading, "sp": other.speed})
		var facing: float = 0.0
		if other.heading.length_squared() > 1e-6 and d > 1e-3:
			facing = other.heading.normalized().dot(to_me / d)
		var closing: float = float(rec.get("prev_d", d)) - d
		var hd: Vector3 = rec.get("hd", Vector3.ZERO) if rec.get("hd") is Vector3 else Vector3.ZERO
		var moved: bool = hd.distance_squared_to(other.heading) > TOM_DELTA_EPS * TOM_DELTA_EPS \
				or absf(float(rec.get("sp", other.speed)) - other.speed) > TOM_DELTA_EPS
		if moved or not f._tom_pred.has(oid):
			var aggressive: bool = (label == "threat" or label == "dominant") \
					and facing > 0.4 and closing > 0.0
			rec["charge"] = lerpf(float(rec.get("charge", 0.0)), 1.0 if aggressive else 0.0, 0.08)
			rec["prev_d"] = d
			rec["hd"] = other.heading
			rec["sp"] = other.speed
			f._tom_pred[oid] = rec
			_tom_touch_lru(f, oid)
		if float(rec.get("charge", 0.0)) > 0.4 and d < 4.0 and facing > 0.3:
			var level: float = float(rec["charge"]) * (1.0 - d / 4.0)
			if level > float(best_alert.get("level", 0.0)):
				best_alert = {"oid": oid, "level": level}
	f._tom_alert = best_alert
	MindSoulPass2.tick_tom_intents(f, neighbors)
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


# META #4 — learned probability that a given neighbour charges this fish.
static func predicted_charge(f: Fish, oid: String) -> float:
	var rec: Variant = f._tom_pred.get(oid, null)
	return float((rec as Dictionary).get("charge", 0.0)) if rec is Dictionary else 0.0


# META #4 — the anticipatory-threat bid: attend to / flee a predicted charger
# before contact. Empty when no learned aggressor is bearing down.
static func collect_predict_bid(f) -> Dictionary:
	var alert: Variant = f.get("_tom_alert")
	if not (alert is Dictionary) or (alert as Dictionary).is_empty():
		return {}
	var level: float = float((alert as Dictionary).get("level", 0.0))
	if level <= 0.05:
		return {}
	return {"label": "threat", "salience": level * 0.7,
			"coalition": ["threat", "safety", "social", "predict"]}


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


static func push_prospective(f, intent: String, pos: Vector3, ttl: float) -> void:
	if f == null:
		return
	f.set("_prospective", {"intent": intent, "pos": pos, "t": ttl})


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


static func novelty_cell_key(f) -> String:
	var w: Node = null
	if f != null and f.has_method("_world_node"):
		w = f._world_node()
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
