extends RefCounted

# SENTIENCE_THE_SOUL_WE_MAKE — deepen cognition: learned values, metacognition,
# finitude, integration. All state is grounded, seeded, persisted, eval-gated.

const FishMind = preload("res://scripts/fish_mind.gd")
const MindActiveInference = preload("res://scripts/mind_active_inference.gd")
const MindSelfModel = preload("res://scripts/mind_self_model.gd")
const FishBinding = preload("res://scripts/fish_binding.gd")
const FishCoreAffect = preload("res://scripts/fish_core_affect.gd")
const FishProtoself = preload("res://scripts/fish_protoself.gd")
const FishGenerativeSelf = preload("res://scripts/fish_generative_self.gd")
const MindSoulPass2 = preload("res://scripts/mind_soul_pass2.gd")

static var _pass3_script: GDScript = null


static func _pass3() -> GDScript:
	if _pass3_script == null:
		_pass3_script = load("res://scripts/mind_soul_pass3.gd") as GDScript
	return _pass3_script

const SCHEMA_VERSION: int = 1
const DRIVE_LABELS: Array[String] = [
	"food", "threat", "mate", "rest", "interoception", "novelty",
]
const RECURSION_CAP: int = 3


static func enabled() -> bool:
	return FishBinding.layer_enabled()


static func ensure(f) -> Dictionary:
	var existing: Variant = f.get("_soul_mind")
	if existing == null or not (existing is Dictionary):
		var fresh: Dictionary = _fresh_state()
		if f is Object:
			(f as Object).set("_soul_mind", fresh)
		return ensure_fields(fresh)
	var s: Dictionary = (existing as Dictionary).duplicate(true)
	if int(s.get("schema_version", 0)) != SCHEMA_VERSION:
		s = _fresh_state()
		if f is Object:
			(f as Object).set("_soul_mind", s)
		return ensure_fields(s)
	if f is Object:
		(f as Object).set("_soul_mind", s)
	return ensure_fields(s)


static func _fresh_state() -> Dictionary:
	var prag: Dictionary = {}
	var hebb: Dictionary = {}
	var trust: Dictionary = {}
	for lb in DRIVE_LABELS:
		prag[lb] = 1.0
		hebb[lb] = 0.0
		trust[lb] = 0.55
	return ensure_fields({
		"schema_version": SCHEMA_VERSION,
		"pragmatic_gain": prag,
		"bid_hebbian": hebb,
		"drive_trust": trust,
		"drive_outcome_ema": {},
		"self_pred_focus": "",
		"self_pred_error": 0.0,
		"surprise_at_self": 0.0,
		"confidence_volatility": 0.0,
		"prev_confidence": 1.0,
		"recursion_depth": 0,
		"rumination_t": 0.0,
		"pe_progress": 0.0,
		"prev_pe": 0.0,
		"last_commit": {},
		"self_summary_prev": "",
		"pending_outcome": {},
		"expectation_tag": "",
		"expectation_violation": 0.0,
	})


static func ensure_fields(s: Dictionary) -> Dictionary:
	return MindSoulPass2.ensure_fields(s)


static func to_dict(f) -> Dictionary:
	if not enabled() or f.get("_soul_mind") == null:
		return {}
	return (ensure(f) as Dictionary).duplicate(true)


static func from_dict(f, d: Variant) -> void:
	if d is Dictionary and not (d as Dictionary).is_empty():
		f._soul_mind = (d as Dictionary).duplicate(true)
		ensure(f)


static func pragmatic_multiplier(f, label: String) -> float:
	if not enabled() or not MindActiveInference.enabled_for(f):
		return 1.0
	var s: Dictionary = ensure(f)
	var gains: Dictionary = s.get("pragmatic_gain", {})
	var trust: Dictionary = s.get("drive_trust", {})
	var key: String = _drive_key(label)
	var g: float = float(gains.get(key, 1.0))
	var t: float = float(trust.get(key, 0.55))
	return clampf(g * lerpf(0.72, 1.0, t), 0.25, 1.85)


