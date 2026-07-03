extends RefCounted

# SENTIENCE_THE_SOUL_WE_MAKE pass 3 — capstone: volition, narrative, social depth,
# sleep/planning, eval hooks. State in f._soul_mind (via _mind_soul().ensure).

const FishMindScience = preload("res://scripts/fish_mind_science.gd")
const FishBinding = preload("res://scripts/fish_binding.gd")
const FishCoreAffect = preload("res://scripts/fish_core_affect.gd")
const FishFeltNow = preload("res://scripts/fish_felt_now.gd")
const FishRelevance = preload("res://scripts/fish_relevance.gd")
const FishProtoself = preload("res://scripts/fish_protoself.gd")
const FishContinuity = preload("res://scripts/fish_continuity.gd")
const FishVolition = preload("res://scripts/fish_volition.gd")
const MindSoulPass2 = preload("res://scripts/mind_soul_pass2.gd")
const MindKeeperModel = preload("res://scripts/mind_keeper_model.gd")
const MindActiveInference = preload("res://scripts/mind_active_inference.gd")
const MindWorldModel = preload("res://scripts/mind_world_model.gd")
const EpisodicMemory = preload("res://scripts/episodic_memory.gd")
const KeeperInput = preload("res://scripts/keeper_input.gd")
const FishGenerativeSelf = preload("res://scripts/fish_generative_self.gd")

static var _mind_soul_script: GDScript = null
static var _fish_mind_script: GDScript = null


static func _mind_soul() -> GDScript:
	if _mind_soul_script == null:
		_mind_soul_script = load("res://scripts/mind_soul.gd") as GDScript
	return _mind_soul_script


static func _fish_mind() -> GDScript:
	if _fish_mind_script == null:
		_fish_mind_script = load("res://scripts/fish_mind.gd") as GDScript
	return _fish_mind_script


static func enabled() -> bool:
	return _mind_soul().enabled() and MindAblation.enabled(MindAblation.SOUL)


static func ensure_fields(s: Dictionary) -> Dictionary:
	s = MindSoulPass2.ensure_fields(s)
	if s.get("character_arc") == null:
		s["character_arc"] = "forming"
	if s.get("value_drift") == null or not (s["value_drift"] is Dictionary):
		s["value_drift"] = {"novelty": 0.5, "safety": 0.5, "social": 0.5}
	if s.get("affect_setpoint") == null:
		s["affect_setpoint"] = {"valence": 0.15, "arousal": 0.35}
	if s.get("biography") == null or not (s["biography"] is Dictionary):
		s["biography"] = {"lines": [], "turning_points": []}
	if s.get("tank_theme") == null:
		s["tank_theme"] = ""
	if s.get("pci_cache") == null:
		s["pci_cache"] = 0.0
	if s.get("us_partner") == null:
		s["us_partner"] = ""
	if s.get("legacy_marks") == null or not (s["legacy_marks"] is Array):
		s["legacy_marks"] = []
	if s.get("vicarious_ema") == null:
		s["vicarious_ema"] = 0.0
	if s.get("endogenous_goal") == null:
		s["endogenous_goal"] = ""
	if s.get("relief_pulse") == null:
		s["relief_pulse"] = 0.0
	if s.get("felt_survey_t") == null:
		s["felt_survey_t"] = 0.0
	return s


static func tick(f, sim, _ms, dt: float) -> void:
	if not enabled():
		return
	var s: Dictionary = ensure_fields(_mind_soul().ensure(f))
	_tick_affect_setpoint(f, s, dt)
	_tick_value_drift(f, s, dt)
	_tick_character_arc(f, s)
	_tick_illness_malaise(f, dt)
	_tick_keeper_absence(f, sim, dt)
	_tick_reconciliation(f, sim, dt)
	_tick_empathy_mirror(f, sim, dt)
	_tick_watched(f, sim, dt)
	_tick_relief_derivative(f, s, dt)
	_tick_vicarious_rest(f, s, dt)
	_tick_endogenous_goal(f, s, sim, dt)
	_tick_volition_costs(f, dt)
	_tick_play(f, sim, dt)
	_tick_tank_theme(f, s, sim)
	_tick_felt_survey(f, s, sim, dt)
	_update_pci(f, s)
	f._soul_mind = s


