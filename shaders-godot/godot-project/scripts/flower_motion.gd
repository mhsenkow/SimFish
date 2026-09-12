extends RefCounted
class_name FlowerMotion

# Damped follow for a bloom riding its stem tip.
#
# THE PROBLEM. _stabilize_flower_against_lean() assigned the flower's whole
# transform from the live tip handle every frame, instantly. The anchor it
# reads is the sum of several independent things - stem lean, canopy
# layover, gust tilt, circumnutation, player brush, and a re-lay of the
# voxel batch whenever the plant grows. Each is individually gentle, but a
# rigid body snapped onto their sum reproduces every one of them at full
# amplitude with zero lag, which is what reads as a bloom thrashing around
# on the end of a calm stem.
#
# A real flower head has mass. It lags its stalk and settles. Damping the
# follow is the physically correct model, not a cosmetic smoothing pass:
# it low-passes the anchor so slow sway comes through and frame-scale
# jitter does not.

# Seconds for the bloom to close most of the way to its anchor. Long enough
# to swallow per-frame jitter, short enough that the bloom never visibly
# trails behind a stem the player is brushing.
const FOLLOW_TAU: float = 0.22
# Rotation settles faster than position, or a leaning stem shows a visible
# gap between the bloom and the tip it is supposed to be attached to.
const ROT_TAU: float = 0.14


# Frame-rate independent damping factor for a given time constant.
# Exponential, so the result is identical at 30 and 240 fps.
static func follow_factor(dt: float, tau: float) -> float:
	if dt <= 0.0:
		return 0.0
	if tau <= 0.0001:
		return 1.0
	return clampf(1.0 - exp(-dt / tau), 0.0, 1.0)


# Step a bloom transform toward its anchor. `snap` is for creation and for
# any path with no dt, where the bloom must land exactly on the tip rather
# than easing in from the origin.
static func step(current: Transform3D, target: Transform3D, dt: float,
		snap: bool = false) -> Transform3D:
	if snap or dt <= 0.0:
		return target
	var pos_f: float = follow_factor(dt, FOLLOW_TAU)
	var rot_f: float = follow_factor(dt, ROT_TAU)
	var cq: Quaternion = current.basis.get_rotation_quaternion()
	var tq: Quaternion = target.basis.get_rotation_quaternion()
	if not cq.is_finite() or not tq.is_finite():
		return target
	return Transform3D(
		Basis(cq.slerp(tq, rot_f)),
		current.origin.lerp(target.origin, pos_f))
