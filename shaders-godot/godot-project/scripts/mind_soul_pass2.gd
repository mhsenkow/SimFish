extends RefCounted

# SENTIENCE_THE_SOUL_WE_MAKE pass 2 — habits, bandit, precision, rollouts,
# social depth, narrative, finitude textures. State lives in `f._soul_mind`.

const FishMind = preload("res://scripts/fish_mind.gd")
const FishMindScience = preload("res://scripts/fish_mind_science.gd")
const FishBinding = preload("res://scripts/fish_binding.gd")
const FishCoreAffect = preload("res://scripts/fish_core_affect.gd")
const FishProtoself = preload("res://scripts/fish_protoself.gd")
const FishGenerativeSelf = preload("res://scripts/fish_generative_self.gd")
const MindActiveInference = preload("res://scripts/mind_active_inference.gd")
const MindWorldModel = preload("res://scripts/mind_world_model.gd")
const MindSoul = preload("res://scripts/mind_soul.gd")

const HABIT_STRENGTH_COMPILE: float = 0.68
const HABIT_STRENGTH_RUN: float = 0.64
const HABIT_BREAK_SURPRISE: float = 0.42


static func enabled() -> bool:
	return MindSoul.enabled() and MindAblation.enabled(MindAblation.SOUL)


static func ensure_fields(s: Dictionary) -> Dictionary:
	if s.get("habits") == null or not (s["habits"] is Dictionary):
		s["habits"] = {}
	if s.get("bandit") == null or not (s["bandit"] is Dictionary):
		s["bandit"] = {}
	if s.get("sense_precision") == null or not (s["sense_precision"] is Dictionary):
		s["sense_precision"] = {
			"food": 0.55, "threat": 0.55, "social": 0.55, "novelty": 0.55,
		}
	if s.get("pavlov") == null or not (s["pavlov"] is Dictionary):
		s["pavlov"] = {}
	if s.get("life_chapters") == null or not (s["life_chapters"] is Array):
		s["life_chapters"] = []
	if s.get("meta_emotion") == null:
		s["meta_emotion"] = ""
	if s.get("mod_reserve") == null:
		s["mod_reserve"] = 1.0
	if s.get("integration_spend") == null:
		s["integration_spend"] = 0.0
	if s.get("tom_intent") == null or not (s["tom_intent"] is Dictionary):
		s["tom_intent"] = {}
	return s


static func context_key(f, sim) -> String:
	var cell: String = FishMindScience.novelty_cell_key(f)
	var phase: String = "day"
	if sim != null and sim.get("day_phase") != null:
		phase = str(sim.day_phase)
	elif sim != null and sim.has_method("daylight"):
		var dl: float = float(sim.daylight())
		if dl < 0.3:
			phase = "night"
		elif dl < 0.45:
			phase = "dawn"
	var focus: String = str(f.attention_focus if f.get("attention_focus") != null else "")
	if focus == "":
		focus = "idle"
	return "%s|%s|%s" % [cell, phase, focus]


static var _habit_attempts: int = 0
static var _habit_hits: int = 0


static func habit_stats() -> Dictionary:
	return {
		"attempts": _habit_attempts,
		"hits": _habit_hits,
		"rate": float(_habit_hits) / maxf(1.0, float(_habit_attempts)),
	}


static func reset_habit_stats_for_test() -> void:
	_habit_attempts = 0
	_habit_hits = 0


static func tick(f, sim, ms, dt: float) -> void:
	if not enabled():
		return
	var s: Dictionary = ensure_fields(MindSoul.ensure(f))
	_tick_mod_budget(f, s, dt)
	_tick_bandit_uncertainty(f, s, sim, dt)
	_tick_expectation_from_world(f, s, sim)
	_tick_meta_emotion(f, s)
	_tick_mortality_discount(f, s, dt)
	_tick_narrative(f, s, sim)
	_try_last_lucidity(f, s, sim, ms)
	f._soul_mind = s


static func after_commit(f, _ms, sim, label: String) -> void:
	if not enabled() or label == "":
		return
	var s: Dictionary = ensure_fields(MindSoul.ensure(f))
	_reinforce_habit(f, s, sim, label)
	_update_bandit(f, s, sim, label)
	_update_sense_precision(f, s, label)
	_pair_pavlov_cue(f, s, sim, label)
	if label == "food" and f.hunger > 0.4:
		FishMindScience.push_prospective(f, "food", f.position, 8.0)
	f._soul_mind = s


