# Per-species water-column band: where in the column a species lives
# (0 = substrate top, 1 = surface) and how wide that band is.
#
# WATER-COLUMN CONTRACT (Holistic #081). One definition everywhere:
#   frac 0.0 = substrate top (World.SUBSTRATE_DEPTH / sim.substrate_top_y)
#   frac 1.0 = water surface (World.WATER_HEIGHT)
# Soft swim margins and dome ceilings are locomotion / footprint concerns;
# they must not redefine what a stored preferred_y_frac means. Use
# y_from_frac / frac_from_y for every placement, home, and probe reading.
#
# WHY THIS EXISTS. world._apply_founding_cohort_spread used to overwrite every
# founding fish's preferred_y_frac with an even 10%..86% ladder across the
# cohort, whatever the species, and the library's legacy preferred_y values put
# guppies, rasboras and glassdarts at 0.40-0.48 of the column anyway. Watched
# (dev/fish_behaviour_probe), guppy depth p10/p50/p90 was 0.23/0.39/0.87 and
# glassdart 0.24/0.47/0.83: every species filled the whole column and the tank
# read as one mixed cloud. Real planted tanks stratify - livebearers work the
# top third and the surface film, rasboras and embers the upper middle,
# rummy-noses the lower middle.
#
# DATA-DRIVEN. A genome can carry its own "depth_frac" (band centre) and
# "depth_band" (half-width, as a fraction of the column); BANDS below is the
# fallback keyed by species id, so species defined elsewhere (FISHLOOK's
# endler / rummy_nose / ember_tetra) stratify without editing their entries.
# An explicit per-fish "preferred_y_frac" (a save, a sphere-tank roll, an
# inherited fry value) still wins over both - this only decides where a
# species' founders are placed and how tightly they hold their layer.
extends RefCounted

const DEFAULT_HALF: float = 0.14

# species -> Vector2(centre_frac, half_width_frac)
# Centres are the intended living depth on the shared 0..1 column (no probe
# compensation offset). Saves that already store preferred_y_frac keep it.
const BANDS: Dictionary = {
	"guppy": Vector2(0.80, 0.13),
	"endler": Vector2(0.84, 0.11),
	"harlequin_rasbora": Vector2(0.60, 0.12),
	"ember_tetra": Vector2(0.52, 0.11),
	"glassdart": Vector2(0.44, 0.12),
	"rummy_nose": Vector2(0.36, 0.11),
}


# Absolute Y for a column fraction. floor_y = substrate top, surface_y = meniscus.
static func y_from_frac(frac: float, floor_y: float, surface_y: float) -> float:
	return lerpf(floor_y, surface_y, clampf(frac, 0.0, 1.0))


# Column fraction for an absolute Y. Matches y_from_frac as its inverse.
static func frac_from_y(y: float, floor_y: float, surface_y: float) -> float:
	return clampf((y - floor_y) / maxf(surface_y - floor_y, 0.5), 0.0, 1.0)


# Band for a genome; x < 0 means "no species band - use the legacy
# preferred_y". y is always a usable half-width.
static func band_for(genome: Dictionary) -> Vector2:
	var b: Vector2 = BANDS.get(String(genome.get("species", "")), Vector2(-1.0, DEFAULT_HALF))
	if genome.has("depth_frac"):
		b.x = clampf(float(genome["depth_frac"]), 0.05, 0.95)
	if genome.has("depth_band"):
		b.y = clampf(float(genome["depth_band"]), 0.03, 0.45)
	return b


static func has_band(genome: Dictionary) -> bool:
	return band_for(genome).x >= 0.0


# Centre of the band, falling back to the legacy absolute preferred_y mapped
# through the reference column the species library was calibrated against.
static func centre_frac(genome: Dictionary, ref_substrate_y: float, ref_column: float) -> float:
	var b: Vector2 = band_for(genome)
	if b.x >= 0.0:
		return b.x
	var legacy: float = float(genome.get("preferred_y", 3.5))
	return clampf((legacy - ref_substrate_y) / maxf(ref_column, 0.5), 0.05, 0.95)


# Where founder i of count sits: a ladder across the species band (not the
# whole column), with a little jitter so the ladder does not read as rungs.
static func cohort_frac(genome: Dictionary, i: int, count: int, jitter: float,
		ref_substrate_y: float, ref_column: float) -> float:
	var half: float = band_for(genome).y
	var t: float = float(i) / float(maxi(count - 1, 1)) * 2.0 - 1.0
	return clampf(centre_frac(genome, ref_substrate_y, ref_column)
		+ t * half * 0.85 + jitter * half * 0.35, 0.06, 0.94)


# Vertical territory radius (world units) for a banded species: the fish may
# wander roughly its band's half-width before the home pull firms up.
static func home_y_radius(genome: Dictionary, column: float) -> float:
	return clampf(band_for(genome).y * column * 0.72, 0.25, 2.5)
