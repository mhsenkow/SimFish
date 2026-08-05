# Registers shared InputMap actions for keyboard + DualSense / Deck / Xbox pads.
# Called once at boot from the GamepadInput autoload (and from smokes).
# SYSTEMIC #88 remapping UI is a follow-up — these are the shipped defaults.

class_name GamepadBindings
extends RefCounted

const ACTIONS: PackedStringArray = [
	"look_left", "look_right", "look_up", "look_down",
	"pan_left", "pan_right", "pan_up", "pan_down",
	"zoom_in", "zoom_out",
	"feed", "follow_pick", "pause", "aquascape",
	"residents", "portal", "settings", "photo", "help",
	"speed_up", "speed_down", "follow_prev", "follow_next",
	"tool_prev", "tool_next", "brush_down", "brush_up",
	"camera_reset",
]


static func ensure() -> void:
	_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_axis("pan_left", JOY_AXIS_LEFT_X, -1.0)
	_axis("pan_right", JOY_AXIS_LEFT_X, 1.0)
	_axis("pan_up", JOY_AXIS_LEFT_Y, -1.0)
	_axis("pan_down", JOY_AXIS_LEFT_Y, 1.0)
	_axis("zoom_out", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_axis("zoom_in", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	# Aquascape brush also on triggers (same physical axes; actions distinct for clarity).
	_axis("brush_down", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_axis("brush_up", JOY_AXIS_TRIGGER_RIGHT, 1.0)

	_btn("feed", JOY_BUTTON_A)
	_btn("follow_pick", JOY_BUTTON_X)
	_btn("aquascape", JOY_BUTTON_Y)
	_btn("pause", JOY_BUTTON_START)
	_btn("help", JOY_BUTTON_BACK)
	_btn("residents", JOY_BUTTON_LEFT_SHOULDER)
	_btn("portal", JOY_BUTTON_RIGHT_SHOULDER)
	_btn("tool_prev", JOY_BUTTON_LEFT_SHOULDER)
	_btn("tool_next", JOY_BUTTON_RIGHT_SHOULDER)
	_btn("settings", JOY_BUTTON_LEFT_STICK)
	_btn("photo", JOY_BUTTON_RIGHT_STICK)
	_btn("camera_reset", JOY_BUTTON_RIGHT_STICK)
	# D-pad: left=prev fish, right=next, up=faster, down=slower.
	_rebind_btn("follow_prev", JOY_BUTTON_DPAD_LEFT)
	_rebind_btn("follow_next", JOY_BUTTON_DPAD_RIGHT)
	_rebind_btn("speed_down", JOY_BUTTON_DPAD_DOWN)
	_rebind_btn("speed_up", JOY_BUTTON_DPAD_UP)

	# Built-in UI actions: Godot's defaults often omit joypad Accept (nav works,
	# activate doesn't). Bind Cross/A + Circle/B for all devices (-1).
	_btn("ui_accept", JOY_BUTTON_A)
	_btn("ui_cancel", JOY_BUTTON_B)
	_widen_ui_joy_devices()

	# Keyboard mirrors so smokes + future remapping share one path.
	_key("pause", KEY_P)
	_key("aquascape", KEY_B)
	_key("residents", KEY_K)
	_key("portal", KEY_C)
	_key("settings", KEY_O)
	_key("photo", KEY_F12)
	_key("help", KEY_QUESTION)
	_key("follow_prev", KEY_LEFT)
	_key("follow_next", KEY_RIGHT)
	_key("camera_reset", KEY_F)
	_key("brush_down", KEY_BRACKETLEFT)
	_key("brush_up", KEY_BRACKETRIGHT)


static func _ensure_action(name: String) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, 0.2)


static func _has_event(action: String, ev: InputEvent) -> bool:
	for existing in InputMap.action_get_events(action):
		if existing.is_match(ev, true):
			return true
	return false


static func _axis(action: String, axis: int, axis_value: float) -> void:
	_ensure_action(action)
	var ev := InputEventJoypadMotion.new()
	ev.device = -1
	ev.axis = axis as JoyAxis
	ev.axis_value = axis_value
	if not _has_event(action, ev):
		InputMap.action_add_event(action, ev)


static func _btn(action: String, button: int) -> void:
	_ensure_action(action)
	var ev := InputEventJoypadButton.new()
	ev.device = -1
	ev.button_index = button as JoyButton
	if not _has_event(action, ev):
		InputMap.action_add_event(action, ev)


# Replace all joypad-button events on an action (used when correcting inverted
# D-pad bindings so stale LEFT/RIGHT events don't linger beside the new ones).
static func _rebind_btn(action: String, button: int) -> void:
	_ensure_action(action)
	var kept: Array[InputEvent] = []
	for existing in InputMap.action_get_events(action):
		if existing is InputEventJoypadButton:
			continue
		kept.append(existing)
	InputMap.action_erase_events(action)
	for ev in kept:
		InputMap.action_add_event(action, ev)
	_btn(action, button)


static func _key(action: String, keycode: int) -> void:
	_ensure_action(action)
	var ev := InputEventKey.new()
	ev.keycode = keycode as Key
	if not _has_event(action, ev):
		InputMap.action_add_event(action, ev)


# Built-in ui_* joy events are often device=0 only; DualSense on Mac may be
# another index. Widen every ui_* joy binding to all devices.
static func _widen_ui_joy_devices() -> void:
	for action in InputMap.get_actions():
		if not String(action).begins_with("ui_"):
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				event.device = -1
