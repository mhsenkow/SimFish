extends RefCounted
# Tank sizing rules shared by the scenario templates, Settings sliders, the
# world's initial stocking and the hero camera. Preload it
# (`const TankSizing := preload("res://scripts/tank_sizing.gd")`) rather than
# relying on a class_name, so headless --script runs resolve it without a
# project rescan.
#
# Scale: every scenario template and every catalogue vessel was enlarged by
# SIZE_SCALE (linear) in one pass, so the whole game stays on one scale.
# Templates keep the size they were authored at in `stocking_ref_dims`; the
# stocking and plant fill scale from THAT size, so a template that grew keeps
# the density it was tuned at instead of reading emptier.

const SIZE_SCALE: float = 1.25

# Settings -> Tank slider limits. Width/depth are FULL dimensions (the config
# stores half-extents); height is full height.
const W_MIN: float = 4.0
const W_MAX: float = 36.0
const D_MIN: float = 2.0
const D_MAX: float = 20.0
const H_MIN: float = 4.0
const H_MAX: float = 24.0

# Fill-scale clamps. Stocking scales with volume^(2/3) (the visible
# cross-section grows with the square of the linear size, not the cube), and
# plant fill with floor area. Small groups (1-2, e.g. a single betta or a
# predator pair) never scale: two bettas is a fight, not a denser tank.
const STOCK_SCALE_MIN: float = 0.5
const STOCK_SCALE_MAX: float = 1.8
const PLANT_SCALE_MIN: float = 0.5
const PLANT_SCALE_MAX: float = 1.9
const MIN_SCALED_GROUP: int = 3

const PLANT_KEYS: Array[String] = [
	"valli", "crypt", "carpet", "red_stem", "moss", "java_fern",
]


# Open floor area of a footprint. Constants only matter between shapes; the
# fill scales compare two sizes of the SAME shape, so they cancel there.
static func floor_area(shape: String, half_w: float, half_d: float) -> float:
	match shape:
		"cylinder", "sphere":
			return PI * half_w * half_d
		"hex":
			return 2.598 * half_w * half_d
		"triangle":
			return 1.299 * half_w * half_d
		_:
			return 4.0 * half_w * half_d


# Shape-aware water volume (a sphere bowl tapers, so it holds ~2/3 of the
# cylinder that bounds it).
static func volume(shape: String, half_w: float, half_d: float, height: float) -> float:
	var v: float = floor_area(shape, half_w, half_d) * maxf(0.0, height)
	if shape == "sphere":
		v *= 0.667
	return v


static func _dims(cfg: Object) -> Dictionary:
	if cfg == null:
		return {}
	return {
		"shape": String(cfg.get("tank_shape")),
		"hw": float(cfg.get("tank_half_w")),
		"hd": float(cfg.get("tank_half_d")),
		"h": float(cfg.get("tank_height")),
	}


static func _ref_dims(cfg: Object) -> Vector3:
	if cfg == null:
		return Vector3.ZERO
	var r: Variant = cfg.get("stocking_ref_dims")
	if r is Vector3:
		return r
	return Vector3.ZERO


# Multiplier on a template's authored stocking counts. 1.0 when the tank has
# no reference size (older saves, tanks made without a template).
static func stocking_scale(cfg: Object) -> float:
	var ref: Vector3 = _ref_dims(cfg)
	if ref.x <= 0.0 or ref.y <= 0.0 or ref.z <= 0.0:
		return 1.0
	var d: Dictionary = _dims(cfg)
	return stocking_scale_for(d["shape"], Vector3(d["hw"], d["hd"], d["h"]), ref)


# Same rule from plain numbers (the scenario picker previews a size before
# any TankConfig holds it).
static func stocking_scale_for(shape: String, dims: Vector3, ref: Vector3) -> float:
	if ref.x <= 0.0 or ref.y <= 0.0 or ref.z <= 0.0:
		return 1.0
	var live: float = volume(shape, dims.x, dims.y, dims.z)
	var authored: float = volume(shape, ref.x, ref.y, ref.z)
	if live <= 0.0 or authored <= 0.0:
		return 1.0
	return clampf(pow(live / authored, 2.0 / 3.0), STOCK_SCALE_MIN, STOCK_SCALE_MAX)


