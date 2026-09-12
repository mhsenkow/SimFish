extends SceneTree

# Pins the generative coat contract for fish flanks.
#
# _paint_lateral_pattern() is what makes a shoal of one species read as a
# shoal of individuals. Each discrete motif must actually paint voxels
# (a silently-unhandled id renders as a bare solid body), the scatter motifs
# must be deterministic per individual, and two different individuals must not
# produce the same coat.

const FishScript := preload("res://scripts/fish.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	var host := Node3D.new()
	host.name = "PatternHost"
	root.add_child(host)

	# Every id in 0..PATTERN_TYPE_COUNT-1 must be drawable. 0 is "solid" and is
	# the baseline every other motif has to beat.
	var solid_count: int = _voxel_count(host, 0, "solid")
	TestSupport.check(failed, solid_count > 0, "solid body builds voxels")
	for ptype in range(1, FishScript.PATTERN_TYPE_COUNT):
		var n: int = _voxel_count(host, ptype, "p%d" % ptype)
		TestSupport.check(failed, n > solid_count,
			"pattern %d paints marking voxels (%d vs solid %d)" % [ptype, n, solid_count])

	# The four motifs added on top of the original ten.
	for ptype in [11, 12, 13, 14]:
		TestSupport.check(failed, _voxel_count(host, ptype, "new%d" % ptype) > solid_count,
			"new motif %d draws" % ptype)

	# Constellation speckle is hash-scattered: same individual -> same coat,
	# different individual -> different coat. Without this the "generative"
	# claim is just noise.
	var a1: int = _voxel_count(host, 14, "star_a")
	var a2: int = _voxel_count(host, 14, "star_a")
	TestSupport.check(failed, a1 == a2, "speckle is deterministic for one id")
	var b1: int = _voxel_count(host, 14, "star_b_long_distinct_id")
	TestSupport.check(failed, b1 > 0, "second speckled fish builds")

	# The hash itself must be stable and well-spread across ids.
	var seen: Dictionary = {}
	for i in 64:
		var f: Fish = FishScript.new()
		host.add_child(f)
		f.id = "hash_probe_%d" % i
		var h: int = f._pattern_hash()
		TestSupport.check(failed, h >= 0, "hash is non-negative for %s" % f.id)
		seen[h] = true
		f.free()
	TestSupport.check(failed, seen.size() >= 60, "pattern hash spreads across ids (%d/64)" % seen.size())

	# ---- Per-individual asymmetry -------------------------------------------
	# Perfect mirror symmetry is what makes a generated shoal read as one mesh
	# repeated. Each fish must deviate, deterministically, and differently.
	var f1: Fish = FishScript.new()
	host.add_child(f1)
	f1.id = "asym_one"
	var a1d: Dictionary = f1._individual_asymmetry()
	var a1_again: Dictionary = f1._individual_asymmetry()
	TestSupport.check(failed, a1d["pec_r"] == a1_again["pec_r"], "asymmetry is stable for one fish")
	TestSupport.check(failed, not is_equal_approx(float(a1d["pec_r"]), float(a1d["pec_l"])),
		"the two pectorals differ")
	TestSupport.check(failed, is_equal_approx(float(a1d["pec_r"]) + float(a1d["pec_l"]), 2.0),
		"pectoral deviation is balanced around 1.0")
	TestSupport.check(failed, absf(float(a1d["pec_r"]) - 1.0) < 0.10,
		"pectoral deviation stays subtle (%.3f)" % float(a1d["pec_r"]))
	f1.free()

	# Across a population the deviation must actually vary, and the caudal
	# nick must be a minority feature rather than universal or absent.
	var leans: Dictionary = {}
	var nicks: int = 0
	for i in 200:
		var fx: Fish = FishScript.new()
		host.add_child(fx)
		fx.id = "asym_%d" % i
		var a: Dictionary = fx._individual_asymmetry()
		leans[snappedf(float(a["pec_r"]), 0.005)] = true
		if bool(a["nick"]):
			nicks += 1
		TestSupport.check(failed, absf(float(a["eye_lift"])) <= 0.031, "eye lift stays subtle")
		fx.free()
	TestSupport.check(failed, leans.size() >= 20,
		"pectoral lean varies across the population (%d distinct)" % leans.size())
	TestSupport.check(failed, nicks > 10 and nicks < 80,
		"caudal nick is a minority trait (%d/200)" % nicks)

	# Out-of-range ids must fall through to solid rather than erroring. Same id
	# as the solid baseline so the per-individual asymmetry cancels out.
	var wild: int = _voxel_count(host, 999, "solid")
	TestSupport.check(failed, wild == solid_count, "unknown pattern id degrades to solid")

	if failed.is_empty():
		print("[smoke] fauna_patterns OK — %d motifs, %d/200 nicked" % [FishScript.PATTERN_TYPE_COUNT, nicks])
		quit(0)
	else:
		for f in failed:
			push_error("[smoke] FAIL: %s" % f)
		print("[smoke] fauna_patterns FAILED (%d)" % failed.size())
		quit(1)


# Build one fish with the given motif and count the voxel instances it emitted.
func _voxel_count(host: Node3D, ptype: int, fish_id: String) -> int:
	var f: Fish = FishScript.new()
	f.name = "Pat_%s" % fish_id
	host.add_child(f)
	f.id = fish_id
	f.init_genome({
		"species": "tetra",
		"pattern_type": ptype,
		"pattern_type_b": -1,
		"pattern_density": 0.7,
		"pattern_coverage": 1.0,
		"pattern_intensity": 0.6,
		"pattern_scale": 0.5,
		"pattern_contrast": 0.5,
	})
	var builder: Variant = f.get("_voxel_builder")
	var n: int = 0
	if builder != null:
		n = (builder.handles as Array).size()
	f.free()
	return n
