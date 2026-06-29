extends SceneTree

# META #8 — sleep consolidates episodic → semantic. Repeated frights in one region
# distil, during sleep, into a generalized spatial schema ("the far corner is
# dangerous") the fish wakes up ACTING on: a caution bid when it re-enters that
# region. Verifies schema formation, the spatial valence query, the learned-region
# bid reaching the workspace, and that neutral / too-sparse memories form nothing.

const GlobalWorkspace = preload("res://scripts/global_workspace.gd")
const EpisodicMemory = preload("res://scripts/episodic_memory.gd")

const DANGER := Vector3(8, 2, 8)
const SAFE := Vector3(-8, 2, -8)


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	MindAblation.reset()

	# A fish startled five times in the far corner.
	var f: Fish = _mk("scarred")
	for i in 5:
		var jitter := Vector3(0.3 * sin(i), 0.0, 0.3 * cos(i))
		EpisodicMemory.encode_episode(f, "startled", "a shadow lunged", 0.7, DANGER + jitter)

	EpisodicMemory.consolidate_sleep(f)
	_assert(failed, not (f._semantic_schemas as Array).is_empty(),
			"sleep distils a semantic schema from repeated frights")

	var vd: float = EpisodicMemory.schema_valence_at(f, DANGER)
	var vs: float = EpisodicMemory.schema_valence_at(f, SAFE)
	_assert(failed, vd < -0.4, "the learned region reads as dangerous (%.2f)" % vd)
	_assert(failed, is_equal_approx(vs, 0.0), "a distant region carries no learned valence (%.2f)" % vs)

	# Acts on the generalized rule: caution bid when back in the bad region...
	f.position = DANGER
	f.spooked = 0.0
	var bid: Dictionary = EpisodicMemory.collect_schema_bid(f)
	_assert(failed, str(bid.get("label", "")) == "threat" and float(bid.get("salience", 0.0)) > 0.0,
			"re-entering the learned-dangerous region raises a caution bid")
	_assert(failed, _has_bid(GlobalWorkspace.collect_bids(f, null), "threat"),
			"schema caution enters the workspace (wakes with a usable rule, not raw episodes)")
	# ...and not in a region it never learned about.
	f.position = SAFE
	_assert(failed, EpisodicMemory.collect_schema_bid(f).is_empty(),
			"no caution in an unlearned region")

	# Control: neutral-kind memories carry no valence → no schema forms.
	var g: Fish = _mk("neutral")
	for i in 5:
		EpisodicMemory.encode_episode(g, "idle_drift", "nothing happened", 0.7, DANGER)
	EpisodicMemory.consolidate_sleep(g)
	_assert(failed, (g._semantic_schemas as Array).is_empty(),
			"neutral-valence memories distil no danger/reward schema")

	if failed.is_empty():
		print("[smoke] sleep_consolidation OK")
		quit(0)
	else:
		for msg in failed:
			push_error("[smoke] " + msg)
		quit(1)


func _mk(id: String) -> Fish:
	var fsh: Fish = Fish.new()
	root.add_child(fsh)
	fsh.id = id
	return fsh


func _has_bid(bids: Array, label: String) -> bool:
	for bd in bids:
		if str(bd.get("label", "")) == label:
			return true
	return false


func _assert(failed: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		failed.append(msg)
