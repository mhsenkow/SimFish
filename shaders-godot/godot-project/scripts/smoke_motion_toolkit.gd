extends SceneTree

# CREATURE_MOTION_700 Phase 1 toolkit (#41–#62, #74, #85–#92): the shared
# motion primitives behave as documented, independently of frame rate.

func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_motion_toolkit")
	_spring(t)
	_ease(t)
	_noise(t)
	_chain(t)
	_envelope(t)
	_composer(t)
	_personality_events_history(t)
	_lod_gaze_breath(t)
	_contact_surface(t)
	_metrics(t)
	quit(t.finish())


func _run_spring(s: MotionSpring, hz: float, seconds: float, target: float) -> float:
	var dt: float = 1.0 / hz
	for i in int(round(seconds * hz)):
		s.step(dt, target)
	return s.y


func _spring(t: TestSupport.Suite) -> void:
	var crit := MotionSpring.new(2.0, 1.0, 0.0)
	var peak: float = 0.0
	for i in 240:
		peak = maxf(peak, crit.step(1.0 / 60.0, 1.0))
	t.check(peak <= 1.001, "critically damped spring doesn't overshoot")
	t.approx(crit.y, 1.0, "critically damped spring settles on the target", 0.01)
	var ring := MotionSpring.new(2.0, 0.3, 0.0)
	var over: float = 0.0
	for i in 240:
		over = maxf(over, ring.step(1.0 / 60.0, 1.0))
	t.check(over > 1.2, "underdamped spring overshoots (follow-through)")
	var at30: float = _run_spring(MotionSpring.new(2.0, 0.6, 0.0), 30.0, 0.5, 1.0)
	var at60: float = _run_spring(MotionSpring.new(2.0, 0.6, 0.0), 60.0, 0.5, 1.0)
	var at120: float = _run_spring(MotionSpring.new(2.0, 0.6, 0.0), 120.0, 0.5, 1.0)
	t.approx(at30, at120, "spring is frame-rate independent at 30 vs 120 Hz", 0.05)
	t.approx(at60, at120, "spring is frame-rate independent at 60 vs 120 Hz", 0.02)
	var ant := MotionSpring.new(3.0, 0.8, -0.5)
	var dip: float = 0.0
	for i in 30:
		dip = minf(dip, ant.step(1.0 / 60.0, 1.0))
	t.check(dip < -0.01, "negative response anticipates (moves the wrong way first)")
	var big := MotionSpring.new(6.0, 0.4, 0.0)
	big.step(0.5, 1.0)
	big.step(0.5, -1.0)
	t.check(is_finite(big.y) and absf(big.y) < 10.0, "a huge dt stays stable")
	var ang := MotionSpring.new(2.0, 1.0, 0.0, PI - 0.1)
	for i in 120:
		ang.step_angle(1.0 / 60.0, -PI + 0.1)
	t.approx(wrapf(ang.y, -PI, PI), -PI + 0.1, "angle spring crosses ±π the short way", 0.02)
	t.check(absf(ang.y) > 3.0, "angle spring did not swing through zero")
	t.check(MotionSpring.for_tissue("veil") != null, "tissue preset builds a spring")
	var v := MotionSpring.Spring3.new(2.0, 1.0, 0.0)
	for i in 240:
		v.step(1.0 / 60.0, Vector3(1, 2, 3))
	t.check(v.value().distance_to(Vector3(1, 2, 3)) < 0.02, "Vector3 spring settles")


func _ease(t: TestSupport.Suite) -> void:
	var curves: Dictionary = {
		"smooth": MotionEase.smooth, "smoother": MotionEase.smoother,
		"sine_in_out": MotionEase.sine_in_out, "expo_out": MotionEase.expo_out,
		"back_out": MotionEase.back_out, "anticipate": MotionEase.anticipate,
	}
	for curve in curves:
		var fn: Callable = curves[curve]
		t.approx(float(fn.call(0.0)), 0.0, "%s starts at 0" % curve, 1e-4)
		t.approx(float(fn.call(1.0)), 1.0, "%s ends at 1" % curve, 1e-4)
	t.check(MotionEase.back_out(0.6) > 1.0, "back_out overshoots")
	t.check(MotionEase.anticipate(0.3) < 0.0, "anticipate pulls back first")
	t.approx(MotionEase.burst(0.15, 0.15), 1.0, "burst peaks at its peak", 1e-4)
	t.check(MotionEase.burst(0.6) < 0.2, "burst releases like drag")
	var a30: float = 0.0
	for i in 30:
		a30 = MotionEase.damp(a30, 1.0, 3.0, 1.0 / 30.0)
	var a120: float = 0.0
	for i in 120:
		a120 = MotionEase.damp(a120, 1.0, 3.0, 1.0 / 120.0)
	t.approx(a30, a120, "damp() is frame-rate independent", 1e-4)
	var lam: float = MotionEase.lambda_for_lerp_rate(6.0)
	t.approx(MotionEase.damp(0.0, 1.0, lam, 1.0 / 60.0), 0.1, "lambda_for_lerp_rate matches lerp(dt*k) at 60 Hz", 1e-4)
	t.approx(MotionEase.damp_angle(PI - 0.1, -PI + 0.1, 1000.0, 1.0), PI + 0.1,
		"damp_angle goes the short way", 1e-3)


