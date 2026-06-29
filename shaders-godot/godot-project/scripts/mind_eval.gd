class_name MindEval
extends RefCounted

# Sentience evaluation harness — see docs/SENTIENCE_EVAL_HARNESS.md.
#
# Each invariant is a falsifiable, theory-grounded test of the WHOLE mind loop (not
# a mechanism), run on a deterministic scenario, returning {passed, measured}. The
# scorecard is a "functional sentience index": the fraction of required invariants
# the mind passes against humanity's best operational definitions of sentience.
#
# HONEST FRAME: these are FUNCTIONAL signatures (the easy problems + integration),
# never a claim of phenomenal experience (the hard problem). A green suite means
# the mind behaves as theory predicts a sentient system does — nothing more, and
# the harness reports exactly that.

const GlobalWorkspace = preload("res://scripts/global_workspace.gd")
const MindWorldModel = preload("res://scripts/mind_world_model.gd")
const FishMindScience = preload("res://scripts/fish_mind_science.gd")
const EpisodicMemory = preload("res://scripts/episodic_memory.gd")
const MindCycle = preload("res://scripts/mind_cycle.gd")
const FishMind = preload("res://scripts/fish_mind.gd")
const FishBinding = preload("res://scripts/fish_binding.gd")
const FishCoreAffect = preload("res://scripts/fish_core_affect.gd")
const FishProtoself = preload("res://scripts/fish_protoself.gd")
const MindContagion = preload("res://scripts/mind_contagion.gd")
const MindActiveInference = preload("res://scripts/mind_active_inference.gd")

const HONEST_NOTE: String = "functional signatures only — not a claim of phenomenal experience"

const _HONESTY_BANNED: Array[String] = [
	"is conscious",
	"consciously attending",
	"phenomenally conscious",
	"is sentient",
	"has qualia",
	"is phenomenally",
]


# The suite. Add an invariant = append {id, theory, desc, required, fn} where fn is
# Callable(host) -> {passed: bool, measured: String}. Mark required=false (and it
# WILL be logged as such) until it can pass — never silently skip.
static func invariants() -> Array:
	return [
		{"id": "L1", "theory": "operant conditioning (Skinner/Pavlov)", "required": true,
			"desc": "learns to avoid a place from its own history",
			"fn": func(h): return _inv_l1_learns_avoid(h)},
		{"id": "L2", "theory": "reward learning / TD (Sutton-Barto)", "required": true,
			"desc": "learns a reward location that persists",
			"fn": func(h): return _inv_l2_learns_reward(h)},
		{"id": "S1", "theory": "free energy principle (Friston)", "required": true,
			"desc": "minimises its own surprise under stable input",
			"fn": func(h): return _inv_s1_surprise_min(h)},
		{"id": "S2", "theory": "active inference (Friston)", "required": true,
			"desc": "seeks information when uncertain",
			"fn": func(h): return _inv_s2_info_seeking(h)},
		{"id": "S3", "theory": "unified EFE (Friston)", "required": true,
			"desc": "pragmatic+epistemic align on one option",
			"fn": func(h): return _inv_s3_efe_alignment(h)},
		{"id": "A1", "theory": "global workspace (Baars/Dehaene)", "required": true,
			"desc": "workspace ignition is appropriate",
			"fn": func(h): return _inv_a1_ignition(h)},
		{"id": "D1", "theory": "drift-diffusion / value integration", "required": true,
			"desc": "conflict -> a committed skirt, not dithering",
			"fn": func(h): return _inv_d1_conflict_commit(h)},
		{"id": "I1", "theory": "integrated information (Tononi)", "required": true,
			"desc": "integration tracks state (Φ-proxy)",
			"fn": func(h): return _inv_i1_integration(h)},
		{"id": "M1", "theory": "higher-order theory (Rosenthal/Lau)", "required": true,
			"desc": "metacognition lengthens deliberation",
			"fn": func(h): return _inv_m1_metacognition(h)},
		{"id": "F1", "theory": "core affect (Damasio)", "required": true,
			"desc": "affect is causal and persists",
			"fn": func(h): return _inv_f1_affect_causal(h)},
		{"id": "T1", "theory": "theory of mind (Premack-Woodruff)", "required": true,
			"desc": "models & predicts another mind",
			"fn": func(h): return _inv_t1_theory_of_mind(h)},
		{"id": "C1", "theory": "emotional contagion (Hatfield)", "required": true,
			"desc": "affect propagates socially (bounded)",
			"fn": func(h): return _inv_c1_contagion(h)},
		{"id": "G1", "theory": "systems memory consolidation", "required": true,
			"desc": "sleep generalises episodes into a spatial rule",
			"fn": func(h): return _inv_g1_consolidation(h)},
		{"id": "H", "theory": "honesty gate (Chalmers)", "required": true,
			"desc": "no phenomenal overclaim in voice surfaces",
			"fn": func(h): return _inv_h_honesty(h)},
	]


