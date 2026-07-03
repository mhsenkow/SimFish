extends SceneTree

# PERFORMANCE_UNTHROTTLED #57 — boids SoA + compute pass smoke.


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	MindBoidsCompute.reset_for_test()
	MindBoidsBuffer.reset_for_test()
	if not MindBoidsCompute.smoke_ok():
		failed.append("boids compute pairwise neighbors")
	var parent := Node3D.new()
	root.add_child(parent)
	var school: Array[Fish] = []
	for i in 8:
		var f := Fish.new()
		parent.add_child(f)
		f.id = "school_%d" % i
		f.species = "glassdart"
		f.position = Vector3(cos(float(i) * 0.9) * 1.2, 0.5, sin(float(i) * 0.9) * 1.2)
		f.heading = Vector3.FORWARD
		f.velocity = Vector3(0.12, 0.0, 0.04)
		school.append(f)
	MindBoidsBuffer.capture(school, 2)
	MindBoidsCompute.run()
	_assert(failed, MindBoidsBuffer.backend in ["cpu", "gpu"], "boids backend active")
	var total_neighbors: int = 0
	for i in MindBoidsBuffer.count:
		total_neighbors += MindBoidsBuffer.neighbor_counts[i]
	_assert(failed, total_neighbors >= 4, "school batch neighbor counts")
	PerfGovernor.record_ledger(57, 1000, 900 if MindBoidsBuffer.backend == "cpu" else 700)
	if failed.is_empty():
		print("[smoke] mind_boids OK (%s)" % MindBoidsBuffer.backend)
		quit(0)
	else:
		for e in failed:
			push_error("[smoke] mind_boids FAIL: %s" % e)
		quit(1)


static func _assert(failed: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		failed.append(msg)
