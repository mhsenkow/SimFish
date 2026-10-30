class_name MotionEase
extends RefCounted

# Easing curves and frame-rate-independent smoothing (CREATURE_MOTION_700
# #46–#48). New motion code uses these instead of hand-written polynomials,
# and damp() instead of lerp(a, b, dt * k): that form overshoots once
# dt * k > 1 and its result depends on the frame rate.


static func smooth(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func smoother(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


static func sine_in_out(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 0.5 - 0.5 * cos(PI * t)


# Drag-shaped decay: fast at first, then a long tail, the way a fish coasts.
# k sets how much of the change happens early (k = 5: about 99% by t = 1).
static func expo_out(t: float, k: float = 5.0) -> float:
	t = clampf(t, 0.0, 1.0)
	return (1.0 - exp(-k * t)) / (1.0 - exp(-k))


static func expo_in(t: float, k: float = 5.0) -> float:
	return 1.0 - expo_out(1.0 - t, k)


# Overshoot then settle at 1. s around 1.7 overshoots about 10%.
static func back_out(t: float, s: float = 1.70158) -> float:
	t = clampf(t, 0.0, 1.0) - 1.0
	return t * t * ((s + 1.0) * t + s) + 1.0


# Pull back before going: dips to about -s * 0.1 early, then rises to 1.
static func anticipate(t: float, s: float = 1.70158) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * ((s + 1.0) * t - s)


# A quick attack and a drag-shaped release, peaking at `peak` (0..1). The
# shape of an explosive action: a dart, a strike, a tail flip.
static func burst(t: float, peak: float = 0.15, k: float = 4.0) -> float:
	t = clampf(t, 0.0, 1.0)
	if t < peak:
		return smooth(t / maxf(peak, 1e-4))
	return 1.0 - expo_out((t - peak) / maxf(1.0 - peak, 1e-4), k)


# Frame-rate-independent exponential approach: after 1/lambda seconds the
# value has covered about 63% of the gap, at any frame rate.
static func damp(a: float, b: float, lambda: float, dt: float) -> float:
	return lerpf(a, b, 1.0 - exp(-maxf(lambda, 0.0) * maxf(dt, 0.0)))


static func damp_v3(a: Vector3, b: Vector3, lambda: float, dt: float) -> Vector3:
	return a.lerp(b, 1.0 - exp(-maxf(lambda, 0.0) * maxf(dt, 0.0)))


static func damp_angle(a: float, b: float, lambda: float, dt: float) -> float:
	return a + wrapf(b - a, -PI, PI) * (1.0 - exp(-maxf(lambda, 0.0) * maxf(dt, 0.0)))


# The lambda that matches an old lerp(a, b, dt * k) at a reference frame rate,
# for converting legacy smoothing without changing its look at that rate.
static func lambda_for_lerp_rate(k: float, ref_hz: float = 60.0) -> float:
	var per_frame: float = clampf(k / maxf(ref_hz, 1.0), 0.0, 0.999)
	return -log(1.0 - per_frame) * ref_hz
