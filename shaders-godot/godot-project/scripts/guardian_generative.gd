extends RefCounted

# Guardian active inference — one self-evidencing model for the tank voice fish.
# Predicts colony + water + keeper; acts (steer/speak) to minimize surprise.

const GuardianFish = preload("res://scripts/guardian_fish.gd")
const KeeperCare = preload("res://scripts/keeper_care.gd")
const FishGenerativeSelf = preload("res://scripts/fish_generative_self.gd")

const SCHEMA_VERSION: int = 1
const HONEST_FRAME: String = "Functional active inference — structured prediction and action, not a claim of inner experience."


static func _policies() -> Array:
	return ["wait", "nudge_keeper", "patrol_surface", "scan_tank"]


static func ensure(arc: Dictionary) -> Dictionary:
	if not arc.has("generative") or not (arc["generative"] is Dictionary):
		arc["generative"] = {
			"schema_version": SCHEMA_VERSION,
			"pred": {"hunger": 0.35, "o2": 0.82, "toxic": 0.08, "keeper": 0.42, "calm": 0.65},
			"set_points": {"hunger": 0.38, "o2": 0.72, "toxic": 0.12, "keeper": 0.55, "calm": 0.7},
			"precision": 0.6,
			"uncertainty": 0.32,
			"free_energy": 0.0,
			"chosen_policy": "wait",
			"counterfactual": "",
			"counterfactual_alt": "",
			"last_situation": "",
		}
	return arc["generative"] as Dictionary


static func markov_blanket() -> Dictionary:
	return {
		"sense": ["colony_hunger", "dissolved_o2", "water_toxicity", "keeper_presence", "daylight"],
		"act": ["nudge_keeper", "patrol_surface", "scan_tank", "hold_watch", "speak"],
	}


static func observe(f: Fish, sim: Node, arc: Dictionary) -> Dictionary:
	var avg_h: float = GuardianFish.tank_avg_hunger(sim)
	var o2: float = 1.0
	if sim != null and sim.get("dissolved_o2") != null:
		o2 = clampf(float(sim.dissolved_o2), 0.0, 1.2)
	var toxic: float = 0.0
	if sim != null and sim.get("water_chemistry") != null:
		var chem = sim.water_chemistry
		toxic = clampf(maxf(float(chem.ammonia), float(chem.nitrite)) * 0.55, 0.0, 1.0)
	var dl: float = float(sim.daylight()) if sim != null and sim.has_method("daylight") else 0.5
	var keeper: float = clampf(f.familiarity * 0.45 + f._cached_glance_strength * 0.55, 0.0, 1.0)
	var mind: Dictionary = arc.get("mind", {}) if arc.get("mind") is Dictionary else {}
	if int(mind.get("visit_count", 0)) >= 8:
		keeper = clampf(keeper + 0.12, 0.0, 1.0)
	if sim != null and sim.has_method("feed_anticipation_active") and sim.feed_anticipation_active():
		keeper = clampf(keeper + 0.18, 0.0, 1.0)
	var calm: float = clampf(
			1.0 - avg_h * 0.42 - toxic * 0.38 - (1.0 - minf(o2, 1.0)) * 0.28, 0.0, 1.0)
	return {
		"hunger": avg_h,
		"o2": minf(o2, 1.0),
		"toxic": toxic,
		"keeper": keeper,
		"calm": calm,
		"daylight": dl,
	}


static func _free_energy(obs: Dictionary, pred: Dictionary, sp: Dictionary, precision: float) -> float:
	var w: Dictionary = {"hunger": 1.1, "o2": 0.85, "toxic": 1.25, "keeper": 0.75, "calm": 0.55}
	var total: float = 0.0
	for k in w.keys():
		var target: float = float(sp.get(k, float(pred.get(k, 0.0))))
		total += absf(float(obs.get(k, 0.0)) - target) * float(w[k])
	return total * clampf(precision, 0.2, 1.0)


static func _simulate_policy(obs: Dictionary, pred: Dictionary, sp: Dictionary,
		precision: float, policy: String, dt: float) -> float:
	var sim_o: Dictionary = obs.duplicate(true)
	match policy:
		"wait":
			sim_o["hunger"] = clampf(float(sim_o.get("hunger", 0.0)) + dt * 0.012, 0.0, 1.0)
			sim_o["keeper"] = maxf(0.0, float(sim_o.get("keeper", 0.0)) - dt * 0.025)
		"nudge_keeper":
			sim_o["keeper"] = clampf(float(sim_o.get("keeper", 0.0)) + 0.22, 0.0, 1.0)
			sim_o["hunger"] = maxf(0.0, float(sim_o.get("hunger", 0.0)) - 0.12)
		"patrol_surface":
			sim_o["o2"] = clampf(float(sim_o.get("o2", 0.0)) + 0.08, 0.0, 1.0)
			sim_o["toxic"] = maxf(0.0, float(sim_o.get("toxic", 0.0)) - 0.04)
		"scan_tank":
			sim_o["calm"] = clampf(float(sim_o.get("calm", 0.0)) + 0.05, 0.0, 1.0)
			sim_o["keeper"] = clampf(float(sim_o.get("keeper", 0.0)) + 0.04, 0.0, 1.0)
	return _free_energy(sim_o, pred, sp, precision)


