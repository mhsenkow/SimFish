extends SceneTree

# LIVING_MOTION #41 + #1 — topological schooling contract smoke.

const _MotionWave = preload("res://scripts/motion_wave.gd")

func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	MindBoidsBuffer.reset_for_test()
	_MotionWave.reset_for_test()
	MindBoidsCompute.reset_for_test()

	var parent := Node3D.new()
	root.add_child(parent)

	var tetras: Array[Fish] = []
	for i in 8:
		var t := Fish.new()
		parent.add_child(t)
		t.id = "tetra_%d" % i
		t.species = "glassdart"
		t.swim_pattern = "school"
		t.schooling_strength = 1.6
		t.position = Vector3(cos(float(i) * 0.7) * 1.2, 1.0, sin(float(i) * 0.7) * 1.2)
		t.heading = Vector3.FORWARD
		t.velocity = Vector3(0.15, 0.0, 0.05)
		t.lead_score = float(i) * 0.1
		tetras.append(t)

	var betta := Fish.new()
	parent.add_child(betta)
	betta.id = "solo_betta"
	betta.species = "betta"
	betta.swim_pattern = "cruise"
	betta.schooling_strength = 0.0
	betta.position = Vector3(0.0, 1.2, 0.0)
	betta.heading = Vector3(1.0, 0.0, 0.0)
	betta.velocity = Vector3(0.05, 0.0, 0.0)

	var all: Array = []
	all.append_array(tetras)
	all.append(betta)

	MindBoidsBuffer.capture(all, 1)
	MindBoidsCompute.run()
	_assert(failed, MindBoidsBuffer.backend == "cpu", "topo schooling uses cpu backend")

	var betta_idx: int = MindBoidsBuffer.index_for(betta)
	_assert(failed, betta_idx >= 0, "betta captured in boids buffer")
	_assert(failed, not MindBoidsBuffer.uses_topo_at(betta_idx), "betta excluded from topo path")
	_assert(failed, MindBoidsBuffer.neighbor_counts[betta_idx] == 0,
		"betta ali/coh neighbor count stays zero (got %d)" % MindBoidsBuffer.neighbor_counts[betta_idx])

	var topo_slots: int = 0
	for t in tetras:
		var idx: int = MindBoidsBuffer.index_for(t)
		_assert(failed, MindBoidsBuffer.uses_topo_at(idx), "tetra on topo path")
		var nc: int = MindBoidsBuffer.neighbor_counts[idx]
		_assert(failed, nc > 0 and nc <= MindBoidsBuffer.N_TOPO,
			"tetra topo neighbor count in 1..%d (got %d)" % [MindBoidsBuffer.N_TOPO, nc])
		for s in MindBoidsBuffer.N_TOPO:
			if MindBoidsBuffer.topo_neighbor_at(idx, s) >= 0:
				topo_slots += 1
	_assert(failed, topo_slots >= 6, "topological links materialized (%d slots)" % topo_slots)

	_MotionWave.inject_at(all, Vector3(1.5, 1.0, 0.0), 0.9)
	var tetra_hot: int = 0
	for t in tetras:
		if t.motion_agitation > 0.2:
			tetra_hot += 1
	_assert(failed, tetra_hot >= 1, "startle injects agitation into schoolers")
	_assert(failed, betta.motion_agitation < 0.05,
		"betta ignores school wave (agitation=%.2f)" % betta.motion_agitation)

	_MotionWave.tick(all, 0.1)
	var spread: int = 0
	for t in tetras:
		if t.motion_agitation > 0.08:
			spread += 1
	_assert(failed, spread >= 2, "agitation propagates through topo links (%d fish)" % spread)

	# REFINEMENT_II #14 — wave integrates in sim-time (fast-forward dt scales).
	MindBoidsBuffer.reset_for_test()
	_MotionWave.reset_for_test()
	for t in tetras:
		t.motion_agitation = 0.0
	_MotionWave.inject_at(tetras, Vector3(1.5, 1.0, 0.0), 0.9)
	for step in 4:
		MindBoidsBuffer.capture(tetras, 20 + step)
		MindBoidsCompute.run()
		_MotionWave.tick(tetras, 0.025)
	var spread_ff: int = 0
	for t in tetras:
		if t.motion_agitation > 0.08:
			spread_ff += 1
	_assert(failed, spread_ff >= 2,
		"4× sim-time tick matches wall-time propagation (%d hot)" % spread_ff)

	# #31 — hover / low-schooling fish stay off topo + wave paths.
	var angel := Fish.new()
	parent.add_child(angel)
	angel.id = "solo_angel"
	angel.species = "angelfish"
	angel.swim_pattern = "hover"
	angel.schooling_strength = 0.25
	angel.position = Vector3(-1.5, 1.1, 0.5)
	angel.heading = Vector3(0.0, 0.0, 1.0)
	_assert(failed, not _MotionWave.uses_wave(angel), "hover angelfish skips wave path")
	all.append(angel)
	MindBoidsBuffer.capture(all, 2)
	MindBoidsCompute.run()
	var angel_idx: int = MindBoidsBuffer.index_for(angel)
	_assert(failed, angel_idx >= 0, "hover fish captured")
	_assert(failed, not MindBoidsBuffer.uses_topo_at(angel_idx), "hover fish off topo path")
	_assert(failed, MindBoidsBuffer.neighbor_counts[angel_idx] == 0,
		"hover fish ali/coh count zero")

	# #39 — cross-species neighbours contribute separation only.
	var rasbora := Fish.new()
	parent.add_child(rasbora)
	rasbora.id = "solo_rasbora"
	rasbora.species = "harlequin"
	rasbora.swim_pattern = "shoal"
	rasbora.schooling_strength = 1.1
	rasbora.position = tetras[0].position + Vector3(0.35, 0.0, 0.0)
	rasbora.heading = Vector3(1.0, 0.0, 0.0)
	rasbora.velocity = Vector3(0.1, 0.0, 0.0)
	MindBoidsBuffer.reset_for_test()
	var steer: Vector3 = tetras[0]._boids([rasbora], 1.0, 1.0)
	_assert(failed, tetras[0]._boids_neighbor_count == 0,
		"non-conspecifics do not ali/coh (count=%d)" % tetras[0]._boids_neighbor_count)
	_assert(failed, steer.length_squared() > 1e-5,
		"cross-species separation still steers")

	# REFINEMENT_II #79 — dart pool steals oldest under mass startle.
	const DartTrailPool = preload("res://scripts/dart_trail_pool.gd")
	DartTrailPool.reset_for_test()
	var trail_parent := Node3D.new()
	root.add_child(trail_parent)
	var gp := Transform3D(Basis.IDENTITY, Vector3(1.0, 1.0, 0.0))
	var dart_ok: int = 0
	for _i in DartTrailPool.POOL_SIZE + 3:
		if DartTrailPool.spawn(trail_parent, gp, Color.CYAN, Vector3.FORWARD, Callable()):
			dart_ok += 1
	_assert(failed, dart_ok >= DartTrailPool.POOL_SIZE,
		"dart pool serves under overload (%d)" % dart_ok)
	DartTrailPool.reset_for_test()
	trail_parent.queue_free()

	parent.queue_free()
	if failed.is_empty():
		print("[smoke] murmuration OK")
		quit(0)
	else:
		for msg in failed:
			push_error("[smoke] murmuration FAIL: %s" % msg)
		quit(1)


func _assert(failed: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		failed.append(msg)
