class_name MotionSurfaceTransition
extends RefCounted

# Moving from one surface to another as a roll over the shared edge
# (CREATURE_MOTION_700 #56), used by snails, climbing shrimp and the
# hillstream loach. Instead of teleporting the orientation, the body pivots
# about the edge line from the old surface's "up" to the new one over a set
# time, so the head reaches over first and the rest follows.
#
# sample(t) gives the up vector and the offset of the body from the edge
# point at progress t (0..1, eased), for a body that stands `clearance` above
# whichever surface it is on.

var from_up: Vector3 = Vector3.UP
var to_up: Vector3 = Vector3.BACK
var edge_point: Vector3 = Vector3.ZERO
var clearance: float = 0.05
var duration: float = 1.5
var t: float = 0.0


func _init(from_normal: Vector3, to_normal: Vector3, edge: Vector3, body_clearance: float = 0.05,
		seconds: float = 1.5) -> void:
	from_up = from_normal.normalized()
	to_up = to_normal.normalized()
	edge_point = edge
	clearance = body_clearance
	duration = maxf(seconds, 0.05)


func done() -> bool:
	return t >= 1.0 - 1e-5


func step(dt: float) -> float:
	t = clampf(t + maxf(dt, 0.0) / duration, 0.0, 1.0)
	return t


# The edge axis is perpendicular to both normals; rolling about it carries
# one up vector into the other.
func axis() -> Vector3:
	var a: Vector3 = from_up.cross(to_up)
	return a.normalized() if a.length_squared() > 1e-6 else Vector3.RIGHT


func up_at(p: float) -> Vector3:
	var e: float = MotionEase.sine_in_out(p)
	var total: float = from_up.angle_to(to_up)
	return from_up.rotated(axis(), total * e).normalized()


func position_at(p: float) -> Vector3:
	return edge_point + up_at(p) * clearance


func sample() -> Dictionary:
	return {"up": up_at(t), "position": position_at(t), "t": t}
