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

const HONEST_NOTE: String = "functional signatures only — not a claim of phenomenal experience"


# The suite. Add an invariant = append {id, theory, desc, required, fn} where fn is
# Callable(host) -> {passed: bool, measured: String}. Mark required=false (and it
# WILL be logged as such) until it can pass — never silently skip.
static func invariants() -> Array:
	return [
		{"id": "D1", "theory": "drift-diffusion / value integration", "required": true,
			"desc": "conflict -> a committed skirt, not dithering",
			"fn": func(h): return _inv_d1_conflict_commit(h)},
		{"id": "S2", "theory": "active inference (Friston)", "required": true,
			"desc": "seeks information when uncertain",
			"fn": func(h): return _inv_s2_info_seeking(h)},
		{"id": "T1", "theory": "theory of mind (Premack-Woodruff)", "required": true,
			"desc": "models & predicts another mind",
			"fn": func(h): return _inv_t1_theory_of_mind(h)},
		{"id": "G1", "theory": "systems memory consolidation", "required": true,
			"desc": "sleep generalises episodes into a spatial rule",
			"fn": func(h): return _inv_g1_consolidation(h)},
	]


# Run the suite. Returns {all_required_passed, index, score, lines}.
static func run_all(host: Node) -> Dictionary:
	var lines: Array = []
	var req_total: int = 0
	var req_passed: int = 0
	for inv in invariants():
		var res: Dictionary = (inv["fn"] as Callable).call(host)
		var ok: bool = bool(res.get("passed", false))
		var req: bool = bool(inv.get("required", true))
		if req:
			req_total += 1
			if ok:
				req_passed += 1
		var tag: String = "PASS" if ok else ("FAIL" if req else "skip")
		lines.append("  [%s] %s  %-46s %s" % [tag, str(inv["id"]), str(inv["desc"]), str(res.get("measured", ""))])
	return {
		"all_required_passed": req_passed == req_total,
		"index": "%d/%d" % [req_passed, req_total],
		"score": (float(req_passed) / float(maxi(req_total, 1))),
		"lines": lines,
	}


# Pretty scorecard for logs.
static func scorecard(host: Node) -> String:
	var r: Dictionary = run_all(host)
	var out: String = "SENTIENCE FUNCTIONAL SIGNATURES\n"
	for ln in r["lines"]:
		out += str(ln) + "\n"
	out += "  functional sentience index: %s  (%s)\n" % [str(r["index"]), HONEST_NOTE]
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


# ---- reference invariants ------------------------------------------------------

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