func _noise(t: TestSupport.Suite) -> void:
	var same: bool = is_equal_approx(MotionNoise.value1(7, 3.3), MotionNoise.value1(7, 3.3))
	t.check(same, "noise is deterministic")
	var lo: float = 9.0
	var hi: float = -9.0
	var max_step: float = 0.0
	var prev: float = MotionNoise.fbm1(11, 0.0)
	for i in range(1, 2000):
		var v: float = MotionNoise.fbm1(11, float(i) * 0.01)
		lo = minf(lo, v)
		hi = maxf(hi, v)
		max_step = maxf(max_step, absf(v - prev))
		prev = v
	t.check(lo >= -1.0 and hi <= 1.0, "fbm stays in [-1, 1]")
	t.check(hi - lo > 0.5, "fbm actually varies")
	t.check(max_step < 0.12, "noise is smooth between close samples")
	t.check(absf(MotionNoise.value1(1, 2.5) - MotionNoise.value1(2, 2.5)) > 1e-4, "seeds differ")


func _chain(t: TestSupport.Suite) -> void:
	var c := MotionChain.new(3, "fin", 0.8)
	var root_angles := PackedFloat32Array()
	var tip := PackedFloat32Array()
	var dt: float = 1.0 / 60.0
	for i in 600:
		var r: float = sin(float(i) * dt * TAU * 1.0) * 0.4
		c.step(dt, r)
		root_angles.append(r)
		tip.append(c.tip_angle())
	var lag: float = MotionMetrics.phase_lag(root_angles.slice(240), tip.slice(240), dt, 1.0)
	t.in_range(lag, 0.05, PI, "chain tip lags the root (travelling follow-through)")
	for i in 600:
		c.step(dt, 0.0)
	t.check(absf(c.tip_angle()) < 0.01, "chain settles when the root stops")
	t.equals(c.relative().size(), 3, "chain reports one angle per link")


func _envelope(t: TestSupport.Suite) -> void:
	var e := MotionEnvelope.from_frames(6, 4, 24, 12, 60.0)
	e.trigger()
	t.equals(e.stage, MotionEnvelope.Stage.WINDUP, "trigger starts with the wind-up")
	var seen_neg: bool = false
	var peak: float = -9.0
	var stages: Array = []
	for i in 60:
		e.step(1.0 / 60.0)
		if not stages.has(e.stage):
			stages.append(e.stage)
		var v: float = e.value()
		seen_neg = seen_neg or v < -0.05
		peak = maxf(peak, v)
	t.check(seen_neg, "the wind-up coils below zero")
	t.check(peak > 0.95, "the action reaches full drive")
	t.check(stages.has(MotionEnvelope.Stage.FOLLOW) and stages.has(MotionEnvelope.Stage.SETTLE),
		"follow-through and settle both run")
	t.equals(e.stage, MotionEnvelope.Stage.IDLE, "the envelope ends idle after its 46 frames")
	e.trigger(true)
	t.equals(e.stage, MotionEnvelope.Stage.ACTION, "an urgent trigger skips the wind-up")
	var h := MotionEnvelope.Hysteresis.new(0.6, 0.4, 0.3)
	var flips: int = 0
	var last: bool = false
	for i in 120:
		var x: float = 0.5 + 0.08 * sin(float(i) * 0.9)
		var on: bool = h.step(1.0 / 60.0, x)
		if on != last:
			flips += 1
		last = on
	t.equals(flips, 0, "hysteresis doesn't flicker between its thresholds")
	var h2 := MotionEnvelope.Hysteresis.new(0.6, 0.4, 0.0)
	t.check(h2.step(0.1, 0.7) and not h2.step(0.1, 0.3), "hysteresis still switches on a real change")


func _composer(t: TestSupport.Suite) -> void:
	var host := Node3D.new()
	var n := Node3D.new()
	host.add_child(n)
	var comp := MotionPoseComposer.new()
	comp.check_foreign = true
	comp.begin_frame()
	comp.add(n, "rotation:z", 0.2)
	comp.add(n, "rotation:z", 0.1)
	comp.set_base(n, "scale", Vector3(1.0, 1.75, 0.85))
	comp.mul(n, "scale", Vector3(1.1, 1.0, 1.0))
	comp.apply()
	t.approx(n.rotation.z, 0.3, "two layers on one channel both survive")
	t.check(n.scale.is_equal_approx(Vector3(1.1, 1.75, 0.85)), "a multiplier composes onto the base")
	n.rotation.z = 0.9
	comp.begin_frame()
	t.check(comp.foreign_writes.size() == 1, "a write that bypasses the composer is reported")
	comp.add(n, "rotation:z", 0.05)
	comp.apply()
	t.approx(n.rotation.z, 0.05, "layers clear every frame")
	t.equals(comp.channel_count(), 2, "one channel per node property")
	host.free()