static func epistemic_progress_bonus(f) -> float:
	if not enabled():
		return 0.0
	var s: Dictionary = ensure(f)
	return clampf(float(s.get("pe_progress", 0.0)) * 0.42, 0.0, 0.35)


static func apply_hebbian_mods(f) -> void:
	if not enabled():
		return
	var s: Dictionary = ensure(f)
	var hebb: Dictionary = s.get("bid_hebbian", {})
	var mods: Dictionary = {}
	if f.get("_bid_salience_mods") is Dictionary:
		mods = (f._bid_salience_mods as Dictionary).duplicate(true)
	for lb in hebb.keys():
		var off: float = clampf(float(hebb[lb]), -0.22, 0.28)
		if absf(off) > 0.01:
			mods[str(lb)] = float(mods.get(str(lb), 0.0)) + off
	f._bid_salience_mods = mods


static func self_attend_bid(f) -> Dictionary:
	if not enabled() or f._asleep:
		return {}
	var s: Dictionary = ensure(f)
	var depth: int = int(s.get("recursion_depth", 0))
	var rum: float = float(s.get("rumination_t", 0.0))
	var stress: float = clampf(f.stress + f.spooked * 0.35, 0.0, 1.0)
	var sal: float = stress * 0.38 + rum * 0.22
	if f.attention_focus in ["interoception", "body", "gills", "gut"]:
		sal += 0.12
	if depth >= RECURSION_CAP - 1:
		sal += 0.18
	if sal < 0.28:
		return {}
	return {
		"label": "self_attend",
		"salience": sal,
		"coalition": ["interoception", "body", "self"],
	}


static func predict_self_before_competition(f, ms) -> void:
	if not enabled() or ms == null:
		return
	var s: Dictionary = ensure(f)
	var pred: String = ""
	if f.get("_mind_self_model") is Dictionary:
		pred = str((f._mind_self_model as Dictionary).get("attending_to", ""))
	if pred == "" and f.attention_focus != "":
		pred = f.attention_focus
	s["self_pred_focus"] = pred
	f._soul_mind = s


static func after_workspace_commit(f, ms, sim) -> void:
	if not enabled() or ms == null:
		return
	var s: Dictionary = ensure(f)
	var actual: String = ms.attention_focus if ms != null else f.attention_focus
	var pred: String = str(s.get("self_pred_focus", ""))
	if pred != "" and actual != "":
		var err: float = 0.0 if pred == actual else 1.0
		s["self_pred_error"] = lerpf(float(s.get("self_pred_error", 0.0)), err, 0.35)
		if err > 0.65 and ms.workspace_ignited:
			s["surprise_at_self"] = clampf(float(s.get("surprise_at_self", 0.0)) + 0.22, 0.0, 1.0)
			_try_surprise_at_self_voice(f, sim, pred, actual)
	var pe: Dictionary = MindActiveInference.preferred_error(f)
	s["pending_outcome"] = {
		"label": actual,
		"pe": pe.duplicate(true),
		"t": 0.0,
	}
	if actual in ["self_attend", "interoception", "body"]:
		s["recursion_depth"] = mini(int(s.get("recursion_depth", 0)) + 1, RECURSION_CAP)
		s["rumination_t"] = clampf(float(s.get("rumination_t", 0.0)) + 0.35, 0.0, 1.0)
	else:
		s["recursion_depth"] = maxi(0, int(s.get("recursion_depth", 0)) - 1)
		s["rumination_t"] = maxf(0.0, float(s.get("rumination_t", 0.0)) - 0.08)
	_record_eligibility(f, actual)
	MindSoulPass2.after_commit(f, ms, sim, actual)
	_pass3().after_broadcast(f, ms, sim)
	f._soul_mind = s


