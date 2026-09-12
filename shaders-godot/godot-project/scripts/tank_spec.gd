class_name TankSpec
extends RefCounted

# Real-world tank identity (tank realism pass).
#
# THE PROBLEM. Vessels were described in abstract game units — "75 gal
# rectangle (16×8×14 in game units)" — and nothing computed a volume. The
# label said 75 gallons; the geometry said something else. Measured against
# real standard aquaria:
#
#   * every box preset was exactly 1 : 0.50 deep — 75g, 60P, column and
#     breeder all identical, when real tanks run 0.375 (75g) to 0.55 (40
#     breeder). Depth was a constant, not a design.
#   * neither "cube" was a cube: nano 1 : 1 : 0.56, reef 1 : 1 : 0.54. Slabs
#     with cube labels.
#   * "75 gal" was 33% too deep front-to-back.
#
# THE FIX. Specs are authored in REAL inches, and game geometry is derived
# from them. Proportions become correct by construction, and the UI can say
# "29 gallon · 30 × 12 × 18 in · 110 L" — which means something instantly to
# anyone who has stood in a fish shop, where "half_w 8.0" never will.
#
# WHAT THIS DELIBERATELY DOES NOT DO. It does not put the world to true
# scale. A fish voxel is 0.18 units and a fish is ~11% of tank width, where a
# real neon tetra is ~3% of a 48" tank. That exaggeration is a readability
# decision at a 512×288 render target — a to-scale tetra would be a couple of
# pixels. So the scale below sets *proportion*, and fish stay stylised.

# PERCEPTUAL SCALE, not a linear one.
#
# A linear 1 unit = 3 in was tried first and breaks at the small end: a 30 cm
# cube becomes 3.9 units wide while a fish is ~1.8 units long — a fish half
# the width of its own tank — and three presets fell below the size sliders'
# minimums. That is a direct consequence of fish being drawn large for
# readability at 512×288: the world cannot be linearly to scale AND hold a
# playable nano tank.
#
# So units follow a power curve: units = K * inches^P, with P < 1 compressing
# the range. Ordering and relative difference survive (a 120 still dwarfs a
# nano) while every vessel stays workable. Solved from two anchors:
#
#   a 5 gallon nano (16 in) -> 7.0 units   (~3.9 fish-lengths across)
#   a 75 gallon     (48 in) -> 16.0 units  (its familiar existing width)
#
# Real volumes are NOT derived from these units — they come from the
# catalogue's true inches — so the numbers shown to players stay honest even
# though the geometry is stylised.
const SCALE_POWER: float = 0.7525
const SCALE_K: float = 0.8690


# Real inches -> game units.
static func units_for_inches(inches: float) -> float:
	if inches <= 0.0:
		return 0.0
	return SCALE_K * pow(inches, SCALE_POWER)


# Game units -> real inches. The inverse, for custom slider geometry that has
# no catalogue entry to read true dimensions from.
static func inches_for_units(units: float) -> float:
	if units <= 0.0:
		return 0.0
	return pow(units / SCALE_K, 1.0 / SCALE_POWER)

const CUBIC_INCHES_PER_US_GALLON: float = 231.0
const LITRES_PER_US_GALLON: float = 3.785411784

# Mirror of TankConfig.POP_CAP_DEFAULTS["fish"]["cap"]. Stocking guidance must
# never exceed what the sim will actually hold, or the advice is a lie.
# smoke_tank_spec.gd asserts the two stay in step.
const SIM_FISH_CAP: int = 60

