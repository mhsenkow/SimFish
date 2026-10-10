extends SceneTree

func _initialize() -> void:
	await process_frame
	var suite := TestSupport.Suite.new("school_merge_equivalence")
	seed(58217)
	var fish: Array = []
	for i in 96:
		var f := Fish.new()
		f.swim_pattern = "school"
		f.schooling_strength = 0.9
		f.species = "guppy" if i % 3 else "neon_tetra"
		f.school_id = i % 7
		f.position = Vector3(randf_range(-5, 5), randf_range(-2, 2), randf_range(-4, 4))
		fish.append(f)
	var expected: Array[int] = []
	for f in fish:
		expected.append(f.school_id)
	# Independent brute-force definition retains ordered, strict 3D proximity.
	for i in fish.size():
		var sid: int = expected[i]
		for j in fish.size():
			if i == j or fish[i].species != fish[j].species or sid == expected[j]:
				continue
			if fish[i].position.distance_squared_to(fish[j].position) < MotionSchool.MERGE_DIST * MotionSchool.MERGE_DIST:
				expected[j] = sid
	MotionSchool._merge_nearby_schools(fish)
	for i in fish.size():
		suite.check(fish[i].school_id == expected[i], "ordered school merge %d" % i)
	MindBoidsBuffer.capture(fish, 1)
	MindBoidsCompute.run()
	MotionSchool._union_find_ids(fish)
	var identities: Array[int] = []
	for f in fish:
		identities.append(f.school_id)
	for _step in 20:
		MotionSchool._union_find_ids(fish)
	for i in fish.size():
		suite.check(fish[i].school_id == identities[i], "connected school identity stays stable %d" % i)
	MotionSchool._fission_timer[999999] = 20.0
	MotionSchool._tick_fission_fusion(fish, 0.1)
	suite.check(not MotionSchool._fission_timer.has(999999), "departed school timer is removed")
	MindBoidsBuffer.reset_for_test()
	for f in fish:
		f.free()
	var a := Fish.new()
	var b := Fish.new()
	for f in [a, b]:
		f.swim_pattern = "school"
		f.schooling_strength = 0.9
		a.school_id = 1
		b.school_id = 2
	b.position.y = MotionSchool.MERGE_DIST
	MotionSchool._merge_nearby_schools([a, b])
	suite.check(a.school_id != b.school_id, "strict radius does not merge boundary")
	b.position.y = 0.1
	b._dying = true
	MotionSchool._merge_nearby_schools([a, b])
	suite.check(b.school_id == 2, "dying fish does not merge into living school")
	a.free()
	b.free()
	quit(suite.finish())
