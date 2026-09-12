extends SceneTree

# Pond-mode computation carved out of main.gd (BROAD_DIRECTIONS #7).
#
# None of this was testable before: it lived inside methods on the main
# scene node, so reaching it meant booting the whole game. That is the
# actual argument for the carve — the line count barely moved, the
# reachability did.


class FakeFish:
	extends Node3D
	var _dying: bool = false


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	# --- Conduct stroke: min-step gating ---
	var pts: Array = []
	TestSupport.check(failed, PondMode.record_conduct_point(pts, Vector3.ZERO),
		"the first point is always recorded")
	TestSupport.check(failed, pts.size() == 1, "first point must be appended")
	# Too close — must be rejected, and must not grow the buffer.
	var tiny := Vector3(PondMode.CONDUCT_MIN_STEP * 0.5, 0.0, 0.0)
	TestSupport.check(failed, not PondMode.record_conduct_point(pts, tiny),
		"a point inside CONDUCT_MIN_STEP must be rejected")
	TestSupport.check(failed, pts.size() == 1, "a rejected point must not be appended")
	# Far enough — recorded.
	var far := Vector3(PondMode.CONDUCT_MIN_STEP * 2.0, 0.0, 0.0)
	TestSupport.check(failed, PondMode.record_conduct_point(pts, far),
		"a point beyond CONDUCT_MIN_STEP must be recorded")
	TestSupport.check(failed, pts.size() == 2, "an accepted point must be appended")
	# Just past the threshold is recorded, so a steady drag is not dropped.
	# NB: not tested AT the threshold — distance_to(0.35) returns 0.34999997
	# in 32-bit float, so an exact-boundary assertion tests float precision
	# rather than the rule. A sub-micron difference in stroke sampling is
	# irrelevant to the gesture.
	var exact: Array = [Vector3.ZERO]
	TestSupport.check(failed, PondMode.record_conduct_point(
			exact, Vector3(PondMode.CONDUCT_MIN_STEP + 0.001, 0.0, 0.0)),
		"a point just past CONDUCT_MIN_STEP must be recorded")

	# --- Conduct stroke: gesture threshold ---
	TestSupport.check(failed, not PondMode.conduct_stroke_is_gesture([]),
		"an empty stroke is not a gesture")
	TestSupport.check(failed, not PondMode.conduct_stroke_is_gesture(
			[Vector3.ZERO, Vector3.ONE]),
		"a 2-point stroke is a stray click, not a gesture")
	TestSupport.check(failed, PondMode.conduct_stroke_is_gesture(
			[Vector3.ZERO, Vector3.ONE, Vector3(2, 2, 2)]),
		"a 3-point stroke is a gesture")

	# --- School centroid ---
	var fallback := Vector2(9.0, 9.0)
	TestSupport.check(failed, PondMode.school_centroid_xz([], fallback) == fallback,
		"an empty school must fall back to the camera target")
	var parent := Node3D.new()
	root.add_child(parent)
	var a := FakeFish.new()
	var b := FakeFish.new()
	parent.add_child(a)
	parent.add_child(b)
	a.global_position = Vector3(-2.0, 5.0, 4.0)
	b.global_position = Vector3(2.0, 1.0, 0.0)
	var cen: Vector2 = PondMode.school_centroid_xz([a, b], fallback)
	TestSupport.check(failed, cen.is_equal_approx(Vector2(0.0, 2.0)),
		"centroid must average XZ only, got %s" % cen)

	# A dying fish must not drag the camera — this is the bug the guard in
	# the original loop existed to prevent.
	b._dying = true
	var cen_alive: Vector2 = PondMode.school_centroid_xz([a, b], fallback)
	TestSupport.check(failed, cen_alive.is_equal_approx(Vector2(-2.0, 4.0)),
		"a dying fish must be excluded from the centroid, got %s" % cen_alive)
	b._dying = false

	# All dying -> fallback, not a divide-by-zero or a (0,0) snap.
	a._dying = true
	b._dying = true
	TestSupport.check(failed, PondMode.school_centroid_xz([a, b], fallback) == fallback,
		"an all-dying school must fall back, not collapse to origin")
	a._dying = false
	b._dying = false

	# A null / freed entry must not crash the loop.
	TestSupport.check(failed, PondMode.school_centroid_xz([null, a], fallback)
			.is_equal_approx(Vector2(-2.0, 4.0)),
		"a null entry must be skipped, not crash")

	# --- Framing keeps Y, pulls XZ ---
	var cur := Vector3(0.0, 3.0, 0.0)
	var framed: Vector3 = PondMode.framing_target(cur, Vector2(10.0, 10.0), 0.5)
	TestSupport.check(failed, is_equal_approx(framed.y, 3.0),
		"framing must not change camera height")
	TestSupport.check(failed, is_equal_approx(framed.x, 5.0) and is_equal_approx(framed.z, 5.0),
		"framing must lerp XZ toward the centroid, got %s" % framed)
	# weight 0 is a no-op; weight 1 snaps.
	TestSupport.check(failed, PondMode.framing_target(cur, Vector2(10, 10), 0.0)
			.is_equal_approx(cur),
		"weight 0 must leave the target untouched")
	TestSupport.check(failed, PondMode.framing_target(cur, Vector2(10, 10), 1.0)
			.is_equal_approx(Vector3(10.0, 3.0, 10.0)),
		"weight 1 must snap to the centroid")

	# --- Startle: range + falloff ---
	var hit := Vector3.ZERO
	TestSupport.check(failed, PondMode.is_in_startle_range(Vector3(0.5, 0.0, 0.0), hit),
		"a nearby fish must be in startle range")
	TestSupport.check(failed, not PondMode.is_in_startle_range(Vector3(50.0, 0.0, 0.0), hit),
		"a distant fish must be out of startle range")
	# Depth must not matter — the tap is on the surface.
	TestSupport.check(failed, PondMode.is_in_startle_range(Vector3(0.5, 99.0, 0.0), hit),
		"startle range is XZ-only; depth must be ignored")

	TestSupport.check(failed, is_equal_approx(PondMode.startle_proximity(hit, hit), 1.0),
		"a point-blank tap must be full proximity")
	TestSupport.check(failed, is_equal_approx(
			PondMode.startle_proximity(Vector3(50.0, 0.0, 0.0), hit), 0.0),
		"an out-of-range fish must have zero proximity")
	var near_p: float = PondMode.startle_proximity(Vector3(0.5, 0.0, 0.0), hit)
	var far_p: float = PondMode.startle_proximity(Vector3(3.0, 0.0, 0.0), hit)
	TestSupport.check(failed, near_p > far_p,
		"proximity must fall off with distance (%.3f vs %.3f)" % [near_p, far_p])
	# Proximity is always a usable 0..1 weight, even just inside the radius.
	for d in [0.0, 0.5, 1.0, 2.0, 3.0, 3.4]:
		var pr: float = PondMode.startle_proximity(Vector3(d, 0.0, 0.0), hit)
		TestSupport.check(failed, pr >= 0.0 and pr <= 1.0,
			"proximity at d=%.1f must be within 0..1, got %.3f" % [d, pr])

	# --- Startle: duration + curiosity stay bounded ---
	TestSupport.check(failed, is_equal_approx(
			PondMode.startle_duration(1.0), PondMode.STARTLE_MAX_S),
		"full proximity must give the maximum startle")
	TestSupport.check(failed, is_equal_approx(
			PondMode.startle_duration(0.0), PondMode.STARTLE_MIN_S),
		"zero proximity must give the minimum startle")
	# Out-of-band proximity must clamp, not extrapolate into a huge startle.
	TestSupport.check(failed, PondMode.startle_duration(5.0) <= PondMode.STARTLE_MAX_S,
		"startle duration must clamp above 1.0 proximity")
	TestSupport.check(failed, PondMode.startle_duration(-5.0) >= PondMode.STARTLE_MIN_S,
		"startle duration must clamp below 0.0 proximity")

	TestSupport.check(failed, PondMode.startle_curiosity(0.5, 1.0) > 0.5,
		"a startle must raise curiosity")
	TestSupport.check(failed, PondMode.startle_curiosity(1.0, 1.0) <= 1.0,
		"curiosity must never exceed 1.0")
	TestSupport.check(failed, PondMode.startle_curiosity(0.0, 0.0) >= 0.0,
		"curiosity must never go negative")
	TestSupport.check(failed, is_equal_approx(PondMode.startle_curiosity(0.5, 0.0), 0.5),
		"zero proximity must not change curiosity")

	# --- Vignette: floors on both sides, no ratchet ---
	TestSupport.check(failed, PondMode.vignette_strength(0.0, true) >= PondMode.VIGNETTE_ON_MIN,
		"entering pond mode must raise the vignette to its floor")
	TestSupport.check(failed, is_equal_approx(PondMode.vignette_strength(0.9, true), 0.9),
		"entering must not LOWER an already-strong vignette")
	TestSupport.check(failed, PondMode.vignette_strength(1.0, false) < 1.0,
		"leaving pond mode must decay the vignette")
	TestSupport.check(failed, PondMode.vignette_strength(0.0, false) >= PondMode.VIGNETTE_OFF_FLOOR,
		"leaving must not drop the vignette below its floor")
	# Repeated toggling must neither ratchet up nor collapse.
	var v: float = 0.3
	for _i in 30:
		v = PondMode.vignette_strength(v, true)
		v = PondMode.vignette_strength(v, false)
	TestSupport.check(failed, v >= PondMode.VIGNETTE_OFF_FLOOR and v <= 1.0,
		"toggling pond mode repeatedly must stay bounded, got %.3f" % v)

	quit(TestSupport.report("smoke_pond_mode", failed))
