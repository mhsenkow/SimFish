extends SceneTree

# Sentience eval harness runner (docs/SENTIENCE_EVAL_HARNESS.md). Runs the suite of
# theory-grounded functional-sentience invariants, prints the scorecard, and fails
# CI if any REQUIRED invariant fails. This is the gate the risky mind epics
# (#1-full active inference, #19, LOD wiring) must be built against.


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	MindEval.enable_dev_run(true)
	print(MindEval.scorecard(root))
	var r: Dictionary = MindEval.run_all(root)

	TestSupport.check(failed, not MindEval.invariants().is_empty(), "the suite is non-empty")
	TestSupport.check(failed, bool(r["all_required_passed"]),
			"all required functional-sentience invariants pass (index %s)" % str(r["index"]))
	TestSupport.check(failed, bool(r.get("honesty_passed", false)),
			"honesty gate passes (no phenomenal overclaim)")
	# The honest frame is part of the contract: the harness must not overclaim.
	TestSupport.check(failed, MindEval.HONEST_NOTE.to_lower().find("not a claim") != -1,
			"the scorecard carries the honesty disclaimer (functional, not phenomenal)")

	# Rollback path: legacy hand-tuned drives still pass the harness when EFE is off.
	var cfg: Node = get_root().get_node_or_null("/root/TankConfig")
	if cfg != null:
		var saved: bool = bool(cfg.consciousness_active_inference)
		cfg.consciousness_active_inference = false
		var r_legacy: Dictionary = MindEval.run_all(root)
		cfg.consciousness_active_inference = saved
		TestSupport.check(failed, bool(r_legacy["all_required_passed"]),
				"legacy drive path passes eval when EFE flag is off (index %s)" % str(r_legacy["index"]))

	quit(TestSupport.report("smoke_mind_eval", failed))
