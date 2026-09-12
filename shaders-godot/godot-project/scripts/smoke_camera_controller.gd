extends SceneTree

# Pure-function golden tests for CameraController (ENGINEERING_EXCELLENCE #2 /
# OPUS_HANDOFF 0B). Fast — no world/autoload setup. Also force-compiles main.gd
# so the extraction's edits (delegating calls + re-exported consts) can't
# silently break the parse.


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	# Force-compile main.gd — a parse error from the 0B edits fails here.
	var main_script: Resource = load("res://scripts/main.gd")
	TestSupport.check(failed, main_script != null, "main.gd must still parse/compile")

	# --- Deadzone gate: orbit/pan/dolly only commit past DRAG_DEADZONE_PX (8px).
	# A release before that is a tap (feed/pick), not a drag. This is the rule.
	TestSupport.check(failed, not CameraController.drag_committed(7.9),
			"7.9px must NOT commit a drag (tap, not orbit)")
	TestSupport.check(failed, CameraController.drag_committed(8.0),
			"8.0px (== deadzone) commits a drag")
	TestSupport.check(failed, CameraController.drag_committed(8.1),
			"8.1px commits a drag")
	TestSupport.check(failed, CameraController.is_tap(4.0) and not CameraController.is_tap(20.0),
			"is_tap is the inverse of drag_committed across the deadzone")

	# --- Orbit: yaw free, pitch clamped to [MIN_PITCH, MAX_PITCH].
	var ob: Vector2 = CameraController.orbit(0.0, 0.0, Vector2(100.0, 0.0))
	TestSupport.check(failed, _approx(ob.x, -0.6) and _approx(ob.y, 0.0),
			"orbit yaw = -delta.x*SENSITIVITY; pitch unchanged on horizontal drag")
	var ob_dn: Vector2 = CameraController.orbit(0.0, 0.0, Vector2(0.0, 100000.0))
	TestSupport.check(failed, _approx(ob_dn.y, CameraController.MIN_PITCH),
			"orbit clamps pitch down to MIN_PITCH")
	var ob_up: Vector2 = CameraController.orbit(0.0, 0.0, Vector2(0.0, -100000.0))
	TestSupport.check(failed, _approx(ob_up.y, CameraController.MAX_PITCH),
			"orbit clamps pitch up to MAX_PITCH")

	# --- Dolly: radius scales with vertical drag, clamped to the orbit shell.
	TestSupport.check(failed, _approx(CameraController.dolly(20.0, 0.0), 20.0),
			"dolly with zero delta is identity")
	TestSupport.check(failed, _approx(CameraController.dolly(20.0, 1000.0), CameraController.MAX_RADIUS),
			"dolly out past MAX_RADIUS clamps")
	TestSupport.check(failed, _approx(CameraController.dolly(20.0, -1000.0), CameraController.MIN_RADIUS),
			"dolly in past MIN_RADIUS clamps")

	# --- Zoom: perspective (radius) + ortho (size) clamps.
	TestSupport.check(failed, _approx(CameraController.zoom_radius(20.0, 1.12), 22.4),
			"zoom_radius scales by factor")
	TestSupport.check(failed, _approx(CameraController.zoom_radius(8.0, 0.4), CameraController.MIN_RADIUS),
			"zoom_radius clamps to MIN_RADIUS")
	TestSupport.check(failed, _approx(CameraController.zoom_radius(40.0, 2.0), CameraController.MAX_RADIUS),
			"zoom_radius clamps to MAX_RADIUS")
	TestSupport.check(failed, _approx(CameraController.zoom_ortho(18.0, 1.12), 20.16),
			"zoom_ortho scales by factor")
	TestSupport.check(failed, _approx(CameraController.zoom_ortho(1.0, 0.5), CameraController.ORTHO_MIN_SIZE),
			"zoom_ortho clamps to ORTHO_MIN_SIZE")

	# ---- Zoom budget: one continuous curve, drained at a bounded rate -------
	# The old per-event classifier switched between three step formulas inside
	# a single trackpad flick (12% -> 4.7% -> 0.85% per event). Every input now
	# converts to log zoom on one curve.
	var precise: float = CameraController.scroll_log_zoom(0.2)
	var notch: float = CameraController.scroll_log_zoom(1.0)
	var hard: float = CameraController.scroll_log_zoom(3.0)
	TestSupport.check(failed, precise > 0.0 and notch > precise and hard > notch,
			"scroll response is monotonic in event magnitude")
	TestSupport.check(failed, _approx(notch, CameraController.WHEEL_NOTCH_LOG),
			"a factor-1 wheel notch is exactly one reference step")
	# Sub-linear: a 15x bigger event must not be 15x the zoom.
	TestSupport.check(failed, hard < precise * 15.0,
			"scroll response is sub-linear, so a hard spin cannot teleport")
	# No branch to fall off: neighbouring magnitudes stay close together.
	var a: float = CameraController.scroll_log_zoom(0.84)
	var b: float = CameraController.scroll_log_zoom(0.86)
	TestSupport.check(failed, absf(a - b) < 0.005,
			"no discontinuity across the old 0.85 branch point")

	# Pinch: magnify > 1 = fingers apart = zoom in = negative log zoom.
	TestSupport.check(failed, CameraController.magnify_log_zoom(1.05) < 0.0,
			"magnify>1 zooms in")
	TestSupport.check(failed, CameraController.magnify_log_zoom(0.95) > 0.0,
			"magnify<1 zooms out")

	# The budget must be bounded, drain toward zero, and never outrun the cap.
	var big: float = CameraController.clamp_zoom_budget(99.0)
	TestSupport.check(failed, _approx(big, CameraController.ZOOM_BUDGET_MAX),
			"queued zoom is capped so a hard spin cannot bank a huge glide")
	var d1: Array = CameraController.drain_zoom_budget(1.0, 1.0 / 60.0)
	TestSupport.check(failed, float(d1[0]) > 0.0 and float(d1[1]) < 1.0,
			"draining consumes part of the budget")
	TestSupport.check(failed, float(d1[0]) <= CameraController.ZOOM_RATE_MAX / 60.0 + 1e-6,
			"per-frame zoom respects the rate cap")
	# A dense event stream (240 fps worth of drains) must not exceed the cap.
	var budget: float = CameraController.ZOOM_BUDGET_MAX
	var total: float = 0.0
	for _i in 240:
		var step: Array = CameraController.drain_zoom_budget(budget, 1.0 / 240.0)
		total += float(step[0])
		budget = float(step[1])
	TestSupport.check(failed, total <= CameraController.ZOOM_RATE_MAX + 1e-3,
			"one second of draining stays under the per-second cap")
	# And it must actually converge, not hang around forever.
	TestSupport.check(failed, absf(budget) < CameraController.ZOOM_BUDGET_MAX * 0.05,
			"the budget drains to near zero within a second")
	# Frame rate must not change how far a given budget travels.
	var slow: float = 0.0
	var sb: float = 1.0
	for _i in 30:
		var st: Array = CameraController.drain_zoom_budget(sb, 1.0 / 30.0)
		slow += float(st[0]); sb = float(st[1])
	var fast: float = 0.0
	var fb: float = 1.0
	for _i in 120:
		var st2: Array = CameraController.drain_zoom_budget(fb, 1.0 / 120.0)
		fast += float(st2[0]); fb = float(st2[1])
	TestSupport.check(failed, absf(slow - fast) < 0.06,
			"same travel at 30 and 120 fps (%.3f vs %.3f)" % [slow, fast])
	TestSupport.check(failed, _approx(float(CameraController.drain_zoom_budget(0.0, 0.016)[0]), 0.0),
			"an empty budget applies nothing")

	# --- Pan: drag right pushes the scene right (target moves left).
	var pt: Vector3 = CameraController.pan_target(
			Vector3.ZERO, Vector2(10.0, 0.0), Vector3.RIGHT, Vector3.UP, 10.0)
	# pan_sc = 0.012 * 10 = 0.12 ; x -= 1*(10*0.12) = -1.2
	TestSupport.check(failed, pt.is_equal_approx(Vector3(-1.2, 0.0, 0.0)),
			"pan_target slides target left on rightward drag")

	# --- Target clamp: the single convergence box.
	var ct: Vector3 = CameraController.clamp_target(Vector3(100.0, 100.0, -100.0))
	TestSupport.check(failed, ct.is_equal_approx(Vector3(20.0, 12.0, -20.0)),
			"clamp_target clamps to the convergence box")

	# --- Eye position: spherical orbit coords (+pitch = eye above target).
	var eye_flat: Vector3 = CameraController.eye_position(Vector3.ZERO, 0.0, 0.0, 10.0)
	TestSupport.check(failed, eye_flat.is_equal_approx(Vector3(0.0, 0.0, 10.0)),
			"eye at yaw=pitch=0 sits +Z of target by radius")
	var eye_top: Vector3 = CameraController.eye_position(Vector3(0, 3, 0), 0.0, PI * 0.5, 10.0)
	TestSupport.check(failed, eye_top.is_equal_approx(Vector3(0.0, 13.0, 0.0)),
			"eye at pitch=90deg sits directly above target")

	# --- Auto-orbit: linear yaw drift.
	TestSupport.check(failed, _approx(CameraController.auto_orbit_yaw(1.0, 0.08, 0.5), 1.04),
			"auto_orbit_yaw advances yaw by speed*dt")

	quit(TestSupport.report("smoke_camera_controller", failed))


func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.0005
