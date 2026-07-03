extends SceneTree

# SENTIENCE_THE_RISING_CURVE pass 3 — rung-1/2 kill tests, Goodhart tripwire,
# gray-cube replay, developmental invariant hooks.

const DeltaG = preload("res://scripts/delta_g.gd")
const PokeHarness = preload("res://scripts/poke_harness.gd")
const MindWorldModel = preload("res://scripts/mind_world_model.gd")
const FeedMockSim = preload("res://scripts/feed_mock_sim.gd")


func _initialize() -> void:
	await process_frame
	if not _run_all():
		quit(1)
		return
	print("[smoke_rising_curve] OK")
	quit(0)


func _fail(msg: String) -> bool:
	push_error(msg)
	return false


func _run_all() -> bool:
	# §C28 — Goodhart CI tripwire.
	var trip: Dictionary = DeltaG.scan_goodhart_tripwire()
	if not bool(trip.get("passed", false)):
		return _fail("Goodhart tripwire: ΔG in reward paths %s" % str(trip.get("hits", [])))
	# §A12 — gray-cube visual replay fixture.
	var gray: Dictionary = DeltaG.gray_cube_replay_fixture()
	if not bool(gray.get("passed", false)):
		return _fail("gray-cube replay invariant failed")
	# §D33 — state-defense audit documents gated script leaks.
	var audit: Array = FishHomeostasis.audit_script_leaks()
	var gated_food: bool = false
	for row in audit:
		if row is Dictionary and str((row as Dictionary).get("id", "")) == "goal_timer_revisit_food":
			gated_food = bool((row as Dictionary).get("gated", false))
	if not gated_food:
		return _fail("homeostasis audit missing gated revisit_food")
	# §D39 — rung-1 move-food kill test.
	var f: Fish = Fish.new()
	f.id = "rung1"
	f.position = Vector3(0.0, 2.0, 0.0)
	var r1: Dictionary = FishHomeostasis.rung1_move_food_kill(
			f, Vector3(3.0, 2.0, 1.0), Vector3(-3.5, 2.0, -2.0))
	if not bool(r1.get("passed", false)):
		return _fail("rung-1 move-food kill failed (reorient=%s dg=%.3f)"
				% [r1.get("reoriented", false), float(r1.get("delta_g_after_move", 0.0))])
	# Live mock-sim variant.
	var sim: Node = FeedMockSim.new()
	sim.feed_pos = Vector3(2.0, 2.5, 0.5)
	f.hunger = 0.8
	var live1: Dictionary = PokeHarness.live_rung1_kill(f, sim)
	if not bool(live1.get("passed", false)):
		return _fail("live rung-1 kill failed")
	# §E42 — world model learns over life (PE falls).
	var wm: Fish = Fish.new()
	wm.id = "wm-learn"
	for i in 200:
		wm.hunger = 0.35 + sin(i * 0.31) * 0.28
		wm.stress = 0.25 + cos(i * 0.23) * 0.18
		wm.curiosity_drive = 0.5
		wm.speed = 0.4 + sin(i * 0.19) * 0.2
		MindWorldModel.tick(wm, null, 0.1)
	if not MindWorldModel.pe_fell_over_life(wm, 40):
		var md: Dictionary = wm._world_model as Dictionary
		return _fail("world model PE should fall over life (err=%.3f gru=%.3f prog=%.3f)" % [
			float(md.get("error", 0.0)), float(md.get("gru_error", 0.0)),
			float(md.get("learning_progress", 0.0))])
	# §E51 — rung-2 novel-obstacle kill test.
	var r2: Dictionary = PokeHarness.live_rung2_kill(wm, null)
	if not bool(r2.get("passed", false)):
		return _fail("rung-2 novel-obstacle kill failed (novel_dg=%.3f)"
				% float(r2.get("delta_g_novel", 0.0)))
	return true
