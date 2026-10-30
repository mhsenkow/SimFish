class_name MotionContact
extends RefCounted

# Minimal contact "IK" (CREATURE_MOTION_700 #55): find the ground under a
# contact point and the angle a one-segment limb must turn to reach it. Used
# for leg tips, the snail foot and fish resting on the bed. Bounded cost: a
# height function (the substrate already has one) sampled at most three
# times, no physics bodies.
#
# height_at: Callable(x: float, z: float) -> float, the ground height there.


static func ground_point(height_at: Callable, p: Vector3) -> Vector3:
	if not height_at.is_valid():
		return p
	return Vector3(p.x, float(height_at.call(p.x, p.z)), p.z)


# Surface normal from three height samples, eps apart.
static func ground_normal(height_at: Callable, p: Vector3, eps: float = 0.05) -> Vector3:
	if not height_at.is_valid():
		return Vector3.UP
	var h: float = float(height_at.call(p.x, p.z))
	var hx: float = float(height_at.call(p.x + eps, p.z))
	var hz: float = float(height_at.call(p.x, p.z + eps))
	var n := Vector3(h - hx, eps, h - hz).normalized()
	return n if n.is_finite() and n.length_squared() > 0.5 else Vector3.UP


# How far (radians, about the pivot's hinge axis) a limb of length `reach`
# hanging along rest_dir must swing so its tip touches `target`. Clamped to
# max_swing so an out-of-reach foot stretches rather than snapping round.
static func swing_to_reach(pivot: Vector3, rest_dir: Vector3, hinge_axis: Vector3,
		target: Vector3, max_swing: float = 0.6) -> float:
	var axis: Vector3 = hinge_axis.normalized()
	var want: Vector3 = target - pivot
	var a: Vector3 = (rest_dir - axis * rest_dir.dot(axis)).normalized()
	var b: Vector3 = (want - axis * want.dot(axis)).normalized()
	if not a.is_finite() or not b.is_finite() or a.length_squared() < 0.5 or b.length_squared() < 0.5:
		return 0.0
	return clampf(a.signed_angle_to(b, axis), -max_swing, max_swing)


# Height to hold a body above the ground so a contact at local depth `sole`
# just touches it; a resting bottom fish sits on its fins, not a voxel above.
static func rest_height(height_at: Callable, p: Vector3, sole: float) -> float:
	return ground_point(height_at, p).y + maxf(sole, 0.0)
