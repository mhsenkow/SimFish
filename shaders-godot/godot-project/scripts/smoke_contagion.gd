extends SceneTree

# META #10 — emotional contagion. Verifies affect spreads toward the local school
# mean (panic in, calm in), damped (converges, never overshoots/explodes), and
# scaled by social susceptibility (bold fish absorb less than timid ones).


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	# A calm fish surrounded by agitated neighbours grows agitated.
	var calm: Fish = _mk("calm", Vector3(0, 2, 0), 0.1, 0.0)
	var mob: Array = [
		_mk("p1", Vector3(1, 2, 0), 0.9, -0.4),
		_mk("p2", Vector3(-1, 2, 0), 0.9, -0.4),
		_mk("p3", Vector3(0, 2, 1), 0.9, -0.4),
	]
	var a0: float = calm.arousal
	for _i in 30:
		MindContagion.tick(calm, mob, 0.1)
	_assert(failed, calm.arousal > a0 + 0.2, "calm fish catches the mob's agitation (%.2f→%.2f)" % [a0, calm.arousal])
	_assert(failed, calm.arousal <= 1.0 and calm.arousal <= 0.9 + 1e-3,
			"contagion never overshoots the local mean / clamps (got %.3f)" % calm.arousal)
	_assert(failed, calm.mood < 0.0, "negative school mood spreads too (slower)")

	# A jittery fish among calm neighbours settles.
	var jittery: Fish = _mk("jittery", Vector3(0, 2, 0), 0.9, 0.0)
	var serene: Array = [
		_mk("s1", Vector3(1, 2, 0), 0.1, 0.2),
		_mk("s2", Vector3(-1, 2, 0), 0.1, 0.2),
	]
	for _j in 30:
		MindContagion.tick(jittery, serene, 0.1)
	_assert(failed, jittery.arousal < 0.5, "jittery fish calms among serene neighbours (%.2f)" % jittery.arousal)

	# Susceptibility: a bold loner absorbs less than a timid schooler (same mob).
	var bold: Fish = _mk("bold", Vector3(0, 2, 0), 0.1, 0.0)
	bold.personality = {"boldness": 0.95, "sociability": 0.1}
	bold.schooling_strength = 0.1
	var timid: Fish = _mk("timid", Vector3(0, 2, 0), 0.1, 0.0)
	timid.personality = {"boldness": 0.05, "sociability": 0.9}
	timid.schooling_strength = 0.9
	for _k in 10:
		MindContagion.tick(bold, mob, 0.1)
		MindContagion.tick(timid, mob, 0.1)
	_assert(failed, timid.arousal > bold.arousal,
			"timid schooler absorbs more than a bold loner (timid=%.2f bold=%.2f)" % [timid.arousal, bold.arousal])
	_assert(failed, MindContagion.susceptibility(bold) < MindContagion.susceptibility(timid),
			"bold fish has lower susceptibility")

	# No neighbours → no change (and no crash).
	var alone: Fish = _mk("alone", Vector3(0, 2, 0), 0.5, 0.0)
	MindContagion.tick(alone, [], 0.1)
	_assert(failed, is_equal_approx(alone.arousal, 0.5), "a lone fish's affect is untouched")

	if failed.is_empty():
		print("[smoke] contagion OK")
		quit(0)
	else:
		for msg in failed:
			push_error("[smoke] " + msg)
		quit(1)


func _mk(id: String, pos: Vector3, arousal: float, mood: float) -> Fish:
	var f: Fish = Fish.new()
	root.add_child(f)
	f.id = id
	f.position = pos
	f.arousal = arousal
	f.mood = mood
	return f


func _assert(failed: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		failed.append(msg)
