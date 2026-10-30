class_name MotionSpring
extends RefCounted

# Second-order dynamics for secondary motion (CREATURE_MOTION_700 #41/#42).
#
# One primitive covers three of the animation principles: follow-through and
# settle (damping ζ < 1 overshoots and rings down), slow in / slow out (the
# output can't jump, it accelerates toward the input), and anticipation
# (a negative response r swings the output the wrong way first).
#
#   f  natural frequency in Hz: how fast the output catches up
#   ζ  damping: 0 rings forever, < 1 overshoots, 1 is critical, > 1 is sluggish
#   r  initial response: 0 eases in, 1 tracks at once, > 1 overshoots on a
#      step, < 0 anticipates
#
# Semi-implicit Euler with the k2 stability clamp, so it stays stable for any
# dt (large hitches just lose fidelity, they don't explode). The same input
# sequence gives the same output at 30, 60 and 120 Hz within a small error,
# which smoke_motion_toolkit checks.

# Tissue presets [f, ζ, r]. Secondary parts pick one of these rather than
# inventing constants.
const TISSUE: Dictionary = {
	"fin": [4.0, 0.45, 0.0],
	"caudal": [5.0, 0.40, 0.0],
	"veil": [1.6, 0.30, 0.0],
	"barbel": [3.0, 0.50, 0.0],
	"antenna": [2.5, 0.35, 0.0],
	"tentacle": [1.2, 0.60, 0.0],
	"shell": [2.0, 0.70, 0.0],
	"body": [3.0, 0.60, 0.0],
	"bank": [1.8, 0.55, 0.0],
	"steer": [2.2, 1.00, 0.0],
	"anticipate": [3.0, 0.80, -0.5],
}

var k1: float = 0.0
var k2: float = 1.0
var k3: float = 0.0
var y: float = 0.0
var yd: float = 0.0
var _xp: float = 0.0


func _init(f: float = 2.0, zeta: float = 0.7, r: float = 0.0, x0: float = 0.0) -> void:
	configure(f, zeta, r)
	reset(x0)


static func for_tissue(tissue: String, x0: float = 0.0) -> MotionSpring:
	var p: Array = TISSUE.get(tissue, TISSUE["body"])
	return MotionSpring.new(float(p[0]), float(p[1]), float(p[2]), x0)


func configure(f: float, zeta: float, r: float) -> void:
	var w: float = TAU * maxf(f, 0.001)
	k1 = zeta / (PI * maxf(f, 0.001))
	k2 = 1.0 / (w * w)
	k3 = r * zeta / w


func reset(x0: float) -> void:
	y = x0
	yd = 0.0
	_xp = x0


# Advance toward input x. xd is the input's velocity; pass NAN to estimate it
# from the previous input (the usual case).
func step(dt: float, x: float, xd: float = NAN) -> float:
	if not (dt > 0.0) or not is_finite(x):
		return y
	if is_nan(xd):
		xd = (x - _xp) / dt
	_xp = x
	var k2_stable: float = maxf(k2, maxf(dt * dt * 0.5 + dt * k1 * 0.5, dt * k1))
	y += dt * yd
	yd += dt * (x + k3 * xd - y - k1 * yd) / k2_stable
	if not is_finite(y) or not is_finite(yd):
		reset(x)
	return y


# Angle variant: the input is unwrapped next to the current output first, so a
# target that crosses ±π doesn't send the spring the long way round.
func step_angle(dt: float, x: float) -> float:
	var near_x: float = y + wrapf(x - y, -PI, PI)
	if absf(near_x - _xp) > PI:
		_xp = near_x
	return step(dt, near_x)


# Vector3 variant, sharing one set of constants across three components.
class Spring3:
	extends RefCounted
	var x: MotionSpring
	var y: MotionSpring
	var z: MotionSpring

	func _init(f: float = 2.0, zeta: float = 0.7, r: float = 0.0, v0: Vector3 = Vector3.ZERO) -> void:
		x = MotionSpring.new(f, zeta, r, v0.x)
		y = MotionSpring.new(f, zeta, r, v0.y)
		z = MotionSpring.new(f, zeta, r, v0.z)

	func reset(v: Vector3) -> void:
		x.reset(v.x)
		y.reset(v.y)
		z.reset(v.z)

	func value() -> Vector3:
		return Vector3(x.y, y.y, z.y)

	func step(dt: float, v: Vector3) -> Vector3:
		return Vector3(x.step(dt, v.x), y.step(dt, v.y), z.step(dt, v.z))
