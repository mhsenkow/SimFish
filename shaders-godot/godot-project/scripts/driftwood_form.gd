extends RefCounted
class_name DriftwoodForm

# Shapes of driftwood.
#
# THE PROBLEM. There was exactly one piece of wood: a single bezier trunk
# arcing low across the floor, plus four hard-coded side twigs. Every tank
# got the same silhouette, the hardscape "styles" only scaled how many
# voxels it was made of, and because the trunk stays near the substrate the
# whole middle and upper water column was left empty. Real driftwood in a
# planted tank is usually the opposite: a branch that climbs, forks, and
# occupies the space the fish swim in.
#
# This returns LIMBS - cubic bezier segments with a thickness taper - and
# leaves the voxelising to the caller, so the shapes are pure and testable
# and world.gd keeps its existing rendering.
#
# Coordinates are tank-relative fractions resolved against half_w / half_d
# and the substrate-to-water span, so a form reads the same in a nano cube
# and a six-footer.

enum { LOG, BRANCH, SPIDER, STUMP }

const FORM_NAMES := {
	"log": LOG,        # the original: a low arc across the floor
	"branch": BRANCH,  # climbs and forks up into the water column
	"spider": SPIDER,  # low centre, many thin limbs radiating outward
	"stump": STUMP,    # squat root mass with short upward prongs
}

# How much of the water column the tallest forms are allowed to occupy.
# Not 1.0: wood that touches the surface reads as a fallen tree, and it
# would also fight the floating plants for the waterline.
const BRANCH_REACH: float = 0.74
const SPIDER_REACH: float = 0.34
const STUMP_REACH: float = 0.30


static func form_id(name: String) -> int:
	return int(FORM_NAMES.get(name, LOG))


static func form_name(id: int) -> String:
	for k in FORM_NAMES.keys():
		if int(FORM_NAMES[k]) == id:
			return k
	return "log"


# One limb: a cubic bezier plus the thickness at each end.
static func _limb(a: Vector3, c1: Vector3, c2: Vector3, b: Vector3,
		t0: float, t1: float, depth: int) -> Dictionary:
	return {"p0": a, "p1": c1, "p2": c2, "p3": b,
		"thick0": t0, "thick1": t1, "depth": depth}


# All limbs for a form. `rng` is seeded by the caller so a tank's wood is
# stable across reloads.
static func limbs(form: int, rng: RandomNumberGenerator,
		half_w: float, half_d: float, substrate_y: float,
		water_y: float) -> Array[Dictionary]:
	var span: float = maxf(0.5, water_y - substrate_y)
	match form:
		BRANCH:
			return _branch(rng, half_w, half_d, substrate_y, span)
		SPIDER:
			return _spider(rng, half_w, half_d, substrate_y, span)
		STUMP:
			return _stump(rng, half_w, half_d, substrate_y, span)
		_:
			return _log(rng, half_w, half_d, substrate_y, span)


# The original silhouette, kept so existing tanks are not restyled.
static func _log(_rng: RandomNumberGenerator, hw: float, hd: float,
		sub: float, _span: float) -> Array[Dictionary]:
	# Reproduces the original trunk EXACTLY - no mirroring, no jitter. Its
	# position is baked into where every other piece of hardscape and
	# planting ends up, and a gratuitous flip here moved the polyp jar's
	# carpet out past where the layout smoke expects it.
	var out: Array[Dictionary] = []
	# The control heights are ABSOLUTE (+1.25 / +1.55 above the substrate),
	# not fractions of the water column. That is how the original was
	# written, and on a tall or spherical vessel a fraction lands somewhere
	# quite different - which moved hardscape occupancy and pushed the polyp
	# jar's carpet planting outside where the layout smoke expects it.
	out.append(_limb(
		Vector3(-hw * 0.8, sub - 0.25, -hd * 0.4),
		Vector3(-hw * 0.4, sub + 1.25, hd * 0.2),
		Vector3(hw * 0.1, sub + 1.55, hd * 0.3),
		Vector3(hw * 0.65, sub + 0.05, -hd * 0.2),
		0.62, 0.25, 0))
	return out