static func after_broadcast(f, ms, _sim) -> void:
	if not enabled() or ms == null:
		return
	# §C26 — ignited workspace colours the whole cycle's readouts.
	if not ms.workspace_ignited:
		return
	var focus: String = ms.attention_focus
	if focus == "":
		return
	var tone: float = FishCoreAffect.tone_for_label(f, focus)
	f.mood = clampf(f.mood + tone * 0.04, -1.0, 1.0)
	if focus in ["threat", "food", "mate"]:
		f.arousal = clampf(f.arousal + absf(tone) * 0.03, 0.0, 1.0)


static func on_sleep_consolidate(f) -> void:
	if not enabled():
		return
	var s: Dictionary = ensure_fields(_mind_soul().ensure(f))
	# §C34 — sleep re-tunes cross-module coupling via integration thread.
	var ct: Dictionary = FishContinuity.ensure(f)
	ct["thread"] = clampf(float(ct.get("thread", 1.0)) + 0.06, 0.0, 1.0)
	(f._felt_self as Dictionary)["continuity"] = ct
	# §D39 — dream recombination: merge two episode kinds into a semantic hint.
	var store: Array = EpisodicMemory.ensure_store(f)
	if store.size() >= 2 and MindRng.for_fish(f).randf() < 0.35:
		var a: Dictionary = store[MindRng.for_fish(f).randi() % store.size()]
		var b: Dictionary = store[(MindRng.for_fish(f).randi() + 1) % store.size()]
		var mix: String = "%s near %s" % [str(a.get("kind", "")), str(b.get("kind", ""))]
		if mix != " near " and not f.semantic_memory.has(mix):
			f.semantic_memory.append("dream-mix: %s" % mix.substr(0, 48))
			while f.semantic_memory.size() > 16:
				f.semantic_memory.pop_front()
	_replay_vicarious(f, s)
	f._soul_mind = s


static func on_witness_death(f, dead: Fish, sim) -> void:
	if not enabled() or dead == null:
		return
	var oid: String = str(dead.id)
	if not f.bonds.has(oid) or float(f.bonds[oid]) < 0.35:
		return
	var s: Dictionary = ensure_fields(_mind_soul().ensure(f))
	f.stress = clampf(f.stress + 0.12, 0.0, 1.0)
	f.mood = clampf(f.mood - 0.1, -1.0, 1.0)
	f._longing_residue = clampf(float(f.get("_longing_residue") if f.get("_longing_residue") != null else 0.0) + 0.28, 0.0, 1.0)
	_fish_mind().record_salient(f, "loss", "the water feels emptier", 0.58, f.position)
	_append_turning_point(s, "witnessed_loss", "since then, the tank feels thinner")
	f._soul_mind = s
	if sim != null and sim.has_method("append_fish_journal_entry"):
		sim.append_fish_journal_entry(f, "someone gone from the water",
				PackedStringArray(["grief", "witness"]))


static func on_fish_death_legacy(dead: Fish, survivors: Array) -> void:
	if not enabled() or dead == null:
		return
	var s_dead: Dictionary = _mind_soul().ensure(dead)
	var habits: Dictionary = s_dead.get("habits", {})
	for surv in survivors:
		if not is_instance_valid(surv) or not (surv is Fish) or surv == dead:
			continue
		var f: Fish = surv
		var oid: String = str(dead.id)
		if not f.bonds.has(oid) or float(f.bonds[oid]) < 0.4:
			continue
		var s: Dictionary = ensure_fields(_mind_soul().ensure(f))
		var marks: Array = s.get("legacy_marks", [])
		var name: String = str(dead.fish_name if dead.fish_name != "" else dead.species)
		marks.append("learned from %s" % name)
		while marks.size() > 6:
			marks.pop_front()
		s["legacy_marks"] = marks
		for ctx in habits.keys():
			var h: Dictionary = habits[ctx]
			if float(h.get("strength", 0.0)) > 0.55:
				var fh: Dictionary = s.get("habits", {})
				fh[ctx] = {"label": str(h.get("label", "")), "strength": float(h["strength"]) * 0.35, "uses": 0}
				s["habits"] = fh
				break
		f._soul_mind = s


