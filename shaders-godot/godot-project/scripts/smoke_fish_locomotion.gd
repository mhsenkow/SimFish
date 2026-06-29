extends SceneTree

# FishLocomotion carve smoke (ENGINEERING_EXCELLENCE #1 / OPUS_HANDOFF 0C).
# Verifies the boundary/collision-avoidance steering extracted out of fish.gd:
#   - fish.gd + fish_locomotion.gd compile
#   - the thin Fish delegates return identical results to the static funcs
#   - a 50-step separation loop (3 crowded fish) stays finite and de-crowds
#     (the "3 fish, 50 ticks, no NaN positions" acceptance, exercised through
#      the extracted clearance push as the integrator — no full SimDriver needed)


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	# Force-compile both files — a parse error from the 0C edits fails here.
	_assert(failed, load("res://scripts/fish.gd") != null, "fish.gd must compile")
	_assert(failed, load("res://scripts/fish_locomotion.gd") != null,
			"fish_locomotion.gd must compile")

	# --- Delegate identity: Fish's thin wrappers == the static funcs (proves the
	# extraction preserves behavior at the call site). Bare fish (no world/sim) →
	# boundary helpers return safe defaults, hardscape early-returns ZERO.
	var a: Fish = _make_fish("loco-a", Vector3(0.0, 2.0, 0.0))
	var b: Fish = _make_fish("loco-b", Vector3(0.05, 2.0, 0.0))
	var c: Fish = _make_fish("loco-c", Vector3(-0.05, 2.0, 0.0))
	var nbrs: Array = [b, c]

	var box := AABB(Vector3(-8, 0, -8), Vector3(16, 10, 16))
	_assert(failed, a._wall_avoid(box) == FishLocomotion.wall_avoid(a, box),
			"_wall_avoid delegate matches static")
	_assert(failed,
			a._local_clearance_push(nbrs, []) == FishLocomotion.local_clearance_push(a, nbrs, []),
			"_local_clearance_push delegate matches static")
	_assert(failed, a._hardscape_clearance_push() == FishLocomotion.hardscape_clearance_push(a),
			"_hardscape_clearance_push delegate matches static")

	# --- hardscape with no sim → ZERO and finite.
	var hs: Vector3 = FishLocomotion.hardscape_clearance_push(a)
	_assert(failed, hs == Vector3.ZERO and _finite(hs), "hardscape push is ZERO/finite with no sim")

	# --- wall_avoid with no world → ZERO and finite (safe defaults).
	var wa: Vector3 = FishLocomotion.wall_avoid(a, box)
	_assert(failed, wa == Vector3.ZERO and _finite(wa), "wall_avoid is ZERO/finite with no world")

	# --- 50-step separation loop: three nearly-coincident fish should de-crowd
	# under the clearance push and never produce NaN/inf.
	var fish: Array[Fish] = [a, b, c]
	var start_min: float = _min_pair_dist(fish)
	for _step in 50:
		var pushes: Array[Vector3] = []
		for fi in fish:
			var others: Array = []
			for fj in fish:
				if fj != fi:
					others.append(fj)
			pushes.append(FishLocomotion.local_clearance_push(fi, others, []))
		for i in fish.size():
			var p: Vector3 = pushes[i]
			if not _finite(p):
				failed.append("clearance push went non-finite at step %d" % _step)
				break
			fish[i].position += p * 0.1
			if not _finite(fish[i].position):
				failed.append("fish position went non-finite at step %d" % _step)
				break
	var end_min: float = _min_pair_dist(fish)
	_assert(failed, _finite_f(end_min) and end_min > start_min,
			"crowded fish separate over 50 steps (%.3f → %.3f)" % [start_min, end_min])
	_assert(failed, end_min > 0.1, "fish reach a sane personal space (got %.3f)" % end_min)

	if failed.is_empty():
		print("[smoke] fish_locomotion OK")
		quit(0)
	else:
		for f in failed:
			push_error("[smoke] " + f)
		quit(1)


func _make_fish(id: String, pos: Vector3) -> Fish:
	var f: Fish = Fish.new()
	# In-tree so global_position (used by wall_avoid) resolves cleanly.
	root.add_child(f)
	f.id = id
	f.position = pos
	f.max_speed = 1.0
	f.speed = 0.5
	f.mouth_orientation = 0
	return f


func _min_pair_dist(fish: Array) -> float:
	var m: float = INF
	for i in fish.size():
		for j in range(i + 1, fish.size()):
			m = minf(m, (fish[i].position - fish[j].position).length())
	return m


func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _finite_f(x: float) -> bool:
	return is_finite(x)


func _assert(failed: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		failed.append(msg)