static func tick(f, sim: Node, ms, dt: float) -> void:
	if not enabled():
		return
	var s: Dictionary = ensure(f)
	_tick_confidence_volatility(f, s, ms, dt)
	_tick_learning_outcomes(f, s, dt)
	_tick_prediction_progress(f, s, dt)
	_tick_expectation_violation(f, s, dt)
	_tick_self_summary_delta(f, s, sim)
	_decay_surprise_at_self(s, dt)
	_apply_metacognitive_ddm(f, s, sim)
	MindSoulPass2.tick(f, sim, ms, dt)
	_pass3().tick(f, sim, ms, dt)
	f._soul_mind = s


static func mortality_shift(f) -> Dictionary:
	var life_frac: float = clampf(f.age / maxf(f.max_age_s, 1.0), 0.0, 1.0)
	var vitality: float = 1.0
	if f.get("energy") != null:
		vitality = clampf(float(f.energy), 0.0, 1.0)
	var decline: float = clampf(life_frac * 0.65 + (1.0 - vitality) * 0.45, 0.0, 1.0)
	return {
		"decline": decline,
		"risk_scale": lerpf(1.0, 0.62, decline),
		"bond_scale": lerpf(1.0, 1.35, decline * 0.85),
		"patience": lerpf(1.0, 0.55, decline),
	}


static func counterfactual_for(f) -> String:
	if not enabled():
		return ""
	var open_ahead: bool = f.stress < 0.42 and f._trait("boldness") > 0.52
	var cover: bool = f.stress > 0.48 or f._trait("boldness") < 0.42
	if f.hunger > 0.62 and open_ahead:
		return "open water toward food"
	if cover and f.spooked > 0.35:
		return "stay near cover"
	if open_ahead:
		return "open water ahead"
	if cover:
		return "stay near cover"
	return ""


static func introspection_report(f, ms, query: String) -> String:
	var q: String = query.to_lower()
	if q.contains("think") or q.contains("attention") or q.contains("mind"):
		if ms != null and ms.workspace_ignited and not ms.workspace.is_empty():
			var labels: PackedStringArray = PackedStringArray()
			for b in ms.workspace:
				if b is Dictionary:
					labels.append(str((b as Dictionary).get("label", "")))
			if labels.size() > 0:
				return "attending: %s" % ", ".join(labels)
		if f.attention_focus != "":
			return "attending: %s" % f.attention_focus
		return "nothing clear right now"
	if q.contains("feel") and q.contains("that"):
		var tex: String = FishCoreAffect.texture(f) if FishBinding.layer_enabled() else ""
		if tex != "":
			return tex
	if q.contains("why") and (q.contains("feel") or q.contains("did")):
		var s: Dictionary = ensure(f)
		if float(s.get("surprise_at_self", 0.0)) > 0.35:
			return "not sure — surprised myself"
		if ms == null or not ms.workspace_ignited:
			return "don't know why"
	return ""


static func integration_cross_talk(f, _dt: float) -> float:
	if not enabled():
		return 0.0
	var affect: float = clampf(absf(FishCoreAffect.valence(f)) + f.arousal * 0.5, 0.0, 1.0)
	var body: float = 0.0
	var pb: Dictionary = FishProtoself.ensure(f)
	if not pb.is_empty():
		body = clampf(1.0 - float(pb.get("comfort", 0.5)), 0.0, 1.0)
	var attn: float = 1.0 if f._workspace_ignited else 0.35
	var held: float = 1.0
	if f.get("_felt_self") is Dictionary:
		var fn: Dictionary = (f._felt_self as Dictionary).get("felt_now", {})
		if fn is Dictionary:
			held = clampf(float((fn as Dictionary).get("present_width", 1.0)) / 1.35, 0.35, 1.0)
	var agree: float = 1.0 - absf(affect - body)
	return clampf(agree * attn * held * (0.55 + float(ensure(f).get("pe_progress", 0.0)) * 0.45), 0.0, 1.0)


