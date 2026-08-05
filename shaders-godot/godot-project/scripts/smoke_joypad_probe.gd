extends SceneTree

# Live joypad probe — lists connected pads and polls a few frames of input.
# Run while DualSense is plugged in (no display needed).


func _initialize() -> void:
	await process_frame
	GamepadBindings.ensure() if false else null
	var Bindings = preload("res://scripts/gamepad_bindings.gd")
	Bindings.ensure()

	var pads: Array = Input.get_connected_joypads()
	print("[probe] connected_joypads=%s" % str(pads))
	if pads.is_empty():
		print("[probe] FAIL — Godot sees no joypads (permissions / wrong process?)")
		quit(1)
		return

	for id in pads:
		var n: String = Input.get_joy_name(id)
		var guid: String = Input.get_joy_guid(id)
		print("[probe] id=%s name='%s' guid=%s" % [id, n, guid])
		print("[probe]   known=%s" % Input.is_joy_known(id))

	print("[probe] ui_accept events=%s" % InputMap.action_get_events("ui_accept").size())
	print("[probe] feed events=%s" % InputMap.action_get_events("feed").size())

	# Poll briefly for any face-button / stick activity.
	print("[probe] polling 90 frames — press Cross / move stick if you can…")
	var saw_btn: bool = false
	var saw_axis: bool = false
	for i in range(90):
		await process_frame
		for id in Input.get_connected_joypads():
			for b in [
				JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y,
				JOY_BUTTON_START, JOY_BUTTON_BACK,
				JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN,
				JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT,
			]:
				if Input.is_joy_button_pressed(id, b):
					print("[probe] button pressed id=%s btn=%s" % [id, b])
					saw_btn = true
			var lx: float = Input.get_joy_axis(id, JOY_AXIS_LEFT_X)
			var ly: float = Input.get_joy_axis(id, JOY_AXIS_LEFT_Y)
			var rx: float = Input.get_joy_axis(id, JOY_AXIS_RIGHT_X)
			var ry: float = Input.get_joy_axis(id, JOY_AXIS_RIGHT_Y)
			if absf(lx) > 0.3 or absf(ly) > 0.3 or absf(rx) > 0.3 or absf(ry) > 0.3:
				print("[probe] stick id=%s LS=(%.2f,%.2f) RS=(%.2f,%.2f)" % [id, lx, ly, rx, ry])
				saw_axis = true
		if saw_btn and saw_axis:
			break

	print("[probe] saw_button=%s saw_stick=%s" % [saw_btn, saw_axis])
	print("[probe] OK — DualSense visible to Godot")
	quit(0)