# A climbing, forking branch. This is the one that fills a tank: the trunk
# rises out of the substrate and splits, and the children split again, so
# there is wood at every height a fish might swim at.
static func _branch(rng: RandomNumberGenerator, hw: float, hd: float,
		sub: float, span: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var base := Vector3(
		rng.randf_range(-0.45, 0.45) * hw, sub - 0.2,
		rng.randf_range(-0.35, 0.35) * hd)
	var lean := Vector3(rng.randf_range(-0.30, 0.30),
		0.0, rng.randf_range(-0.30, 0.30))
	var top: Vector3 = base + Vector3(lean.x * hw, span * BRANCH_REACH, lean.z * hd)
	out.append(_limb(base,
		base + Vector3(lean.x * hw * 0.2, span * 0.26, lean.z * hd * 0.2),
		base + Vector3(lean.x * hw * 0.7, span * 0.54, lean.z * hd * 0.7),
		top, 0.68, 0.30, 0))
	# Forks. Two generations is enough to read as a branch without turning
	# the tank into a thicket the fish cannot path through.
	_fork(out, rng, base, top, hw, hd, span, 1)
	return out


static func _fork(out: Array[Dictionary], rng: RandomNumberGenerator,
		base: Vector3, tip: Vector3, hw: float, hd: float, span: float,
		depth: int) -> void:
	if depth > 2:
		return
	var count: int = 3 if depth == 1 else 2
	for i in count:
		var t: float = rng.randf_range(0.35, 0.85)
		var from: Vector3 = base.lerp(tip, t)
		var ang: float = rng.randf() * TAU
		var reach: float = (0.34 if depth == 1 else 0.20) * (1.0 - t * 0.35)
		var to: Vector3 = from + Vector3(
			cos(ang) * hw * reach,
			span * (0.22 if depth == 1 else 0.13),
			sin(ang) * hd * reach)
		var t0: float = 0.34 if depth == 1 else 0.20
		out.append(_limb(from,
			from.lerp(to, 0.35) + Vector3(0.0, span * 0.04, 0.0),
			from.lerp(to, 0.7),
			to, t0, t0 * 0.55, depth))
		if depth == 1 and rng.randf() < 0.7:
			_fork(out, rng, from, to, hw, hd, span, depth + 1)


# Spiderwood: a low hub with thin limbs snaking outward across the floor.
static func _spider(rng: RandomNumberGenerator, hw: float, hd: float,
		sub: float, span: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var hub := Vector3(rng.randf_range(-0.3, 0.3) * hw, sub + span * 0.06,
		rng.randf_range(-0.3, 0.3) * hd)
	var n: int = rng.randi_range(4, 6)
	for i in n:
		var ang: float = TAU * (float(i) + rng.randf_range(-0.2, 0.2)) / float(n)
		var reach: float = rng.randf_range(0.45, 0.85)
		var to: Vector3 = hub + Vector3(cos(ang) * hw * reach,
			span * SPIDER_REACH * rng.randf_range(0.3, 1.0),
			sin(ang) * hd * reach)
		out.append(_limb(hub,
			hub.lerp(to, 0.3) + Vector3(0.0, span * 0.05, 0.0),
			hub.lerp(to, 0.72) + Vector3(0.0, span * 0.02, 0.0),
			to, 0.34, 0.13, 0))
	return out


# A squat root mass - wide and low, with short prongs.
static func _stump(rng: RandomNumberGenerator, hw: float, hd: float,
		sub: float, span: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var c := Vector3(rng.randf_range(-0.4, 0.4) * hw, sub - 0.15,
		rng.randf_range(-0.4, 0.4) * hd)
	out.append(_limb(c,
		c + Vector3(0.0, span * 0.08, 0.0),
		c + Vector3(0.0, span * 0.14, 0.0),
		c + Vector3(0.0, span * STUMP_REACH * 0.6, 0.0), 0.85, 0.45, 0))
	var n: int = rng.randi_range(3, 5)
	for i in n:
		var ang: float = TAU * float(i) / float(n) + rng.randf_range(-0.3, 0.3)
		var to: Vector3 = c + Vector3(cos(ang) * hw * 0.30,
			span * STUMP_REACH * rng.randf_range(0.5, 1.0),
			sin(ang) * hd * 0.30)
		out.append(_limb(c + Vector3(0.0, span * 0.05, 0.0),
			c.lerp(to, 0.4), c.lerp(to, 0.75), to, 0.40, 0.18, 1))
	return out


# Total limb count, for a caller budgeting voxels.
static func limb_steps(limb: Dictionary, base_steps: int) -> int:
	var d: int = int(limb.get("depth", 0))
	return maxi(4, int(round(float(base_steps) * pow(0.62, float(d)))))