static func inherit_learned_values(child: Fish, parent: Fish) -> void:
	if not enabled() or parent == null or child == null:
		return
	var ps: Dictionary = ensure_fields(_mind_soul().ensure(parent))
	var cs: Dictionary = ensure_fields(_mind_soul().ensure(child))
	var vd: Dictionary = ps.get("value_drift", {})
	for k in vd.keys():
		var pv: float = float(vd[k])
		var cv: Dictionary = cs.get("value_drift", {})
		cv[k] = lerpf(float(cv.get(k, 0.5)), pv, 0.25)
		cs["value_drift"] = cv
	child._soul_mind = cs


static func continuity_on_restore(f, snap: Dictionary) -> void:
	if not enabled():
		return
	var ct: Dictionary = FishContinuity.ensure(f)
	var ok: bool = true
	if snap.has("mood") and absf(f.mood - float(snap.get("mood", f.mood))) > 0.35:
		ok = false
	if snap.has("familiarity") and absf(f.familiarity - float(snap.get("familiarity", f.familiarity))) > 0.4:
		ok = false
	ct["still_me"] = ok
	ct["fractured"] = not ok
	if not ok:
		ct["away_pickup"] = "something shifted in the quiet"
	(f._felt_self as Dictionary)["continuity"] = ct


static func pci_score(f) -> float:
	if not enabled():
		return 0.0
	var s: Dictionary = ensure_fields(_mind_soul().ensure(f))
	return float(s.get("pci_cache", 0.0))


static func perturb_and_measure(f) -> float:
	if not enabled():
		return 0.0
	if not FishBinding.layer_enabled():
		return 0.35
	FishProtoself.ensure(f)
	FishCoreAffect.ensure(f)
	FishFeltNow.ensure(f)
	FishRelevance.ensure(f)
	var base_phi: float = float(FishBinding.bind_moment(f, null, 0.05).get("phi_proxy", 0.0))
	var saved_stress: float = f.stress
	f.stress = clampf(maxf(f.stress, 0.72) + 0.2, 0.0, 1.0)
	FishCoreAffect.tick(f, null, 0.05)
	FishProtoself.tick(f, null, 0.05)
	var phi2: float = float(FishBinding.bind_moment(f, null, 0.05).get("phi_proxy", 0.0))
	f.stress = saved_stress
	FishCoreAffect.tick(f, null, 0.05)
	FishProtoself.tick(f, null, 0.05)
	return clampf(absf(phi2 - base_phi) * 3.5, 0.0, 1.0)


static func collect_extra_bids(f, sim) -> Array:
	if not enabled():
		return []
	var out: Array = []
	var emp: Dictionary = empowerment_bid(f, sim)
	if not emp.is_empty():
		out.append(emp)
	var eg: Dictionary = endogenous_bid(f)
	if not eg.is_empty():
		out.append(eg)
	var us: Dictionary = us_bid(f, sim)
	if not us.is_empty():
		out.append(us)
	var kp: Dictionary = keeper_predict_bid(f)
	if not kp.is_empty():
		out.append(kp)
	var pl: Dictionary = play_bid(f)
	if not pl.is_empty():
		out.append(pl)
	var teach: Dictionary = teaching_bid(f, sim)
	if not teach.is_empty():
		out.append(teach)
	return out


static func salience_mods(f) -> Dictionary:
	if not enabled():
		return {}
	var mods: Dictionary = {}
	mods.merge(self_consistency_mods(f), true)
	mods.merge(relief_mods(f), true)
	mods.merge(ambivalence_hold(f), true)
	return mods


static func rollout_depth_scale(f) -> float:
	var s: Dictionary = ensure_fields(_mind_soul().ensure(f))
	var reserve: float = float(s.get("mod_reserve", 1.0))
	var conf: float = 1.0
	if f.get("_mind_self_model") is Dictionary:
		conf = float((f._mind_self_model as Dictionary).get("confidence", 1.0))
	return clampf(reserve * conf, 0.2, 1.0)


static func cognitive_map_bias(f) -> Vector3:
	var schemas: Array = f._semantic_schemas if f.get("_semantic_schemas") is Array else []
	var best: Vector3 = Vector3.ZERO
	var best_w: float = 0.0
	for sch in schemas:
		if not sch is Dictionary:
			continue
		var val: float = float((sch as Dictionary).get("valence", 0.0))
		if val <= 0.0:
			continue
		var pos: Variant = (sch as Dictionary).get("center", null)
		if pos is Vector3:
			var w: float = float((sch as Dictionary).get("strength", 0.5))
			if w > best_w:
				best_w = w
				best = (pos as Vector3) - f.position
	if best.length_squared() > 0.01:
		return best.normalized() * clampf(best_w, 0.0, 1.0) * 0.4
	return Vector3.ZERO


