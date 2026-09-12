extends RefCounted
class_name SnailSurface

# Pure geometry for the snail surface-film glide and the waterline band.
#
# WHY THIS IS SEPARATE. snail.gd is a Node3D that needs a live World to do
# anything, so none of its behaviour is reachable from a headless smoke. The
# maths that decides which way up a snail hangs, and where the waterline band
# sits, is pure - so it lives here and gets asserted directly.
#
# THE BEHAVIOUR. Pulmonate snails (bladder, pond, ramshorn) glide inverted
# along the underside of the water's surface film, foot spread flat against
# the surface tension and shell hanging below. In a planted tank that is
# where they congregate: a dense band at the waterline plus a few hanging
# upside-down in open water.


# Dorsal (shell) axis for a snail attached to a surface whose inward normal
# is `wall_normal`. The shell sits on the inward side, so this is just the
# normal - but the SIGN matters on a vertical normal and is easy to lose.
#
#   substrate     normal = UP    -> shell up      (standing on the floor)
#   surface film  normal = DOWN  -> shell DOWN    (hanging under the film)
#
# Collapsing both to UP, which an absf() test does, stands film snails
# upright on top of the water instead of inverting them beneath it.
static func shell_up_for(wall_normal: Vector3) -> Vector3:
	if wall_normal.length_squared() < 1e-8:
		return Vector3.UP
	var n: Vector3 = wall_normal.normalized()
	if absf(n.dot(Vector3.UP)) > 0.95:
		return Vector3.UP if n.y >= 0.0 else Vector3.DOWN
	return n


static func is_film_normal(wall_normal: Vector3) -> bool:
	return wall_normal.dot(Vector3.UP) < -0.95


# The film plane sits just under the water surface so the shell reads as
# wetted rather than floating on top of it.
static func film_plane_y(water_y: float, submerge: float) -> float:
	return water_y - maxf(0.0, submerge)


# Is this snail close enough to the surface to count as "at the waterline"?
static func in_waterline_band(y: float, water_y: float, band: float) -> bool:
	var depth: float = water_y - y
	return depth >= 0.0 and depth <= band


# Probability of taking the film. Heavier, larger shells break through the
# surface tension more readily, so they hang from it less reliably - but a
# big apple snail still surfaces, so this scales rather than gates.
static func film_attach_chance(base: float, shell_size: float,
		size_penalty: float) -> float:
	var over: float = clampf(shell_size - 1.0, 0.0, 1.0)
	return clampf(base * (1.0 - over * size_penalty), 0.0, 1.0)
