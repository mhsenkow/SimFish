class_name MindActiveInference
extends RefCounted

# META #1 (active-inference core) — the unified objective. See
# docs/ACTIVE_INFERENCE_CORE.md. Today collect_bids has ~15 hand-tuned salience
# formulas; this collapses them into ONE quantity per option: expected free energy
# G = pragmatic value (divergence of the predicted outcome from the fish's
# preferred/homeostatic priors — fed/safe/calm/social) + epistemic value (expected
# information gain — uncertainty the option would resolve). Salience ∝ −G, so the
# mind acts to minimise expected surprise (Friston): one principled drive instead
# of three hand-tuned ones.
#
# PHASE 0 (this file): the pure objective — computable, tested, consumed by NOTHING
# yet. The eval harness stays 13/13 because behaviour is unchanged. Phases 1-3 wire
# it into collect_bids / action selection behind the `consciousness_active_inference`
# flag, each phase gated by smoke_mind_eval.gd.

const MindWorldModel = preload("res://scripts/mind_world_model.gd")

# How much epistemic (information-seeking) value weighs against pragmatic (need)
# value. Fit against the eval harness in Phase 1 — not a guess once wired.
const EPISTEMIC_W: float = 0.6


# Divergence of the fish's current state from its preferred outcomes (priors).
# This IS the free energy of the present moment, per need.
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


# Epistemic (intrinsic) value: expected information gain from attending. Driven by
# the world model's uncertainty (variance) + curiosity; full for explore-type
# drives, small for drives whose outcome is already well-modelled.
static func epistemic_value(f: Fish, label: String) -> float:
	var info: float = MindWorldModel.expected_free_energy_explore(f)   # variance + goal
	match label:
		"novelty", "free_energy", "uncertainty", "explore":
			return info
		"food", "threat", "mate":
			return info * 0.2
		_:
			return info * 0.35


# The unified expected-free-energy salience — a drop-in for a hand-tuned bid
# salience. Pragmatic value is sharpened by precision (model confidence = attention
# in active inference); epistemic value is added so uncertain options stay
# attractive. Always ≥ 0, same range as the existing bids.
static func efe_salience(f: Fish, label: String) -> float:
	var prec: float = MindWorldModel.precision_scale(f, label)
	return maxf(0.0, pragmatic_value(f, label) * prec + EPISTEMIC_W * epistemic_value(f, label))