static func habit_shortcut(f, sim) -> Dictionary:
	if not enabled() or f._asleep:
		return {}
	_habit_attempts += 1
	if FishBinding.layer_enabled() and bool(FishBinding.ensure(f).get("fragmented", false)):
		return {}
	var pe: float = float(f.get("_prediction_error") if f.get("_prediction_error") != null else 0.0)
	if pe > HABIT_BREAK_SURPRISE or f.surprise > 0.45:
		_weaken_habits(f, MindSoul.ensure(f), 0.12)
		return {}
	var s: Dictionary = ensure_fields(MindSoul.ensure(f))
	var ctx: String = context_key(f, sim)
	var h: Variant = s.get("habits", {}).get(ctx, null)
	if not h is Dictionary:
		return {}
	var strength: float = float((h as Dictionary).get("strength", 0.0))
	if strength + 0.001 < HABIT_STRENGTH_RUN:
		return {}
	var lb: String = str((h as Dictionary).get("label", ""))
	if lb == "":
		return {}
	s["habit_active"] = true
	f._soul_mind = s
	_habit_hits += 1
	return {
		"contents": [{"label": lb, "salience": 0.88, "coalition": [lb, "habit"]}],
		"ignited": true,
		"top_salience": 0.88,
		"habit": true,
	}


static func prospective_bid(f) -> Dictionary:
	if not enabled():
		return {}
	var pro_v: Variant = f.get("_prospective")
	if not (pro_v is Dictionary) or (pro_v as Dictionary).is_empty():
		return {}
	var pro: Dictionary = pro_v as Dictionary
	var intent: String = str(pro.get("intent", ""))
	var sal: float = 0.42 + (1.0 - float(pro.get("t", 0.0)) / 8.0) * 0.2
	if intent == "food":
		sal += f.hunger * 0.25
	return {"label": intent if intent != "" else "goal_hold",
			"salience": clampf(sal, 0.0, 0.85),
			"coalition": ["goal", intent, "prospective"]}


static func shared_attention_bid(f, sim) -> Dictionary:
	if not enabled() or sim == null:
		return {}
	# PERFORMANCE_UNTHROTTLED #40 — reuse bonded-focus cache from `_boids()`.
	if f.get("_boids_shared_focus") != null:
		var cached_focus: String = str(f._boids_shared_focus)
		var cached_sal: float = float(f.get("_boids_shared_sal") if f.get("_boids_shared_sal") != null else 0.0)
		if cached_focus != "" and cached_sal >= 0.22:
			return {"label": cached_focus, "salience": cached_sal,
					"coalition": ["social", "shared_attention", cached_focus]}
	if sim.get("fish") == null:
		return {}
	var best: float = 0.0
	var focus: String = ""
	for other in sim.fish:
		if not is_instance_valid(other) or other == f or not (other is Fish):
			continue
		var oid: String = str(other.id)
		if not f.bonds.has(oid) or float(f.bonds[oid]) < 0.35:
			continue
		if not other._workspace_ignited or other.attention_focus == "":
			continue
		var bond: float = float(f.bonds[oid])
		var sal: float = bond * 0.55
		if sal > best:
			best = sal
			focus = other.attention_focus
	if focus == "" or best < 0.22:
		return {}
	return {"label": focus, "salience": best,
			"coalition": ["social", "shared_attention", focus]}


static func bandit_explore_bonus(f, label: String) -> float:
	if not enabled():
		return 0.0
	var s: Dictionary = ensure_fields(MindSoul.ensure(f))
	var ctx: String = context_key(f, null)
	var row: Variant = s.get("bandit", {}).get(ctx, null)
	if not row is Dictionary:
		return 0.0
	var vals: Array = []
	for k in (row as Dictionary).keys():
		vals.append(float((row as Dictionary)[k]))
	if vals.size() < 2:
		return 0.0
	var mean: float = 0.0
	for v in vals:
		mean += float(v)
	mean /= float(vals.size())
	var var_sum: float = 0.0
	for v in vals:
		var_sum += (float(v) - mean) * (float(v) - mean)
	var variance: float = var_sum / float(vals.size())
	var key: String = _drive_key(label)
	var mine: float = float((row as Dictionary).get(key, mean))
	return clampf(sqrt(variance) * 0.35 + maxf(0.0, mean - mine) * 0.2, 0.0, 0.28)