# Real aquarium catalogue. `nominal_gal` is what the tank is SOLD as, which
# differs from the raw glass volume (rim, thickness, and the trade rounding
# down) — a "75" measures 78.5 gal of box. Both are kept: nominal for the
# name, computed for anything that reasons about water.
#
# `shape` maps to the engine's existing TANK_SHAPE values.
const CATALOGUE: Array[Dictionary] = [
	# --- Everyday glass boxes, the sizes a shop actually stocks ---
	{"key": "nano_5g", "label": "5 gallon nano", "shape": "box",
	 "w_in": 16.0, "d_in": 8.0, "h_in": 10.0, "nominal_gal": 5.5,
	 "blurb": "Desk-scale starter. Shrimp, a betta, or a tiny nano school."},
	{"key": "standard_10g", "label": "10 gallon", "shape": "box",
	 "w_in": 20.0, "d_in": 10.0, "h_in": 12.0, "nominal_gal": 10.0,
	 "blurb": "The classic first tank. Cheap, forgiving, everywhere."},
	{"key": "long_20g", "label": "20 gallon long", "shape": "box",
	 "w_in": 30.0, "d_in": 12.0, "h_in": 12.0, "nominal_gal": 20.0,
	 "blurb": "Low and wide — more floor for corys and carpeting than a 29."},
	{"key": "standard_29g", "label": "29 gallon", "shape": "box",
	 "w_in": 30.0, "d_in": 12.0, "h_in": 18.0, "nominal_gal": 29.0,
	 "blurb": "Tall community tank. Room for stem plants to reach the light."},
	{"key": "breeder_40g", "label": "40 gallon breeder", "shape": "box",
	 "w_in": 36.0, "d_in": 18.0, "h_in": 16.0, "nominal_gal": 40.0,
	 "blurb": "Deep front-to-back. The aquascaper's favourite footprint."},
	{"key": "standard_55g", "label": "55 gallon", "shape": "box",
	 "w_in": 48.0, "d_in": 13.0, "h_in": 21.0, "nominal_gal": 55.0,
	 "blurb": "Long and narrow — a corridor for schooling fish."},
	{"key": "standard_75g", "label": "75 gallon", "shape": "box",
	 "w_in": 48.0, "d_in": 18.0, "h_in": 21.0, "nominal_gal": 75.0,
	 "blurb": "Wide community centrepiece. Stable, forgiving, heavy."},
	{"key": "standard_120g", "label": "120 gallon", "shape": "box",
	 "w_in": 48.0, "d_in": 24.0, "h_in": 24.0, "nominal_gal": 120.0,
	 "blurb": "Deep enough to aquascape in layers. A serious piece of furniture."},

	# --- Planted / metric shop sizes ---
	{"key": "rimless_60p", "label": "60P rimless", "shape": "box",
	 "w_in": 23.6, "d_in": 11.8, "h_in": 14.2, "nominal_gal": 17.0,
	 "blurb": "60 × 30 × 36 cm. The standard planted-tank canvas."},
	{"key": "cube_30c", "label": "30C cube", "shape": "cube",
	 "w_in": 11.8, "d_in": 11.8, "h_in": 11.8, "nominal_gal": 7.1,
	 "blurb": "A true 30 cm cube. Iwagumi in miniature."},
	{"key": "reef_cube_20", "label": "Reef cube", "shape": "cube",
	 "w_in": 20.0, "d_in": 20.0, "h_in": 18.0, "nominal_gal": 30.0,
	 "blurb": "Rimless saltwater cube. Viewable from three sides."},

	# --- Shaped vessels ---
	{"key": "column_blackwater", "label": "Column", "shape": "box",
	 "w_in": 24.0, "d_in": 12.0, "h_in": 24.0, "nominal_gal": 30.0,
	 "blurb": "Tall and narrow. Tannins, driftwood, dim light."},
	{"key": "breeder_shallow", "label": "Shallow breeder", "shape": "box",
	 "w_in": 36.0, "d_in": 18.0, "h_in": 10.0, "nominal_gal": 28.0,
	 "blurb": "Riparium proportions — wide surface, low water."},
	{"key": "round_column", "label": "Round column", "shape": "cylinder",
	 "w_in": 18.0, "d_in": 18.0, "h_in": 30.0, "nominal_gal": 30.0,
	 "blurb": "Cylindrical tower. Unusual sightlines, awkward to scape."},
	{"key": "hex_pan", "label": "Hex", "shape": "hex",
	 "w_in": 24.0, "d_in": 24.0, "h_in": 12.0, "nominal_gal": 20.0,
	 "blurb": "Six-sided shallow pan. Viewed from above as much as the side."},
	{"key": "fishbowl", "label": "Fishbowl", "shape": "sphere",
	 "w_in": 12.0, "d_in": 12.0, "h_in": 10.0, "nominal_gal": 2.5,
	 "blurb": "Charming and cruel. Almost no surface area for gas exchange."},
]


# --- Lookup ----------------------------------------------------------------

static func all_specs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in CATALOGUE:
		out.append(s.duplicate())
	return out


static func spec(key: String) -> Dictionary:
	for s in CATALOGUE:
		if String(s["key"]) == key:
			return s.duplicate()
	return {}


static func has_spec(key: String) -> bool:
	return not spec(key).is_empty()


# --- Real -> game geometry -------------------------------------------------

# Engine geometry for a spec: half-extents for width/depth, FULL height.
# (That asymmetry is the existing TankConfig API — half_w/half_d but
# tank_height — kept rather than churned.)
static func geometry(key: String) -> Dictionary:
	var s: Dictionary = spec(key)
	if s.is_empty():
		return {}
	return {
		"tank_shape": String(s["shape"]),
		"tank_half_w": units_for_inches(float(s["w_in"])) * 0.5,
		"tank_half_d": units_for_inches(float(s["d_in"])) * 0.5,
		"tank_height": units_for_inches(float(s["h_in"])),
	}


# --- Volume ----------------------------------------------------------------

