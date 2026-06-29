extends SceneTree

# META #1 Phase 0 — the unified active-inference objective. Proves the single EFE
# function (a) tracks need pragmatically, (b) tracks uncertainty epistemically, and
# (c) THE UNIFICATION: one function makes a hungry fish food-dominant and a sated
# curious fish explore-dominant — three hand-tuned drives collapsed into one
# principled trade-off. (Consumed by nothing yet → the eval harness stays 13/13.)

const MindActiveInference = preload("res://scripts/mind_active_inference.gd")
const MindWorldModel = preload("res://scripts/mind_world_model.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	# (a) Pragmatic value tracks need.
	var f: Fish = _mk("ai-core")
	f.hunger = 0.2
	var prag_low: float = MindActiveInference.pragmatic_value(f, "food")
	f.hunger = 0.9
	var prag_high: float = MindActiveInference.pragmatic_value(f, "food")
	_assert(failed, prag_high > prag_low, "pragmatic food value rises with hunger (%.2f→%.2f)" % [prag_low, prag_high])

	f.spooked = 0.1
	var thr_low: float = MindActiveInference.pragmatic_value(f, "threat")
	f.spooked = 0.8
	var thr_high: float = MindActiveInference.pragmatic_value(f, "threat")
	_assert(failed, thr_high > thr_low, "pragmatic threat value rises with fright")

	# (b) Epistemic value tracks world-model uncertainty.
	var g: Fish = _mk("ai-epi")
	g.curiosity_drive = 0.6
	MindWorldModel.ensure_model(g)
	g._world_model["variance"] = 0.2
	var epi_certain: float = MindActiveInference.epistemic_value(g, "novelty")
	g._world_model["variance"] = 0.7
	var epi_uncertain: float = MindActiveInference.epistemic_value(g, "novelty")
	_assert(failed, epi_uncertain > epi_certain, "epistemic value rises with uncertainty (%.2f→%.2f)" % [epi_certain, epi_uncertain])

	# (c) THE UNIFICATION — one objective, the right trade-off in both regimes.
	var hungry: Fish = _mk("ai-hungry")
	hungry.hunger = 0.85
	hungry.curiosity_drive = 0.1
	hungry.stress = 0.1
	MindWorldModel.ensure_model(hungry)
	var hf: float = MindActiveInference.efe_salience(hungry, "food")
	var hn: float = MindActiveInference.efe_salience(hungry, "novelty")
	_assert(failed, hf > hn, "hungry+incurious → food dominates (food=%.2f > novelty=%.2f)" % [hf, hn])

	var curious: Fish = _mk("ai-curious")
	curious.hunger = 0.1
	curious.curiosity_drive = 0.9
	curious.stress = 0.1
	MindWorldModel.ensure_model(curious)
	curious._world_model["variance"] = 0.55
	var cf: float = MindActiveInference.efe_salience(curious, "food")
	var cn: float = MindActiveInference.efe_salience(curious, "novelty")
	_assert(failed, cn > cf, "sated+curious → exploring dominates (novelty=%.2f > food=%.2f)" % [cn, cf])

	# Safety property: the drop-in salience for a hungry fish is in the same ballpark
	# as the legacy `hunger + 0.1` drive (so Phase 1 won't lurch the behaviour).
	_assert(failed, hf > 0.4 and hf < 1.3 and is_finite(hf),
			"hungry food EFE salience is a sane drop-in (%.2f vs legacy ~%.2f)" % [hf, hungry.hunger + 0.1])

	if failed.is_empty():
		print("[smoke] active_inference_core OK")
		quit(0)
	else:
		for m in failed:
			push_error("[smoke] " + m)
		quit(1)


func _mk(id: String) -> Fish:
	var f: Fish = Fish.new()
	root.add_child(f)
	f.id = id
	return f


func _assert(failed: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		failed.append(msg)