func _personality_events_history(t: TestSupport.Suite) -> void:
	var p1 := MotionPersonality.from_seed(42)
	var p2 := MotionPersonality.from_seed(42)
	t.approx(p1.tempo, p2.tempo, "personality is seeded")
	t.in_range(p1.laterality, -1.0, 1.0, "laterality is bounded")
	var back := MotionPersonality.from_dict(p1.to_dict())
	t.approx(back.boldness, p1.boldness, "personality round-trips through save data")
	MotionEvents.clear()
	var got: Array = []
	var cb := func(ev: Dictionary) -> void: got.append(ev["kind"])
	MotionEvents.subscribe(&"strike", cb)
	MotionEvents.emit(&"strike", null, Vector3.ZERO, 0.8)
	MotionEvents.emit(&"gulp", null, Vector3.ZERO)
	t.equals(got.size(), 1, "subscribers hear only their kind")
	t.equals(MotionEvents.recent(&"gulp").size(), 1, "recent events are kept for debugging")
	MotionEvents.clear()
	var h := MotionPoseHistory.new(4)
	for i in 6:
		h.push(float(i), Vector3(i, 0, 0), Vector3.ZERO, float(i), 0.0)
	t.equals(h.size(), 4, "history keeps its capacity")
	t.approx(h.ordered_speeds()[0], 2.0, "history drops the oldest sample first")
	t.approx(h.ordered_speeds()[3], 5.0, "history keeps samples in time order")


func _lod_gaze_breath(t: TestSupport.Suite) -> void:
	t.equals(MotionLod.tier_for(3.0, false, true), MotionLod.Tier.OFFSCREEN, "offscreen wins over hero")
	t.equals(MotionLod.tier_for(20.0, true, true), MotionLod.Tier.HERO, "hero ignores distance")
	t.equals(MotionLod.tier_for(20.0, true, false), MotionLod.Tier.FAR, "distant creatures are far")
	t.check(MotionLod.has(MotionLod.Tier.HERO, "face") and not MotionLod.has(MotionLod.Tier.FAR, "chains"),
		"tiers declare their features")
	var g: float = MotionLod.legibility_gain(0.01, 45.0, 2.0)
	t.in_range(g, 1.0, MotionLod.EXAGGERATION_CAP, "legibility gain is capped")
	t.approx(MotionLod.legibility_gain(1.0, 45.0, 2.0), 1.0, "big motion gets no gain")
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 10.0
	t.approx(MotionLod.px_per_unit(cam, Vector3.ZERO, 500.0), 50.0, "orthographic pixels per unit")
	cam.free()
	var gaze := MotionGaze.new(3)
	gaze.look_at_point(&"food", Vector3(1.0, 0.0, -2.0), 2.0)
	for i in 20:
		gaze.step(1.0 / 60.0, Transform3D.IDENTITY, 1.0)
	t.check(gaze.eye_yaw() < -0.2, "eyes turn toward a target on the right")
	t.check(absf(gaze.head_yaw()) <= MotionGaze.HEAD_LEAD_MAX + 1e-4, "the head leads only a little")
	t.check(not gaze.look_at_point(&"idle", Vector3.ZERO), "an idle glance can't steal a food target")
	t.check(gaze.look_at_point(&"threat", Vector3(-1, 0, -1)), "a threat takes over")
	var calm := MotionBreath.new()
	var gasp := MotionBreath.new()
	for i in 300:
		calm.step(1.0 / 60.0, 1.0, 0.0)
		gasp.step(1.0 / 60.0, 0.2, 0.8, 0.5)
	t.check(gasp.rate_hz > calm.rate_hz * 1.6, "low oxygen and exertion speed breathing")
	t.check(gasp.depth > calm.depth, "a gasping fish breathes deeper")
	t.approx(calm.operculum() / maxf(calm.depth, 1e-4) + calm.mouth() / maxf(calm.depth, 1e-4), 1.0,
		"mouth and opercula pump in anti-phase", 1e-3)


