extends SceneTree

# META #14 + #18 — cognition-framework instrumentation.
#   #14 per-module ablation: every module has an independent enable; disabling one
#       removes its effect (verified through the active-inference bid in collect_bids).
#   #18 cognition trace bus: structured per-tick events on a ring buffer, zero-cost
#       when disabled, cap-bounded, populated by a real cognitive cycle.

const GlobalWorkspace = preload("res://scripts/global_workspace.gd")
const MindWorldModel = preload("res://scripts/mind_world_model.gd")
const MindCycle = preload("res://scripts/mind_cycle.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	MindAblation.reset()
	MindTrace.set_enabled(false)
	MindTrace.clear()

	# --- #14: flag API defaults to enabled, toggles, resets.
	_assert(failed, MindAblation.enabled(MindAblation.WORLD_MODEL), "modules enabled by default")
	MindAblation.set_enabled(MindAblation.WORLD_MODEL, false)
	_assert(failed, not MindAblation.enabled(MindAblation.WORLD_MODEL), "set_enabled(false) disables")
	MindAblation.reset()
	_assert(failed, MindAblation.enabled(MindAblation.WORLD_MODEL), "reset re-enables")

	# --- #14: a real ablation — the active-inference (free_energy) drive disappears
	# when the world-model module is lesioned, and returns when restored.
	var f: Fish = _mk("ablate")
	f.fish_name = "Probe"
	f.stress = 0.05
	f.curiosity_drive = 0.9
	f.hunger = 0.1
	MindWorldModel.ensure_model(f)
	_assert(failed, _has_bid(GlobalWorkspace.collect_bids(f, null), "free_energy"),
			"world-model intact → active-inference drive present")
	MindAblation.set_enabled(MindAblation.WORLD_MODEL, false)
	_assert(failed, not _has_bid(GlobalWorkspace.collect_bids(f, null), "free_energy"),
			"world-model lesioned → active-inference drive gone (ablation works)")
	MindAblation.reset()
	_assert(failed, _has_bid(GlobalWorkspace.collect_bids(f, null), "free_energy"),
			"restored → drive returns")

	# --- #18: disabled trace is a true no-op.
	MindTrace.set_enabled(false)
	MindTrace.record("x", {"focus": "food"})
	_assert(failed, MindTrace.size() == 0, "disabled trace records nothing (zero cost)")

	# --- #18: enabled trace records, keeps order, and is cap-bounded.
	MindTrace.set_enabled(true)
	for i in (MindTrace.CAP + 25):
		MindTrace.record("f%d" % i, {"focus": "food", "n": i})
	_assert(failed, MindTrace.size() == MindTrace.CAP, "ring buffer is cap-bounded")
	var tail: Array = MindTrace.recent(3)
	_assert(failed, tail.size() == 3 and int(tail[2]["n"]) == MindTrace.CAP + 24,
			"recent() returns the latest events in order")

	# --- #18: a real cognitive cycle emits a trace event.
	MindTrace.clear()
	var g: Fish = _mk("traced")
	g.fish_name = "Trace"
	g.hunger = 0.8   # a food bid so the workspace has content
	var ms = MindChannel.for_cycle(g, true)
	MindCycle.run_attention_phase(g, null, ms, 0.1)
	_assert(failed, MindTrace.size() >= 1, "a cognitive cycle emits a trace event")
	if MindTrace.size() >= 1:
		var ev: Dictionary = MindTrace.recent(1)[0]
		_assert(failed, ev.has("focus") and ev.has("ignited") and str(ev.get("id", "")) == "traced",
				"trace event carries focus/ignition and the fish id")

	MindTrace.set_enabled(false)
	MindAblation.reset()

	if failed.is_empty():
		print("[smoke] cognition_framework OK")
		quit(0)
	else:
		for msg in failed:
			push_error("[smoke] " + msg)
		quit(1)


func _mk(id: String) -> Fish:
	var f: Fish = Fish.new()
	root.add_child(f)
	f.id = id
	return f


func _has_bid(bids: Array, label: String) -> bool:
	for b in bids:
		if str(b.get("label", "")) == label:
			return true
	return false


func _assert(failed: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		failed.append(msg)