static func ddm_threshold_scale(f) -> float:
	if not enabled():
		return 1.0
	var s: Dictionary = ensure(f)
	var trust_mean: float = 0.55
	var trust: Dictionary = s.get("drive_trust", {})
	if not trust.is_empty():
		var sum: float = 0.0
		for k in trust.keys():
			sum += float(trust[k])
		trust_mean = sum / float(trust.size())
	var vol: float = float(s.get("confidence_volatility", 0.0))
	return clampf(lerpf(0.88, 1.28, vol) * lerpf(1.12, 0.92, trust_mean), 0.75, 1.45)


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


static func _record_eligibility(f, label: String) -> void:
	var key: String = _drive_key(label)
	var trace: float = float(f.get("_td_eligibility_peak") if f.get("_td_eligibility_peak") != null else 0.0)
	trace = trace * 0.86 + 1.0
	f._td_eligibility_peak = trace
	var s: Dictionary = ensure(f)
	var hebb: Dictionary = s.get("bid_hebbian", {})
	hebb[key] = float(hebb.get(key, 0.0))
	s["bid_hebbian"] = hebb
	f._soul_mind = s


static func _tick_learning_outcomes(f, s: Dictionary, dt: float) -> void:
	var pending: Variant = s.get("pending_outcome", null)
	if not pending is Dictionary or (pending as Dictionary).is_empty():
		return
	var p: Dictionary = pending as Dictionary
	p["t"] = float(p.get("t", 0.0)) + dt
	if float(p["t"]) < 0.18:
		s["pending_outcome"] = p
		return
	var label: String = _drive_key(str(p.get("label", "")))
	var before: Dictionary = p.get("pe", {})
	var after: Dictionary = MindActiveInference.preferred_error(f)
	var delta: float = _pe_improvement(before, after, label)
	var ema: Dictionary = s.get("drive_outcome_ema", {})
	var old: float = float(ema.get(label, 0.0))
	var nudged: float = lerpf(old, delta, clampf(dt * 2.2, 0.05, 0.45))
	ema[label] = nudged
	s["drive_outcome_ema"] = ema
	var gains: Dictionary = s.get("pragmatic_gain", {})
	gains[label] = clampf(0.42 + (nudged + 0.5) * 1.1, 0.28, 1.85)
	s["pragmatic_gain"] = gains
	var trust: Dictionary = s.get("drive_trust", {})
	trust[label] = clampf(float(trust.get(label, 0.55)) + delta * 0.12, 0.12, 0.95)
	s["drive_trust"] = trust
	var hebb: Dictionary = s.get("bid_hebbian", {})
	var trace: float = float(f.get("_td_eligibility_peak") if f.get("_td_eligibility_peak") != null else 1.0)
	hebb[label] = clampf(float(hebb.get(label, 0.0)) + delta * 0.04 * trace, -0.22, 0.28)
	s["bid_hebbian"] = hebb
	f._td_eligibility_peak = trace * 0.9
	s["pending_outcome"] = {}


static func _pe_improvement(before: Dictionary, after: Dictionary, label: String) -> float:
	var key: String = "hunger"
	match label:
		"food":
			key = "hunger"
		"threat":
			key = "safety"
		"mate":
			key = "social"
		"rest":
			key = "rest"
		_:
			key = "hunger"
	var b: float = float(before.get(key, 0.5))
	var a: float = float(after.get(key, 0.5))
	return clampf(b - a, -1.0, 1.0)


static func _tick_prediction_progress(f, s: Dictionary, dt: float) -> void:
	var pe: float = float(f.get("_prediction_error") if f.get("_prediction_error") != null else 0.0)
	var prev: float = float(s.get("prev_pe", pe))
	var progress: float = clampf((prev - pe) / maxf(prev, 0.08), -1.0, 1.0)
	s["pe_progress"] = lerpf(float(s.get("pe_progress", 0.0)), maxf(0.0, progress), clampf(dt * 1.8, 0.0, 1.0))
	s["prev_pe"] = pe


