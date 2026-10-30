class_name MotionMetrics
extends RefCounted

# Numbers for "does this motion look right" (CREATURE_MOTION_700 #85–#92,
# #102, #119). Each answers one principle from recorded samples, so probes and
# smokes can check motion quality instead of only behaviour statistics:
#
#   jerk          slow in / slow out: spikes are snaps
#   heading_kinks arcs: frames that turn faster than the body can
#   curvature     arcs: discontinuities in the path's bend
#   phase_lag     follow-through: a travelling wave lags head to tail
#   strouhal      timing: tail beat matched to speed (0.2-0.4 in real fish)
#   correlation   solid drawing: twins (mirrored fins, lockstep neighbours)
#   snaps         any channel that jumps between frames
#   foot_slip     contact: feet sliding while planted
#   percentiles   distributions, because a right mean with no spread is robotic


static func percentiles(values: PackedFloat32Array, ps: Array = [10, 50, 90]) -> Dictionary:
	var out: Dictionary = {}
	if values.is_empty():
		for p in ps:
			out[int(p)] = 0.0
		return out
	var sorted: Array = Array(values)
	sorted.sort()
	for p in ps:
		var idx: float = clampf(float(p) / 100.0, 0.0, 1.0) * float(sorted.size() - 1)
		var lo: int = floori(idx)
		var hi: int = mini(lo + 1, sorted.size() - 1)
		out[int(p)] = lerpf(float(sorted[lo]), float(sorted[hi]), idx - float(lo))
	return out


static func mean(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var s: float = 0.0
	for v in values:
		s += v
	return s / float(values.size())


# Third derivative of position, sampled every dt. Returns mean and p95.
static func jerk(positions: PackedVector3Array, dt: float) -> Dictionary:
	var mags := PackedFloat32Array()
	if positions.size() < 4 or dt <= 0.0:
		return {"mean": 0.0, "p95": 0.0}
	var inv: float = 1.0 / (dt * dt * dt)
	for i in range(3, positions.size()):
		var j: Vector3 = positions[i] - positions[i - 1] * 3.0 + positions[i - 2] * 3.0 - positions[i - 3]
		mags.append(j.length() * inv)
	return {"mean": mean(mags), "p95": float(percentiles(mags, [95])[95])}


# Frames whose yaw rate exceeds cap (rad/s), ignoring the listed exempt frames
# (declared C-starts and startles).
static func heading_kinks(yaws: PackedFloat32Array, dt: float, cap: float,
		exempt: PackedInt32Array = PackedInt32Array()) -> int:
	var n: int = 0
	for i in range(1, yaws.size()):
		if exempt.has(i):
			continue
		var rate: float = absf(wrapf(yaws[i] - yaws[i - 1], -PI, PI)) / maxf(dt, 1e-6)
		if rate > cap:
			n += 1
	return n


# Signed curvature (1/units) of a path in the XZ plane at each interior point.
static func curvature(points: PackedVector3Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in range(1, points.size() - 1):
		var a := Vector2(points[i - 1].x, points[i - 1].z)
		var b := Vector2(points[i].x, points[i].z)
		var c := Vector2(points[i + 1].x, points[i + 1].z)
		var ab: float = a.distance_to(b)
		var bc: float = b.distance_to(c)
		var ac: float = a.distance_to(c)
		var denom: float = ab * bc * ac
		if denom < 1e-9:
			out.append(0.0)
			continue
		var cross: float = (b - a).cross(c - b)
		out.append(2.0 * cross / denom)
	return out


# Count of curvature jumps larger than limit between neighbouring samples:
# kinks in what should be a smooth arc.
static func curvature_breaks(points: PackedVector3Array, limit: float) -> int:
	var k: PackedFloat32Array = curvature(points)
	var n: int = 0
	for i in range(1, k.size()):
		if absf(k[i] - k[i - 1]) > limit:
			n += 1
	return n


# Phase lag (radians, 0..2π) of signal b behind signal a, both sampled every
# dt, at a known frequency hz. Projects each onto sin/cos at that frequency,
# which is robust to noise and to slowly changing amplitude.
static func phase_lag(a: PackedFloat32Array, b: PackedFloat32Array, dt: float, hz: float) -> float:
	var n: int = mini(a.size(), b.size())
	if n < 4 or hz <= 0.0:
		return 0.0
	var sa: float = 0.0
	var ca: float = 0.0
	var sb: float = 0.0
	var cb: float = 0.0
	for i in n:
		var w: float = TAU * hz * float(i) * dt
		sa += a[i] * sin(w)
		ca += a[i] * cos(w)
		sb += b[i] * sin(w)
		cb += b[i] * cos(w)
	return fposmod(atan2(ca, sa) - atan2(cb, sb), TAU)


# Dominant frequency (Hz) of a signal by counting upward zero crossings.
static func dominant_hz(x: PackedFloat32Array, dt: float) -> float:
	if x.size() < 3 or dt <= 0.0:
		return 0.0
	var m: float = mean(x)
	var crossings: int = 0
	for i in range(1, x.size()):
		if x[i - 1] - m < 0.0 and x[i] - m >= 0.0:
			crossings += 1
	return float(crossings) / (float(x.size() - 1) * dt)


# St = f·A/U, with A the peak-to-peak tail-tip excursion.
static func strouhal(hz: float, amplitude_pp: float, speed: float) -> float:
	return hz * amplitude_pp / maxf(speed, 1e-4)


static func correlation(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var n: int = mini(a.size(), b.size())
	if n < 2:
		return 0.0
	var ma: float = 0.0
	var mb: float = 0.0
	for i in n:
		ma += a[i]
		mb += b[i]
	ma /= float(n)
	mb /= float(n)
	var num: float = 0.0
	var da: float = 0.0
	var db: float = 0.0
	for i in n:
		num += (a[i] - ma) * (b[i] - mb)
		da += (a[i] - ma) * (a[i] - ma)
		db += (b[i] - mb) * (b[i] - mb)
	if da < 1e-12 or db < 1e-12:
		return 0.0
	return num / sqrt(da * db)


# Frames where a channel moved more than limit in one step.
static func snaps(values: PackedFloat32Array, limit: float, angular: bool = false) -> int:
	var n: int = 0
	for i in range(1, values.size()):
		var d: float = wrapf(values[i] - values[i - 1], -PI, PI) if angular else values[i] - values[i - 1]
		if absf(d) > limit:
			n += 1
	return n


# Distance a foot slides over the ground while planted, as a fraction of the
# stride. feet: tip world positions; planted: whether the foot is in stance.
static func foot_slip(feet: PackedVector3Array, planted: Array, stride: float) -> float:
	var slid: float = 0.0
	for i in range(1, mini(feet.size(), planted.size())):
		if bool(planted[i]) and bool(planted[i - 1]):
			var d: Vector3 = feet[i] - feet[i - 1]
			d.y = 0.0
			slid += d.length()
	return slid / maxf(stride, 1e-4)