static func surface_counterfactual_line(f, _ms) -> String:
	if not enabled():
		return ""
	if f.stress < 0.38 or f.stress > 0.72:
		return ""
	var gap: float = absf(f._delib_approach_s - f._delib_avoid_s) if f.get("_delib_approach_s") != null else 1.0
	if gap > 0.35:
		return ""
	var cf: String = _mind_soul().counterfactual_for(f)
	if cf == "":
		cf = FishGenerativeSelf.protention(f)
	if cf == "":
		return ""
	if MindRng.for_fish(f).randf() > 0.18:
		return ""
	return "almost went %s" % cf


static func biography_for(f) -> Dictionary:
	var s: Dictionary = ensure_fields(_mind_soul().ensure(f))
	var bio: Dictionary = s.get("biography", {})
	var chapters: PackedStringArray = MindSoulPass2.autobiography_lines(f)
	var lines: Array = bio.get("lines", [])
	var out_lines: PackedStringArray = PackedStringArray()
	for ln in lines:
		out_lines.append(str(ln))
	for ch in chapters:
		if not out_lines.has(ch):
			out_lines.append(ch)
	return {
		"arc": str(s.get("character_arc", "")),
		"lines": out_lines,
		"turning_points": (bio.get("turning_points", []) as Array).duplicate(true),
		"legacy_marks": s.get("legacy_marks", []),
		"tank_theme": str(s.get("tank_theme", "")),
	}


static func try_effortful_override(f, dominant: String, chosen: String) -> bool:
	if not enabled() or dominant == chosen:
		return true
	var v: Dictionary = FishVolition.ensure(f)
	var pool: float = float(v.get("will_pool", 1.0))
	if pool < 0.22:
		return false
	v["will_pool"] = pool - 0.18
	v["effort"] = clampf(float(v.get("effort", 0.0)) + 0.2, 0.0, 1.0)
	v["authorship"] = clampf(float(v.get("authorship", 0.0)) + 0.1, 0.0, 1.0)
	v["last_initiated"] = "went against %s" % dominant
	(f._felt_self as Dictionary)["volition"] = v
	return true


static func record_veto(f, sim) -> void:
	if not enabled():
		return
	_fish_mind().record_salient(f, "self", "stopped myself", 0.42, f.position)
	if sim != null and sim.has_method("append_fish_journal_entry"):
		sim.append_fish_journal_entry(f, "stopped myself", PackedStringArray(["volition", "veto"]))


static func hard_choice_line(f) -> String:
	if not enabled():
		return ""
	var v: Dictionary = FishVolition.ensure(f)
	if float(v.get("effort", 0.0)) < 0.45:
		return ""
	var gap: float = absf(float(f.get("_delib_approach_s") if f.get("_delib_approach_s") != null else 0.0)
			- float(f.get("_delib_avoid_s") if f.get("_delib_avoid_s") != null else 0.0))
	if gap > 0.25:
		return ""
	return "had to choose"


static func episode_usefulness_weight(e: Dictionary) -> float:
	var w: float = SaveHelpers._num(e.get("weight", 0.5), 0.5)
	var sal: float = SaveHelpers._num(e.get("salience", w), w)
	var surprise: float = SaveHelpers._num(e.get("surprise", 0.0), 0.0)
	return w * (1.0 + sal * 0.35 + surprise * 0.25)


static func empowerment_bid(f, _sim) -> Dictionary:
	if f.stress > 0.55:
		return {}
	var openness: float = 1.0 - clampf(f.spooked + f.stress * 0.4, 0.0, 1.0)
	if openness < 0.35:
		return {}
	return {"label": "explore", "salience": openness * 0.32 + f.curiosity_drive * 0.2,
			"coalition": ["novelty", "empowerment"]}