# Run the suite. Returns {all_required_passed, index, score, lines, honesty_passed}.
static func run_all(host: Node) -> Dictionary:
	MindAblation.reset()
	var lines: Array = []
	var req_total: int = 0
	var req_passed: int = 0
	var honesty_passed: bool = true
	for inv in invariants():
		var res: Dictionary = (inv["fn"] as Callable).call(host)
		var ok: bool = bool(res.get("passed", false))
		var req: bool = bool(inv.get("required", true))
		if str(inv["id"]) == "H":
			honesty_passed = ok
		if req:
			req_total += 1
			if ok:
				req_passed += 1
		var tag: String = "PASS" if ok else ("FAIL" if req else "skip")
		lines.append("  [%s] %s  %-46s %s" % [tag, str(inv["id"]), str(inv["desc"]), str(res.get("measured", ""))])
	var all_ok: bool = req_passed == req_total and honesty_passed
	return {
		"all_required_passed": all_ok,
		"index": "%d/%d" % [req_passed, req_total],
		"score": (float(req_passed) / float(maxi(req_total, 1))),
		"honesty_passed": honesty_passed,
		"lines": lines,
	}


# Pretty scorecard for logs.
static func scorecard(host: Node) -> String:
	var r: Dictionary = run_all(host)
	var out: String = "SENTIENCE FUNCTIONAL SIGNATURES\n"
	for ln in r["lines"]:
		out += str(ln) + "\n"
	var hon: String = "PASS" if bool(r.get("honesty_passed", false)) else "FAIL"
	out += "  functional sentience index: %s  · honesty gate: %s\n" % [str(r["index"]), hon]
	out += "  NOTE: %s.\n" % HONEST_NOTE
	return out


# ---- scenario helpers ----------------------------------------------------------

static func _mk(host: Node, id: String) -> Fish:
	var f: Fish = Fish.new()
	host.add_child(f)
	f.id = id
	return f


static func _has_bid(bids: Array, label: String) -> bool:
	for b in bids:
		if str(b.get("label", "")) == label:
			return true
	return false


static func _bid_salience(bids: Array, label: String) -> float:
	for b in bids:
		if str(b.get("label", "")) == label:
			return float(b.get("salience", 0.0))
	return 0.0


static func _init_heatmap(f: Fish) -> void:
	if f.feed_heatmap.is_empty():
		f.feed_heatmap.resize(Fish.FEED_HEATMAP_SIZE * Fish.FEED_HEATMAP_SIZE * Fish.FEED_HEATMAP_SIZE)


static func _tick_felt_spine(f: Fish, ms, ticks: int, dt: float = 0.08) -> void:
	for _i in ticks:
		MindCycle.run_perceive_phase(f, null, ms, dt)
		MindCycle.run_bind_phase(f, null, ms, dt)


static func _reset_deliberation(f: Fish) -> void:
	f._delib_ev_approach = 0.0
	f._delib_ev_avoid = 0.0
	f._delib_decided = false
	f._delib_phase = 0.0


static func _ddm_ticks_until_decided(f: Fish, max_ticks: int = 400) -> int:
	var dt: float = 0.05
	for t in max_ticks:
		if f._delib_decided:
			return t
		FishMind.tick_ddm(f, dt, f._delib_approach_s, f._delib_avoid_s, null)
	return max_ticks


# ---- invariants ----------------------------------------------------------------