static func _steer_for_policy(f: Fish, sim: Node, policy: String, obs: Dictionary) -> Vector3:
	var out: Vector3 = Vector3.ZERO
	match policy:
		"nudge_keeper":
			if f._cached_glance_strength > 0.08:
				var to_glass: Vector3 = f._cached_glance_point - f.position
				to_glass.y *= 0.35
				if to_glass.length_squared() > 0.08:
					out += to_glass.normalized() * lerpf(0.45, 0.95, float(obs.get("hunger", 0.0)))
		"patrol_surface":
			var surface_y: float = f._water_surface_y() - 0.35
			var up: float = surface_y - f.position.y
			if up > 0.05:
				out += Vector3(0.0, up, 0.0).normalized() * 0.55
		"scan_tank":
			if sim != null and sim.get("TANK_HALF_W") != null:
				var center: Vector3 = Vector3(0.0, f.home_y, 0.0)
				var to_c: Vector3 = center - f.position
				to_c.y *= 0.4
				if to_c.length_squared() > 0.2:
					out += to_c.normalized() * 0.35
			else:
				out += f.heading * 0.25
	return out


static func _situation_from(sim: Node, obs: Dictionary, _pred: Dictionary, sp: Dictionary,
		policy: String, chapter: int) -> Dictionary:
	var hunger_e: float = float(obs.get("hunger", 0.0)) - float(sp.get("hunger", 0.35))
	var toxic_e: float = float(obs.get("toxic", 0.0)) - float(sp.get("toxic", 0.12))
	var o2_e: float = float(sp.get("o2", 0.7)) - float(obs.get("o2", 1.0))
	var keeper_e: float = float(sp.get("keeper", 0.5)) - float(obs.get("keeper", 0.0))
	var dl: float = float(obs.get("daylight", 0.5))
	var situation: String = ""
	var action: String = ""
	if toxic_e > 0.22 or o2_e > 0.28:
		situation = "water_stress"
	elif hunger_e > 0.28 and policy == "nudge_keeper":
		situation = "feed_nudge"
		action = "drop_feed" if float(obs.get("hunger", 0.0)) > GuardianFish.STARVE_THRESHOLD else "nudge_feed"
	elif sim != null and KeeperCare.tank_needs_care_nudge(sim) and policy == "scan_tank" and toxic_e > 0.05:
		situation = "tank_care"
	elif dl > 0.35 and dl < 0.55 and keeper_e > 0.18 and chapter >= 1:
		situation = "morning"
	elif policy == "scan_tank" and float(obs.get("calm", 0.0)) > 0.55:
		situation = "observe"
	return {"situation": situation, "action": action}


