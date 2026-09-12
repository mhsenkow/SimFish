extends SceneTree

# Tank realism contract (tank shapes/sizes pass).
#
# Vessel geometry used to be hand-authored and had drifted from the labels:
# every box was exactly 1 : 0.50 deep whatever tank it claimed to be (a real
# 75 gallon is 0.375), and neither "cube" was a cube (1 : 1 : 0.56). Geometry
# is now DERIVED from real dimensions in `tank_spec.gd`, and this keeps the
# two from drifting apart again.

# Size-slider bounds from settings_panel.gd. A preset outside these cannot be
# represented by the UI that is supposed to edit it.
const W_MIN: float = 4.0
const W_MAX: float = 24.0
const D_MIN: float = 2.0
const D_MAX: float = 14.0
const H_MIN: float = 4.0
const H_MAX: float = 20.0

# A fish is ~1.8 units long. Below this a tank reads as a jar, not a tank.
const MIN_FISH_LENGTHS_ACROSS: float = 3.0
const FISH_LENGTH_UNITS: float = 1.8


func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_tank_spec")

	# --- Catalogue integrity ---
	var keys: Dictionary = {}
	for spec in TankSpec.CATALOGUE:
		var key: String = String(spec["key"])
		t.check(not keys.has(key), "duplicate spec key %s" % key)
		keys[key] = true
		for field in ["label", "shape", "w_in", "d_in", "h_in", "nominal_gal", "blurb"]:
			t.check(spec.has(field), "%s is missing '%s'" % [key, field])
		for dim in ["w_in", "d_in", "h_in"]:
			t.check(float(spec[dim]) > 0.0, "%s has non-positive %s" % [key, dim])
		t.check(float(spec["nominal_gal"]) > 0.0, "%s needs a nominal volume" % key)

	# --- Computed volume must match what the tank is SOLD as ---
	# Not exactly: a "75" measures 78.5 gallons of glass (rim, thickness, and
	# the trade rounding down). Anything beyond 15% means the dimensions and
	# the name disagree about what tank this is.
	for spec in TankSpec.CATALOGUE:
		var key: String = String(spec["key"])
		var g: Dictionary = TankSpec.geometry(key)
		var computed: float = TankSpec.volume_gallons(
			String(g["tank_shape"]), float(g["tank_half_w"]),
			float(g["tank_half_d"]), float(g["tank_height"]), 1.0)
		var nominal: float = float(spec["nominal_gal"])
		var err: float = absf(computed / nominal - 1.0)
		t.check(err <= 0.15,
			"%s: geometry computes %.1f gal but it is sold as %.1f (%.0f%% off)"
				% [key, computed, nominal, err * 100.0])

	# --- A cube must be a cube ---
	for spec in TankSpec.CATALOGUE:
		if String(spec["shape"]) != "cube":
			continue
		var key: String = String(spec["key"])
		var w: float = float(spec["w_in"])
		t.approx(float(spec["d_in"]), w, "%s is a cube: depth must equal width" % key, 0.5)
		t.approx(float(spec["h_in"]), w,
			"%s is labelled a cube but is %.1f tall vs %.1f wide — that is a slab"
				% [key, float(spec["h_in"]), w], w * 0.15)

	# --- Depth proportions must actually vary ---
	# The tell that geometry was hand-waved: every box identical at 1 : 0.50.
	var ratios: Dictionary = {}
	for spec in TankSpec.CATALOGUE:
		if String(spec["shape"]) != "box":
			continue
		var r: float = float(spec["d_in"]) / float(spec["w_in"])
		ratios["%.2f" % r] = true
	t.check(ratios.size() >= 3,
		"box tanks use only %d distinct depth ratios — real tanks vary from "
			% ratios.size() + "0.375 (75g) to 0.55 (40 breeder)")

	# --- Generated geometry fits the sliders that edit it ---
	for spec in TankSpec.CATALOGUE:
		var key: String = String(spec["key"])
		var g: Dictionary = TankSpec.geometry(key)
		var w: float = float(g["tank_half_w"]) * 2.0
		var d: float = float(g["tank_half_d"]) * 2.0
		var h: float = float(g["tank_height"])
		t.in_range(w, W_MIN, W_MAX, "%s width is outside the size slider" % key)
		t.in_range(d, D_MIN, D_MAX, "%s depth is outside the size slider" % key)
		t.in_range(h, H_MIN, H_MAX, "%s height is outside the size slider" % key)
		# Playability: fish are drawn large, so a linearly-scaled nano tank
		# ends up narrower than a few fish. This is why the scale is a curve.
		t.check(w / FISH_LENGTH_UNITS >= MIN_FISH_LENGTHS_ACROSS,
			"%s is only %.1f fish-lengths across — too cramped to read as a tank"
				% [key, w / FISH_LENGTH_UNITS])

	# --- TankConfig.VESSEL_PRESETS must match the catalogue ---
	# The presets are generated from TankSpec; if someone hand-edits one, this
	# is what catches it.
	var cfg_src: String = FileAccess.get_file_as_string("res://scripts/tank_config.gd")
	t.check(not cfg_src.is_empty(), "tank_config.gd readable")
	for spec in TankSpec.CATALOGUE:
		var key: String = String(spec["key"])
		t.check(cfg_src.contains('"%s": {' % key),
			"VESSEL_PRESETS is missing catalogue vessel '%s'" % key)

	# --- The scale curve behaves ---
	t.check(TankSpec.units_for_inches(48.0) > TankSpec.units_for_inches(16.0),
		"a bigger tank must be bigger in game units")
	t.approx(TankSpec.inches_for_units(TankSpec.units_for_inches(30.0)), 30.0,
		"inches -> units -> inches must round-trip", 0.01)
	t.approx(TankSpec.units_for_inches(48.0), 16.0,
		"a 48in tank should keep its familiar 16-unit width", 0.2)
	t.equals(TankSpec.units_for_inches(0.0), 0.0, "zero inches is zero units")
	# Monotonic, or the ordering players perceive breaks.
	var prev: float = -1.0
	for i in 60:
		var inches: float = float(i) + 1.0
		var u: float = TankSpec.units_for_inches(inches)
		t.check(u > prev, "scale must increase monotonically at %.0f in" % inches)
		prev = u

	# --- Stocking advice must never exceed what the sim will hold ---
	for spec in TankSpec.CATALOGUE:
		var key: String = String(spec["key"])
		var g: Dictionary = TankSpec.geometry(key)
		var hint: String = TankSpec.stocking_hint(
			String(g["tank_shape"]), float(g["tank_half_w"]),
			float(g["tank_half_d"]), float(g["tank_height"]), 0.93)
		t.check(not hint.is_empty(), "%s needs a stocking hint" % key)
		# Pull the first number out of the hint and sanity-check it.
		var digits := ""
		for ch in hint:
			if ch.is_valid_int():
				digits += ch
			elif not digits.is_empty():
				break
		if not digits.is_empty():
			t.check(int(digits) <= TankSpec.SIM_FISH_CAP,
				"%s advises %s fish, above the sim's %d cap — advice that "
					% [key, digits, TankSpec.SIM_FISH_CAP]
				+ "brushes the ceiling gets tanks crashed")
	# The mirrored cap must match TankConfig's real one.
	t.check(cfg_src.contains('"fish":       {"cap": %d' % TankSpec.SIM_FISH_CAP),
		"TankSpec.SIM_FISH_CAP (%d) has drifted from TankConfig.POP_CAP_DEFAULTS"
			% TankSpec.SIM_FISH_CAP)

	# --- A bowl must read as the bad idea it is ---
	var bowl: Dictionary = TankSpec.geometry("fishbowl")
	var bowl_gal: float = TankSpec.volume_gallons(
		String(bowl["tank_shape"]), float(bowl["tank_half_w"]),
		float(bowl["tank_half_d"]), float(bowl["tank_height"]), 1.0)
	t.check(bowl_gal < 5.0,
		"a fishbowl must compute as tiny, got %.1f gal" % bowl_gal)

	quit(t.finish())