static func sense_precision_scale(f, label: String) -> float:
	if not enabled():
		return 1.0
	var s: Dictionary = ensure_fields(MindSoul.ensure(f))
	var sp: Dictionary = s.get("sense_precision", {})
	var key: String = "novelty"
	match label:
		"food", "forage":
			key = "food"
		"threat", "safety", "vibration":
			key = "threat"
		"mate", "player", "social":
			key = "social"
		"novelty", "free_energy", "explore", "uncertainty":
			key = "novelty"
	var p: float = float(sp.get(key, 0.55))
	return clampf(lerpf(0.72, 1.28, p), 0.65, 1.35)


static func rollout_efe_bonus(f, label: String, sim) -> float:
	if not enabled() or not MindActiveInference.enabled_for(f, sim):
		return 0.0
	MindWorldModel.ensure_model(f)
	var pe: Dictionary = MindActiveInference.preferred_error(f)
	var gain: float = 0.0
	match label:
		"food", "forage":
			gain = float(pe.get("hunger", 0.5)) * 0.18
		"threat", "safety":
			gain = float(pe.get("safety", 0.5)) * 0.16
		"rest", "night_quiet":
			gain = float(pe.get("rest", 0.0)) * 0.14
		_:
			gain = 0.0
	var m: Dictionary = f._world_model as Dictionary
	var gru_e: float = float(m.get("gru_error", 0.0))
	return clampf(gain * (1.0 - gru_e * 0.35), 0.0, 0.22)


static func mood_congruence_scale(f, label: String) -> float:
	if not enabled() or not FishBinding.layer_enabled():
		return 1.0
	var v: float = FishCoreAffect.valence(f)
	if label in ["threat", "interoception", "vibration"] and v < -0.15:
		return lerpf(1.0, 1.18, absf(v))
	if label in ["food", "mate", "player"] and v > 0.12:
		return lerpf(1.0, 1.12, v)
	if label in ["rest", "night_quiet"] and f.stress > 0.45:
		return 1.14
	return 1.0


static func markov_permits(f, label: String) -> bool:
	if not enabled():
		return true
	var stress_load: float = clampf(f.stress + f.spooked * 0.5, 0.0, 1.0)
	if stress_load < 0.55:
		return true
	var blanket: Dictionary = FishGenerativeSelf.markov_blanket()
	var sense: Array = blanket.get("sense", [])
	if label in ["novelty", "free_energy", "explore"] and stress_load > 0.72:
		return false
	if label in ["player", "keeper_message"] and stress_load > 0.82:
		return "keeper" in sense
	return true


static func tom_predict_intent(_f, other: Fish) -> String:
	if not enabled() or other == null:
		return "idle"
	if other.hunger > 0.62:
		return "foraging"
	if other.spooked > 0.45 or other._startle_remaining > 0.0:
		return "fleeing"
	if other.current_mode == Fish.Mode.COURT:
		return "courting"
	if other._asleep:
		return "resting"
	if other.speed > 0.12:
		return "swimming"
	return "idle"


static func tick_tom_intents(f, neighbors: Array) -> void:
	if not enabled():
		return
	var s: Dictionary = ensure_fields(MindSoul.ensure(f))
	var intents: Dictionary = s.get("tom_intent", {})
	for n in neighbors:
		if not is_instance_valid(n) or not (n is Fish) or n == f:
			continue
		var oid: String = str(n.id)
		if oid == "":
			continue
		var pred: String = tom_predict_intent(f, n)
		var prev: String = str(intents.get(oid, ""))
		intents[oid] = pred
		if prev != "" and prev != pred and f.bonds.has(oid):
			var surprise: float = 0.0 if prev == pred else 0.15
			f.surprise = clampf(f.surprise + surprise, 0.0, 1.0)
	s["tom_intent"] = intents
	f._soul_mind = s


static func tom_follow_food_bid(f) -> Dictionary:
	if not enabled():
		return {}
	var s: Dictionary = ensure_fields(MindSoul.ensure(f))
	var intents: Dictionary = s.get("tom_intent", {})
	var best: float = 0.0
	var target: String = ""
	for oid in intents.keys():
		if not f.bonds.has(oid):
			continue
		if str(intents[oid]) != "foraging":
			continue
		var bond: float = float(f.bonds[oid])
		if bond > best:
			best = bond
			target = oid
	if best < 0.3:
		return {}
	return {"label": "food", "salience": best * 0.5 + 0.12,
			"coalition": ["social", "tom", "food"], "tom_target": target}


static func autobiography_lines(f) -> PackedStringArray:
	if not enabled():
		return PackedStringArray()
	var s: Dictionary = ensure_fields(MindSoul.ensure(f))
	var out: PackedStringArray = PackedStringArray()
	for ch in s.get("life_chapters", []):
		if ch is Dictionary:
			var line: String = str((ch as Dictionary).get("line", ""))
			if line != "":
				out.append(line)
	return out


