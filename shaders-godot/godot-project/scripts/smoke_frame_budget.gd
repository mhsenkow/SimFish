extends SceneTree

# Pins the frame-budget contract.
#
# PerfGovernor.budget_pressure drives two expensive decisions: MindLOD's
# cognition tier per fish, and the adaptive resolution / shader-cost ladder.
# It used to be measured against a hardcoded 16.6 ms (60 fps) no matter what
# the frame rate was capped to. Mobile ships fps_cap = 30, so a device hitting
# its target exactly produced 33 ms frames, read as a 100% budget overrun, and
# permanently ran the mind kernel at its lowest tier with shader cost pinned
# at maximum. The budget must follow Engine.max_fps.


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	var restore_cap: int = Engine.max_fps

	# ---- Uncapped: the 60 fps budget still applies ---------------------------
	Engine.max_fps = 0
	PerfGovernor.reset_for_test()
	PerfGovernor.refresh_target()
	TestSupport.check(failed, is_equal_approx(PerfGovernor.target_frame_ms, PerfGovernor.TARGET_FRAME_MS),
		"uncapped budget is the 60 fps constant")
	for i in 90:
		PerfGovernor.record_frame(1.0 / 60.0)
	# The curve deliberately starts lifting at 85% of budget, so "on target"
	# is a small non-zero reading — but nowhere near the step-down gate.
	var on_target_uncapped: float = PerfGovernor.budget_pressure
	TestSupport.check(failed, on_target_uncapped < 0.2,
		"steady 60 fps uncapped -> slack (got %.2f)" % on_target_uncapped)
	TestSupport.check(failed, not PerfGovernor.governor_step_down() and not PerfGovernor.governor_step_up_block(),
		"on-target uncapped device trips no governor gate")
	for i in 90:
		PerfGovernor.record_frame(1.0 / 30.0)
	TestSupport.check(failed, PerfGovernor.budget_pressure > 0.6,
		"30 fps against a 60 fps budget -> real pressure (got %.2f)" % PerfGovernor.budget_pressure)

	# ---- Capped to 30: a steady 30 fps is success, not an overrun ------------
	Engine.max_fps = 30
	PerfGovernor.reset_for_test()
	PerfGovernor.refresh_target()
	TestSupport.check(failed, PerfGovernor.target_frame_ms > 30.0,
		"30 fps cap widens the budget (got %.1f ms)" % PerfGovernor.target_frame_ms)
	for i in 90:
		PerfGovernor.record_frame(1.0 / 30.0)
	var on_target_capped: float = PerfGovernor.budget_pressure
	# The whole point: hitting a 30 fps cap must read exactly like hitting a
	# 60 fps cap. Before the fix this was 1.0.
	# (Not exactly equal: the uncapped constant is 16.6 ms, a hair tighter than
	# a true 1/60 s, so the two curves land within a couple of percent.)
	TestSupport.check(failed, absf(on_target_capped - on_target_uncapped) < 0.02,
		"30 fps under a 30 fps cap reads the same as 60 under 60 (%.3f vs %.3f)"
			% [on_target_capped, on_target_uncapped])
	TestSupport.check(failed, not PerfGovernor.governor_step_down(),
		"capped-but-healthy device does not trip the step-down gate")
	TestSupport.check(failed, not PerfGovernor.governor_step_up_block(),
		"capped-but-healthy device is not blocked from stepping quality up")
	# A real hitch must still register even with the widened budget.
	for i in 90:
		PerfGovernor.record_frame(0.120)
	TestSupport.check(failed, PerfGovernor.budget_pressure > 0.6,
		"120 ms frames still register as pressure under a 30 fps cap")

	# A very low cap must not widen the budget without limit.
	Engine.max_fps = 5
	PerfGovernor.refresh_target()
	TestSupport.check(failed, PerfGovernor.target_frame_ms <= 50.0,
		"budget is clamped so a tiny cap cannot hide a 200 ms hitch")

	# The cap change has to be picked up mid-session, not just at reset.
	Engine.max_fps = 0
	PerfGovernor.record_frame(1.0 / 60.0)
	TestSupport.check(failed, is_equal_approx(PerfGovernor.target_frame_ms, PerfGovernor.TARGET_FRAME_MS),
		"record_frame re-reads the cap when it changes")

	# ---- record_frame must stay allocation-free ------------------------------
	PerfGovernor.reset_for_test()
	for i in 200:
		PerfGovernor.record_frame(1.0 / 60.0)
	var before: int = OS.get_static_memory_usage()
	for i in 2000:
		PerfGovernor.record_frame(1.0 / 60.0)
	var grew: int = OS.get_static_memory_usage() - before
	TestSupport.check(failed, grew < 262144,
		"2000 frames of governor bookkeeping allocate <256 KB (grew %d B)" % grew)

	# ---- The adaptive scaler must not chase an impossible target -------------
	var src: String = FileAccess.get_file_as_string("res://scripts/main.gd")
	TestSupport.check(failed, src.contains("target_fps = minf(target_fps, float(Engine.max_fps) * 0.97)"),
		"adaptive quality target is clamped to the fps cap")
	TestSupport.check(failed, src.contains("func _seed_render_budget_for_tier"),
		"first launch seeds a render budget from the device tier")
	TestSupport.check(failed, src.contains('"low": Vector2i(384, 216)'),
		"low-tier handhelds start below the desktop default")

	Engine.max_fps = restore_cap
	PerfGovernor.reset_for_test()

	if failed.is_empty():
		print("[smoke] frame_budget OK")
		quit(0)
	else:
		for f in failed:
			push_error("[smoke] FAIL: %s" % f)
		print("[smoke] frame_budget FAILED (%d)" % failed.size())
		quit(1)
