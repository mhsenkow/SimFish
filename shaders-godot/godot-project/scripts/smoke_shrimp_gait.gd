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
	t.check(src.contains("speed * dt * float(g[\"steps_per_unit\"])"),
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

	quit(t.finish())