static func competence_hesitation_scale(f) -> float:
	if not enabled():
		return 1.0
	var s: Dictionary = ensure_fields(MindSoul.ensure(f))
	var habits: Dictionary = s.get("habits", {})
	if habits.is_empty():
		return 1.0
	var mean_str: float = 0.0
	for k in habits.keys():
		mean_str += float((habits[k] as Dictionary).get("strength", 0.0))
	mean_str /= float(maxi(1, habits.size()))
	return clampf(lerpf(1.12, 0.82, mean_str), 0.78, 1.15)


static func _reinforce_habit(f, s: Dictionary, sim, label: String) -> void:
	var ctx: String = context_key(f, sim)
	var habits: Dictionary = s.get("habits", {})
	var h: Dictionary = habits.get(ctx, {"label": label, "strength": 0.0, "uses": 0})
	if str(h.get("label", "")) == label:
		h["strength"] = clampf(float(h.get("strength", 0.0)) + 0.06, 0.0, 1.0)
	else:
		h = {"label": label, "strength": 0.08, "uses": 0}
	h["uses"] = int(h.get("uses", 0)) + 1
	habits[ctx] = h
	s["habits"] = habits


static func _weaken_habits(f, s: Dictionary, amount: float) -> void:
	var habits: Dictionary = s.get("habits", {})
	for k in habits.keys():
		var h: Dictionary = habits[k]
		h["strength"] = maxf(0.0, float(h.get("strength", 0.0)) - amount)
		habits[k] = h
	s["habits"] = habits
	f._soul_mind = s


static func _update_bandit(f, s: Dictionary, sim, label: String) -> void:
	var ctx: String = context_key(f, sim)
	var bandit: Dictionary = s.get("bandit", {})
	var row: Dictionary = bandit.get(ctx, {})
	var key: String = label
	match label:
		"food", "forage":
			key = "food"
		"threat", "safety":
			key = "threat"
		"mate", "social":
			key = "mate"
		"rest", "night_quiet":
			key = "rest"
		_:
			key = "novelty"
	var delta: float = 0.0
	if s.get("pending_outcome") is Dictionary:
		var p: Dictionary = s["pending_outcome"]
		if str(p.get("label", "")) == label:
			delta = 0.05
	var old: float = float(row.get(key, 0.5))
	row[key] = clampf(lerpf(old, old + delta, 0.35), 0.0, 1.0)
	bandit[ctx] = row
	s["bandit"] = bandit


static func _update_sense_precision(f, s: Dictionary, label: String) -> void:
	var sp: Dictionary = s.get("sense_precision", {})
	var key: String = "novelty"
	match label:
		"food", "forage":
			key = "food"
		"threat", "safety":
			key = "threat"
		"mate", "player":
			key = "social"
		_:
			key = "novelty"
	var pe: float = float(f.get("_prediction_error") if f.get("_prediction_error") != null else 0.0)
	var old: float = float(sp.get(key, 0.55))
	if pe < 0.22:
		sp[key] = clampf(old + 0.03, 0.12, 0.95)
	elif pe > 0.45:
		sp[key] = clampf(old - 0.04, 0.12, 0.95)
	s["sense_precision"] = sp


static func _pair_pavlov_cue(f, s: Dictionary, sim, label: String) -> void:
	var cue: String = ""
	if f.get("_keeper_pending") is Dictionary:
		var kp: Dictionary = f._keeper_pending as Dictionary
		if str(kp.get("keeper_intent", "")) == "food" and label == "food":
			cue = "keeper_feed_ritual"
	if sim != null and sim.has_method("feed_anticipation_active") and sim.feed_anticipation_active():
		cue = "feed_anticipation"
	if cue == "":
		return
	var pav: Dictionary = s.get("pavlov", {})
	var rec: Dictionary = pav.get(cue, {"outcome": label, "strength": 0.0})
	rec["strength"] = clampf(float(rec.get("strength", 0.0)) + 0.08, 0.0, 1.0)
	rec["outcome"] = label
	pav[cue] = rec
	s["pavlov"] = pav


static func pavlov_bid_boost(f, label: String) -> float:
	if not enabled():
		return 0.0
	var s: Dictionary = ensure_fields(MindSoul.ensure(f))
	var pav: Dictionary = s.get("pavlov", {})
	var boost: float = 0.0
	for k in pav.keys():
		var rec: Dictionary = pav[k]
		if str(rec.get("outcome", "")) == label:
			boost = maxf(boost, float(rec.get("strength", 0.0)) * 0.35)
	return boost


