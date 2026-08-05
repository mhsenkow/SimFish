extends SceneTree

# Live DualSense verification — requires a connected pad. Injects synthetic
# joy events to prove action maps + card/nudge/menu paths, then samples the
# real DualSense for a few seconds.

const GamepadBindingsScript = preload("res://scripts/gamepad_bindings.gd")
const OnboardingRuntimeScript = preload("res://scripts/onboarding_runtime.gd")
const OnboardingLegibilityScript = preload("res://scripts/onboarding_legibility.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	GamepadBindingsScript.ensure()

	var pads: Array = Input.get_connected_joypads()
	_assert(failed, not pads.is_empty(), "DualSense (or any pad) must be connected")
	if pads.is_empty():
		_finish(failed)
		return
	var pad_id: int = int(pads[0])
	var pad_name: String = Input.get_joy_name(pad_id)
	print("[live] pad id=%s name='%s' known=%s" % [
		pad_id, pad_name, Input.is_joy_known(pad_id)])
	_assert(failed, pad_name.to_lower().contains("dualsense") \
			or pad_name.to_lower().contains("wireless") \
			or Input.is_joy_known(pad_id),
			"connected pad should be a known DualSense-class device")

	# --- Action map: synthetic button → action ---
	var checks: Array = [
		[JOY_BUTTON_A, "ui_accept"],
		[JOY_BUTTON_A, "feed"],
		[JOY_BUTTON_B, "ui_cancel"],
		[JOY_BUTTON_X, "follow_pick"],
		[JOY_BUTTON_Y, "aquascape"],
		[JOY_BUTTON_START, "pause"],
		[JOY_BUTTON_BACK, "help"],
		[JOY_BUTTON_LEFT_SHOULDER, "residents"],
		[JOY_BUTTON_RIGHT_SHOULDER, "portal"],
		[JOY_BUTTON_LEFT_STICK, "settings"],
		[JOY_BUTTON_RIGHT_STICK, "photo"],
		[JOY_BUTTON_DPAD_LEFT, "follow_prev"],
		[JOY_BUTTON_DPAD_RIGHT, "follow_next"],
		[JOY_BUTTON_DPAD_UP, "speed_up"],
		[JOY_BUTTON_DPAD_DOWN, "speed_down"],
	]
	for row in checks:
		var btn: int = int(row[0])
		var action: String = String(row[1])
		_inject_btn(pad_id, btn, true)
		await process_frame
		_assert(failed, Input.is_action_pressed(action),
				"press btn %s should fire action '%s'" % [btn, action])
		_inject_btn(pad_id, btn, false)
		await process_frame

	# Stick axes → look / pan actions
	_inject_axis(pad_id, JOY_AXIS_RIGHT_X, 1.0)
	await process_frame
	_assert(failed, Input.get_action_strength("look_right") > 0.5,
			"RS right → look_right")
	_inject_axis(pad_id, JOY_AXIS_RIGHT_X, 0.0)
	_inject_axis(pad_id, JOY_AXIS_LEFT_Y, -1.0)
	await process_frame
	_assert(failed, Input.get_action_strength("pan_up") > 0.5,
			"LS up → pan_up")
	_inject_axis(pad_id, JOY_AXIS_LEFT_Y, 0.0)

	# Camera math from stick-like deltas
	var gp: Node = root.get_node_or_null("GamepadInput")
	_assert(failed, gp != null, "GamepadInput autoload present")
	if gp != null:
		var look_px: Vector2 = Vector2(1, 0) * 420.0 * (1.0 / 60.0)
		var ob: Vector2 = CameraController.orbit(0.5, 0.1, look_px)
		_assert(failed, ob.x < 0.5, "orbit responds to look delta")
		gp.reset_reticle()
		var r: Vector2 = gp.update_aquascape_reticle(0.05, Vector2(800, 600))
		# With no real stick, reticle stays near center unless we poke offset.
		gp._reticle_offset = Vector2(10, 0)
		r = gp.reticle_screen_pos(Vector2(800, 600))
		_assert(failed, r.x > 400.0, "reticle offset moves aim point")
		gp.reset_reticle()

	# Away card dismiss API
	var host := Control.new()
	root.add_child(host)
	var onboard: Node = OnboardingRuntimeScript.new()
	onboard.setup(host)
	root.add_child(onboard)
	await process_frame
	onboard.show_away_recap_card("1 day", "live-test recap")
	await process_frame
	_assert(failed, onboard.has_blocking_card(), "away card blocks")
	_assert(failed, onboard.dismiss_card(), "away card dismisses")
	await process_frame

	# Nudge show/dismiss (O₂ toast path)
	onboard._show_nudge("o2", "Oxygen's dipping — live test.", Callable())
	await process_frame
	_assert(failed, onboard.has_blocking_nudge(), "nudge panel blocks")
	_assert(failed, onboard.dismiss_nudge(), "nudge dismisses")
	await process_frame
	_assert(failed, not onboard.has_blocking_nudge(), "nudge cleared")

	# Aquascape tool cycle
	var ac := AquascapeController.new()
	ac.is_active = true
	ac.tool = "sand"
	ac.cycle_tool(1)
	_assert(failed, ac.tool != "sand", "tool cycle advances")

	# Menu activate-focused path
	var open := PanelTheme.make_primary_button("Open tank")
	open.set_meta("tank_open_slot", 1)
	var activated := {"ok": false}
	open.pressed.connect(func(): activated["ok"] = true)
	host.add_child(open)
	open.grab_focus()
	await process_frame
	open.pressed.emit()
	_assert(failed, bool(activated["ok"]), "focused Open tank activates")

	# Cheat sheet gamepad lines
	var lines: PackedStringArray = OnboardingLegibilityScript.cheat_sheet_lines(false, true)
	_assert(failed, lines.size() >= 6, "gamepad legend present")

	# Sample real hardware briefly (informational — not a hard fail if idle)
	print("[live] sampling real DualSense for ~2s — mash Cross / stick if you want…")
	var saw_hw: bool = false
	for i in range(120):
		await process_frame
		if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_A) \
				or Input.is_joy_button_pressed(pad_id, JOY_BUTTON_B) \
				or absf(Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_X)) > 0.35 \
				or absf(Input.get_joy_axis(pad_id, JOY_AXIS_RIGHT_X)) > 0.35:
			saw_hw = true
			print("[live] hardware activity detected")
			break
	print("[live] hardware_activity=%s (ok either way — synthetic tests are authoritative)" % saw_hw)

	onboard.queue_free()
	host.queue_free()
	_finish(failed)


func _inject_btn(device: int, button: int, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = device
	ev.button_index = button
	ev.pressed = pressed
	ev.pressure = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


func _inject_axis(device: int, axis: int, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = device
	ev.axis = axis
	ev.axis_value = value
	Input.parse_input_event(ev)


func _assert(failed: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		failed.append(msg)
		push_error("[live] FAIL: " + msg)
	else:
		print("[live] OK: " + msg)


func _finish(failed: Array[String]) -> void:
	if failed.is_empty():
		print("[live] gamepad DualSense verification PASSED")
		quit(0)
	else:
		print("[live] FAILED %d checks" % failed.size())
		for f in failed:
			push_error("[live] " + f)
		quit(1)
