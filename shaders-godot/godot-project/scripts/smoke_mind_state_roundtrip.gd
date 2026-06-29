extends SceneTree

# MindState round-trip golden test (ENGINEERING_EXCELLENCE #14/#15 / OPUS_HANDOFF
# 0E). MindState is the sanctioned bridge between the cognitive modules and the
# Fish's scalar fields (mind_state.gd sync_from_fish / apply_to_fish). This pins
# its contract so the eventual "MindState as the SOLE channel" migration can't
# silently corrupt the mind:
#   - sync_from_fish copies every tracked field off the fish
#   - apply_to_fish writes the writable subset back, byte-stable on round-trip
#   - apply_to_fish does NOT clobber sync-only fields (hunger, neuromodulators)
#   - dict-typed fields (workspace, self_model) are deep-copied, not aliased


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	_assert(failed, load("res://scripts/mind_state.gd") != null, "mind_state.gd compiles")

	var f: Fish = Fish.new()
	root.add_child(f)
	f.id = "ms-roundtrip"
	# Writable-on-apply scalars.
	f.mood = 0.31
	f.arousal = 0.62
	f.vigilance = 0.18
	f.stress = 0.44
	f.surprise = 0.27
	f.curiosity_drive = 0.55
	f.spooked = 0.09
	f.attention_focus = "food"
	f.current_intention = "approach"
	f._current_thought = "is that food?"
	f._workspace_ignited = true
	f._mind_workspace = [{"label": "food", "salience": 0.7, "coalition": "food"}]
	f._mind_self_model = {"feel": "curious", "agency": "self"}
	f._thought_stream = "a small bright thing drifts down"
	# Sync-only scalars (read by sync, NOT written by apply — owned elsewhere).
	f.hunger = 0.66
	f.familiarity = 0.4
	f.dopamine = 0.7
	f.serotonin = 0.6
	f.cortisol = 0.15

	# --- sync_from_fish copies tracked fields off the fish.
	var ms = MindState.for_fish(f, true)
	_assert(failed, is_equal_approx(ms.mood, 0.31) and is_equal_approx(ms.arousal, 0.62),
			"sync copies affect scalars")
	_assert(failed, ms.attention_focus == "food" and ms.current_intention == "approach",
			"sync copies cognitive labels")
	_assert(failed, is_equal_approx(ms.hunger, 0.66) and is_equal_approx(ms.dopamine, 0.7),
			"sync copies sync-only scalars (hunger/neuromodulators)")
	_assert(failed, ms.workspace.size() == 1 and String(ms.workspace[0].get("label")) == "food",
			"sync copies the workspace array")
	_assert(failed, ms.workspace_ignited == true, "sync copies ignition flag")

	# --- deep-copy independence: mutating the fish's dict must NOT bleed into ms.
	f._mind_workspace.append({"label": "threat", "salience": 0.9})
	_assert(failed, ms.workspace.size() == 1, "ms.workspace is a deep copy, not aliased")

	# --- apply_to_fish writes the writable subset back, byte-stable.
	var g: Fish = Fish.new()
	root.add_child(g)
	g.id = "ms-target"
	g.hunger = 0.05        # sync-only; apply must NOT touch it
	g.dopamine = 0.45
	ms.mood = -0.2         # mutate writable fields on ms
	ms.attention_focus = "mate"
	ms.workspace = [{"label": "mate", "salience": 0.8}]
	ms.apply_to_fish(g)
	_assert(failed, is_equal_approx(g.mood, -0.2), "apply writes mood back")
	_assert(failed, g.attention_focus == "mate", "apply writes attention_focus back")
	_assert(failed, g._mind_workspace.size() == 1 and String(g._mind_workspace[0].get("label")) == "mate",
			"apply writes the workspace back")

	# --- apply must NOT clobber sync-only fields.
	_assert(failed, is_equal_approx(g.hunger, 0.05),
			"apply leaves sync-only hunger untouched")
	_assert(failed, is_equal_approx(g.dopamine, 0.45),
			"apply leaves sync-only dopamine untouched")

	# --- full round-trip is byte-stable for the writable subset:
	# fish -> sync -> apply -> sync again -> identical snapshot.
	var ms2 = MindState.for_fish(g, true)
	var before: Dictionary = ms2.snapshot()
	ms2.apply_to_fish(g)
	var ms3 = MindState.for_fish(g, true)
	var after: Dictionary = ms3.snapshot()
	_assert(failed, _snapshots_equal(before, after),
			"sync->apply->sync is byte-stable (no drift)")

	if failed.is_empty():
		print("[smoke] mind_state_roundtrip OK")
		quit(0)
	else:
		for m in failed:
			push_error("[smoke] " + m)
		quit(1)


func _snapshots_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.keys().size() != b.keys().size():
		return false
	for k in a.keys():
		var av: Variant = a[k]
		var bv: Variant = b.get(k, null)
		if av is float and bv is float:
			if not is_equal_approx(av, bv):
				return false
		elif str(av) != str(bv):
			return false
	return true


func _assert(failed: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		failed.append(msg)
