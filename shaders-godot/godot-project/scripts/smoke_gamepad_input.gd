extends SceneTree

# Couch / DualSense substrate smoke — InputMap actions, stick→orbit math,
# reticle helper, aquascape tool cycle, menu accept, onboarding card dismiss.
# No hardware pad required.

const GamepadBindingsScript = preload("res://scripts/gamepad_bindings.gd")
const OnboardingLegibilityScript = preload("res://scripts/onboarding_legibility.gd")
const OnboardingRuntimeScript = preload("res://scripts/onboarding_runtime.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	GamepadBindingsScript.ensure()
	for action in GamepadBindingsScript.ACTIONS:
		_assert(failed, InputMap.has_action(action),
				"InputMap missing action: %s" % action)

	_assert(failed, InputMap.action_get_events("look_right").size() > 0,
			"look_right must have at least one event")
	_assert(failed, InputMap.action_get_events("feed").size() > 0,
			"feed must have at least one event")
	_assert(failed, InputMap.action_get_events("pause").size() > 0,
			"pause must have at least one event")

	# ui_accept / ui_cancel must include joypad face buttons (D-pad alone is not enough).
	_assert(failed, _action_has_joy_btn("ui_accept", JOY_BUTTON_A),
			"ui_accept must bind JOY_BUTTON_A (Cross)")
	_assert(failed, _action_has_joy_btn("ui_cancel", JOY_BUTTON_B),
			"ui_cancel must bind JOY_BUTTON_B (Circle)")
	_assert(failed, _joy_device_is_all("ui_accept", JOY_BUTTON_A),
			"ui_accept joy binding should accept all devices")

	# Stick→orbit: same CameraController path main.gd uses for RS.
	var look := Vector2(1.0, 0.0)
	var px: Vector2 = look * 420.0 * (1.0 / 60.0)
	var ob: Vector2 = CameraController.orbit(0.0, 0.0, px)
	_assert(failed, ob.x < 0.0 and _approx(ob.y, 0.0),
			"right-stick look should yaw via CameraController.orbit")

	# Pan + zoom helpers on GamepadInput.
	var gp: Node = Engine.get_main_loop().root.get_node_or_null("GamepadInput")
	_assert(failed, gp != null, "GamepadInput autoload must exist")
	if gp != null:
		gp.reset_reticle()
		var pos: Vector2 = gp.reticle_screen_pos(Vector2(800, 600))
		_assert(failed, pos.is_equal_approx(Vector2(400, 300)),
				"reticle starts at viewport center")
		gp._reticle_offset = Vector2(40, -20)
		pos = gp.reticle_screen_pos(Vector2(800, 600))
		_assert(failed, pos.is_equal_approx(Vector2(440, 280)),
				"reticle offset applies in screen space")
		gp.reset_reticle()
		_assert(failed, gp.has_method("look_pixel_delta"),
				"GamepadInput exposes look_pixel_delta")
		_assert(failed, gp.has_method("pan_pixel_delta"),
				"GamepadInput exposes pan_pixel_delta")
		_assert(failed, gp.has_method("zoom_factor_for_dt"),
				"GamepadInput exposes zoom_factor_for_dt")
		var z_idle: float = gp.zoom_factor_for_dt(1.0 / 60.0)
		_assert(failed, _approx(z_idle, 1.0),
				"zoom_factor_for_dt is identity with no trigger")
		_assert(failed, gp.get_look_vector().is_equal_approx(Vector2.ZERO),
				"look vector is zero with no hardware input")

	# Aquascape tool cycle (no world host needed for index wrap).
	var ac := AquascapeController.new()
	ac.is_active = true
	ac.tool = "aquasoil"
	ac.cycle_tool(1)
	_assert(failed, ac.tool == AquascapeController.AQUASCAPE_TOOLS[1],
			"cycle_tool(+1) advances within AQUASCAPE_TOOLS")
	ac.cycle_tool(-1)
	_assert(failed, ac.tool == "aquasoil",
			"cycle_tool(-1) wraps back")
	var last: String = AquascapeController.AQUASCAPE_TOOLS[
			AquascapeController.AQUASCAPE_TOOLS.size() - 1]
	ac.tool = last
	ac.cycle_tool(1)
	_assert(failed, ac.tool == AquascapeController.AQUASCAPE_TOOLS[0],
			"cycle_tool wraps past end")
	_assert(failed, ac.has_method("clear_selection"),
			"aquascape exposes clear_selection for pad Circle")
	ac.clear_selection()
	_assert(failed, not ac.has_selection(),
			"clear_selection empties selection")

	# Cheat sheet exposes a gamepad column.
	var pad_lines: PackedStringArray = OnboardingLegibilityScript.cheat_sheet_lines(false, true)
	_assert(failed, pad_lines.size() >= 6,
			"gamepad cheat sheet must list core bindings")
	var joined: String = " ".join(pad_lines)
	_assert(failed, joined.contains("Options") or joined.contains("stick") or joined.contains("Stick"),
			"gamepad cheat sheet mentions Options menu or sticks")
	_assert(failed, OnboardingLegibilityScript.control_hint_for_context("gamepad") != "",
			"gamepad control hint exists")
	_assert(failed, OnboardingLegibilityScript.control_hint_for_context("aquascape_pad").to_lower().contains("exit"),
			"aquascape_pad hint mentions exit")
	# force_none mutes a subtree without clearing global couch flag.
	PanelTheme.set_couch_focus(true)
	var mute_host := Node.new()
	root.add_child(mute_host)
	var mute_btn := Button.new()
	mute_btn.focus_mode = Control.FOCUS_ALL
	mute_host.add_child(mute_btn)
	PanelTheme.apply_couch_focus_tree(mute_host, true, true)
	_assert(failed, mute_btn.focus_mode == Control.FOCUS_NONE,
			"force_none mutes button focus")
	_assert(failed, PanelTheme.couch_focus(),
			"force_none does not clear global couch_focus")
	mute_host.queue_free()
	PanelTheme.set_couch_focus(false)

	# PanelTheme couch focus flip.
	PanelTheme.set_couch_focus(true)
	_assert(failed, PanelTheme.couch_focus(), "couch_focus flag sets")
	var btn := Button.new()
	btn.set_meta("couch_was_none", true)
	btn.focus_mode = Control.FOCUS_NONE
	var host := Node.new()
	root.add_child(host)
	host.add_child(btn)
	PanelTheme.apply_couch_focus_tree(host, true)
	_assert(failed, btn.focus_mode == Control.FOCUS_ALL,
			"apply_couch_focus_tree enables FOCUS_ALL on chrome buttons")
	PanelTheme.apply_couch_focus_tree(host, false)
	_assert(failed, btn.focus_mode == Control.FOCUS_NONE,
			"apply_couch_focus_tree restores FOCUS_NONE")
	var primary := PanelTheme.make_primary_button("Got it")
	_assert(failed, primary.get_theme_stylebox("focus") != null,
			"primary button has focus stylebox")
	host.add_child(primary)
	var grab_src_ok: bool = (load("res://scripts/panel_theme.gd") as Script).source_code \
			.contains("func grab_couch_focus")
	_assert(failed, grab_src_ok, "PanelTheme.grab_couch_focus defined")
	host.queue_free()
	PanelTheme.set_couch_focus(false)

	# Onboarding away-card: show → has_blocking → dismiss.
	var main_host := Control.new()
	main_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(main_host)
	var onboard: Node = OnboardingRuntimeScript.new()
	onboard.setup(main_host)
	root.add_child(onboard)
	await process_frame
	_assert(failed, not onboard.has_blocking_card(),
			"no blocking card before show")
	onboard.show_away_recap_card("28.4 days", "weathered a quiet scare alone")
	await process_frame
	_assert(failed, onboard.has_blocking_card(),
			"away recap creates a blocking card")
	_assert(failed, onboard._card_ok_btn != null \
			and is_instance_valid(onboard._card_ok_btn),
			"Got it button exists on card")
	_assert(failed, onboard.dismiss_card(),
			"dismiss_card returns true when card open")
	await process_frame
	_assert(failed, not onboard.has_blocking_card(),
			"card gone after dismiss")
	_assert(failed, not onboard.dismiss_card(),
			"second dismiss is a no-op")
	onboard.queue_free()
	main_host.queue_free()

	# Tank menu exposes activate-focused + gamepad setup symbols.
	var menu_script: Script = load("res://scripts/tank_menu.gd") as Script
	_assert(failed, menu_script != null, "tank_menu.gd loads")
	if menu_script != null:
		var src: String = menu_script.source_code
		_assert(failed, src.contains("_activate_focused_button"),
				"tank_menu activates focused button on accept")
		_assert(failed, src.contains("_unhandled_input"),
				"tank_menu handles unhandled joy accept")
		_assert(failed, src.contains("_suppress_card_chrome_focus"),
				"tank_menu keeps D-pad on Open actions")

	# Main wires card dismiss into overlay stack + gamepad feed gate.
	var main_script: Script = load("res://scripts/main.gd") as Script
	_assert(failed, main_script != null, "main.gd loads")
	if main_script != null:
		var msrc: String = main_script.source_code
		_assert(failed, msrc.contains("dismiss_card"),
				"main dismisses onboarding cards from overlay stack")
		_assert(failed, msrc.contains("has_blocking_card"),
				"main gates tank actions while card is up")
		_assert(failed, msrc.contains("_process_gamepad_camera"),
				"main processes gamepad camera")
		_assert(failed, msrc.contains("_aim_screen_pos"),
				"main aims via reticle when pad active")
		_assert(failed, msrc.contains("_gamepad_toggle_aquascape"),
				"main has pad aquascape toggle/exit")
		_assert(failed, msrc.contains("_sync_aquascape_pad_focus"),
				"main mutes workbench focus under pad")
		_assert(failed, msrc.contains("Exit Aquascape"),
				"controller menu labels Exit Aquascape")
		_assert(failed, msrc.contains("_confirm_quit_game") or msrc.contains("Quit game"),
				"controller menu can quit without keyboard")
		_assert(failed, msrc.contains("Tank list"),
				"controller menu returns to tank list")

	_assert(failed, load("res://scripts/gamepad_bindings.gd") != null, "gamepad_bindings parses")
	_assert(failed, load("res://scripts/gamepad_input.gd") != null, "gamepad_input parses")
	_assert(failed, load("res://scripts/onboarding_runtime.gd") != null, "onboarding_runtime parses")
	_assert(failed, load("res://scripts/ui_panel_manager.gd") != null, "ui_panel_manager parses")

	if failed.is_empty():
		print("[smoke] gamepad_input OK")
		quit(0)
	else:
		for f in failed:
			push_error("[smoke] " + f)
		quit(1)


func _action_has_joy_btn(action: String, button: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton \
				and (ev as InputEventJoypadButton).button_index == button:
			return true
	return false


func _joy_device_is_all(action: String, button: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton \
				and (ev as InputEventJoypadButton).button_index == button:
			return (ev as InputEventJoypadButton).device == -1
	return false


func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.0005


func _assert(failed: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		failed.append(msg)
