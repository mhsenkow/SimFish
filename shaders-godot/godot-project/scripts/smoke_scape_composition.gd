extends SceneTree

# The scape has to use the water VOLUME (VISUAL_DIRECTIONS #17).
#
# `aquascape_craft.analyze_scape()` already scores composition — and scores it
# well — but it scores the grid the PLAYER built, in the editor, and it scores
# it in XZ. The tank that actually boots is assembled by procedural layouts in
# world.gd, nothing checks the result, and neither says anything about height.
#
# The gap shows up twice in the capture set: the hero angles carry no highlight
# because nothing reaches the upper third of the water to catch the lamp, and
# the close angle is undifferentiated mid-water. Both are the same fact.

const SC = preload("res://scripts/scape_composition.gd")


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_scape_composition")

	# --- Mass spreads across the bands an item SPANS ---
	# A blade running floor to surface belongs to all three bands. Counting it
	# only where its root sits is how a tank full of tall stems measures empty
	# on top — which is exactly the mistake this replaces.
	var tall: Array = [SC.item(0.0, 6.0, 1.0)]
	var occ: PackedFloat32Array = SC.band_occupancy(tall, 0.0, 6.0)
	t.equals(occ.size(), SC.BANDS, "three bands")
	for i in occ.size():
		t.approx(occ[i], 1.0 / 3.0, "a full-height stem fills every band", 0.001)

	# A carpet sits only in the bottom band.
	var carpet: PackedFloat32Array = SC.band_occupancy(
		[SC.item(0.0, 0.3, 1.0)], 0.0, 6.0)
	t.approx(carpet[0], 1.0, "a carpet is entirely bottom band", 0.001)
	t.approx(carpet[2], 0.0, "…and nothing is on top", 0.001)

	# A zero-height item lands in the band its surface is in.
	var flat_rock: PackedFloat32Array = SC.band_occupancy(
		[SC.item(4.5, 4.5, 1.0)], 0.0, 6.0)
	t.approx(flat_rock[2], 1.0, "a flat item sits in one band", 0.001)

	# --- Occupancy is a distribution ---
	var mixed: Array = [
		SC.item(0.0, 1.0, 3.0), SC.item(0.0, 6.0, 1.0), SC.item(2.0, 4.0, 2.0),
	]
	var mocc: PackedFloat32Array = SC.band_occupancy(mixed, 0.0, 6.0)
	var total: float = 0.0
	for v in mocc:
		total += v
		t.in_range(v, 0.0, 1.0, "each band is a fraction")
	t.approx(total, 1.0, "bands sum to 1", 0.001)

	# --- The failure this exists to catch ---
	# Everything on the floor: the grade must call out the empty upper band.
	var bottom_heavy: Array = []
	for i in 12:
		bottom_heavy.append(SC.item(0.0, 0.8, 1.0, -3.0 + float(i) * 0.5))
	var bh: PackedFloat32Array = SC.band_occupancy(bottom_heavy, 0.0, 6.0)
	var bh_grade: Array[Dictionary] = SC.grade(bh, SC.focal_offset_frac(bottom_heavy, 6.0))
	var named: Dictionary = {}
	for row in bh_grade:
		named[String(row["name"])] = row
	t.check(not bool((named["upper band"] as Dictionary)["ok"]),
		"a floor-only scape must fail the upper band")
	t.check(not bool((named["mid band"] as Dictionary)["ok"]),
		"…and the mid band")
	t.approx(SC.open_band_fraction(bh), 2.0 / 3.0,
		"two of three bands are open", 0.01)

	# --- …and the opposite failure ---
	# A column filled evenly top to bottom is a hedge, not a scape.
	var hedge: PackedFloat32Array = SC.band_occupancy(
		[SC.item(0.0, 6.0, 1.0, 2.0)], 0.0, 6.0)
	var hedge_named: Dictionary = {}
	for row in SC.grade(hedge, 0.3):
		hedge_named[String(row["name"])] = row
	t.check(not bool((hedge_named["top vs bottom"] as Dictionary)["ok"]),
		"an evenly-filled column must fail top-vs-bottom — that is a hedge, "
			+ "and it leaves no swimming room")

	# --- A composed scape passes all four ---
	# Masses matter as much as heights. A single light stem cannot hold the
	# upper third against fifteen units of floor mass — which is precisely why
	# a tank can be "full of tall plants" and still measure empty on top.
	var good: Array = [
		SC.item(0.0, 0.6, 5.0, -2.2),   # foreground carpet, opposite the focal
		SC.item(0.0, 2.4, 4.0, 1.6),    # midground bush
		SC.item(0.0, 5.4, 9.0, 2.4),    # background STAND, reaching the surface
		SC.item(0.2, 1.8, 5.0, 2.0),    # focal stone
	]
	var gocc: PackedFloat32Array = SC.band_occupancy(good, 0.0, 6.0)
	var gfocal: float = SC.focal_offset_frac(good, 6.0)
	for row in SC.grade(gocc, gfocal):
		t.check(bool(row["ok"]),
			"a composed scape should pass %s (got %.3f, want %s)"
				% [row["name"], float(row["value"]), row["want"]])

	# --- Focal offset ---
	t.approx(SC.focal_offset_frac([SC.item(0, 1, 1, 0.0)], 6.0), 0.0,
		"mass at the centre reads 0", 0.001)
	t.approx(SC.focal_offset_frac([SC.item(0, 1, 1, 3.0)], 6.0), 0.5,
		"halfway out reads 0.5", 0.001)
	t.approx(SC.focal_offset_frac([SC.item(0, 1, 1, -3.0)], 6.0), -0.5,
		"…and is signed", 0.001)
	# Mass-weighted, not a plain mean: a boulder outweighs a sprig.
	var weighted: float = SC.focal_offset_frac(
		[SC.item(0, 1, 9.0, 3.0), SC.item(0, 1, 1.0, -3.0)], 6.0)
	t.check(weighted > 0.3, "the heavier side wins (got %.2f)" % weighted)
	var centred_grade: Array[Dictionary] = SC.grade(
		SC.band_occupancy(good, 0.0, 6.0), 0.02)
	for row in centred_grade:
		if String(row["name"]) == "focal offset":
			t.check(not bool(row["ok"]),
				"dead centre must fail — it is the one placement every "
					+ "aquascaping tradition agrees is wrong")

	# --- The bias leans a layout, it does not relocate it ---
	# smoke_scenario_layouts caught the unbounded version: a `corner_refuge`
	# stem at x = -5.85 with a 0.7 pull toward +3.0 landed at +2.6, out of the
	# corner the layout exists to make.
	var moved: float = SC.bias_toward(-5.85, 3.0, 0.7)
	t.check(absf(moved - (-5.85)) <= SC.FOCAL_MAX_SHIFT + 0.001,
		"a corner plant moves at most FOCAL_MAX_SHIFT (went to %.2f)" % moved)
	t.check(moved < 0.0, "…and stays on its own side of the tank")
	t.approx(SC.bias_toward(0.2, 3.0, 0.05), 0.34,
		"a small pull is not capped", 0.01)
	t.approx(SC.bias_toward(1.0, 3.0, 0.0), 1.0, "zero pull moves nothing", 0.001)
	t.check(absf(SC.bias_toward(9.0, -3.0, 1.0) - 9.0) <= SC.FOCAL_MAX_SHIFT + 0.001,
		"the cap is symmetric")

	# --- Degenerate inputs ---
	t.equals(SC.band_occupancy([], 0.0, 6.0).size(), SC.BANDS,
		"an empty scape still returns bands")
	t.approx(SC.band_occupancy([SC.item(0, 1, 1)], 5.0, 5.0)[0], 0.0,
		"a zero-height column does not divide by zero", 0.001)
	t.approx(SC.focal_offset_frac([], 6.0), 0.0, "no items, no offset", 0.001)
	t.approx(SC.focal_offset_frac([SC.item(0, 1, 1, 3.0)], 0.0), 0.0,
		"a zero half-width does not divide by zero", 0.001)
	t.approx(SC.band_occupancy([SC.item(0, 1, 0.0)], 0.0, 6.0)[0], 0.0,
		"massless items contribute nothing", 0.001)
	t.check(SC.format_report(SC.band_occupancy(good, 0.0, 6.0), gfocal).length() > 0,
		"the report formats")

	# --- Items outside the column are clamped, not dropped ---
	var overshoot: PackedFloat32Array = SC.band_occupancy(
		[SC.item(-2.0, 9.0, 1.0)], 0.0, 6.0)
	var os_total: float = 0.0
	for v in overshoot:
		os_total += v
	t.approx(os_total, 1.0, "an item taller than the tank still sums to 1", 0.01)

	quit(t.finish())
