extends SceneTree

# LIVING_MOTION #94 + #100 — headless murmuration capture scenario (40 tetras + shadow).

const _MotionField = preload("res://scripts/motion_field.gd")
const _MotionWave = preload("res://scripts/motion_wave.gd")


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
	for i in 40:
		var f := Fish.new()
		parent.add_child(f)
		f.id = "cap_%d" % i
		f.species = "glassdart"
		f.swim_pattern = "school"
		f.schooling_strength = 1.65
		f.position = Vector3(
			cos(float(i) * 0.157) * 2.4,
			1.0 + sin(float(i) * 0.23) * 0.15,
			sin(float(i) * 0.157) * 2.4)
		f.heading = Vector3(1.0, 0.0, 0.0)
		f.velocity = f.heading * 0.14
		f.lead_score = float(i) * 0.02
		school.append(f)

	var betta := Fish.new()
	parent.add_child(betta)
	betta.id = "cap_betta"
	betta.species = "betta"
	betta.swim_pattern = "cruise"
	betta.schooling_strength = 0.0
	betta.position = Vector3(-2.0, 1.2, 0.0)
	betta.heading = Vector3(1.0, 0.0, 0.0)

	var all: Array = []
	all.append_array(school)
	all.append(betta)

	MindBoidsBuffer.capture(all, 1)
	MindBoidsCompute.run()
	var pol_before: float = _polarization(school)
	_assert(failed, pol_before > 0.45, "40-fish school reads cohesive (%.2f)" % pol_before)

	_MotionWave.inject_at(school, Vector3(2.5, 1.0, 0.0), 0.95, Vector3(-1.0, 0.0, 0.0))
	var inj_hot: int = 0
	for f in school:
		if f.motion_agitation > 0.35:
			inj_hot += 1
	_assert(failed, inj_hot >= 1, "startle injects local leader (%d)" % inj_hot)

	for step in 8:
		MindBoidsBuffer.capture(school, 2 + step)
		MindBoidsCompute.run()
		_MotionField.tick(school, 0.1)
	var wave_n: int = 0
	for f in school:
		if f.motion_agitation > 0.05:
			wave_n += 1
	_assert(failed, wave_n >= 3, "startle wave spreads through flock (%d)" % wave_n)
	_MotionField.inject_shadow(all, Vector3(0.0, 3.2, 0.0), 1.0)
	var freeze_n: int = 0
	for f in school:
		if f.motion_freeze_t > 0.05:
			freeze_n += 1
	_assert(failed, freeze_n >= 6, "shadow freeze hits school (%d)" % freeze_n)
	_assert(failed, betta.motion_agitation < 0.06,
		"lone betta ignores school shadow (%.2f)" % betta.motion_agitation)

	var pol_after: float = _polarization(school)
	print("[smoke] murmuration_capture pol_before=%.2f pol_after=%.2f freeze=%d wave=%d" % [
		pol_before, pol_after, freeze_n, wave_n])

	parent.queue_free()
	if failed.is_empty():
		print("[smoke] murmuration_capture OK")
		quit(0)
	else:
		for msg in failed:
			push_error("[smoke] murmuration_capture FAIL: %s" % msg)
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
