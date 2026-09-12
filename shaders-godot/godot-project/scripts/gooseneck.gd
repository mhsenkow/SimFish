extends RefCounted
class_name Gooseneck

# Shape of a clip-on gooseneck lamp: a clamp bitten onto the tank rim, a
# flexible neck arcing over the water, a head on the end, and a cable
# hanging off the back.
#
# WHY THIS IS NOT JUST AN OFFSET. The fixture used to be a fixed set of
# voxels whose whole root was moved as one piece. Drag it and the clamp
# went with it - a rim clamp floating in mid-air over the middle of the
# water, with its cable pointing off into the room. Nothing about that
# reads as a lamp you can move.
#
# A real gooseneck moves differently: the CLAMP stays bitten to the rim,
# and the NECK bends. So the head is what you drag, the clamp slides along
# the rim to the nearest point that can reach it, and the arm is rebuilt as
# a curve between the two. The cable always hangs from the clamp, down the
# outside of the glass, because that is the only place it can go.

# How many segments the neck is built from. Enough to read as a smooth
# flexible tube after palette quantization, not so many that rebuilding it
# every mouse-move costs anything.
const ARM_SEGMENTS: int = 9
const CABLE_SEGMENTS: int = 7
const ARM_THICKNESS: float = 0.10
const CABLE_THICKNESS: float = 0.06

# How high the neck bows above the straight clamp-to-head line. A real
# gooseneck is bent up and over, never a taut wire.
const ARM_BOW: float = 0.55
# Minimum bow so a head parked right next to its clamp still arcs.
const ARM_BOW_MIN: float = 0.22


# Nearest point on the footprint perimeter to an xz position. This is where
# the clamp bites: a clip lamp is attached to the rim, so its position is
# one-dimensional - it slides around the edge, it does not float.
static func clamp_point(head: Vector3, corners: Array, rim_y: float) -> Vector3:
	if corners.size() < 2:
		return Vector3(head.x, rim_y, head.z)
	var best := Vector2(INF, INF)
	var best_d: float = INF
	var h := Vector2(head.x, head.z)
	for i in corners.size():
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % corners.size()]
		var p: Vector2 = _closest_on_segment(
			h, Vector2(a.x, a.z), Vector2(b.x, b.z))
		var d: float = p.distance_squared_to(h)
		if d < best_d:
			best_d = d
			best = p
	return Vector3(best.x, rim_y, best.y)


static func _closest_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab: Vector2 = b - a
	var len2: float = ab.length_squared()
	if len2 < 1e-8:
		return a
	return a + ab * clampf((p - a).dot(ab) / len2, 0.0, 1.0)


# Outward normal at the clamp, so the cable knows which way is "off the
# back of the tank" rather than into the water.
static func outward_at(point: Vector3, corners: Array) -> Vector3:
	var c := Vector3.ZERO
	for p in corners:
		c += p
	if corners.size() > 0:
		c /= float(corners.size())
	var away := Vector3(point.x - c.x, 0.0, point.z - c.z)
	if away.length_squared() < 1e-6:
		return Vector3.FORWARD
	return away.normalized()


# The neck, as a quadratic Bezier from clamp to head bowed upward. Returns
# world-space sample points.
static func arm_samples(clamp_pos: Vector3, head: Vector3,
		count: int = ARM_SEGMENTS) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n: int = maxi(2, count)
	var span: float = clamp_pos.distance_to(head)
	var bow: float = maxf(ARM_BOW_MIN, span * ARM_BOW)
	# Control point above the midpoint: up first, then over and down, which
	# is the silhouette of every clip lamp ever made.
	var ctrl: Vector3 = (clamp_pos + head) * 0.5 + Vector3.UP * bow
	for i in n:
		var t: float = float(i) / float(n - 1)
		var inv: float = 1.0 - t
		out.append(clamp_pos * (inv * inv) + ctrl * (2.0 * inv * t)
			+ head * (t * t))
	return out


# The cable: out from the clamp, then straight down the outside of the
# glass. It is what tells you the lamp is plugged into something.
static func cable_samples(clamp_pos: Vector3, outward: Vector3,
		drop: float, count: int = CABLE_SEGMENTS) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n: int = maxi(2, count)
	var lip: Vector3 = clamp_pos + outward * 0.18
	for i in n:
		var t: float = float(i) / float(n - 1)
		# Ease outward quickly then fall: a cable bends over the rim, it
		# does not leave at 45 degrees.
		var side: float = 1.0 - pow(1.0 - t, 2.2)
		out.append(Vector3(
			lerpf(clamp_pos.x, lip.x, side),
			clamp_pos.y - drop * (t * t),
			lerpf(clamp_pos.z, lip.z, side)))
	return out


# Keep the head within reach of the rim it is clamped to. A neck that
# stretches halfway across the room is the same failure as a clamp that
# floats: it stops reading as one object.
static func max_reach(half_w: float, half_d: float) -> float:
	return maxf(1.2, minf(half_w, half_d) * 1.35)


static func constrain_head(head: Vector3, clamp_pos: Vector3,
		reach: float) -> Vector3:
	var d: Vector3 = head - clamp_pos
	var dist: float = d.length()
	if dist <= reach or dist < 1e-6:
		return head
	return clamp_pos + d / dist * reach
