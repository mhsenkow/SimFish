extends SceneTree

# LIVING_MOTION #97 — topological N_topo=7 should stay cheap at high density.

const _MotionWave = preload("res://scripts/motion_wave.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	MindBoidsBuffer.reset_for_test()
	_MotionWave.reset_for_test()
	MindBoidsCompute.reset_for_test()

	var parent := Node3D.new()
	root.add_child(parent)

	var school: Array[Fish] = []
	for i in 64:
		var f := Fish.new()
		parent.add_child(f)
		f.id = "perf_%d" % i
		f.species = "glassdart"
		f.swim_pattern = "school"
		f.schooling_strength = 1.6
		f.position = Vector3(
			cos(float(i) * 0.31) * 1.1 + randf_range(-0.08, 0.08),
			1.0 + randf_range(-0.05, 0.05),
			sin(float(i) * 0.31) * 1.1 + randf_range(-0.08, 0.08))
		f.heading = Vector3(1.0, 0.0, 0.0)
		school.append(f)

	var all: Array = []
	all.append_array(school)

	var t0: int = Time.get_ticks_usec()
	for step in 24:
		MindBoidsBuffer.capture(all, step)
		MindBoidsCompute.run()
		_MotionWave.tick(all, 0.1)
	var elapsed_us: int = Time.get_ticks_usec() - t0
	var per_fish_us: float = float(elapsed_us) / float(64 * 24)
	print("[smoke] topo_boids 64×24 ticks = %d µs (%.1f µs/fish/tick)" % [elapsed_us, per_fish_us])
	_assert(failed, per_fish_us < 900.0,
		"topo boids perf budget (%.1f µs/fish/tick)" % per_fish_us)

	var hot: int = 0
	_MotionWave.inject_at(all, Vector3(1.2, 1.0, 0.0), 0.9)
	for step in 6:
		MindBoidsBuffer.capture(all, 100 + step)
		MindBoidsCompute.run()
		_MotionWave.tick(all, 0.1)
	for f in school:
		if f.motion_agitation > 0.05:
			hot += 1
	_assert(failed, hot >= 4, "dense flock still propagates waves (%d hot)" % hot)

	parent.queue_free()
	if failed.is_empty():
		print("[smoke] motion_topo_perf OK")
		quit(0)
	else:
		for msg in failed:
			push_error("[smoke] motion_topo_perf FAIL: %s" % msg)
		quit(1)


func _assert(failed: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		failed.append(msg)
