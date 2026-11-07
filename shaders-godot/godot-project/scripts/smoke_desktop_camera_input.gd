extends SceneTree

# Desktop camera input pass: trackpad gesture helpers, Alt+arrow follow binding,
# cheat-sheet truth, and aquascape Q/E / arrow ownership documented in source.


const GamepadBindingsScript = preload("res://scripts/gamepad_bindings.gd")
const OnboardingLegibilityScript = preload("res://scripts/onboarding_legibility.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	GamepadBindingsScript.ensure()

	# follow_prev / follow_next keyboard mirrors must be Alt+arrow, not bare.
	TestSupport.check(failed, _action_has_alt_key("follow_prev", KEY_LEFT),
			"follow_prev binds Alt+Left (bare arrows orbit)")
	TestSupport.check(failed, _action_has_alt_key("follow_next", KEY_RIGHT),
			"follow_next binds Alt+Right")
	TestSupport.check(failed, not _action_has_bare_key("follow_prev", KEY_LEFT),
			"follow_prev must not keep a bare Left binding")
	TestSupport.check(failed, not _action_has_bare_key("follow_next", KEY_RIGHT),
			"follow_next must not keep a bare Right binding")
	TestSupport.check(failed, _action_has_joy_btn("follow_prev", JOY_BUTTON_DPAD_LEFT),
			"follow_prev still has D-pad Left for pads")

	# Pure helpers used by main._handle_pan_gesture / _drain_zoom / keyboard orbit.
	var filtered: Vector2 = CameraController.pan_gesture_axes(Vector2(0.03, 0.15))
	TestSupport.check(failed, _approx(filtered.x, 0.0) and filtered.y > 0.0,
			"PanGesture filter prefers vertical zoom over yaw")
	var soft: float = CameraController.soften_log_zoom_at_limit(
			CameraController.MAX_RADIUS - 0.2, 0.4)
	TestSupport.check(failed, soft < 0.4,
			"soft zoom limit eases near MAX_RADIUS")
	var kbd: Vector2 = CameraController.keyboard_orbit_pixels(
			true, false, false, false, 0.05, 1.0)
	var ob: Vector2 = CameraController.orbit(1.0, 0.2, kbd)
	TestSupport.check(failed, ob.x > 1.0,
			"arrow-left orbit increases yaw")

	# Magnify still shares the log-zoom budget path with the wheel.
	var mag: float = CameraController.magnify_log_zoom(1.08)
	TestSupport.check(failed, mag < 0.0,
			"magnify>1 queues zoom-in (negative log)")

	# Cheat sheet + default hint match the shipped desktop map.
	var lines: PackedStringArray = OnboardingLegibilityScript.cheat_sheet_lines(false)
	var joined: String = " ".join(lines).to_lower()
	for needle in ["wasd", "arrow", "alt+", "trackpad", "pinch", "middle", "shift", "auto-orbit"]:
		TestSupport.check(failed, joined.contains(needle),
				"desktop cheat sheet mentions %s" % needle)
	var follow_hint: String = OnboardingLegibilityScript.control_hint_for_context("follow")
	TestSupport.check(failed, follow_hint.contains("Alt"),
			"follow hint documents Alt+arrows")
	var def_hint: String = OnboardingLegibilityScript.control_hint_for_context("")
	TestSupport.check(failed, def_hint.to_lower().contains("wasd") \
			or def_hint.to_lower().contains("orbit"),
			"default control hint mentions keyboard camera")

	# main.gd owns the routing symbols this pass added.
	var main_src: String = FileAccess.get_file_as_string("res://scripts/main.gd")
	TestSupport.check(failed, main_src.contains("func _process_keyboard_orbit"),
			"main exposes _process_keyboard_orbit")
	TestSupport.check(failed, main_src.contains("func _handle_alt_arrow_follow"),
			"main exposes _handle_alt_arrow_follow")
	TestSupport.check(failed, main_src.contains("pan_gesture_axes"),
			"main routes trackpad through pan_gesture_axes")
	TestSupport.check(failed, main_src.contains("soften_log_zoom_at_limit"),
			"main softens zoom at limits")
	TestSupport.check(failed, not main_src.contains("PINCH_ZOOM_SENSITIVITY"),
			"unused PINCH_ZOOM_SENSITIVITY removed")
	# Q/E vertical pan yields while aquascape is active.
	TestSupport.check(failed, main_src.contains("not _aquascape.is_active") \
			and main_src.contains("KEY_E") and main_src.contains("KEY_Q"),
			"Q/E pan gated off during aquascape")

	quit(TestSupport.report("smoke_desktop_camera_input", failed))


func _action_has_alt_key(action: String, keycode: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k: InputEventKey = ev as InputEventKey
			if k.keycode == (keycode as Key) and k.alt_pressed and not k.shift_pressed \
					and not k.ctrl_pressed and not k.meta_pressed:
				return true
	return false


func _action_has_bare_key(action: String, keycode: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k: InputEventKey = ev as InputEventKey
			if k.keycode == (keycode as Key) and not k.alt_pressed and not k.shift_pressed \
					and not k.ctrl_pressed and not k.meta_pressed:
				return true
	return false


func _action_has_joy_btn(action: String, button: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton \
				and (ev as InputEventJoypadButton).button_index == (button as JoyButton):
			return true
	return false


func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.0005
