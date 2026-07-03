extends SceneTree

# SENTIENCE_THE_RISING_CURVE — ΔG estimator calibration + poke robustness + isolation.

const DeltaG = preload("res://scripts/delta_g.gd")
const PokeHarness = preload("res://scripts/poke_harness.gd")
const DeltaGCurve = preload("res://scripts/delta_g_curve.gd")
const FishMind = preload("res://scripts/fish_mind.gd")


func _initialize() -> void:
	await process_frame
	if not _run_all():
		quit(1)
		return
	print("[smoke_delta_g] OK")
	quit(0)


func _fail(msg: String) -> bool:
	push_error(msg)
	return false


func _run_all() -> bool:
	if not DeltaG.is_diagnostic_only():
		return _fail("ΔG must remain diagnostic-only")
	var iso: Dictionary = DeltaG.verify_reward_isolation()
	if not bool(iso.get("ok", false)):
		return _fail("reward isolation check failed")
	var ord: Dictionary = DeltaG.calibration_ordering()
	if not bool(ord.get("passed", false)):
		return _fail("calibration ordering failed (goal=%.3f boids=%.3f noise=%.3f scripted=%.3f)"
				% [ord.get("goal", 0.0), ord.get("boids", 0.0), ord.get("noise", 0.0), ord.get("scripted", 0.0)])
	var trip: Dictionary = DeltaG.scan_goodhart_tripwire()
	if not bool(trip.get("passed", false)):
		return _fail("Goodhart tripwire failed: %s" % str(trip.get("hits", [])))
	var gray: Dictionary = DeltaG.gray_cube_replay_fixture()
	if not bool(gray.get("passed", false)):
		return _fail("gray-cube replay fixture failed")
	var fx: Dictionary = DeltaG.calibration_fixtures()
	var dt: float = float(fx["dt"])
	var bounds: Dictionary = fx["bounds"]
	var goals: Dictionary = fx["goals"]
	var goal_pts: PackedVector3Array = fx["goal"]
	# Gray-cube invariance — positions only.
	var est_a: Dictionary = DeltaG.estimate(goal_pts, goals, dt, bounds)
	var est_b: Dictionary = DeltaG.estimate(goal_pts, goals, dt, bounds)
	if absf(float(est_a.get("delta_g", 0.0)) - float(est_b.get("delta_g", 0.0))) > 0.001:
		return _fail("gray-cube replay should be invariant")
	# §A11 — ΔG should beat dumb surface stats on goal pursuit.
	var fals: Dictionary = DeltaG.falsification_compare(goal_pts, goals, dt, bounds)
	if not bool(fals.get("dg_beats_surface", false)):
		return _fail("ΔG should beat surface statistic on goal path")
	if not bool(fals.get("dg_beats_surrogate", false)):
		return _fail("ΔG should beat surrogate on goal path")
	# Poke: move food.
	var food_a: Vector3 = Vector3(4.0, 2.0, 0.0)
	var food_b: Vector3 = Vector3(-4.0, 2.0, 0.0)
	var old_path: PackedVector3Array = fx["goal"]
	var new_path: PackedVector3Array = PackedVector3Array()
	var p: Vector3 = Vector3(-3.0, 2.0, 2.0)
	for i in 28:
		new_path.append(p)
		var to: Vector3 = food_b - p
		if to.length_squared() > 1e-6:
			p += to.normalized() * 1.2 * dt * 0.85
	var poke: Dictionary = PokeHarness.poke_move_food(old_path, food_a, food_b, new_path, dt, bounds)
	if float(poke.get("brittle_robustness", 1.0)) > 0.75:
		return _fail("memorized path should fail move-food poke (robust=%.2f)" % poke.get("brittle_robustness"))
	if float(poke.get("adaptive_delta_g", 0.0)) < 0.08:
		return _fail("re-planned path should keep ΔG high (%.3f)" % poke.get("adaptive_delta_g"))
	var body: Dictionary = PokeHarness.poke_change_body(goal_pts, goals, dt, bounds)
	if float(body.get("baseline", 0.0)) < 0.05:
		return _fail("change-body poke needs baseline ΔG")
	# Developmental curve + save roundtrip.
	var f: Fish = Fish.new()
	f.id = "dg-smoke"
	f.fish_name = "DgSmoke"
	f.familiarity = 0.55
	f.age = 120.0
	for i in DeltaG.MIN_SAMPLES + 4:
		f.position += Vector3(0.08, 0.0, -0.05)
		DeltaG.record_tick(f, dt)
	var est: Dictionary = DeltaG.estimate_fish(f, null, dt)
	if float(est.get("delta_g", 0.0)) < 0.0:
		return _fail("live trajectory estimate invalid")
	DeltaGCurve.record_robustness(f, 0.42, float(est.get("delta_g", 0.0)))
	f.age = 280.0
	DeltaGCurve.record_robustness(f, 0.58, float(est.get("delta_g", 0.0)) + 0.05)
	if DeltaGCurve.slope(f) <= 0.0:
		return _fail("robustness curve slope should rise")
	var bio: String = DeltaGCurve.biography_line(f)
	if bio == "":
		return _fail("biography line should exist after robustness samples")
	var mind_d: Dictionary = FishMind.mind_to_dict(f)
	var f2: Fish = Fish.new()
	f2.id = "dg-smoke-2"
	FishMind.apply_mind_dict(f2, mind_d)
	if (f2._delta_g_curve as Dictionary).get("samples", []).is_empty():
		return _fail("delta_g_curve not persisted in mind_to_dict")
	if (f2._delta_g_log as Array).is_empty():
		return _fail("delta_g log not persisted")
	# §J97 — reward paths must not import ΔG for steering.
	for path in ["res://scripts/mind_active_inference.gd", "res://scripts/global_workspace.gd",
			"res://scripts/fish_volition.gd", "res://scripts/fish_spark_behavior.gd"]:
		var text: String = FileAccess.get_file_as_string(path)
		if text.find("delta_g") != -1 or text.find("DeltaG") != -1:
			return _fail("reward path imports ΔG: %s" % path)
	return true
