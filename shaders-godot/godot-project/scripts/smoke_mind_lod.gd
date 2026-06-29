extends SceneTree

# META #20 — cognition LOD tiers. Verifies tier assignment by status / visibility /
# budget pressure, and that the phase gates are consistent with the tier ladder.


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	var guardian: Fish = _mk("g", true, "")
	var named: Fish = _mk("n", false, "Sage")
	var familiar: Fish = _mk("fam", false, "")
	familiar.familiarity = 0.7
	var nobody: Fish = _mk("x", false, "")

	# Visibility + status → tier.
	_assert(failed, MindLOD.tier_for(guardian, true) == MindLOD.T3_VOICE,
			"visible guardian thinks at full depth (voice)")
	_assert(failed, MindLOD.tier_for(named, true) == MindLOD.T3_VOICE,
			"visible named fish earns a voice")
	_assert(failed, MindLOD.tier_for(nobody, true) == MindLOD.T2_WORLD_MODEL,
			"a visible anonymous fish runs world-model but not voice")
	_assert(failed, MindLOD.tier_for(named, false) == MindLOD.T2_WORLD_MODEL,
			"off-screen protagonist keeps its world model")
	_assert(failed, MindLOD.tier_for(familiar, false) == MindLOD.T1_WORKSPACE,
			"off-screen familiar keeps attention only")
	_assert(failed, MindLOD.tier_for(nobody, false) == MindLOD.T0_REFLEX,
			"a distant nobody runs reflex only")

	# Budget pressure sheds depth.
	_assert(failed, MindLOD.tier_for(guardian, true, 0.5) == MindLOD.T2_WORLD_MODEL,
			"moderate load drops the guardian off voice")
	_assert(failed, MindLOD.tier_for(guardian, true, 0.9) == MindLOD.T1_WORKSPACE,
			"heavy load sheds the guardian down to attention")

	# Gate consistency along the ladder.
	_assert(failed, not MindLOD.runs_workspace(MindLOD.T0_REFLEX)
			and not MindLOD.runs_world_model(MindLOD.T0_REFLEX)
			and not MindLOD.runs_voice(MindLOD.T0_REFLEX),
			"T0 runs nothing above reflex")
	_assert(failed, MindLOD.runs_workspace(MindLOD.T3_VOICE)
			and MindLOD.runs_world_model(MindLOD.T3_VOICE)
			and MindLOD.runs_voice(MindLOD.T3_VOICE),
			"T3 runs the full stack")
	_assert(failed, MindLOD.runs_workspace(MindLOD.T2_WORLD_MODEL)
			and MindLOD.runs_world_model(MindLOD.T2_WORLD_MODEL)
			and not MindLOD.runs_voice(MindLOD.T2_WORLD_MODEL),
			"T2 runs world-model but not voice")

	if failed.is_empty():
		print("[smoke] mind_lod OK")
		quit(0)
	else:
		for m in failed:
			push_error("[smoke] " + m)
		quit(1)


func _mk(id: String, guardian: bool, nm: String) -> Fish:
	var f: Fish = Fish.new()
	root.add_child(f)
	f.id = id
	f.is_guardian = guardian
	f.fish_name = nm
	return f


func _assert(failed: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		failed.append(msg)
