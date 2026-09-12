extends SceneTree

# Valve Full Controller Support contract (BuildID #24083947, failure 3).
#
# The store category was rejected because a pad could not reach every
# function. The manual retest still needs a Windows box and a physical pad —
# this smoke gates the part that CAN be checked headlessly: that the pad
# "Options" menu still *offers* every destination Valve's checklist walks,
# that main.gd has an action wired for each label ControllerMenu orders, and
# that ○ / ✕ stay bound for all devices.
#
# No hardware pad required. See smoke_gamepad_live.gd for the pad-attached run.

const GamepadBindingsScript = preload("res://scripts/gamepad_bindings.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	# --- 1. Required destinations present in both aquascape modes ---
	for aqua_active in [false, true]:
		var labels: PackedStringArray = ControllerMenu.destination_labels(aqua_active)
		var missing: PackedStringArray = ControllerMenu.missing_required(labels)
		TestSupport.check(failed, missing.is_empty(),
			"pad menu (aquascape=%s) missing required destinations: %s"
			% [aqua_active, ", ".join(missing)])
		# Aquascape must be reachable either way, under the mode's own label.
		var aqua_label: String = ControllerMenu.AQUASCAPE_EXIT if aqua_active \
				else ControllerMenu.AQUASCAPE_ENTER
		TestSupport.check(failed, labels.has(aqua_label),
			"pad menu (aquascape=%s) must offer '%s'" % [aqua_active, aqua_label])
		# An escape hatch must exist so a pad is never trapped in the menu.
		TestSupport.check(failed, labels.has("Close menu"),
			"pad menu (aquascape=%s) must offer 'Close menu'" % aqua_active)
		# No duplicate labels — the action Dictionary in main.gd is keyed by
		# label, so a duplicate would silently collapse two destinations.
		var seen: Dictionary = {}
		var dupes := PackedStringArray()
		for l in labels:
			if seen.has(l):
				dupes.append(l)
			seen[l] = true
		TestSupport.check(failed, dupes.is_empty(),
			"pad menu (aquascape=%s) has duplicate labels: %s"
			% [aqua_active, ", ".join(dupes)])

	# --- 2. Aquascape-exit is hoisted first while aquascaping ---
	var active_labels: PackedStringArray = ControllerMenu.destination_labels(true)
	TestSupport.check(failed, active_labels.size() > 0 \
			and active_labels[0] == ControllerMenu.AQUASCAPE_EXIT,
		"'%s' must be the first pad entry while aquascaping (couch escape)"
			% ControllerMenu.AQUASCAPE_EXIT)

	# --- 3. main.gd wires an action for every ordered label ---
	# _open_gamepad_menu() builds a label->Callable Dictionary and iterates
	# ControllerMenu.destination_labels(); a label with no action push_error()s
	# at runtime. Assert the source lists each one so that never ships.
	var src: String = FileAccess.get_file_as_string("res://scripts/main.gd")
	TestSupport.check(failed, not src.is_empty(), "main.gd readable for action-wiring check")
	if not src.is_empty():
		# The aquascape toggle is keyed by a variable (its label flips with
		# mode), so it is checked separately from the literal-keyed rest.
		TestSupport.check(failed, src.contains("aqua_label: func()"),
			"main._open_gamepad_menu must wire the aquascape toggle under aqua_label")
		for aqua_active in [false, true]:
			for label in ControllerMenu.destination_labels(aqua_active):
				if label == ControllerMenu.AQUASCAPE_ENTER \
						or label == ControllerMenu.AQUASCAPE_EXIT:
					continue
				TestSupport.check(failed, src.contains('"%s": func()' % label),
					"main._open_gamepad_menu has no action wired for '%s'" % label)

	# --- 4. Face buttons bound for all devices ---
	GamepadBindingsScript.ensure()
	TestSupport.check(failed, _joy_all_devices("ui_accept", JOY_BUTTON_A),
		"ui_accept must bind Cross/A for all devices")
	TestSupport.check(failed, _joy_all_devices("ui_cancel", JOY_BUTTON_B),
		"ui_cancel must bind Circle/B for all devices (panel close)")

	# --- 5. Pad-reachable quit still exists ---
	# Source-text check, not instantiation: main.gd depends on autoloads that
	# a --script run does not mount.
	TestSupport.check(failed, src.contains("func _confirm_quit_game()"),
		"main must expose a pad-reachable _confirm_quit_game()")

	quit(TestSupport.report("smoke_controller_coverage", failed))


func _joy_all_devices(action: String, button: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for ev in InputMap.action_get_events(action):
		var jb := ev as InputEventJoypadButton
		if jb != null and jb.button_index == button and jb.device == -1:
			return true
	return false