static func endogenous_bid(f) -> Dictionary:
	var s: Dictionary = ensure_fields(_mind_soul().ensure(f))
	var goal: String = str(s.get("endogenous_goal", ""))
	if goal == "":
		return {}
	return {"label": "novelty", "salience": 0.38 + f.curiosity_drive * 0.25,
			"coalition": ["explore", "endogenous", goal]}


static func us_bid(f, sim) -> Dictionary:
	if sim == null or sim.get("fish") == null:
		return {}
	var s: Dictionary = ensure_fields(_mind_soul().ensure(f))
	var partner_id: String = str(s.get("us_partner", ""))
	if partner_id == "":
		for oid in f.bonds.keys():
			if float(f.bonds[oid]) > 0.62:
				partner_id = str(oid)
				s["us_partner"] = partner_id
				f._soul_mind = s
				break
	if partner_id == "":
		return {}
	for other in sim.fish:
		if not is_instance_valid(other) or str(other.id) != partner_id:
			continue
		var d: float = f.position.distance_to(other.position)
		if d > 5.0:
			return {"label": "mate", "salience": float(f.bonds[partner_id]) * 0.45,
					"coalition": ["social", "us", "bond"]}
		break
	return {}


static func keeper_predict_bid(f) -> Dictionary:
	var km: Dictionary = MindKeeperModel.ensure(f)
	var trust: float = float(km.get("care_trust", 0.3))
	if trust < 0.45:
		return {}
	if KeeperInput.gaze_fish_id == str(f.id) and KeeperInput.gaze_seconds > 2.0:
		return {"label": "food", "salience": trust * 0.35,
				"coalition": ["keeper", "food", "predict"]}
	return {}


static func play_bid(f) -> Dictionary:
	if f.maturity != Fish.MATURITY_FRY and f.age > 60.0:
		return {}
	if f.stress > 0.35 or f.hunger > 0.55:
		return {}
	if MindRng.for_fish(f).randf() > 0.04:
		return {}
	return {"label": "novelty", "salience": 0.28 + f.curiosity_drive * 0.3,
			"coalition": ["play", "novelty"]}


static func teaching_bid(f, sim) -> Dictionary:
	if sim == null or sim.get("fish") == null:
		return {}
	for other in sim.fish:
		if not is_instance_valid(other) or not (other is Fish) or other == f:
			continue
		if other.familiarity > f.familiarity + 0.25 and other.hunger < 0.35:
			var d: float = f.position.distance_to(other.position)
			if d < 6.0 and MindRng.for_fish(f).randf() < 0.15:
				return {"label": "food", "salience": 0.22,
						"coalition": ["social", "teaching", "food"]}
	return {}


static func self_consistency_mods(f) -> Dictionary:
	var s: Dictionary = ensure_fields(_mind_soul().ensure(f))
	var arc: String = str(s.get("character_arc", ""))
	var mods: Dictionary = {}
	if arc == "bold":
		mods["novelty"] = 0.06
		mods["threat"] = -0.04
	elif arc == "cautious":
		mods["threat"] = 0.06
		mods["food"] = 0.03
	return mods


static func relief_mods(f) -> Dictionary:
	var s: Dictionary = ensure_fields(_mind_soul().ensure(f))
	var pulse: float = float(s.get("relief_pulse", 0.0))
	if pulse < 0.2:
		return {}
	return {"rest": pulse * 0.25, "interoception": -pulse * 0.1}


static func ambivalence_hold(f) -> Dictionary:
	var a: float = float(f.get("_delib_approach_s") if f.get("_delib_approach_s") != null else 0.0)
	var v: float = float(f.get("_delib_avoid_s") if f.get("_delib_avoid_s") != null else 0.0)
	if absf(a - v) > 0.12 or maxf(a, v) < 0.35:
		return {}
	return {"food": -0.04, "threat": -0.04}


static func _tick_affect_setpoint(f, s: Dictionary, dt: float) -> void:
	var sp: Dictionary = s.get("affect_setpoint", {})
	var dev: float = absf(FishCoreAffect.valence(f) - float(sp.get("valence", 0.15)))
	if dev > 0.35:
		f.curiosity_drive = clampf(f.curiosity_drive + dt * 0.02, 0.0, 1.0)