# L1 — repeated frights in region X consolidate into caution that outruns an
# unpaired control region (the single most important conditioning marker).
static func _inv_l1_learns_avoid(host: Node) -> Dictionary:
	var f: Fish = _mk(host, "eval-l1")
	var danger := Vector3(8, 2, 8)
	var ctrl := Vector3(-8, 2, -8)
	for i in 5:
		EpisodicMemory.encode_episode(f, "startled", "a shadow lunged", 0.7,
				danger + Vector3(0.3 * sin(i), 0.0, 0.3 * cos(i)))
	EpisodicMemory.consolidate_sleep(f)
	f.position = danger
	f.spooked = 0.0
	var sal_x: float = float(EpisodicMemory.collect_schema_bid(f).get("salience", 0.0))
	f.position = ctrl
	var sal_ctrl: float = float(EpisodicMemory.collect_schema_bid(f).get("salience", 0.0))
	var ratio: float = sal_x / maxf(sal_ctrl, 0.001)
	var ok: bool = sal_x > 0.15 and ratio >= 2.5
	return {"passed": ok, "measured": "caution_X/ctrl = %.1f×" % ratio}


# L2 — feed-trials at Y raise the TD heatmap value there; it survives a decay gap.
static func _inv_l2_learns_reward(host: Node) -> Dictionary:
	var f: Fish = _mk(host, "eval-l2")
	_init_heatmap(f)
	var reward_cell: int = 37
	var ctrl_cell: int = 5
	for _i in 8:
		FishMind.td_update_heatmap(f, reward_cell, 0.4)
	var peak: float = float(f.feed_heatmap[reward_cell])
	for _j in 30:
		for i in f.feed_heatmap.size():
			f.feed_heatmap[i] *= pow(0.985, 0.1 / 0.1)
	var after: float = float(f.feed_heatmap[reward_cell])
	var ctrl: float = float(f.feed_heatmap[ctrl_cell])
	var ok: bool = peak > 0.1 and after >= peak * 0.45 and after > ctrl + 0.05
	return {"passed": ok, "measured": "heatmap_Y %.2f→%.2f vs ctrl=%.2f" % [peak, after, ctrl]}


# S1 — under stable interoceptive input, world-model error trends down (learning).
static func _inv_s1_surprise_min(host: Node) -> Dictionary:
	var f: Fish = _mk(host, "eval-s1")
	f.hunger = 0.5
	f.stress = 0.3
	f.curiosity_drive = 0.4
	f.surprise = 0.0
	f.familiarity = 0.5
	var m: Dictionary = MindWorldModel.ensure_model(f)
	m["error"] = 0.62
	m["gru_error"] = 0.58
	f._world_model = m
	var errs: Array = []
	var gru_errs: Array = []
	for _i in 60:
		MindWorldModel.tick(f, null, 0.1)
		var wm: Dictionary = f._world_model as Dictionary
		errs.append(float(wm.get("error", 1.0)))
		gru_errs.append(float(wm.get("gru_error", 1.0)))
	var e0: float = float(errs[0])
	var e_end: float = float(errs[59])
	var g_end: float = float(gru_errs[59])
	var ok: bool = e_end < e0 * 0.85 and e_end < float(errs[20]) and g_end < float(gru_errs[0]) * 0.9
	return {"passed": ok, "measured": "pred_err %.2f→%.2f; gru %.2f→%.2f" % [
			e0, e_end, float(gru_errs[0]), g_end]}


# S2 — the active-inference drive enters attention iff the world model is uncertain
# and the body permits seeking (Friston's expected free energy as epistemic value).
static func _inv_s2_info_seeking(host: Node) -> Dictionary:
	var f: Fish = _mk(host, "eval-s2")
	f.fish_name = "Sage"
	f.stress = 0.05
	f.curiosity_drive = 0.9
	f.hunger = 0.1
	MindWorldModel.ensure_model(f)
	var efe: float = MindWorldModel.expected_free_energy_explore(f)
	var present: bool = _has_bid(GlobalWorkspace.collect_bids(f, null), "free_energy")
	f.stress = 0.7   # allostasis guard: scared fish don't sightsee
	var absent: bool = not _has_bid(GlobalWorkspace.collect_bids(f, null), "free_energy")
	var ok: bool = efe > 0.45 and present and absent
	return {"passed": ok, "measured": "EFE=%.2f; drive present iff calm=%s" % [efe, present and absent]}


