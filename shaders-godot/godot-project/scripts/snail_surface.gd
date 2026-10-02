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


# --- Holistic #126: corner continuity (box + hex) ---------------------------

# True when the nearest glass normal is a different face from the current
# crawl plane and the snail is close enough to transfer without a jump.
static func should_transfer_wall(current_n: Vector3, nearest_n: Vector3,
		clearance: float, corner_band: float = 0.28) -> bool:
	if current_n.length_squared() < 1e-8 or nearest_n.length_squared() < 1e-8:
		return false
	var a: Vector3 = current_n.normalized()
	var b: Vector3 = nearest_n.normalized()
	# Stay on vertical glass; substrate/film handled elsewhere.
	if absf(a.y) > 0.55 or absf(b.y) > 0.55:
		return false
	if clearance > corner_band:
		return false
	# Distinct faces: normals diverge (box 90°, hex ~60°).
	return a.dot(b) < 0.72


# Unit normal after a continuous corner turn. Keeps Y, slerps XZ.
static func blend_wall_normal(from_n: Vector3, to_n: Vector3, t: float) -> Vector3:
	var a: Vector3 = from_n.normalized() if from_n.length_squared() > 1e-8 else Vector3.RIGHT
	var b: Vector3 = to_n.normalized() if to_n.length_squared() > 1e-8 else a
	var u: float = clampf(t, 0.0, 1.0)
	var mixed: Vector3 = a.slerp(b, u)
	if mixed.length_squared() < 1e-8:
		return b
	return mixed.normalized()


# Walk the snail around a glass corner on the exterior path (never the chord
# through the aquarium interior). Returns the new position on the new face.
static func wrap_position_around_corner(pos: Vector3, from_n: Vector3, to_n: Vector3,
		nudge: float = 0.06) -> Vector3:
	var a: Vector3 = from_n.normalized() if from_n.length_squared() > 1e-8 else Vector3.RIGHT
	var b: Vector3 = to_n.normalized() if to_n.length_squared() > 1e-8 else a
	# Corner edge direction (shared glass seam).
	var edge: Vector3 = a.cross(b)
	if edge.length_squared() < 1e-8:
		edge = Vector3.UP
	else:
		edge = edge.normalized()
	# Keep Y; project XZ onto the new face just inside the glass.
	var out := Vector3(pos.x, pos.y, pos.z)
	# Stay near the seam so path length ≈ arc, not a diagonal shortcut.
	var along: float = (out - pos).dot(edge)
	out = pos + edge * along + b * nudge
	out.y = pos.y
	return out


# Slime mark anchors: always offset along the glass normal. Corner hops emit
# intermediate glass-side marks instead of a chord through the interior.
static func slime_trail_anchors(prev_pos: Vector3, prev_n: Vector3,
		pos: Vector3, wall_n: Vector3, max_chord: float = 0.55) -> Array:
	var n: Vector3 = wall_n.normalized() if wall_n.length_squared() > 1e-8 else Vector3.RIGHT
	var pn: Vector3 = prev_n.normalized() if prev_n.length_squared() > 1e-8 else n
	var delta: Vector3 = pos - prev_pos
	var chord: float = delta.length()
	if chord < 1e-5:
		return [pos + n * 0.02]
	# Interior chord: displacement has a large component opposite both normals.
	var inward_cut: float = maxf(-delta.dot(n), -delta.dot(pn))
	if chord > max_chord or inward_cut > chord * 0.35:
		var mid: Vector3 = wrap_position_around_corner(prev_pos, pn, n, 0.02)
		return [
			prev_pos + pn * 0.02,
			mid + blend_wall_normal(pn, n, 0.5) * 0.02,
			pos + n * 0.02,
		]
	return [pos + n * 0.02]


# Path length along glass vs Euclidean chord. Continuous corners keep ratio ≈ 1.
static func glass_path_ratio(prev_pos: Vector3, pos: Vector3, from_n: Vector3,
		to_n: Vector3) -> float:
	var chord: float = prev_pos.distance_to(pos)
	if chord < 1e-6:
		return 1.0
	var wrapped: Vector3 = wrap_position_around_corner(prev_pos, from_n, to_n, 0.0)
	var via: float = prev_pos.distance_to(wrapped) + wrapped.distance_to(pos)
	return via / maxf(chord, 1e-6)
