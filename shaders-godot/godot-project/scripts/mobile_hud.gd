# Mobile HUD overlay.
#
# Shows on-screen buttons for actions that have no touch equivalent (speed
# control, photo, undo). Only visible when OS.has_feature("mobile") is true.
# The Main script wires up signals in _setup_mobile_ui().
#
# Layout: bottom-left speed row, bottom-right action cluster. Buttons size
# scales with DisplayServer.screen_get_dpi() so tablets get larger targets.
# Anchored inside DisplayServer.get_display_safe_area() so notches and the
# Android 3-button nav bar don't clip the controls.
#
# Idle dim: HUD fades to 30% modulate after IDLE_DIM_SECONDS of no input;
# the main script calls notify_input() on every touch to keep it lit.

extends Control

signal pause_pressed
signal speed_pressed(scale: float)
signal photo_pressed
signal undo_pressed

var _pause_btn: Button
var _speed_btns: Dictionary = {}
var _photo_btn: Button
var _undo_btn: Button
var _current_speed: float = 1.0
var _is_paused: bool = false

# Per-side container refs so we can re-layout on viewport resize / orientation
# change. (Built once in _ready; offsets re-applied each layout pass.)
var _speed_container: HBoxContainer = null
var _action_container: HBoxContainer = null

# Idle dim state.
var _idle_seconds: float = 0.0
const IDLE_DIM_SECONDS: float = 5.0
const DIM_MODULATE: Color = Color(1, 1, 1, 0.35)
const LIT_MODULATE: Color = Color(1, 1, 1, 1)


func _ready() -> void:
	# Only show on mobile.
	if not (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")):
		visible = false
		set_process(false)
		return

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_speed_row()
	_build_action_row()
	_apply_layout()
	# Re-apply on viewport resize so rotating the device or showing/hiding
	# the system nav bar doesn't leave controls under the gesture pill.
	get_viewport().size_changed.connect(_apply_layout)


func _process(dt: float) -> void:
	# Idle dim: tick when no touch is active. Main script calls
	# notify_input() on every touch to reset the timer.
	_idle_seconds += dt
	if _idle_seconds > IDLE_DIM_SECONDS:
		if modulate != DIM_MODULATE:
			modulate = DIM_MODULATE


# Called by the main script on every touch / pointer event so the HUD stays
# lit while the user is interacting.
func notify_input() -> void:
	_idle_seconds = 0.0
	if modulate != LIT_MODULATE:
		modulate = LIT_MODULATE


# Sizing - DPI-aware so tablets get bigger buttons. Phones (~320dpi) get the
# baseline 56x48; tablets (~160-220dpi physical pixels per dp) get scaled up.
func _btn_size() -> Vector2:
	var dpi: float = float(DisplayServer.screen_get_dpi())
	# dp_to_px = dpi / 160. Clamp to [1.0, 2.0] so very high-dpi phones don't
	# get monster buttons. Tablets typically report ~200-280; we want ~1.4x
	# there. Phones ~300-450 → 1.0x (already at baseline).
	var scale: float = 1.0
	if dpi > 0.0:
		# Larger physical screens (tablets) tend to *under*-report dpi relative
		# to the dp standard, so we invert: low dpi number == big screen.
		# Map dpi 320+ → 1.0x, dpi ≤ 160 → 1.6x.
		scale = clampf(remap(dpi, 320.0, 160.0, 1.0, 1.6), 1.0, 1.6)
	return Vector2(56.0 * scale, 48.0 * scale)


func _font_size() -> int:
	var dpi: float = float(DisplayServer.screen_get_dpi())
	var scale: float = 1.0
	if dpi > 0.0:
		scale = clampf(remap(dpi, 320.0, 160.0, 1.0, 1.4), 1.0, 1.4)
	return int(round(18.0 * scale))


# Safe area in window/viewport coordinates. Falls back to a generous default
# inset on platforms that don't report a safe area.
func _safe_area() -> Rect2:
	var area: Rect2i = DisplayServer.get_display_safe_area()
	var win: Vector2 = get_viewport().get_visible_rect().size
	# DisplayServer reports in physical pixels in some configs; if it's
	# clearly bogus (zero size, or huge), fall back.
	if area.size.x <= 0 or area.size.y <= 0:
		# Default Android nav-bar height ~48dp + status bar ~24dp. Be generous.
		return Rect2(0, 24, win.x, win.y - 72)
	# Scale physical -> logical if needed. We assume DisplayServer returns
	# physical px and viewport is in logical px (Godot's mobile default).
	var scale_x: float = win.x / float(DisplayServer.screen_get_size().x)
	var scale_y: float = win.y / float(DisplayServer.screen_get_size().y)
	if scale_x > 0.0 and scale_y > 0.0:
		return Rect2(
			float(area.position.x) * scale_x,
			float(area.position.y) * scale_y,
			float(area.size.x) * scale_x,
			float(area.size.y) * scale_y,
		)
	return Rect2(area.position, area.size)


func _build_speed_row() -> void:
	# Bottom-left: ⏸ 1× 4× 16×
	_speed_container = HBoxContainer.new()
	_speed_container.add_theme_constant_override("separation", 6)
	_speed_container.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_speed_container)

	_pause_btn = _make_btn("⏸", Color8(220, 180, 80))
	_pause_btn.pressed.connect(func():
		_is_paused = not _is_paused
		_pause_btn.text = "▶" if _is_paused else "⏸"
		pause_pressed.emit())
	_speed_container.add_child(_pause_btn)

	for entry in [
		{"label": "1×", "scale": 1.0},
		{"label": "4×", "scale": 4.0},
		{"label": "16×", "scale": 16.0},
	]:
		var btn := _make_btn(String(entry["label"]), Color8(180, 200, 220))
		var s: float = float(entry["scale"])
		btn.pressed.connect(func():
			_current_speed = s
			_is_paused = false
			_pause_btn.text = "⏸"
			_highlight_speed(s)
			speed_pressed.emit(s))
		_speed_container.add_child(btn)
		_speed_btns[s] = btn
	_highlight_speed(1.0)