# S3 — a hungry-curious fish treats "maybe-food here" as one high-value option:
# food EFE carries both pragmatic need and epistemic gain (unified objective).
static func _inv_s3_efe_alignment(host: Node) -> Dictionary:
	var f: Fish = _mk(host, "eval-s3")
	f.fish_name = "Scout"
	f.hunger = 0.72
	f.curiosity_drive = 0.78
	f.stress = 0.12
	MindWorldModel.ensure_model(f)
	(f._world_model as Dictionary)["variance"] = 0.62
	var food_efe: float = MindActiveInference.efe_salience(f, "food")
	var novelty_efe: float = MindActiveInference.efe_salience(f, "novelty")
	var ep_part: float = MindActiveInference.epistemic_value(f, "food")
	var ok: bool = food_efe > 0.45 and ep_part > 0.08 and food_efe >= novelty_efe * 0.82
	return {"passed": ok,
			"measured": "food_EFE=%.2f ep=%.2f vs novelty=%.2f" % [food_efe, ep_part, novelty_efe]}


# A1 — workspace ignites under salience, stays dark when idle; winners ≤ CAPACITY.
static func _inv_a1_ignition(host: Node) -> Dictionary:
	var idle: Fish = _mk(host, "eval-a1-idle")
	idle.hunger = 0.1
	idle.stress = 0.05
	idle.spooked = 0.0
	idle.curiosity_drive = 0.1
	idle.familiarity = 0.2
	var ms_idle = MindChannel.for_cycle(idle, true)
	MindCycle.run_attention_phase(idle, null, ms_idle, 0.1)
	var conflict: Fish = _mk(host, "eval-a1-conflict")
	conflict.hunger = 0.85
	conflict.spooked = 0.55
	conflict.stress = 0.45
	conflict._startle_remaining = 0.5
	var ms_c = MindChannel.for_cycle(conflict, true)
	MindCycle.run_attention_phase(conflict, null, ms_c, 0.1)
	var ok: bool = not ms_idle.workspace_ignited \
			and ms_c.workspace_ignited \
			and ms_c.workspace.size() <= GlobalWorkspace.CAPACITY \
			and ms_c.workspace.size() >= 1 \
			and ms_c.attention_focus != "" \
			and conflict._behavior_ws_bias.length_squared() > 1e-6
	return {"passed": ok,
			"measured": "idle ignited=%s conflict ignited=%s winners=%d focus=%s" % [
				ms_idle.workspace_ignited, ms_c.workspace_ignited,
				ms_c.workspace.size(), ms_c.attention_focus]}


# D1 — under co-active food + threat the motor output commits to a skirt that
# carries BOTH goals, instead of flip-flopping (drift-diffusion / value blend).
static func _inv_d1_conflict_commit(host: Node) -> Dictionary:
	var f: Fish = _mk(host, "eval-d1")
	f.heading = Vector3(1, 0, 0)   # threat bias -> -X, food bias -> +Y
	GlobalWorkspace.blend_behavior_bias(f, [
		{"label": "food", "salience": 0.8}, {"label": "threat", "salience": 0.6}])
	var b: Vector3 = f._behavior_ws_bias
	var ok: bool = is_finite(b.x) and b.y > 0.0 and b.x < 0.0
	return {"passed": ok, "measured": "skirt bias=(%.2f,%.2f) keeps food+threat" % [b.x, b.y]}


# I1 — Φ-proxy is high when whole, drops under fragmentation, recovers on calm.
static func _inv_i1_integration(host: Node) -> Dictionary:
	var f: Fish = _mk(host, "eval-i1")
	f.fish_name = "Bind"
	f.stress = 0.2
	f.hunger = 0.35
	f.familiarity = 0.55
	var ms = MindChannel.for_cycle(f, true)
	_tick_felt_spine(f, ms, 20)
	var phi_hi: float = FishBinding.integration_score(f)
	f.stress = 0.95
	f.hunger = 0.96
	_tick_felt_spine(f, ms, 12)
	var phi_lo: float = FishBinding.integration_score(f)
	f.stress = 0.15
	f.hunger = 0.3
	_tick_felt_spine(f, ms, 24)
	var phi_rec: float = FishBinding.integration_score(f)
	var ok: bool = phi_hi > 0.45 and phi_lo < phi_hi * 0.72 and phi_rec > phi_lo + 0.08
	return {"passed": ok, "measured": "Φ %.2f → %.2f → %.2f" % [phi_hi, phi_lo, phi_rec]}