func _contact_surface(t: TestSupport.Suite) -> void:
	var flat := func(_x: float, _z: float) -> float: return 0.5
	var slope := func(x: float, _z: float) -> float: return x * 0.5
	t.check(MotionContact.ground_normal(flat, Vector3.ZERO).is_equal_approx(Vector3.UP), "flat ground faces up")
	var n: Vector3 = MotionContact.ground_normal(slope, Vector3.ZERO)
	t.check(n.x < -0.3 and n.y > 0.8, "a rising slope tilts the normal back")
	t.approx(MotionContact.ground_point(flat, Vector3(1, 9, 1)).y, 0.5, "ground point drops onto the height field")
	var sw: float = MotionContact.swing_to_reach(Vector3.ZERO, Vector3.DOWN, Vector3.RIGHT,
		Vector3(0, -1, 0.5), 1.0)
	var aimed: Vector3 = Vector3.DOWN.rotated(Vector3.RIGHT, sw)
	t.check(aimed.distance_to(Vector3(0, -1, 0.5).normalized()) < 1e-3, "a limb swings onto its foothold")
	t.approx(absf(MotionContact.swing_to_reach(Vector3.ZERO, Vector3.DOWN, Vector3.RIGHT,
		Vector3(0, -1, 9), 0.6)), 0.6, "an out-of-reach foothold clamps the swing")
	var roll := MotionSurfaceTransition.new(Vector3.UP, Vector3.BACK, Vector3.ZERO, 0.05, 1.0)
	t.check(roll.up_at(0.0).is_equal_approx(Vector3.UP), "the roll starts on the old surface")
	t.check(roll.up_at(1.0).distance_to(Vector3.BACK) < 1e-4, "the roll ends on the new surface")
	t.check(absf(roll.up_at(0.5).angle_to(Vector3.UP) - PI * 0.25) < 0.01, "halfway is halfway round the edge")
	for i in 30:
		roll.step(1.0 / 30.0)
	t.check(roll.done(), "the roll finishes in its duration")


func _metrics(t: TestSupport.Suite) -> void:
	var line := PackedVector3Array()
	for i in 60:
		line.append(Vector3(float(i) * 0.02, 0, 0))
	# Float32 positions leave a small numeric floor (well under a snap's).
	t.check(float(MotionMetrics.jerk(line, 1.0 / 60.0)["p95"]) < 1.0, "constant velocity has no jerk")
	var snap: PackedVector3Array = line.duplicate()
	snap[30] = snap[30] + Vector3(0, 0.2, 0)
	t.check(float(MotionMetrics.jerk(snap, 1.0 / 60.0)["p95"]) > 100.0, "a snap shows as jerk")
	var circle := PackedVector3Array()
	for i in 64:
		var ang: float = float(i) / 64.0 * TAU
		circle.append(Vector3(cos(ang) * 2.0, 0, sin(ang) * 2.0))
	var k: PackedFloat32Array = MotionMetrics.curvature(circle)
	t.approx(absf(MotionMetrics.mean(k)), 0.5, "curvature of a radius-2 circle is 0.5", 0.01)
	t.equals(MotionMetrics.curvature_breaks(circle, 0.05), 0, "a circle has no curvature breaks")
	var a := PackedFloat32Array()
	var b := PackedFloat32Array()
	var dt: float = 1.0 / 60.0
	for i in 240:
		var w: float = TAU * 2.0 * float(i) * dt
		a.append(sin(w))
		b.append(sin(w - PI * 0.5))
	t.approx(MotionMetrics.phase_lag(a, b, dt, 2.0), PI * 0.5, "phase lag of a quarter cycle", 0.02)
	t.approx(MotionMetrics.dominant_hz(a, dt), 2.0, "dominant frequency", 0.1)
	t.approx(MotionMetrics.correlation(a, a), 1.0, "a signal correlates with itself")
	var neg := PackedFloat32Array()
	for v in a:
		neg.append(-v)
	t.approx(MotionMetrics.correlation(a, neg), -1.0, "mirrored twins anti-correlate")
	t.approx(MotionMetrics.strouhal(2.0, 0.2, 1.0), 0.4, "Strouhal number")
	var yaws := PackedFloat32Array([0.0, 0.01, 0.02, 0.9, 0.91])
	t.equals(MotionMetrics.heading_kinks(yaws, dt, 5.0), 1, "one heading kink")
	t.equals(MotionMetrics.heading_kinks(yaws, dt, 5.0, PackedInt32Array([3])), 0, "declared actions are exempt")
	t.equals(MotionMetrics.snaps(yaws, 0.5), 1, "one channel snap")
	var p: Dictionary = MotionMetrics.percentiles(PackedFloat32Array([1, 2, 3, 4, 5]))
	t.approx(float(p[50]), 3.0, "median")
	var feet := PackedVector3Array([Vector3.ZERO, Vector3(0.01, 0, 0), Vector3(0.02, 0, 0)])
	t.approx(MotionMetrics.foot_slip(feet, [true, true, true], 0.2), 0.1, "foot slip as a fraction of stride")