static func _tick_mod_budget(f, s: Dictionary, dt: float) -> void:
	var reserve: float = float(s.get("mod_reserve", 1.0))
	if f._asleep:
		reserve = clampf(reserve + dt * 0.08, 0.0, 1.0)
	elif f._workspace_ignited:
		reserve = maxf(0.0, reserve - dt * 0.025)
	s["mod_reserve"] = reserve
	var spend: float = float(s.get("integration_spend", 0.0))
	if FishBinding.layer_enabled():
		spend = lerpf(spend, FishBinding.integration_score(f), dt * 0.5)
	s["integration_spend"] = spend
	if reserve < 0.25:
		f._learning_rate_mult = clampf(float(f.get("_learning_rate_mult") if f.get("_learning_rate_mult") != null else 1.0) * 0.92, 0.35, 1.2)


static func _tick_bandit_uncertainty(_f, _s: Dictionary, _sim, _dt: float) -> void:
	pass


static func _tick_expectation_from_world(f, _s: Dictionary, sim) -> void:
	if sim != null and sim.has_method("feed_anticipation_active") and sim.feed_anticipation_active():
		MindSoul.set_expectation(f, "feed")
	elif f.spooked > 0.5:
		MindSoul.set_expectation(f, "safety")


static func _tick_meta_emotion(f, s: Dictionary) -> void:
	if not FishBinding.layer_enabled():
		return
	var v: float = FishCoreAffect.valence(f)
	var meta: String = ""
	if f.stress > 0.62 and v < -0.2:
		meta = "distress_at_distress"
	elif f.stress < 0.25 and float(s.get("confidence_volatility", 0.0)) > 0.3:
		meta = "uneasy_at_calm"
	elif f.arousal > 0.65 and v > 0.1:
		meta = "excited_about_excitement"
	s["meta_emotion"] = meta


static func _tick_mortality_discount(f, _s: Dictionary, dt: float) -> void:
	var mort: Dictionary = MindSoul.mortality_shift(f)
	var decline: float = float(mort.get("decline", 0.0))
	if decline > 0.55 and f.brooding_remaining <= 0.0 and f.partner != null:
		f._legacy_drive = clampf(f._legacy_drive + dt * 0.02, 0.0, 1.0)


static func _tick_narrative(f, s: Dictionary, sim) -> void:
	var chapters: Array = s.get("life_chapters", [])
	if chapters.size() >= 12:
		return
	var tag: String = ""
	var line: String = ""
	if float(s.get("pe_progress", 0.0)) > 0.4 and chapters.size() < 2:
		tag = "learning_tank"
		line = "learning this water"
	elif float(s.get("surprise_at_self", 0.0)) > 0.5:
		tag = "surprised_self"
		line = "surprised by my own turn"
	elif float(MindSoul.mortality_shift(f).get("decline", 0.0)) > 0.7:
		tag = "aging"
		line = "not what I was"
	elif f._mate_grief > 0.45:
		tag = "loss"
		line = "someone missing in the water"
	if tag == "":
		return
	for ch in chapters:
		if ch is Dictionary and str((ch as Dictionary).get("tag", "")) == tag:
			return
	chapters.append({"tag": tag, "line": line, "t": Time.get_ticks_msec()})
	s["life_chapters"] = chapters
	if sim != null and sim.has_method("append_fish_journal_entry") and MindRng.for_fish(f).randf() < 0.04:
		sim.append_fish_journal_entry(f, line, PackedStringArray(["autobiography", tag]))


static func _try_last_lucidity(f, s: Dictionary, sim, ms) -> void:
	var mort: Dictionary = MindSoul.mortality_shift(f)
	if float(mort.get("decline", 0.0)) < 0.82 or f.get("_dying") != true:
		return
	if bool(s.get("lucidity_spoke", false)):
		return
	if ms == null or not ms.workspace_ignited:
		return
	s["lucidity_spoke"] = true
	f._soul_mind = s
	var line: String = FishBinding.CAPSTONE_LINE
	if sim != null and sim.has_method("append_fish_journal_entry"):
		sim.append_fish_journal_entry(f, line, PackedStringArray(["finitude", "lucidity"]))


static func _drive_key(label: String) -> String:
	match label:
		"food", "forage":
			return "food"
		"threat", "safety":
			return "threat"
		"mate", "social":
			return "mate"
		"rest", "night_quiet":
			return "rest"
		"novelty", "free_energy", "explore", "uncertainty":
			return "novelty"
		"interoception", "body":
			return "interoception"
		_:
			return label
