extends RefCounted
class_name PlantEstablish

# How tall plants are when a tank is first built.
#
# THE PROBLEM. "Established" meant established CHEMISTRY - a cycled
# biofilter, seeded bacteria - but the plants still spawned at nursery
# height. Vallisneria's spec allows a max_height of 14-22 voxels and it was
# planted at randi_range(2, 5). So an "established" tank opened with a
# mature filter and a lawn of 3-voxel stubs, and the player had to wait out
# real growth time before it looked like the planted tank they picked.
#
# A tank that has been running long enough to cycle has grown its plants
# too. In established mode a plant now spawns at a fraction of its own
# mature height instead of a flat literal, so the background actually
# reaches the surface on day one.
#
# Fresh/cycling tanks are untouched: there the small starts are the point.

# Fraction of mature height an established plant spawns at. Not 1.0 - a
# real tank has a spread of ages and something left to grow into, and
# plants pinned at max have no headroom for the growth system to show.
const ESTABLISHED_FRAC: float = 0.72
# Spread around that, so a stand of valli is ragged rather than a hedge cut
# to one level. This is most of what makes planting read as grown rather
# than placed.
const ESTABLISHED_JITTER: float = 0.26


# Stable 0..1 jitter derived from a plant's own spawn position.
#
# DELIBERATELY NOT AN RNG DRAW. Pulling another number from world.gd's
# _rng inside _spawn_plant shifts the whole stream, so every plant placed
# afterwards lands somewhere else - which silently reshuffles the hand-tuned
# composition of every preset just to vary some heights. Hashing the
# position keeps the stream untouched, and neighbouring plants still get
# unrelated values, which is all the raggedness needs.
static func roll_for_position(x: float, z: float) -> float:
	var h: float = sin(x * 12.9898 + z * 78.233) * 43758.5453
	return h - floor(h)


# `roll` is 0..1, normally from roll_for_position. `requested` is the legacy literal;
# an established plant is never SHORTER than it would have been before, so
# this can only add height.
static func initial_height(requested: int, mature_height: int,
		established: bool, scale: float = ESTABLISHED_FRAC,
		roll: float = 0.5) -> int:
	var req: int = maxi(1, requested)
	if not established:
		return req
	var mature: int = maxi(1, mature_height)
	var frac: float = clampf(scale, 0.0, 1.0) * lerpf(
		1.0 - ESTABLISHED_JITTER, 1.0 + ESTABLISHED_JITTER,
		clampf(roll, 0.0, 1.0))
	var grown: int = int(round(float(mature) * clampf(frac, 0.05, 1.0)))
	# Never above the plant's own mature height, never below the legacy
	# value, always at least one voxel.
	return clampi(maxi(req, grown), 1, mature)


# --- Reaching the surface ------------------------------------------------
#
# Plant heights were fixed voxel counts (vallisneria 14-22) while tanks are
# any size the player picks. In an 11-unit tank the water column is 8.25
# units and valli tops out at 7.04, so it finished growing 1.06 units below
# the surface - and the whole canopy-layover path, which bends ribbon
# blades over at the waterline and lays them along it, could never run.
# Making tanks bigger made it worse.
#
# A species that reaches the surface in reality should reach it in whatever
# tank it is planted in, so the height is derived from the water column
# rather than written down.

# Blade length allowed to lie ALONG the surface once the tip gets there.
# _apply_canopy_layover pins the top 14 voxels to the water plane, so
# without at least that much surplus the "pool" is just a bent tip - and
# with far less, the laid-over voxels tear away from the vertical stem
# below them and the blade visibly breaks.
# Must equal Plant.CANOPY_LAY_RIBBON: the layover pins exactly that many
# voxels to the water plane, so that is exactly how much surplus blade a
# pooling plant needs. More and a stub pokes above the waterline; less and
# the laid-over run tears away from the vertical stem below it.
const POOL_SURPLUS_VOXELS: int = 14
# Ceiling, so a very tall vessel does not turn one plant into a hundred
# voxels. Generous: it only bites on tanks past ~13 units of water.
# Raised from 52: the Settings height slider goes to 20, whose water column
# needs 47 voxels of blade before any surplus at all, so the old ceiling
# squeezed the pooling surplus to 5 on the tallest tanks and the laid-over
# run tore away from the stem it grew out of.
const MAX_PLANT_VOXELS: int = 72


# Voxels needed for a plant based at `base_y` to just touch the surface.
static func surface_reach_voxels(base_y: float, water_y: float,
		voxel_size: float) -> int:
	var span: float = water_y - base_y
	if span <= 0.0 or voxel_size <= 0.0001:
		return 1
	return maxi(1, int(ceil(span / voxel_size)))


# Mature height for a species that should reach the surface. `surplus` is
# the extra blade that lies along it; 0 for plants that simply stop at the
# waterline (a stem plant breaking the meniscus) rather than pooling.
static func surface_height(base_y: float, water_y: float, voxel_size: float,
		natural_max: int, surplus: int = 0) -> int:
	var reach: int = surface_reach_voxels(base_y, water_y, voxel_size)
	# Never SHORTER than the species would naturally be - a tiny tank must
	# not stunt a plant below its own genome.
	return clampi(maxi(natural_max, reach + maxi(0, surplus)),
		1, MAX_PLANT_VOXELS)


# Starting height for an established surface-reaching plant.
#
# THE BUG THIS FIXES. The generic rule starts an established plant at 72% of
# its mature height. On a small tank that happens to land past the
# waterline, so valli opens already pooling; on a tall one it lands well
# short - 10 voxels short at height 20 - and the plant then has to grow
# there against a per-tick growth budget shared by every plant in the tank.
# So "plants reach the surface" was quietly true only on small tanks.
#
# An established tank has, by definition, been running long enough for its
# vallisneria to have reached the top. So it starts AT the waterline, with a
# jittered share of the surplus already laid over - which also keeps the
# stand ragged rather than a hedge cut to one level.
static func established_surface_height(reach: int, mature: int,
		roll: float) -> int:
	var r: int = maxi(1, reach)
	var m: int = maxi(r, mature)
	var surplus: int = m - r
	var laid: int = int(round(float(surplus)
		* lerpf(0.30, 1.0, clampf(roll, 0.0, 1.0))))
	return clampi(r + laid, 1, m)
