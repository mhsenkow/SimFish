extends SceneTree

# REFINEMENT_II §A — mind-stack decay, digests, hint TTL, cache reset.

const GlobalWorkspace = preload("res://scripts/global_workspace.gd")
const MindCacheRegistry = preload("res://scripts/mind_cache_registry.gd")
const MindCacheStats = preload("res://scripts/mind_cache_stats.gd")
const MindReplayParity = preload("res://scripts/mind_replay_parity.gd")


func _initialize() -> void:
	await process_frame
	MindCacheStats.reset_for_test()
	var failed: Array[String] = []

	var bids_a: Array = [
		{"label": "food", "salience": 0.5, "coalition": ["food"], "coal_mask": 1},
	]
	var bids_b: Array = [
		{"label": "food", "salience": 0.5, "coalition": ["threat"], "coal_mask": 4},
	]
	_assert(failed, GlobalWorkspace.bids_digest(bids_a) != GlobalWorkspace.bids_digest(bids_b),
		"bid digest folds in coal_mask")

	var res_a: Dictionary = {"ignited": true, "contents": [
		{"label": "b", "salience": 0.6, "coal_mask": 2},
		{"label": "a", "salience": 0.6, "coal_mask": 1},
	]}
	var res_b: Dictionary = {"ignited": true, "contents": [
		{"label": "a", "salience": 0.6, "coal_mask": 1},
		{"label": "b", "salience": 0.6, "coal_mask": 2},
	]}
	_assert(failed,
		GlobalWorkspace.competition_digest(res_a) == GlobalWorkspace.competition_digest(res_b),
		"competition digest is order-independent")

	var slow: Array = [{"label": "food", "salience": 1.0, "coalition": ["food"], "coal_mask": 1}]
	GlobalWorkspace._decay_cached_bids(slow, 0.1)
	var sal_exp: float = float((slow[0] as Dictionary).get("salience", 0.0))
	_assert(failed, absf(sal_exp - exp(-0.35 * 0.1)) < 0.02,
		"slow-bid decay is exponential (got %.3f)" % sal_exp)

	var parent := Node3D.new()
	root.add_child(parent)
	var f := Fish.new()
	parent.add_child(f)
	f.id = "refine_fish"
	f._episodic_retrieval_hint = {"kind": "food", "salience": 0.5}
	f._episodic_retrieval_hint_ttl = 0.05
	MindCacheRegistry.tick_retrieval_hint(f, 0.1)
	_assert(failed, f._episodic_retrieval_hint.is_empty(), "retrieval hint TTL clears")

	f._ws_broadcast_digest = 42
	MindCacheRegistry.reset_transient(f)
	_assert(failed, int(f._ws_broadcast_digest) == -2, "cache registry clears broadcast digest")

	MindCacheStats.competition_misses = 0
	GlobalWorkspace.resolve_competition(f, bids_a)
	GlobalWorkspace.resolve_competition(f, bids_a)
	_assert(failed, MindCacheStats.competition_hits >= 1, "competition cache hits on repeat")

	parent.queue_free()
	if failed.is_empty():
		print("[smoke] refinement_ii_mind OK")
		quit(0)
	else:
		for msg in failed:
			push_error("[smoke] refinement_ii_mind FAIL: %s" % msg)
		quit(1)


func _assert(failed: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		failed.append(msg)
