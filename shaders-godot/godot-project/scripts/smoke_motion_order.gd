extends SceneTree

# LIVING_MOTION #95 — polarization rises after topological wave injection.

const _MotionWave = preload("res://scripts/motion_wave.gd")
const _MotionField = preload("res://scripts/motion_field.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	MindBoidsBuffer.reset_for_test()
	_MotionWave.reset_for_test()
	_MotionField.reset_for_test()
	MindBoidsCompute.reset_for_test()

	var parent := Node3D.new()
	root.add_child(parent)

	var school: Array[Fish] = []
	for i in 16:
		var f := Fish.new()
		parent.add_child(f)
		f.id = "ord_%d" % i
		f.species = "glassdart"
		f.swim_pattern = "school"
		f.schooling_strength = 1.6
		f.position = Vector3(cos(float(i) * 0.42) * 2.0, 1.0, sin(float(i) * 0.42) * 2.0)
		f.heading = Vector3(1.0, 0.0, 0.0)
		f.velocity = Vector3(0.12, 0.0, 0.0)
		school.append(f)

	var all: Array = []
	all.append_array(school)

	MindBoidsBuffer.capture(all, 1)
	MindBoidsCompute.run()
	var pol_before: float = _polarization(school)
	_assert(failed, pol_before > 0.85, "school starts aligned (%.2f)" % pol_before)

	_MotionWave.inject_at(all, Vector3(2.5, 1.0, 0.0), 0.95, Vector3(-1.0, 0.0, 0.0))
	var injected: int = 0
	for f in school:
		if f.motion_agitation > 0.35:
			injected += 1
	_assert(failed, injected >= 1, "startle injects local agitation")

	for step in 8:
		MindBoidsBuffer.capture(all, 2 + step)
		MindBoidsCompute.run()
		_MotionWave.tick(all, 0.1)
	var hot: int = 0
	for f in school:
		if f.motion_agitation > 0.06:
			hot += 1
	_assert(failed, hot >= 3, "wave propagates through topo links (%d fish)" % hot)

	parent.queue_free()
	if failed.is_empty():
		print("[smoke] motion_order OK")
		quit(0)
	else:
		for msg in failed:
			push_error("[smoke] motion_order FAIL: %s" % msg)
		quit(1)


func _polarization(fish_arr: Array) -> float:
	var sum := Vector3.ZERO
	var n: int = 0
	for f in fish_arr:
		if f == null or not is_instance_valid(f):
			continue
		var h: Vector3 = f.heading as Vector3
		if h.length_squared() < 1e-5:
			continue
		sum += h.normalized()
		n += 1
	if n <= 0:
		return 0.0
	return sum.length() / float(n)


func _assert(failed: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		failed.append(msg)