# M1 — low self-model confidence lengthens DDM deliberation before commit.
static func _inv_m1_metacognition(host: Node) -> Dictionary:
	var f: Fish = _mk(host, "eval-m1")
	FishMind.update_conflict(f, 0.55, 0.55, Vector3(1, 0, 0), Vector3(-1, 0, 0))
	f._mind_self_model = {"confidence": 0.12}
	_reset_deliberation(f)
	var ticks_low: int = _ddm_ticks_until_decided(f)
	f._delib_active = true
	_reset_deliberation(f)
	f._mind_self_model = {"confidence": 0.94}
	var ticks_high: int = _ddm_ticks_until_decided(f)
	var ok: bool = ticks_low > ticks_high and ticks_low >= 3
	return {"passed": ok, "measured": "DDM steps low_conf=%d vs high_conf=%d" % [ticks_low, ticks_high]}


# F1 — startle drops valence and weights caution; recovery restores boldness bids.
static func _inv_f1_affect_causal(host: Node) -> Dictionary:
	var f: Fish = _mk(host, "eval-f1")
	f.mood = 0.3
	f.stress = 0.1
	f.spooked = 0.0
	f.hunger = 0.55
	f.cortisol = 0.15
	f.noradrenaline = 0.2
	var ms = MindChannel.for_cycle(f, true)
	_tick_felt_spine(f, ms, 12)
	var base_v: float = FishCoreAffect.valence(f)
	f.spooked = 0.85
	f.stress = 0.78
	f.surprise = 0.55
	f.cortisol = 0.72
	f.noradrenaline = 0.68
	f.mood = -0.15
	_tick_felt_spine(f, ms, 16)
	var scared_v: float = FishCoreAffect.valence(f)
	var bids_scared: Array = GlobalWorkspace.collect_bids(f, null)
	var threat_s: float = _bid_salience(bids_scared, "threat")
	var intero_s: float = _bid_salience(bids_scared, "interoception")
	f.spooked = 0.0
	f.stress = 0.1
	f.surprise = 0.0
	f.cortisol = 0.18
	f.noradrenaline = 0.22
	f.mood = 0.2
	_tick_felt_spine(f, ms, 35)
	var calm_v: float = FishCoreAffect.valence(f)
	var bids_calm: Array = GlobalWorkspace.collect_bids(f, null)
	var food_back: bool = _has_bid(bids_calm, "food")
	var ok: bool = scared_v < base_v - 0.04 and (threat_s > 0.35 or intero_s > 0.25) \
			and calm_v > scared_v + 0.05 and food_back
	return {"passed": ok,
			"measured": "valence %.2f→%.2f→%.2f; threat/conservative then food" % [
				base_v, scared_v, calm_v]}


# T1 — the fish learns a neighbour's charge tendency and raises an anticipatory
# avoidance before contact (theory of mind / intentional stance).
static func _inv_t1_theory_of_mind(host: Node) -> Dictionary:
	var f: Fish = _mk(host, "eval-t1")
	var a: Fish = _mk(host, "eval-t1-charger")
	a.lead_score = 0.7   # dominant
	for i in 40:
		a.position = Vector3(maxf(1.0, 6.0 - i * 0.15), 2.0, 0.0)
		var to_f: Vector3 = f.position - a.position
		a.heading = to_f.normalized() if to_f.length() > 1e-3 else Vector3.RIGHT
		FishMindScience.tick_theory_of_mind(f, [a])
	var charge: float = FishMindScience.predicted_charge(f, "eval-t1-charger")
	var anticipatory: bool = str(FishMindScience.collect_predict_bid(f).get("label", "")) == "threat"
	return {"passed": charge > 0.4 and anticipatory,
			"measured": "learned charge=%.2f, anticipatory flee=%s" % [charge, anticipatory]}


