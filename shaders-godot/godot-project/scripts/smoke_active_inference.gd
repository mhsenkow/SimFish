extends SceneTree

# 1A / META #1 — active inference as bid currency. Expected free energy (info gain
# + goal value) from the per-fish generative model becomes a workspace bid, so a
# fish acts to REDUCE uncertainty (Friston's free-energy principle), not just react
# to surprise. Verifies the drive fires, the allostasis/dark-room guard suppresses
# it under stress, the conservative (named/familiar) rollout gate holds, and the
# steer is finite.

const GlobalWorkspace = preload("res://scripts/global_workspace.gd")
const MindWorldModel = preload("res://scripts/mind_world_model.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	# Named, curious, calm fish → exploring has epistemic value.
	var f: Fish = Fish.new()
	root.add_child(f)
	f.id = "ai-sage"
	f.fish_name = "Sage"
	f.stress = 0.05
	f.curiosity_drive = 0.9
	f.hunger = 0.1
	MindWorldModel.ensure_model(f)

	var efe: float = MindWorldModel.expected_free_energy_explore(f)
	_assert(failed, efe > 0.45, "calm curious fish has high expected free energy (%.2f)" % efe)
	_assert(failed, _has_bid(GlobalWorkspace.collect_bids(f, null), "free_energy"),
			"high-EFE named fish bids free_energy (the active-inference drive)")

	# Allostasis / dark-room guard: a scared fish does not go sightseeing.
	f.stress = 0.7
	_assert(failed, not _has_bid(GlobalWorkspace.collect_bids(f, null), "free_energy"),
			"stress suppresses the free_energy bid")

	# Conservative rollout: an anonymous, unfamiliar fish is excluded for now.
	var g: Fish = Fish.new()
	root.add_child(g)
	g.id = "ai-anon"
	g.fish_name = ""
	g.familiarity = 0.0
	g.stress = 0.05
	g.curiosity_drive = 0.9
	MindWorldModel.ensure_model(g)
	_assert(failed, not _has_bid(GlobalWorkspace.collect_bids(g, null), "free_energy"),
			"anonymous fish excluded from the conservative rollout")

	# The free_energy focus yields a finite epistemic-foraging steer.
	var bias: Vector3 = GlobalWorkspace._bias_for(f, "free_energy", 0.6)
	_assert(failed, _finite(bias), "free_energy bias is finite")

	if failed.is_empty():
		print("[smoke] active_inference OK")
		quit(0)
	else:
		for m in failed:
			push_error("[smoke] " + m)
		quit(1)


func _has_bid(bids: Array, label: String) -> bool:
	for b in bids:
		if str(b.get("label", "")) == label:
			return true
	return false


func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _assert(failed: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		failed.append(msg)
