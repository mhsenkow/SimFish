# Couch / DualSense / Steam Deck input substrate.
# Tracks whether a gamepad is the active device, exposes stick vectors with
# deadzone, and a screen reticle for feed / follow / aquascape placement.

extends Node

const GamepadBindingsScript = preload("res://scripts/gamepad_bindings.gd")

signal active_changed(active: bool)
signal joy_connected(device: int, name: String)
signal joy_disconnected(device: int)

const DEADZONE: float = 0.22
const LOOK_PX_PER_SEC: float = 420.0
const PAN_PX_PER_SEC: float = 380.0
const ZOOM_RATE: float = 1.35  # scale factor per second at full trigger
const RETICLE_STICK_SPEED: float = 520.0  # aquascape reticle px/s
const HOLD_RESET_S: float = 0.55

var _gamepad_recent: bool = false
var _was_active: bool = false
var _reticle_offset: Vector2 = Vector2.ZERO
var _r3_held_s: float = 0.0
var _brush_trigger_armed: Dictionary = {"down": true, "up": true}


func _ready() -> void:
	GamepadBindingsScript.ensure()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	# If a pad is already plugged in at boot, treat as recent so menu focus works.
	if not Input.get_connected_joypads().is_empty():
		_gamepad_recent = true
	_emit_active_if_changed()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event is InputEventJoypadMotion:
			var jm: InputEventJoypadMotion = event
			if absf(jm.axis_value) < DEADZONE:
				return
		_gamepad_recent = true
		_emit_active_if_changed()
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		if event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length_squared() < 1.0:
			return
		if _gamepad_recent:
			_gamepad_recent = false
			_emit_active_if_changed()
	elif event is InputEventKey and event.pressed:
		if _gamepad_recent:
			_gamepad_recent = false
			_emit_active_if_changed()


func _process(dt: float) -> void:
	_emit_active_if_changed()
	if Input.is_action_pressed("photo") or Input.is_action_pressed("camera_reset"):
		_r3_held_s += dt
	else:
		_r3_held_s = 0.0


func is_gamepad_active() -> bool:
	return _gamepad_recent and not Input.get_connected_joypads().is_empty()


func has_joypad() -> bool:
	return not Input.get_connected_joypads().is_empty()


func couch_focus_wanted() -> bool:
	return has_joypad() and _gamepad_recent


func get_pan_vector() -> Vector2:
	# Negate vs raw stick: CameraController.pan_target treats +x like mouse-drag
	# (scene slides with the drag). Couch players expect stick-right = pan view
	# toward the right (camera trucks right) — opposite of drag-the-world.
	return -get_move_vector()


func get_move_vector() -> Vector2:
	# Raw left stick — screen-aligned (stick right → +x). Used for aquascape
	# reticle aim so workbench doesn't inherit camera-pan invert.
	return _stick("pan_left", "pan_right", "pan_up", "pan_down")


func get_look_vector() -> Vector2:
	# Invert look X so stick-right yaws the view right (natural DualSense feel).
	var v: Vector2 = _stick("look_left", "look_right", "look_up", "look_down")
	return Vector2(-v.x, v.y)


func get_zoom_axis() -> float:
	# Positive = zoom in (narrower), negative = zoom out.
	var zin: float = _axis_strength("zoom_in")
	var zout: float = _axis_strength("zoom_out")
	return zin - zout


func look_pixel_delta(dt: float) -> Vector2:
	return get_look_vector() * LOOK_PX_PER_SEC * dt


func pan_pixel_delta(dt: float) -> Vector2:
	return get_pan_vector() * PAN_PX_PER_SEC * dt


func zoom_factor_for_dt(dt: float) -> float:
	var axis: float = get_zoom_axis()
	if absf(axis) < 0.05:
		return 1.0
	# axis > 0 → zoom in → factor < 1 for perspective radius multiply path used by main.
	var rate: float = pow(ZOOM_RATE, absf(axis) * dt)
	return (1.0 / rate) if axis > 0.0 else rate


func reticle_screen_pos(viewport_size: Vector2) -> Vector2:
	var center: Vector2 = viewport_size * 0.5
	return center + _reticle_offset


func reset_reticle() -> void:
	_reticle_offset = Vector2.ZERO


func update_aquascape_reticle(dt: float, viewport_size: Vector2) -> Vector2:
	# Screen-space aim: stick right/up moves the reticle right/up.
	# Do NOT reuse get_pan_vector() — that is camera-truck inverted and made
	# workbench aim feel backwards vs DualSense.
	var stick: Vector2 = get_move_vector()
	if stick.length_squared() > 0.0:
		_reticle_offset += stick * RETICLE_STICK_SPEED * dt
		var half: Vector2 = viewport_size * 0.5 - Vector2(24, 24)
		_reticle_offset.x = clampf(_reticle_offset.x, -half.x, half.x)
		_reticle_offset.y = clampf(_reticle_offset.y, -half.y, half.y)
	return reticle_screen_pos(viewport_size)


func r3_hold_triggered() -> bool:
	return _r3_held_s >= HOLD_RESET_S


func consume_brush_edge(direction: String) -> bool:
	# Edge-trigger brush ± while trigger held past threshold (aquascape).
	var action: String = "brush_up" if direction == "up" else "brush_down"
	var pressed: bool = _axis_strength(action) > 0.55
	var armed: bool = bool(_brush_trigger_armed.get(direction, true))
	if pressed and armed:
		_brush_trigger_armed[direction] = false
		return true
	if not pressed:
		_brush_trigger_armed[direction] = true
	return false


func _stick(left: String, right: String, up: String, down: String) -> Vector2:
	var v := Input.get_vector(left, right, up, down, DEADZONE)
	if v.length() < DEADZONE:
		return Vector2.ZERO
	# Rescale past deadzone so full deflection = 1.
	var mag: float = (v.length() - DEADZONE) / (1.0 - DEADZONE)
	return v.normalized() * clampf(mag, 0.0, 1.0)


func _axis_strength(action: String) -> float:
	if not InputMap.has_action(action):
		return 0.0
	return clampf(Input.get_action_strength(action), 0.0, 1.0)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		_gamepad_recent = true
		var n: String = Input.get_joy_name(device)
		joy_connected.emit(device, n if n != "" else "Controller")
	else:
		joy_disconnected.emit(device)
		if Input.get_connected_joypads().is_empty():
			_gamepad_recent = false
			reset_reticle()
	_emit_active_if_changed()


func _emit_active_if_changed() -> void:
	var now: bool = is_gamepad_active()
	if now != _was_active:
		_was_active = now
		active_changed.emit(now)