static func _tick_value_drift(f, s: Dictionary, dt: float) -> void:
	var vd: Dictionary = s.get("value_drift", {})
	var focus: String = f.attention_focus
	if focus in ["novelty", "explore", "free_energy"]:
		vd["novelty"] = clampf(float(vd.get("novelty", 0.5)) + dt * 0.015, 0.0, 1.0)
	elif focus in ["threat", "safety"]:
		vd["safety"] = clampf(float(vd.get("safety", 0.5)) + dt * 0.012, 0.0, 1.0)
	elif focus in ["mate", "player", "social"]:
		vd["social"] = clampf(float(vd.get("social", 0.5)) + dt * 0.01, 0.0, 1.0)
	s["value_drift"] = vd


static func _tick_character_arc(_f, s: Dictionary) -> void:
	var vd: Dictionary = s.get("value_drift", {})
	if float(vd.get("novelty", 0.5)) > 0.68:
		s["character_arc"] = "bold"
	elif float(vd.get("safety", 0.5)) > 0.65:
		s["character_arc"] = "cautious"
	elif float(vd.get("social", 0.5)) > 0.62:
		s["character_arc"] = "bonded"


static func _tick_illness_malaise(f, dt: float) -> void:
	var ill: float = 0.0
	if f.get("disease_stress") != null:
		ill = clampf(float(f.disease_stress), 0.0, 1.0)
	elif f.get("_sick") == true:
		ill = 0.5
	if ill < 0.2:
		return
	f.stress = clampf(f.stress + ill * dt * 0.08, 0.0, 1.0)
	f.arousal = clampf(f.arousal - ill * dt * 0.06, 0.0, 1.0)
	f.mood = clampf(f.mood - ill * dt * 0.05, -1.0, 1.0)
	var pb: Dictionary = FishProtoself.ensure(f)
	pb["pain"] = clampf(float(pb.get("pain", 0.0)) + ill * 0.15, 0.0, 1.0)
	(f._felt_self as Dictionary)["protoself"] = pb


static func _tick_keeper_absence(f, _sim, dt: float) -> void:
	var km: Dictionary = MindKeeperModel.ensure(f)
	var gap: int = int(km.get("last_absence_s", 0))
	if gap < 86400:
		return
	f._longing_residue = clampf(float(f.get("_longing_residue") if f.get("_longing_residue") != null else 0.0)
			+ dt * 0.004, 0.0, 1.0)


static func _tick_reconciliation(f, sim, dt: float) -> void:
	if f.grudges.is_empty():
		return
	for oid in f.grudges.keys():
		var g: float = float(f.grudges[oid])
		if g < 0.55:
			f.grudges[oid] = maxf(0.0, g - dt * 0.002)
		elif sim != null and sim.get("fish") != null:
			for other in sim.fish:
				if is_instance_valid(other) and str(other.id) == str(oid):
					if f.position.distance_to(other.position) < 3.0 and g < 0.85:
						f.grudges[oid] = maxf(0.0, g - dt * 0.008)
					break


static func _tick_empathy_mirror(f, sim, dt: float) -> void:
	if sim == null or sim.get("fish") == null:
		return
	for other in sim.fish:
		if not is_instance_valid(other) or not (other is Fish) or other == f:
			continue
		var oid: String = str(other.id)
		if not f.bonds.has(oid) or float(f.bonds[oid]) < 0.4:
			continue
		if other.stress < 0.55:
			continue
		var d: float = f.position.distance_to(other.position)
		if d > 5.0:
			continue
		var pb: Dictionary = FishProtoself.ensure(f)
		pb["comfort"] = lerpf(float(pb.get("comfort", 0.5)), 1.0 - other.stress * 0.4, dt * 0.4)
		(f._felt_self as Dictionary)["protoself"] = pb
		f.stress = clampf(f.stress + other.stress * dt * 0.03, 0.0, 1.0)
		break


static func _tick_watched(f, _sim, _dt: float) -> void:
	if KeeperInput.gaze_fish_id != str(f.id):
		return
	if KeeperInput.gaze_seconds < 1.5:
		return
	if f._trait("boldness") > 0.55:
		f.speed = clampf(f.speed * 0.92, 0.0, 999.0)
	else:
		f.spooked = clampf(f.spooked + 0.02, 0.0, 1.0)


