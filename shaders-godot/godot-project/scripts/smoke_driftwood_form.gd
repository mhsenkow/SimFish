extends SceneTree

# Driftwood shapes (DriftwoodForm).
#
# THE PROBLEM. There was exactly one piece of wood - a single bezier trunk
# arcing low across the floor plus four hard-coded twigs - so every tank had
# the same silhouette, the hardscape "styles" only scaled how many voxels it
# was made of, and because the trunk hugs the substrate the entire middle and
# upper water column was left empty.

const D := preload("res://scripts/driftwood_form.gd")


func _init() -> void:
	var t := TestSupport.Suite.new("driftwood_form")
	var hw := 8.0
	var hd := 5.0
	var sub := 3.6
	var water := 17.1
	var span: float = water - sub

	for name in ["log", "branch", "spider", "stump"]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		var form: int = D.form_id(name)
		t.equals(D.form_name(form), name, "%s round-trips" % name)
		var limbs: Array = D.limbs(form, rng, hw, hd, sub, water)
		t.check(limbs.size() >= 1, "%s produces wood" % name)

		var highest: float = -INF
		for limb in limbs:
			for key in ["p0", "p1", "p2", "p3"]:
				var p: Vector3 = limb[key]
				t.check(is_finite(p.x) and is_finite(p.y) and is_finite(p.z),
					"%s %s is finite" % [name, key])
				# Wood must stay inside the glass, or it pokes through.
				t.check(absf(p.x) <= hw * 1.02,
					"%s stays inside the width (%.2f)" % [name, p.x])
				t.check(absf(p.z) <= hd * 1.02,
					"%s stays inside the depth (%.2f)" % [name, p.z])
				highest = maxf(highest, p.y)
			# Thickness must taper outward, or a twig is as fat as the trunk.
			t.check(float(limb["thick1"]) <= float(limb["thick0"]) + 0.001,
				"%s limbs taper toward their tips" % name)
			t.check(float(limb["thick1"]) > 0.0, "%s limbs have width" % name)
		# And below the waterline: wood breaking the surface reads as a
		# fallen tree and fights the floating plants for the meniscus.
		t.check(highest < water,
			"%s stays under the water (%.2f vs %.2f)" % [name, highest, water])

	# --- the point of the exercise ----------------------------------------
	# A branch must actually climb. The log deliberately does not.
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 7
	var branch: Array = D.limbs(D.BRANCH, rng_b, hw, hd, sub, water)
	var rng_l := RandomNumberGenerator.new()
	rng_l.seed = 7
	var log_limbs: Array = D.limbs(D.LOG, rng_l, hw, hd, sub, water)
	var b_top: float = -INF
	for limb in branch:
		b_top = maxf(b_top, float(limb["p3"].y))
	var l_top: float = -INF
	for limb in log_limbs:
		l_top = maxf(l_top, float(limb["p3"].y))
	t.check(b_top > sub + span * 0.45,
		"a branch reaches well up the water column (%.2f of %.2f)"
		% [b_top - sub, span])
	t.check(b_top > l_top + span * 0.2,
		"and much higher than a log (%.2f vs %.2f)" % [b_top, l_top])
	t.check(branch.size() > log_limbs.size() + 2,
		"a branch forks (%d limbs vs %d)" % [branch.size(), log_limbs.size()])

	# Spider spreads wide and low rather than tall.
	var rng_s := RandomNumberGenerator.new()
	rng_s.seed = 3
	var spider: Array = D.limbs(D.SPIDER, rng_s, hw, hd, sub, water)
	var widest: float = 0.0
	var s_top: float = -INF
	for limb in spider:
		widest = maxf(widest, absf(float(limb["p3"].x)))
		s_top = maxf(s_top, float(limb["p3"].y))
	t.check(spider.size() >= 4, "spiderwood has several limbs")
	t.check(widest > hw * 0.3, "and reaches outward (%.2f)" % widest)
	t.check(s_top - sub < span * 0.55, "while staying low")

	# --- determinism --------------------------------------------------------
	# The same tank must grow the same wood every load.
	var r1 := RandomNumberGenerator.new()
	r1.seed = 4242
	var r2 := RandomNumberGenerator.new()
	r2.seed = 4242
	var a: Array = D.limbs(D.BRANCH, r1, hw, hd, sub, water)
	var b: Array = D.limbs(D.BRANCH, r2, hw, hd, sub, water)
	t.equals(a.size(), b.size(), "same seed, same limb count")
	if a.size() == b.size() and a.size() > 0:
		t.check(a[0]["p3"].is_equal_approx(b[0]["p3"]),
			"same seed, same shape")

	# Step budget must fall off with depth or a twig costs as much as a trunk.
	t.check(D.limb_steps({"depth": 2}, 80) < D.limb_steps({"depth": 0}, 80),
		"deeper limbs use fewer voxels")
	t.check(D.limb_steps({"depth": 4}, 80) >= 4, "but never zero")

	# --- every form must be reachable ---------------------------------------
	# `spider` shipped as dead code: the form existed but no style or preset
	# selected it, so the only way to see it was to read the source.
	var t2 := preload("res://scripts/tank_config.gd").new()
	var w2: String = _read("res://scripts/world.gd")
	var used: Dictionary = {}
	for line in w2.split("\n"):
		if line.contains("hs_wood_form = \""):
			used[line.split("\"")[1]] = true
	for preset_key in t2.TANK_PRESETS.keys():
		var pd: Dictionary = t2.TANK_PRESETS[preset_key]
		if pd.has("wood_form"):
			used[String(pd["wood_form"])] = true
	for form_name in ["log", "branch", "spider", "stump"]:
		t.check(used.has(form_name) or form_name == "log",
			"%s is reachable without editing source" % form_name)
	# And selectable directly.
	t.check("wood_form" in t2, "driftwood shape is a real setting")
	t.equals(String(t2.wood_form), "auto",
		"defaulting to auto, so existing tanks keep the shape they were "
		+ "designed with")
	var sp: String = _read("res://scripts/settings_panel.gd")
	t.check(sp.contains("_wood_form_option"), "Settings exposes it")
	for opt in ["\"auto\"", "\"log\"", "\"branch\"", "\"spider\"",
			"\"stump\"", "\"none\""]:
		t.check(sp.contains(opt), "Settings offers %s" % opt)
	t2.free()

	# --- wiring -------------------------------------------------------------
	var w: String = _read("res://scripts/world.gd")
	t.check(w.contains("DriftwoodForm.limbs("),
		"world.gd builds wood from the form vocabulary")
	t.check(w.contains("hs_wood_form"),
		"hardscape styles pick a shape, not just a count")
	t.check(w.contains("preset_form"),
		"a preset can name its own wood shape")
	t.check(w.contains("cfg_hs.get(\"wood_form\")"),
		"and a Settings choice overrides it")
	t.check(w.contains("wood_rng"),
		"wood uses its own RNG rather than consuming the world stream, "
		+ "which would shift every placement made after it")

	quit(t.finish())


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt: String = f.get_as_text()
	f.close()
	return txt