# Picker size steps: a multiplier on a template's own (medium) dimensions.
# Stocking and plants follow automatically through stocking_ref_dims.
const SIZE_STEPS: Array[Dictionary] = [
	{"label": "Compact", "scale": 0.8, "hint": "Smaller glass, fewer residents. Lighter on older machines."},
	{"label": "Standard", "scale": 1.0, "hint": "The size each scenario was designed around."},
	{"label": "Large", "scale": 1.2, "hint": "More swim room; fish and plants scale up to match."},
	{"label": "Grand", "scale": 1.4, "hint": "Showpiece size. The most residents - heaviest to simulate."},
]


# A template's (half_w, half_d, height) at size multiplier `s`, kept inside
# the Settings slider range so the panel can always represent it.
static func scaled_dims(half_w: float, half_d: float, height: float, s: float) -> Vector3:
	return Vector3(
		clampf(half_w * s, W_MIN * 0.5, W_MAX * 0.5),
		clampf(half_d * s, D_MIN * 0.5, D_MAX * 0.5),
		clampf(height * s, H_MIN, H_MAX))


# Multiplier on a template's plant palette (floor-area ratio).
static func plant_fill_scale(cfg: Object) -> float:
	var ref: Vector3 = _ref_dims(cfg)
	if ref.x <= 0.0 or ref.y <= 0.0:
		return 1.0
	var d: Dictionary = _dims(cfg)
	var live: float = floor_area(d["shape"], d["hw"], d["hd"])
	var authored: float = floor_area(d["shape"], ref.x, ref.y)
	if live <= 0.0 or authored <= 0.0:
		return 1.0
	return clampf(live / authored, PLANT_SCALE_MIN, PLANT_SCALE_MAX)


static func scale_count(n: int, s: float) -> int:
	if n < MIN_SCALED_GROUP or is_equal_approx(s, 1.0):
		return n
	return maxi(MIN_SCALED_GROUP, int(round(float(n) * s)))


# Copy of a plant palette with every species multiplied by `s` (missing keys
# are the implicit 1.0, so they scale too).
static func scaled_palette(palette: Dictionary, s: float) -> Dictionary:
	var out: Dictionary = palette.duplicate()
	if is_equal_approx(s, 1.0):
		return out
	for key in PLANT_KEYS:
		out[key] = float(palette.get(key, 1.0)) * s
	return out


# Orbit radius that frames a tank of these half-extents at `fill` of the
# viewport, seen from (yaw, pitch) with vertical fov `fov_deg`. Calibrated so
# the classic 8x4x7 box at fov 55 / 16:9 lands on the old 15.5 hero radius.
static func fit_radius(half_w: float, half_d: float, height: float, fov_deg: float,
		aspect: float, yaw: float, pitch: float, fill: float = 0.68) -> float:
	var cy: float = absf(cos(yaw))
	var sy: float = absf(sin(yaw))
	var ext_x: float = half_w * cy + half_d * sy
	var ext_y: float = height * 0.55 * absf(cos(pitch)) + half_d * absf(sin(pitch))
	var tan_v: float = tan(deg_to_rad(clampf(fov_deg, 20.0, 110.0)) * 0.5)
	var tan_h: float = tan_v * maxf(0.3, aspect)
	var r_x: float = ext_x / maxf(0.05, tan_h * fill)
	var r_y: float = ext_y / maxf(0.05, tan_v * fill)
	# The front glass sits nearer than the orbit centre and reads larger.
	return maxf(r_x, r_y) + half_d * 0.3


# One-line size summary for UI captions: "25 x 14 x 10 · ~48 gal". Gallons
# come from TankSpec (real inches), so they match the vessel picker.
static func size_caption(shape: String, half_w: float, half_d: float, height: float,
		water_fraction: float = 0.93) -> String:
	var dims: String = "%d x %d x %d" % [roundi(half_w * 2.0), roundi(half_d * 2.0), roundi(height)]
	var gal: float = TankSpec.volume_gallons(shape, half_w, half_d, height, water_fraction)
	if gal > 0.0:
		return "%s · ~%d gal" % [dims, roundi(gal)]
	return dims
