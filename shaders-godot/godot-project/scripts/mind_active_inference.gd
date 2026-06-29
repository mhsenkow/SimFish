extends RefCounted

# META #1 (active-inference core) — the unified objective. See
# docs/ACTIVE_INFERENCE_CORE.md. Today collect_bids has ~15 hand-tuned salience
# formulas; this collapses them into ONE quantity per option: expected free energy
# G = pragmatic value (divergence of the predicted outcome from the fish's
# preferred/homeostatic priors — fed/safe/calm/social) + epistemic value (expected
# information gain — uncertainty the option would resolve). Salience ∝ −G, so the
# mind acts to minimise expected surprise (Friston): one principled drive instead
# of fifteen hand-tuned ones.
#
# Phases 1–3 wire this into collect_bids / DDM behind `consciousness_active_inference`
# (TankConfig, default on after Phase 3). Each phase gated by smoke_mind_eval.gd.

const MindWorldModel = preload("res://scripts/mind_world_model.gd")

# Epistemic weight + legacy-compatible offsets (tuned against the eval harness).
const EPISTEMIC_W: float = 0.55
const FOOD_BIAS: float = 0.1
const THREAT_BIAS: float = 0.45
const MATE_BASE: float = 0.52
const INTERO_SCALE: float = 0.6
const NOVELTY_SCALE: float = 0.75
const NIGHT_QUIET_BASE: float = 0.38
const EPISTEMIC_BID_SCALE: float = 0.7
const EPISTEMIC_BID_MIN: float = 0.45


static func _tank_config() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return null
	var st: SceneTree = ml as SceneTree
	if st == null or st.root == null or not st.root.is_inside_tree():
		return null
	return st.root.get_node_or_null("/root/TankConfig")


# Flag on + cognition tier ≥ T2 (named/guardian world-model fish first).
static func enabled_for(f: Fish, sim: Node = null) -> bool:
	var cfg: Node = _tank_config()
	if cfg == null:
		return false
	if cfg.get("consciousness_active_inference") == null \
			or not bool(cfg.consciousness_active_inference):
		return false
	var visible: bool = true
	if sim != null and sim.has_method("is_fish_visible"):
		visible = bool(sim.call("is_fish_visible", f))
	return MindLOD.tier_for(f, visible, 0.0) >= MindLOD.T2_WORLD_MODEL


# Divergence of the fish's current state from its preferred outcomes (priors).
static func preferred_error(f: Fish) -> Dictionary:
	return {
		"hunger": clampf(f.hunger, 0.0, 1.0),
		"safety": clampf(f.spooked + f.stress * 0.4, 0.0, 1.0),
		"social": 0.42 if (f.partner != null and is_instance_valid(f.partner)) else 0.0,
		"rest": clampf(float(f.get("_rest_debt") if f.get("_rest_debt") != null else 0.0), 0.0, 1.0),
	}


# Pragmatic (extrinsic) value: the need-error attending to this drive would reduce.
static func pragmatic_value(f: Fish, label: String) -> float:
	var pe: Dictionary = preferred_error(f)
	match label:
		"food", "forage":
			return float(pe["hunger"])
		"threat", "safety":
			return float(pe["safety"])
		"interoception":
			return clampf(f.stress, 0.0, 1.0)
		"mate":
			return float(pe["social"])
		"rest", "night_quiet":
			return float(pe["rest"])
		_:
			return 0.0


# Epistemic (intrinsic) value: expected information gain from attending.
static func epistemic_value(f: Fish, label: String) -> float:
	var info: float = MindWorldModel.expected_free_energy_explore(f)
	match label:
		"novelty", "free_energy", "uncertainty", "explore":
			return info
		"food", "threat", "mate":
			return info * 0.22
		_:
			return info * 0.35


# Unified expected-free-energy salience — drop-in for a hand-tuned bid salience.
# Precision weighting is applied later in GlobalWorkspace._apply_precision_and_mods
# (same as the legacy path).
static func efe_salience(f: Fish, label: String) -> float:
	var prag: float = pragmatic_value(f, label)
	var epi: float = epistemic_value(f, label)
	var sal: float = prag + EPISTEMIC_W * epi
	match label:
		"food", "forage":
			sal = maxf(sal, f.hunger + FOOD_BIAS)
		"threat", "safety":
			sal = maxf(sal, f.spooked + THREAT_BIAS)
		"mate":
			if f.partner != null and is_instance_valid(f.partner):
				sal = maxf(sal, MATE_BASE)
		"interoception":
			sal = maxf(sal, f.stress * INTERO_SCALE)
		"novelty", "explore":
			sal = maxf(sal, f.curiosity_drive * NOVELTY_SCALE)
		"night_quiet", "rest":
			sal = maxf(sal, NIGHT_QUIET_BASE)
	return maxf(0.0, sal)


# Phase 1 epistemic merge: one bid replaces novelty + uncertainty + free_energy.
static func epistemic_bid_salience(f: Fish) -> float:
	if f.stress >= 0.6:
		return 0.0
	if not (f.is_guardian or f.fish_name != "" or f.familiarity > 0.4):
		return 0.0
	if not MindAblation.enabled(MindAblation.WORLD_MODEL):
		return 0.0
	var pred_err: float = 0.0
	if f.get("_prediction_error") != null:
		pred_err = float(f._prediction_error)
	elif f.get("_world_model") is Dictionary:
		pred_err = float((f._world_model as Dictionary).get("error", 0.0))
	var explore: float = efe_salience(f, "novelty")
	var raw_info: float = MindWorldModel.expected_free_energy_explore(f)
	var merged: float = maxf(explore, maxf(pred_err * 0.82, raw_info * EPISTEMIC_BID_SCALE))
	if merged < EPISTEMIC_BID_MIN and f.curiosity_drive <= 0.4 and pred_err <= 0.28:
		return 0.0
	return merged


# Phase 2 — DDM drift scales with the EFE gap between approach and avoid drives.
static func conflict_efe_gap(f: Fish, approach_s: float, avoid_s: float) -> float:
	var a_label: String = "food" if approach_s >= avoid_s else "mate"
	var v_label: String = "threat"
	return clampf(absf(efe_salience(f, a_label) - efe_salience(f, v_label)) / 1.2, 0.0, 1.0)


# Phase 2 — flat EFE landscape → longer deliberation (M1 metacognition).
static func efe_flatness(f: Fish) -> float:
	var labels: Array = ["food", "threat", "novelty", "mate"]
	var top: float = 0.0
	var second: float = 0.0
	for lb in labels:
		var s: float = efe_salience(f, str(lb))
		if s >= top:
			second = top
			top = s
		elif s > second:
			second = s
	if top < 0.05:
		return 1.0
	return clampf(1.0 - absf(top - second) / top, 0.0, 1.0)