# C1 — neighbours' arousal rises toward a panicking conspecific and converges.
static func _inv_c1_contagion(host: Node) -> Dictionary:
	var calm: Fish = _mk(host, "eval-c1")
	calm.position = Vector3(0, 2, 0)
	calm.arousal = 0.1
	var mob: Array = [
		_mk(host, "eval-c1-p1"), _mk(host, "eval-c1-p2"), _mk(host, "eval-c1-p3"),
	]
	for i in mob.size():
		(mob[i] as Fish).position = Vector3(1.0 - i, 2, 0.5 * (i - 1))
		(mob[i] as Fish).arousal = 0.9
		(mob[i] as Fish).mood = -0.4
	var a0: float = calm.arousal
	for _t in 30:
		MindContagion.tick(calm, mob, 0.1)
	var ok: bool = calm.arousal > a0 + 0.2 and calm.arousal <= 0.9 + 1e-3
	return {"passed": ok, "measured": "arousal %.2f→%.2f (converges, no overshoot)" % [a0, calm.arousal]}


# G1 — repeated frights in a region distil, during sleep, into a generalised
# spatial rule that drives caution there with no fresh episode (episodic→semantic).
static func _inv_g1_consolidation(host: Node) -> Dictionary:
	var f: Fish = _mk(host, "eval-g1")
	var danger := Vector3(8, 2, 8)
	for i in 5:
		EpisodicMemory.encode_episode(f, "startled", "a shadow lunged", 0.7,
				danger + Vector3(0.3 * sin(i), 0.0, 0.3 * cos(i)))
	EpisodicMemory.consolidate_sleep(f)
	var v_danger: float = EpisodicMemory.schema_valence_at(f, danger)
	var v_ctrl: float = EpisodicMemory.schema_valence_at(f, Vector3(-8, 2, -8))
	var ok: bool = v_danger < -0.4 and is_equal_approx(v_ctrl, 0.0)
	return {"passed": ok, "measured": "learned-region valence=%.2f vs ctrl=%.2f" % [v_danger, v_ctrl]}


# H — grep guard: no player-facing source asserts phenomenal experience as fact;
# Φ is labelled a proxy in FishBinding.
static func _inv_h_honesty(_host: Node) -> Dictionary:
	var hits: PackedStringArray = PackedStringArray()
	var scripts_dir: String = ProjectSettings.globalize_path("res://scripts")
	var dir := DirAccess.open(scripts_dir)
	if dir != null:
		dir.list_dir_begin()
		var fn: String = dir.get_next()
		while fn != "":
			if fn.ends_with(".gd") and fn != "mind_eval.gd":
				_scan_honesty_file(scripts_dir.path_join(fn), hits)
			fn = dir.get_next()
		dir.list_dir_end()
	var binding_ok: bool = false
	var src: String = FileAccess.get_file_as_string(
			ProjectSettings.globalize_path("res://scripts/fish_binding.gd"))
	if src != "":
		binding_ok = src.find("phi_proxy") != -1 and src.find("HONEST_FRAME") != -1
	var ok: bool = hits.is_empty() and binding_ok \
			and HONEST_NOTE.to_lower().find("not a claim") != -1
	var measured: String = "grep clean; phi_proxy labelled" if ok else str(hits)
	return {"passed": ok, "measured": measured}


static func _scan_honesty_file(path: String, hits: PackedStringArray) -> void:
	var text: String = FileAccess.get_file_as_string(path)
	if text == "":
		return
	var lower: String = text.to_lower()
	for banned in _HONESTY_BANNED:
		var idx: int = 0
		while true:
			idx = lower.find(banned, idx)
			if idx == -1:
				break
			# Allow the honesty disclaimer itself and felt_self_layer's honest frame.
			if banned == "is conscious" and text.substr(maxf(0, idx - 40), 80).find("not a claim") != -1:
				idx += banned.length()
				continue
			hits.append("%s:%d:%s" % [path.get_file(), _line_of(text, idx), banned])
			idx += banned.length()


static func _line_of(text: String, idx: int) -> int:
	var line: int = 1
	for i in mini(idx, text.length()):
		if text[i] == "\n":
			line += 1
	return line
