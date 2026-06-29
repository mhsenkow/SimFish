extends SceneTree

# META #4 — predictive theory of mind. A fish learns which neighbours tend to
# charge it (closing distance while aimed at it, when threat/dominant) and raises
# an ANTICIPATORY threat bid so it can act on the prediction — fleeing before
# contact, not after. Verifies learning, the anticipatory bid reaching the
# workspace, the #14 ablation gate, and a non-approaching control staying unfeared.

const GlobalWorkspace = preload("res://scripts/global_workspace.gd")
const FishMindScience = preload("res://scripts/fish_mind_science.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	MindAblation.reset()

	# A dominant neighbour repeatedly charges the prey (closing + aimed at it).
	var f: Fish = _mk("prey", Vector3(0, 2, 0))
	f.spooked = 0.0
	var a: Fish = _mk("charger", Vector3(6, 2, 0))
	a.lead_score = 0.7   # → inferred label "dominant"
	for i in 40:
		a.position = Vector3(maxf(1.0, 6.0 - i * 0.15), 2.0, 0.0)
		var to_f: Vector3 = f.position - a.position
		a.heading = to_f.normalized() if to_f.length() > 1e-3 else Vector3.RIGHT
		FishMindScience.tick_theory_of_mind(f, [a])

	var charge: float = FishMindScience.predicted_charge(f, "charger")
	_assert(failed, charge > 0.4, "fish LEARNS the charger's tendency (%.2f)" % charge)

	var pb: Dictionary = FishMindScience.collect_predict_bid(f)
	_assert(failed, str(pb.get("label", "")) == "threat" and float(pb.get("salience", 0.0)) > 0.0,
			"a predicted charger raises an anticipatory threat bid")
	_assert(failed, _has_bid(GlobalWorkspace.collect_bids(f, null), "threat"),
			"anticipatory threat enters the workspace (flee BEFORE contact, not after)")

	# #14 ablation: lesion theory-of-mind → the predictive threat disappears.
	MindAblation.set_enabled(MindAblation.THEORY_OF_MIND, false)
	_assert(failed, not _has_bid(GlobalWorkspace.collect_bids(f, null), "threat"),
			"ablating theory-of-mind removes the predictive threat bid")
	MindAblation.reset()

	# Control: a dominant that just loiters (never closes/aims) isn't feared.
	var g: Fish = _mk("calm-prey", Vector3(0, 2, 0))
	g.spooked = 0.0
	var b: Fish = _mk("loiterer", Vector3(3, 2, 0))
	b.lead_score = 0.7
	b.heading = Vector3.ZERO
	for _i in 40:
		FishMindScience.tick_theory_of_mind(g, [b])
	_assert(failed, FishMindScience.predicted_charge(g, "loiterer") < 0.2,
			"a non-approaching neighbour is NOT learned as a charger (%.2f)" % FishMindScience.predicted_charge(g, "loiterer"))
	_assert(failed, FishMindScience.collect_predict_bid(g).is_empty(),
			"no anticipatory bid for a calm neighbour")

	if failed.is_empty():
		print("[smoke] theory_of_mind OK")
		quit(0)
	else:
		for msg in failed:
			push_error("[smoke] " + msg)
		quit(1)


func _mk(id: String, pos: Vector3) -> Fish:
	var f: Fish = Fish.new()
	root.add_child(f)
	f.id = id
	f.position = pos
	return f


func _has_bid(bids: Array, label: String) -> bool:
	for bd in bids:
		if str(bd.get("label", "")) == label:
			return true
	return false


func _assert(failed: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		failed.append(msg)
