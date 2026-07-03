extends RefCounted
# SENTIENCE_THE_FELT_SELF §5 — self-evidencing generative model.

const _MindSimSnapScript = preload("res://scripts/mind_sim_snap.gd")

const MindWorldModel = preload("res://scripts/mind_world_model.gd")
const MindKeeperModel = preload("res://scripts/mind_keeper_model.gd")
const FishCoreAffect = preload("res://scripts/fish_core_affect.gd")
const FeltSelfLayer = preload("res://scripts/felt_self_layer.gd")

const SCHEMA_VERSION: int = 1


static func enabled() -> bool:
	return FeltSelfLayer.layer_enabled()


static func ensure(f: Fish) -> Dictionary:
	if f.get("_felt_self") == null or not (f._felt_self is Dictionary):
		f._felt_self = {}
	var fs: Dictionary = f._felt_self as Dictionary
	if fs.get("generative") == null or not (fs["generative"] is Dictionary):
		fs["generative"] = {
			"schema_version": SCHEMA_VERSION,
			"body_pred": 0.5,
			"world_pred": 0.5,
			"keeper_pred": 0.5,
			"precision": 0.55,
			"uncertainty": 0.35,
			"set_points": {"hunger": 0.35, "stress": 0.25, "o2": 0.65},
			"counterfactual": "",
		}
	f._felt_self = fs
	return fs["generative"] as Dictionary


static func tick(f: Fish, sim: Node, dt: float) -> void:
	if not enabled() or f == null:
		return
	var g: Dictionary = ensure(f)
	MindWorldModel.tick(f, sim, dt)
	g["body_pred"] = lerpf(float(g.get("body_pred", 0.5)), 1.0 - f.stress * 0.4 - f.hunger * 0.3,
			clampf(dt * 0.5, 0.0, 1.0))
	g["world_pred"] = lerpf(float(g.get("world_pred", 0.5)), 1.0 - float(
			f.get("_prediction_error") if f.get("_prediction_error") != null else 0.0),
			clampf(dt * 0.6, 0.0, 1.0))
	var km: Dictionary = MindKeeperModel.ensure(f)
	g["keeper_pred"] = lerpf(float(g.get("keeper_pred", 0.5)),
			0.45 + f.familiarity * 0.35 + float(km.get("trust", 0.0)) * 0.2, clampf(dt * 0.4, 0.0, 1.0))
	var dl: float = MindSimSnap.daylight_of(sim)
	g["precision"] = lerpf(float(g.get("precision", 0.55)), clampf(0.35 + dl * 0.45, 0.2, 0.9),
			clampf(dt * 0.8, 0.0, 1.0))
	g["uncertainty"] = clampf(1.0 - float(g["precision"]) * float(g["world_pred"]), 0.05, 0.95)
	# Dark-room guard (#45): homeostatic set-points resist hiding forever.
	var sp: Dictionary = g.get("set_points", {})
	sp["hunger"] = lerpf(float(sp.get("hunger", 0.35)), 0.35 + clampf(f.age / maxf(f.max_age_s, 1.0), 0.0, 1.0) * 0.05,
			dt * 0.001)
	g["set_points"] = sp
	# SOUL #37 — counterfactual protention, grounded in body + boldness.
	const MindSoul = preload("res://scripts/mind_soul.gd")
	if MindSoul.enabled():
		var cf: String = MindSoul.counterfactual_for(f)
		if cf != "":
			g["counterfactual"] = cf
	elif f.stress > 0.5 and MindRng.for_fish(f).randf() < dt * 0.02:
		g["counterfactual"] = "open water ahead" if f._trait("boldness") > 0.55 else "stay near cover"
	(f._felt_self as Dictionary)["generative"] = g


static func protention(f: Fish) -> String:
	return str(ensure(f).get("counterfactual", ""))


static func markov_blanket() -> Dictionary:
	return {"sense": ["body", "world", "keeper"], "act": ["swim", "feed", "hide", "social"]}
