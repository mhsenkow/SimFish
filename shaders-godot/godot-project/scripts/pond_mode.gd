class_name PondMode
extends RefCounted

# Pond-mode computation, carved out of main.gd (BROAD_DIRECTIONS #7).
#
# WHY THIS SHAPE. main.gd is 11k lines / 490 functions, and the obvious way
# to shrink it — move whole feature clusters into a module that reaches back
# via `host.get("...")` / `host.call("...")` — is how `SaveManager` and
# `UiPanelManager` were done. It works, but it trades god-object size for
# exactly the stringly-typed coupling that direction #8 is about: 1,077
# `has_method()` guards and counting.
#
# So this carve takes only the *computational* core and gives it real typed
# signatures: stroke accumulation, school centroid, per-fish startle
# response, camera framing, vignette. No Node references, no `host`, no
# `has_method`. main.gd keeps the thin orchestration that genuinely does
# belong to the scene (spawning ripples, moving the camera, haptics).
#
# The payoff beyond line count is that all of this is now unit-testable —
# see smoke_pond_mode.gd. None of it was reachable from a headless test
# before, because it all lived inside methods on the main scene node.

# Minimum world-space gap between recorded conduct-stroke points. Sampling
# every mouse-move would pack hundreds of near-identical points into a
# gesture that only needs its shape.
const CONDUCT_MIN_STEP: float = 0.35

# A conduct stroke needs at least this many points to read as a gesture
# rather than a stray click.
const CONDUCT_MIN_POINTS: int = 3

# Fish within this squared XZ distance of a tap respond to it.
const STARTLE_RADIUS_SQ: float = 12.0

# Proximity falloff: a tap this far away (world units) produces no response.
const STARTLE_FALLOFF: float = 3.5

# Startle duration range, scaled by proximity.
const STARTLE_MIN_S: float = 0.12
const STARTLE_MAX_S: float = 0.35

# How much a startle raises curiosity at point-blank range.
const CURIOSITY_GAIN: float = 0.08

# How hard pond framing pulls the camera toward the school centroid.
const FRAMING_WEIGHT: float = 0.72

# Vignette floor while in pond mode, and the decay applied on exit.
const VIGNETTE_ON_MIN: float = 0.32
const VIGNETTE_OFF_FLOOR: float = 0.20
const VIGNETTE_OFF_DECAY: float = 0.85


# --- Conduct stroke --------------------------------------------------------

# Should this point be appended to the stroke? Pulled out so the caller does
# not have to re-derive the min-step rule, and so the rule is testable.
static func should_record_conduct_point(points: Array, hit: Vector3) -> bool:
	if points.is_empty():
		return true
	var last: Vector3 = points[points.size() - 1]
	return last.distance_to(hit) >= CONDUCT_MIN_STEP


# Append `hit` to `points` when it clears the min-step gap. Returns true when
# the point was recorded. Mutates `points` (the caller owns the buffer).
static func record_conduct_point(points: Array, hit: Vector3) -> bool:
	if not should_record_conduct_point(points, hit):
		return false
	points.append(hit)
	return true


static func conduct_stroke_is_gesture(points: Array) -> bool:
	return points.size() >= CONDUCT_MIN_POINTS


# --- School framing --------------------------------------------------------

# Mean XZ position of the living fish, or `fallback` when there are none.
#
# `fish` is an Array of Fish, but is typed loosely so a test can pass simple
# stand-ins. Invalid and dying fish are skipped: a corpse should not drag
# the camera, and a freed instance would crash the loop.
static func school_centroid_xz(fish: Array, fallback: Vector2) -> Vector2:
	var cx: float = 0.0
	var cz: float = 0.0
	var n: int = 0
	for f in fish:
		if f == null or not is_instance_valid(f):
			continue
		if f.get("_dying") == true:
			continue
		var pos: Vector3 = f.global_position
		cx += pos.x
		cz += pos.z
		n += 1
	if n <= 0:
		return fallback
	return Vector2(cx / float(n), cz / float(n))


# Where the camera target should move to frame the school. Only X/Z are
# pulled; Y (height) is the player's business.
static func framing_target(current: Vector3, centroid: Vector2,
		weight: float = FRAMING_WEIGHT) -> Vector3:
	return Vector3(
		lerpf(current.x, centroid.x, weight),
		current.y,
		lerpf(current.z, centroid.y, weight))


# --- Startle response ------------------------------------------------------

# How strongly a fish at `pos` reacts to a tap at `hit`: 1.0 point-blank,
# 0.0 at STARTLE_FALLOFF and beyond. XZ only — a tap on the surface startles
# by horizontal distance, not depth.
static func startle_proximity(pos: Vector3, hit: Vector3) -> float:
	var dx: float = pos.x - hit.x
	var dz: float = pos.z - hit.z
	var d2: float = dx * dx + dz * dz
	if d2 > STARTLE_RADIUS_SQ:
		return 0.0
	return 1.0 - clampf(sqrt(d2) / STARTLE_FALLOFF, 0.0, 1.0)


static func is_in_startle_range(pos: Vector3, hit: Vector3) -> bool:
	var dx: float = pos.x - hit.x
	var dz: float = pos.z - hit.z
	return (dx * dx + dz * dz) <= STARTLE_RADIUS_SQ


# Startle duration for a given proximity. The caller takes max() with any
# startle already in flight, so a second tap never shortens the first.
static func startle_duration(proximity: float) -> float:
	return lerpf(STARTLE_MIN_S, STARTLE_MAX_S, clampf(proximity, 0.0, 1.0))


static func startle_curiosity(current: float, proximity: float) -> float:
	return clampf(current + clampf(proximity, 0.0, 1.0) * CURIOSITY_GAIN, 0.0, 1.0)


# --- Visuals ---------------------------------------------------------------

# Vignette strength when entering (`on`) or leaving pond mode. Entering
# raises to a floor; leaving decays toward a lower floor, so repeated
# toggling neither ratchets up forever nor snaps to zero.
static func vignette_strength(current: float, on: bool) -> float:
	if on:
		return maxf(current, VIGNETTE_ON_MIN)
	return maxf(current * VIGNETTE_OFF_DECAY, VIGNETTE_OFF_FLOOR)
