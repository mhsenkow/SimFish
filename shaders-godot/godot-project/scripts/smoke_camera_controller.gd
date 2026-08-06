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
	_assert(failed, main_script != null, "main.gd must still parse/compile")

	# --- Deadzone gate: orbit/pan/dolly only commit past DRAG_DEADZONE_PX (8px).
	# A release before that is a tap (feed/pick), not a drag. This is the rule.
	_assert(failed, not CameraController.drag_committed(7.9),
			"7.9px must NOT commit a drag (tap, not orbit)")
	_assert(failed, CameraController.drag_committed(8.0),
			"8.0px (== deadzone) commits a drag")
	_assert(failed, CameraController.drag_committed(8.1),
			"8.1px commits a drag")
	_assert(failed, CameraController.is_tap(4.0) and not CameraController.is_tap(20.0),
			"is_tap is the inverse of drag_committed across the deadzone")

	# --- Orbit: yaw free, pitch clamped to [MIN_PITCH, MAX_PITCH].
	var ob: Vector2 = CameraController.orbit(0.0, 0.0, Vector2(100.0, 0.0))
	_assert(failed, _approx(ob.x, -0.6) and _approx(ob.y, 0.0),
			"orbit yaw = -delta.x*SENSITIVITY; pitch unchanged on horizontal drag")
	var ob_dn: Vector2 = CameraController.orbit(0.0, 0.0, Vector2(0.0, 100000.0))
	_assert(failed, _approx(ob_dn.y, CameraController.MIN_PITCH),
			"orbit clamps pitch down to MIN_PITCH")
	var ob_up: Vector2 = CameraController.orbit(0.0, 0.0, Vector2(0.0, -100000.0))
	_assert(failed, _approx(ob_up.y, CameraController.MAX_PITCH),
			"orbit clamps pitch up to MAX_PITCH")

	# --- Dolly: radius scales with vertical drag, clamped to the orbit shell.
	_assert(failed, _approx(CameraController.dolly(20.0, 0.0), 20.0),
			"dolly with zero delta is identity")
	_assert(failed, _approx(CameraController.dolly(20.0, 1000.0), CameraController.MAX_RADIUS),
			"dolly out past MAX_RADIUS clamps")
	_assert(failed, _approx(CameraController.dolly(20.0, -1000.0), CameraController.MIN_RADIUS),
			"dolly in past MIN_RADIUS clamps")

	# --- Zoom: perspective (radius) + ortho (size) clamps.
	_assert(failed, _approx(CameraController.zoom_radius(20.0, 1.12), 22.4),
			"zoom_radius scales by factor")
	_assert(failed, _approx(CameraController.zoom_radius(8.0, 0.4), CameraController.MIN_RADIUS),
			"zoom_radius clamps to MIN_RADIUS")
	_assert(failed, _approx(CameraController.zoom_radius(40.0, 2.0), CameraController.MAX_RADIUS),
			"zoom_radius clamps to MAX_RADIUS")
	_assert(failed, _approx(CameraController.zoom_ortho(18.0, 1.12), 20.16),
			"zoom_ortho scales by factor")
	_assert(failed, _approx(CameraController.zoom_ortho(1.0, 0.5), CameraController.ORTHO_MIN_SIZE),
			"zoom_ortho clamps to ORTHO_MIN_SIZE")

	# Trackpad / magnify helpers — soft steps, correct zoom-in direction.
	var tp_in: float = CameraController.zoom_factor_from_scroll(0.2, true, 1)
	_assert(failed, tp_in < 1.0 and tp_in > 0.90,
			"precise trackpad scroll-up zooms in gently")
	var burst: float = CameraController.zoom_factor_from_scroll(1.0, true, 8)
	_assert(failed, burst < 1.0 and burst > 0.92,
			"macOS wheel-burst spray softens instead of 12% jumps")
	var mag_in: float = CameraController.zoom_factor_from_magnify(1.05)
	_assert(failed, mag_in < 1.0,
			"magnify>1 shrinks radius (zoom in)")
	var mag_out: float = CameraController.zoom_factor_from_magnify(0.95)
	_assert(failed, mag_out > 1.0,
			"magnify<1 grows radius (zoom out)")

	# --- Pan: drag right pushes the scene right (target moves left).
	var pt: Vector3 = CameraController.pan_target(
			Vector3.ZERO, Vector2(10.0, 0.0), Vector3.RIGHT, Vector3.UP, 10.0)
	# pan_sc = 0.012 * 10 = 0.12 ; x -= 1*(10*0.12) = -1.2
	_assert(failed, pt.is_equal_approx(Vector3(-1.2, 0.0, 0.0)),
			"pan_target slides target left on rightward drag")

	# --- Target clamp: the single convergence box.
	var ct: Vector3 = CameraController.clamp_target(Vector3(100.0, 100.0, -100.0))
	_assert(failed, ct.is_equal_approx(Vector3(20.0, 12.0, -20.0)),
			"clamp_target clamps to the convergence box")

	# --- Eye position: spherical orbit coords (+pitch = eye above target).
	var eye_flat: Vector3 = CameraController.eye_position(Vector3.ZERO, 0.0, 0.0, 10.0)
	_assert(failed, eye_flat.is_equal_approx(Vector3(0.0, 0.0, 10.0)),
			"eye at yaw=pitch=0 sits +Z of target by radius")
	var eye_top: Vector3 = CameraController.eye_position(Vector3(0, 3, 0), 0.0, PI * 0.5, 10.0)
	_assert(failed, eye_top.is_equal_approx(Vector3(0.0, 13.0, 0.0)),
			"eye at pitch=90deg sits directly above target")

	# --- Auto-orbit: linear yaw drift.
	_assert(failed, _approx(CameraController.auto_orbit_yaw(1.0, 0.08, 0.5), 1.04),
			"auto_orbit_yaw advances yaw by speed*dt")

	if failed.is_empty():
		print("[smoke] camera_controller OK")
		quit(0)
	else:
		for f in failed:
			push_error("[smoke] " + f)
		quit(1)


func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.0005


func _assert(failed: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		failed.append(msg)