static func tick(f: Fish, sim: Node, arc: Dictionary, dt: float) -> Dictionary:
	if f == null or not f.is_guardian:
		return {}
	var g: Dictionary = ensure(arc)
	var obs: Dictionary = observe(f, sim, arc)
	var pred: Dictionary = g.get("pred", {})
	var sp: Dictionary = g.get("set_points", {})
	# Set-points mature with chapter (#49).
	var chapter: int = int(arc.get("chapter", 0))
	sp["hunger"] = lerpf(float(sp.get("hunger", 0.38)), 0.32, clampf(float(chapter) / 4.0, 0.0, 1.0))
	sp["keeper"] = lerpf(float(sp.get("keeper", 0.55)), 0.62, clampf(float(chapter) / 4.0, 0.0, 1.0))
	# Precision-weighting (#43): murky water / night → cautious model.
	var dl: float = float(obs.get("daylight", 0.5))
	var prec: float = clampf(0.28 + dl * 0.48 - float(obs.get("toxic", 0.0)) * 0.35, 0.18, 0.92)
	g["precision"] = lerpf(float(g.get("precision", 0.6)), prec, clampf(dt * 2.0, 0.0, 1.0))
	prec = float(g["precision"])
	# Online prediction (#40).
	for k in ["hunger", "o2", "toxic", "keeper", "calm"]:
		var rate: float = 0.35 if k == "hunger" else 0.55
		pred[k] = lerpf(float(pred.get(k, float(obs.get(k, 0.0)))), float(obs.get(k, 0.0)),
				clampf(dt * rate * prec, 0.0, 1.0))
	g["pred"] = pred
	g["set_points"] = sp
	var fe: float = _free_energy(obs, pred, sp, prec)
	g["free_energy"] = lerpf(float(g.get("free_energy", 0.0)), fe, clampf(dt * 3.0, 0.0, 1.0))
	g["uncertainty"] = clampf(1.0 - prec * (1.0 - fe * 0.65), 0.05, 0.95)
	# Counterfactual rollouts (#46): pick policy minimizing expected free energy.
	var best_p: String = "wait"
	var best_e: float = INF
	var alt_p: String = "wait"
	var alt_e: float = INF
	for p in _policies():
		var e: float = _simulate_policy(obs, pred, sp, prec, p, maxf(dt, 0.05))
		if e < best_e:
			alt_e = best_e
			alt_p = best_p
			best_e = e
			best_p = p
		elif e < alt_e:
			alt_e = e
			alt_p = p
	g["chosen_policy"] = best_p
	g["counterfactual"] = _counterfactual_line(best_p, obs)
	g["counterfactual_alt"] = _counterfactual_line(alt_p, obs)
	# Situation + action from errors + chosen policy.
	var sit: Dictionary = _situation_from(sim, obs, pred, sp, best_p, chapter)
	if str(sit.get("situation", "")) == "" and fe > 0.42 and best_p == "nudge_keeper":
		sit = {"situation": "feed_nudge", "action": "nudge_feed"}
	g["last_situation"] = str(sit.get("situation", ""))
	# Steer = self-evidencing action (#41).
	var steer: Vector3 = _steer_for_policy(f, sim, best_p, obs)
	arc["_inf_steer"] = steer
	arc["generative"] = g
	# Sync fish-level generative stub for felt-now protention on the guardian body.
	if f.get("_felt_self") is Dictionary:
		var gen: Dictionary = FishGenerativeSelf.ensure(f)
		gen["counterfactual"] = str(g.get("counterfactual", ""))
		gen["keeper_pred"] = float(pred.get("keeper", 0.5))
		gen["body_pred"] = float(obs.get("calm", 0.5))
		gen["world_pred"] = 1.0 - fe * 0.5
		gen["precision"] = prec
		gen["uncertainty"] = float(g.get("uncertainty", 0.3))
		(f._felt_self as Dictionary)["generative"] = gen
	# Dark-room guard (#45): if only waiting, boredom rises in relevance elsewhere.
	return {
		"steer": steer,
		"free_energy": float(g["free_energy"]),
		"precision": prec,
		"uncertainty": float(g["uncertainty"]),
		"chosen_policy": best_p,
		"counterfactual": str(g.get("counterfactual", "")),
		"situation": str(sit.get("situation", "")),
		"action": str(sit.get("action", "")),
		"speak_urgency": clampf(fe * 0.85 + float(obs.get("hunger", 0.0)) * 0.25, 0.0, 1.0),
	}


static func _counterfactual_line(policy: String, obs: Dictionary) -> String:
	match policy:
		"nudge_keeper":
			if float(obs.get("hunger", 0.0)) > 0.55:
				return "if I call now, hunger might ease"
			return "if I reach the glass, the keeper might notice"
		"patrol_surface":
			return "if I ride the surface, breath might come easier"
		"scan_tank":
			return "if I circle the tank, I'll know who needs me"
		_:
			return "if I hold still, the rhythm might return"


static func note_feed(arc: Dictionary) -> void:
	var g: Dictionary = ensure(arc)
	var pred: Dictionary = g.get("pred", {})
	pred["hunger"] = maxf(0.0, float(pred.get("hunger", 0.35)) - 0.35)
	pred["calm"] = clampf(float(pred.get("calm", 0.5)) + 0.15, 0.0, 1.0)
	g["pred"] = pred
	g["free_energy"] = maxf(0.0, float(g.get("free_energy", 0.0)) - 0.25)
	arc["generative"] = g


static func note_keeper_present(arc: Dictionary) -> void:
	var g: Dictionary = ensure(arc)
	var pred: Dictionary = g.get("pred", {})
	pred["keeper"] = clampf(float(pred.get("keeper", 0.4)) + 0.25, 0.0, 1.0)
	g["pred"] = pred
	arc["generative"] = g


static func doubt_line(arc: Dictionary) -> String:
	var g: Dictionary = ensure(arc)
	if float(g.get("uncertainty", 0.0)) < 0.45:
		return ""
	if float(g.get("free_energy", 0.0)) > 0.35:
		return "I'm not sure what's coming next"
	return ""


static func context_fields(arc: Dictionary) -> Dictionary:
	var g: Dictionary = ensure(arc)
	return {
		"generative_policy": str(g.get("chosen_policy", "")),
		"generative_counterfactual": str(g.get("counterfactual", "")),
		"prediction_uncertainty": snappedf(float(g.get("uncertainty", 0.0)), 0.01),
		"free_energy": snappedf(float(g.get("free_energy", 0.0)), 0.01),
		"model_precision": snappedf(float(g.get("precision", 0.0)), 0.01),
		"honest_frame": HONEST_FRAME,
	}
