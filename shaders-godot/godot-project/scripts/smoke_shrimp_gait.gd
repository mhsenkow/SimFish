extends SceneTree

# Crawling gait contract (shrimp motion pass).
#
# Shrimp were oriented with `look_at` on their full 3D heading, so gravity's
# downward pull pitched the whole body nose-down — a "crawling" shrimp sat
# permanently tipped forward at whatever angle it was descending at. Their
# legs were also welded voxels, so a walking shrimp slid along with its legs
# frozen.
#
# These pin the two properties that make walking read: the gait is driven by
# DISTANCE (so legs stop when the body stops), and each body plan walks
# differently.


func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_shrimp_gait")

	var src: String = FileAccess.get_file_as_string("res://scripts/shrimp.gd")
	t.check(not src.is_empty(), "shrimp.gd readable")

	# --- Ground-lock: a grounded shrimp must not pitch ---
	t.check(src.contains("var on_bottom: bool"),
		"orientation must test whether the shrimp is on the bottom")
	t.check(src.contains("d = Vector3(d.x, 0.0, d.z)"),
		"a grounded shrimp's facing must be flattened to yaw — pitching it "
			+ "with the heading is what tipped them nose-down")

	# --- Distance-driven cycle ---
	t.check(src.contains("distance * float(g[\"steps_per_unit\"])"),
		"the gait must advance with DISTANCE travelled — a time-driven cycle "
			+ "keeps paddling when the animal has stopped")

	# --- Legs are animatable ---
	t.check(src.contains("_leg_pivots.append"),
		"legs must hang off pivots, or they cannot swing")
	t.check(src.contains("node.rotation.x = swing"), "legs must actually swing")

	# --- Every body plan has a distinct gait ---
	var plans: Array[String] = ["crab", "lobster", "mantis", "default"]
	var seen: Dictionary = {}
	for plan in plans:
		var sh := Shrimp.new()
		sh.body_shape = plan if plan != "default" else "caridean"
		var g: Dictionary = sh._gait_profile()
		for field in ["steps_per_unit", "swing", "bob", "waddle", "sideways"]:
			t.check(g.has(field), "%s gait is missing '%s'" % [plan, field])
		t.check(float(g["steps_per_unit"]) > 0.0,
			"%s must take steps" % plan)
		t.in_range(float(g["swing"]), 0.05, 1.5, "%s leg swing is sane" % plan)
		t.in_range(float(g["bob"]), 0.0, 0.2, "%s body bob is subtle" % plan)
		var sig: String = "%.2f|%.2f|%.3f" % [
			float(g["steps_per_unit"]), float(g["swing"]), float(g["bob"])]
		t.check(not seen.has(sig),
			"%s walks identically to %s — the point is that they differ"
				% [plan, String(seen.get(sig, "?"))])
		seen[sig] = plan
		sh.free()

	# --- Crabs walk sideways, nothing else does ---
	var crab := Shrimp.new()
	crab.body_shape = "crab"
	t.approx(float(crab._gait_profile()["sideways"]), 1.0,
		"a crab must face across its direction of travel")
	crab.free()
	for plan in ["lobster", "mantis", "caridean"]:
		var sh2 := Shrimp.new()
		sh2.body_shape = plan
		t.approx(float(sh2._gait_profile()["sideways"]), 0.0,
			"%s must walk forwards, not sideways" % plan)
		sh2.free()

	# --- A scurrying shrimp steps faster than a lumbering lobster ---
	var quick := Shrimp.new()
	quick.body_shape = "caridean"
	var slow := Shrimp.new()
	slow.body_shape = "lobster"
	t.check(float(quick._gait_profile()["steps_per_unit"])
			> float(slow._gait_profile()["steps_per_unit"]),
		"a caridean shrimp must scurry faster than a lobster lumbers")
	t.check(float(slow._gait_profile()["bob"])
			> float(quick._gait_profile()["bob"]),
		"a lobster's weight transfer must bob more than a shrimp's")
	quick.free()
	slow.free()

	# --- Ground band scales with the animal ---
	var small := Shrimp.new()
	var big := Shrimp.new()
	big.adult_voxel_scale = small.adult_voxel_scale * 2.5
	t.check(big._ground_band() >= small._ground_band(),
		"a larger animal needs at least as much ground clearance")
	small.free()
	big.free()

	await process_frame

	# --- Crab legs are hinged (#24) ---
	# They were welded voxels on BankPivot, so a walking crab slid on frozen legs.
	var crab_walker := Shrimp.new()
	root.add_child(crab_walker)
	crab_walker.init_genome({"body_shape": "crab"})
	crab_walker.set_process(false)
	t.equals(crab_walker._leg_pivots.size(), 8, "a crab stands on four hinged leg pairs")
	crab_walker._tick_gait(1.0 / 60.0, true, 0.01)
	var pose_a: Array[Vector3] = []
	for entry in crab_walker._leg_pivots:
		pose_a.append((entry["node"] as Node3D).rotation)
	crab_walker._tick_gait(1.0 / 60.0, true, 0.01)
	var stepped: int = 0
	for i in crab_walker._leg_pivots.size():
		if (crab_walker._leg_pivots[i]["node"] as Node3D).rotation.distance_to(pose_a[i]) > 0.02:
			stepped += 1
	t.equals(stepped, 8, "every leg of a walking crab moves between poses")
	crab_walker.free()

	# --- Eggs ride the abdomen (#22) ---
	# A non-gravid frame used to free the egg mass built on TailPivot, and a
	# later brood got a new one on BankPivot that stayed still under the tail.
	for plan in ["caridean", "crab", "lobster", "mantis"]:
		var hen := Shrimp.new()
		root.add_child(hen)
		hen.init_genome({"body_shape": plan})
		var eggs: Node3D = hen._egg_cluster
		t.check(eggs != null and eggs.get_parent() == hen._tail_pivot,
			"%s eggs hang off the abdomen pivot" % plan)
		if eggs == null:
			hen.free()
			continue
		t.check(not eggs.visible, "%s without a brood shows no eggs" % plan)
		hen._process(1.0 / 60.0)
		t.check(hen._egg_cluster == eggs, "%s keeps its egg mass through a non-gravid frame" % plan)
		hen.is_gravid = true
		hen._process(1.0 / 60.0)
		t.check(eggs.visible and eggs.get_parent() == hen._tail_pivot,
			"%s berried female carries visible eggs on the tail" % plan)
		hen.free()

	quit(t.finish())