# Water volume in US gallons, computed from ACTUAL geometry so the custom
# sliders report a real number too — not just the catalogue entries.
#
# `half_w`/`half_d` are half-extents, `height` is full, all in game units.
# `fill` is the water fraction of height (TankConfig.water_surface_fraction).
static func volume_gallons(shape: String, half_w: float, half_d: float,
		height: float, fill: float = 1.0) -> float:
	var w_in: float = inches_for_units(half_w * 2.0)
	var d_in: float = inches_for_units(half_d * 2.0)
	var h_in: float = inches_for_units(height) * maxf(fill, 0.0)
	var cubic: float = 0.0
	match shape:
		"cylinder":
			# Footprint is a circle inscribed in the w×d box.
			var r: float = minf(w_in, d_in) * 0.5
			cubic = PI * r * r * h_in
		"hex":
			# Regular hexagon across the flats of the bounding box.
			var hr: float = minf(w_in, d_in) * 0.5
			cubic = (3.0 * sqrt(3.0) / 2.0) * hr * hr * h_in
		"sphere":
			# A bowl is a sphere truncated at the top — roughly 2/3 of it
			# holds water, which is exactly why bowls hold so little.
			var sr: float = minf(w_in, d_in) * 0.5
			cubic = (4.0 / 3.0) * PI * sr * sr * sr * 0.66
		_:
			cubic = w_in * d_in * h_in
	return cubic / CUBIC_INCHES_PER_US_GALLON


static func volume_litres(shape: String, half_w: float, half_d: float,
		height: float, fill: float = 1.0) -> float:
	return volume_gallons(shape, half_w, half_d, height, fill) * LITRES_PER_US_GALLON


# --- Player-facing text ----------------------------------------------------

# "48 × 18 × 21 in" — the way a tank is actually described.
static func dimensions_label(key: String) -> String:
	var s: Dictionary = spec(key)
	if s.is_empty():
		return ""
	return "%s × %s × %s in" % [
		_trim(float(s["w_in"])), _trim(float(s["d_in"])), _trim(float(s["h_in"])),
	]


# "75 gallon · 284 L" — nominal, because that is what it is sold as.
static func volume_label(key: String) -> String:
	var s: Dictionary = spec(key)
	if s.is_empty():
		return ""
	var gal: float = float(s["nominal_gal"])
	return "%s gallon · %d L" % [_trim(gal), int(round(gal * LITRES_PER_US_GALLON))]


# Same, for arbitrary (custom-slider) geometry where there is no nominal.
static func measured_label(shape: String, half_w: float, half_d: float,
		height: float, fill: float = 1.0) -> String:
	var gal: float = volume_gallons(shape, half_w, half_d, height, fill)
	return "~%s gallon · %d L" % [_trim(gal), int(round(gal * LITRES_PER_US_GALLON))]


# Rough stocking guidance, in the language a shop uses. Based on surface area
# rather than raw volume — gas exchange is what actually limits a tank, which
# is why a shallow breeder out-stocks a column of the same volume, and why a
# bowl is a bad idea.
static func stocking_hint(shape: String, half_w: float, half_d: float,
		height: float, fill: float = 1.0) -> String:
	var gal: float = volume_gallons(shape, half_w, half_d, height, fill)
	var w_in: float = inches_for_units(half_w * 2.0)
	var d_in: float = inches_for_units(half_d * 2.0)
	var surface_sq_in: float = w_in * d_in
	if shape == "cylinder" or shape == "sphere":
		var r: float = minf(w_in, d_in) * 0.5
		surface_sq_in = PI * r * r
	# Calibration matters here: the first pass used the old "12 square inches
	# per fish" rule and told the player a 75 gallon holds 72+ small fish.
	# That is roughly the SIM's hard ceiling (60), not keeping advice — and
	# advice that brushes the cap is advice that gets the tank crashed.
	#
	# 24 sq in of surface per small fish, and ~1 fish per 2 gallons, lands on
	# ~36 for a planted 75 and 5 for a 10 — which is what a shop would say.
	var by_surface: int = int(floor(surface_sq_in / 24.0))
	var by_volume: int = int(floor(gal * 0.5))
	var n: int = maxi(0, mini(by_surface, by_volume))
	# Never promise more than the simulation will actually hold.
	n = mini(n, SIM_FISH_CAP)
	if n <= 0:
		return "Too small for fish — shrimp or a planted bowl."
	if n <= 3:
		return "Room for about %d small fish, or a single betta." % n
	if n <= 10:
		return "Comfortable for a school of %d-%d small fish." % [maxi(1, n - 2), n]
	return "Holds a community of %d+ small fish." % n


# Drop a trailing ".0" so "48.0" reads as "48" but "23.6" survives.
static func _trim(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return "%.1f" % v