static func _tick_confidence_volatility(f, s: Dictionary, ms, dt: float) -> void:
	var conf: float = 1.0
	if f.get("_mind_self_model") is Dictionary:
		conf = float((f._mind_self_model as Dictionary).get("confidence", 1.0))
	var prev: float = float(s.get("prev_confidence", conf))
	var vol: float = float(s.get("confidence_volatility", 0.0))
	vol = lerpf(vol, absf(conf - prev), clampf(dt * 1.4, 0.0, 1.0))
	s["confidence_volatility"] = vol
	s["prev_confidence"] = conf
	if ms != null and f.get("_mind_self_model") is Dictionary:
		var sm: Dictionary = f._mind_self_model as Dictionary
		sm["confidence_volatility"] = snappedf(vol, 0.01)
		sm["second_order_doubt"] = vol > 0.22 and conf < 0.55
		f._mind_self_model = sm


static func _tick_expectation_violation(f, s: Dictionary, dt: float) -> void:
	var tag: String = str(s.get("expectation_tag", ""))
	if tag == "":
		return
	var violated: bool = false
	if tag == "feed" and f.hunger > 0.55:
		violated = true
	if tag == "safety" and f.spooked > 0.45:
		violated = true
	var v: float = float(s.get("expectation_violation", 0.0))
	if violated:
		v = clampf(v + dt * 0.45, 0.0, 1.0)
	else:
		v = maxf(0.0, v - dt * 0.25)
	s["expectation_violation"] = v
	if v > 0.55:
		f.surprise = clampf(f.surprise + dt * 0.12, 0.0, 1.0)


static func set_expectation(f, tag: String) -> void:
	if not enabled():
		return
	var s: Dictionary = ensure(f)
	s["expectation_tag"] = tag
	s["expectation_violation"] = 0.0
	f._soul_mind = s


static func _tick_self_summary_delta(f, s: Dictionary, sim: Node) -> void:
	var prev: String = str(s.get("self_summary_prev", ""))
	var cur_frag: String = _self_delta_fragment(f, s)
	if cur_frag == "":
		return
	if prev.contains(cur_frag):
		return
	s["self_summary_prev"] = cur_frag
	MindSelfModel.update_self_summary(f, cur_frag, sim)


static func _self_delta_fragment(f, s: Dictionary) -> String:
	if float(s.get("pe_progress", 0.0)) > 0.35:
		return "learning this tank"
	if float(s.get("surprise_at_self", 0.0)) > 0.4:
		return "surprised by my own turn"
	if int(s.get("recursion_depth", 0)) >= RECURSION_CAP:
		return "caught in my own loops"
	var mort: Dictionary = mortality_shift(f)
	if float(mort.get("decline", 0.0)) > 0.72:
		return "not what I was"
	if f.stress > 0.7 and float(s.get("rumination_t", 0.0)) > 0.5:
		return "turned inward"
	return ""


static func _decay_surprise_at_self(s: Dictionary, dt: float) -> void:
	s["surprise_at_self"] = maxf(0.0, float(s.get("surprise_at_self", 0.0)) - dt * 0.08)


static func _apply_metacognitive_ddm(f, s: Dictionary, _sim: Node) -> void:
	f._learning_rate_mult = clampf(
		lerpf(1.0, 0.55, float(s.get("confidence_volatility", 0.0))), 0.45, 1.15)


static func _try_surprise_at_self_voice(f, sim: Node, pred: String, actual: String) -> void:
	if f.fish_name == "" and not f.is_guardian and f.familiarity < 0.5:
		return
	if MindRng.for_fish(f).randf() > 0.22:
		return
	var line: String = "expected %s, went to %s instead" % [pred, actual]
	FishMind.record_salient(f, "self", line, 0.38, f.position)
	if sim != null and sim.has_method("append_fish_journal_entry"):
		sim.append_fish_journal_entry(f, line, PackedStringArray(["metacognition", "surprise_at_self"]))