static func _tick_relief_derivative(f, s: Dictionary, dt: float) -> void:
	var prev_stress: float = float(s.get("_prev_stress_relief", f.stress))
	var delta: float = prev_stress - f.stress
	if delta > 0.08:
		s["relief_pulse"] = clampf(float(s.get("relief_pulse", 0.0)) + delta, 0.0, 1.0)
		if delta > 0.15 and f.mood > -0.2:
			f.mood = clampf(f.mood + 0.06, -1.0, 1.0)
	else:
		s["relief_pulse"] = maxf(0.0, float(s.get("relief_pulse", 0.0)) - dt * 0.15)
	s["_prev_stress_relief"] = f.stress


static func _tick_vicarious_rest(f, s: Dictionary, dt: float) -> void:
	if not f._asleep and f.stress > 0.25:
		return
	var ema: float = float(s.get("vicarious_ema", 0.0))
	ema = lerpf(ema, float(s.get("pe_progress", 0.0)), dt * 0.5)
	s["vicarious_ema"] = ema
	if ema > 0.2:
		var gains: Dictionary = s.get("pragmatic_gain", {})
		for k in gains.keys():
			gains[k] = clampf(float(gains[k]) + ema * 0.01, 0.28, 1.85)
		s["pragmatic_gain"] = gains


static func _replay_vicarious(f, s: Dictionary) -> void:
	_tick_vicarious_rest(f, s, 0.5)


static func _tick_endogenous_goal(f, s: Dictionary, _sim, dt: float) -> void:
	if f.hunger > 0.6 or f.spooked > 0.45:
		s["endogenous_goal"] = ""
		return
	if str(s.get("endogenous_goal", "")) != "":
		return
	if MindRng.for_fish(f).randf() >= dt * 0.02:
		return
	var cell: String = FishMindScience.novelty_cell_key(f)
	if f._hypotheses.has(cell) and str(f._hypotheses[cell].get("guess", "")) == "unknown":
		s["endogenous_goal"] = "visit_%s" % cell


static func _tick_volition_costs(f, dt: float) -> void:
	var v: Dictionary = FishVolition.ensure(f)
	var hold: String = str(v.get("intention_hold", ""))
	if hold != "" and f.current_intention != "" and f.current_intention != hold:
		v["will_pool"] = maxf(0.05, float(v.get("will_pool", 1.0)) - dt * 0.12)
		(f._felt_self as Dictionary)["volition"] = v


static func _tick_play(_f, _sim, _dt: float) -> void:
	pass


static func _tick_tank_theme(_f, s: Dictionary, sim) -> void:
	if sim == null or sim.get("fish") == null:
		return
	var counts: Dictionary = {}
	for other in sim.fish:
		if not is_instance_valid(other) or not (other is Fish):
			continue
		var af: String = other.attention_focus
		if af == "":
			continue
		counts[af] = int(counts.get(af, 0)) + 1
	var top: String = ""
	var top_n: int = 0
	for k in counts.keys():
		if int(counts[k]) > top_n:
			top_n = int(counts[k])
			top = str(k)
	if top != "" and top_n >= 2:
		s["tank_theme"] = "tank dwelling on %s" % top.replace("_", " ")


static func _tick_felt_survey(f, s: Dictionary, sim, dt: float) -> void:
	var t: float = float(s.get("felt_survey_t", 0.0)) + dt
	s["felt_survey_t"] = t
	if t < 120.0 or f.familiarity < 0.55:
		return
	if sim == null or not sim.has_method("append_fish_journal_entry"):
		return
	if MindRng.for_fish(f).randf() > 0.002:
		return
	s["felt_survey_t"] = 0.0
	sim.append_fish_journal_entry(f, "bond note: %.0f%% familiar" % (f.familiarity * 100.0),
			PackedStringArray(["felt_survey", "keeper"]))


static func _update_pci(f, s: Dictionary) -> void:
	s["pci_cache"] = perturb_and_measure(f)


static func _append_turning_point(s: Dictionary, tag: String, line: String) -> void:
	var bio: Dictionary = s.get("biography", {})
	var tps: Array = bio.get("turning_points", [])
	for tp in tps:
		if tp is Dictionary and str((tp as Dictionary).get("tag", "")) == tag:
			return
	tps.append({"tag": tag, "line": line, "t": Time.get_ticks_msec()})
	bio["turning_points"] = tps
	var lines: Array = bio.get("lines", [])
	lines.append(line)
	bio["lines"] = lines
	s["biography"] = bio