func _build_action_row() -> void:
	# Bottom-right: 📷 ↩
	_action_container = HBoxContainer.new()
	_action_container.add_theme_constant_override("separation", 6)
	_action_container.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_action_container)

	_photo_btn = _make_btn("📷", Color8(150, 200, 170))
	_photo_btn.pressed.connect(func(): photo_pressed.emit())
	_action_container.add_child(_photo_btn)

	_undo_btn = _make_btn("↩", Color8(220, 130, 130))
	_undo_btn.pressed.connect(func(): undo_pressed.emit())
	_undo_btn.visible = false  # Only shown in aquascape mode.
	_action_container.add_child(_undo_btn)


# Re-anchor both containers inside the safe area. Called on _ready and again
# on viewport size_changed (rotation, nav-bar show/hide).
func _apply_layout() -> void:
	var safe: Rect2 = _safe_area()
	var btn_h: float = _btn_size().y
	# Bottom edge of buttons - 12px above the safe-area bottom, which leaves
	# clearance for the gesture pill on phones that hide the safe-area bottom
	# inset under their nav bar.
	var bottom_y: float = safe.position.y + safe.size.y - 12.0
	# Speed row: anchored to bottom-left of safe area.
	if _speed_container != null:
		_speed_container.anchor_left = 0.0
		_speed_container.anchor_top = 0.0
		_speed_container.anchor_right = 0.0
		_speed_container.anchor_bottom = 0.0
		_speed_container.offset_left = safe.position.x + 16.0
		_speed_container.offset_top = bottom_y - btn_h
		_speed_container.offset_right = _speed_container.offset_left + 320.0
		_speed_container.offset_bottom = bottom_y
	# Action row: anchored to bottom-right of safe area.
	if _action_container != null:
		var right_x: float = safe.position.x + safe.size.x - 16.0
		_action_container.anchor_left = 0.0
		_action_container.anchor_top = 0.0
		_action_container.anchor_right = 0.0
		_action_container.anchor_bottom = 0.0
		_action_container.offset_left = right_x - 160.0
		_action_container.offset_top = bottom_y - btn_h
		_action_container.offset_right = right_x
		_action_container.offset_bottom = bottom_y


func _make_btn(label: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = _btn_size()
	btn.add_theme_font_size_override("font_size", _font_size())
	btn.add_theme_color_override("font_color", color)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	return btn


func _highlight_speed(active: float) -> void:
	for s in _speed_btns.keys():
		var btn: Button = _speed_btns[s]
		if is_equal_approx(float(s), active):
			btn.modulate = Color(1.3, 1.3, 0.8)
		else:
			btn.modulate = Color(0.7, 0.7, 0.7)


# Called by the main script when aquascape mode toggles.
func set_aquascape_mode(on: bool) -> void:
	if _undo_btn != null:
		_undo_btn.visible = on
