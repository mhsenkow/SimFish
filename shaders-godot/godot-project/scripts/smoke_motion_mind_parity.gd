extends SceneTree

# LIVING_MOTION #96 — topological boids must not change mind workspace traces.



func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	MindBoidsBuffer.reset_for_test()
	MindBoidsCompute.reset_for_test()

	var parent := Node3D.new()
	root.add_child(parent)
	var sim := SimDriver.new()
	parent.add_child(sim)

	var f := Fish.new()
	parent.add_child(f)
	f.id = "parity_fish"
	f.species = "glassdart"
	f.swim_pattern = "school"
	f.schooling_strength = 1.4
	f.position = Vector3(0.0, 1.0, 0.0)
	f.heading = Vector3(1.0, 0.0, 0.0)
	sim.register_fish(f)

	TestSupport.check(failed, MindReplayParity.run_smoke(f, sim), "mind replay parity baseline")

	var school: Array[Fish] = []
	for i in 12:
		var t := Fish.new()
		parent.add_child(t)
		t.id = "school_%d" % i
		t.species = "glassdart"
		t.swim_pattern = "school"
		t.schooling_strength = 1.5
		t.position = Vector3(cos(float(i) * 0.5) * 1.5, 1.0, sin(float(i) * 0.5) * 1.5)
		t.heading = Vector3(1.0, 0.0, 0.0)
		school.append(t)
	school.append(f)
	sim.register_fish(f)
	MindBoidsBuffer.capture(school, 1)
	MindBoidsCompute.run()
	TestSupport.check(failed, MindReplayParity.run_smoke(f, sim),
		"mind replay parity after topo boids capture")

	parent.queue_free()
	quit(TestSupport.report("smoke_motion_mind_parity", failed))
