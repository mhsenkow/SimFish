# Speed dock + mobile action HUD.
#
# The bottom-left speed row (pause + 1× / 4× / 16×) lives inside FooterBar
# on every platform so sim speed is always one tap away — including focus
# mode where the shortcut legend is hidden but speed controls stay.
#
# The bottom-right action cluster (camera, residents, photo, undo) is
# mobile-only. Desktop keeps keyboard shortcuts for those actions.
#
# Layout: speed row in FooterBar; bottom-right action cluster (mobile).
# Buttons size scales with DisplayServer.screen_get_dpi() on touch devices.
#
# Idle dim (mobile only): HUD fades to 30% modulate after IDLE_DIM_SECONDS
# of no input; main.gd calls notify_input() on every touch to keep it lit.

extends Control

@export var footer_speed_slot: NodePath

signal pause_pressed
signal speed_pressed(scale: float)
signal photo_pressed
signal undo_pressed
signal camera_views_pressed
signal residents_pressed

var _pause_btn: Button
var _speed_btns: Dictionary = {}
var _photo_btn: Button
var _undo_btn: Button
var _camera_views_btn: Button
var _residents_btn: Button
var _is_mobile: bool = false
var _immersive_mode: bool = false

var _speed_container: HBoxContainer = null
var _action_container: HBoxContainer = null

var _idle_seconds: float = 0.0
const IDLE_DIM_SECONDS: float = 5.0
const DIM_MODULATE: Color = Color(1, 1, 1, 0.35)
const LIT_MODULATE: Color = Color(1, 1, 1, 1)

const SPEED_STEPS: Array = [
	{"label": "1×", "scale": 1.0},
	{"label": "4×", "scale": 4.0},
	{"label": "16×", "scale": 16.0},
]


func _ready() -> void:
	_is_mobile = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_speed_row()
	if _is_mobile:
		_build_action_row()
		set_process(true)
	_apply_layout()
	get_viewport().size_changed.connect(_apply_layout)


func _process(dt: float) -> void:
	if not _is_mobile:
		return
	_idle_seconds += dt
	if _idle_seconds > IDLE_DIM_SECONDS:
		if modulate != DIM_MODULATE:
			modulate = DIM_MODULATE


func notify_input() -> void:
	_idle_seconds = 0.0
	if modulate != LIT_MODULATE:
		modulate = LIT_MODULATE


# Focus mode hides the mobile action cluster; speed dock stays in FooterBar.
func set_immersive_mode(on: bool) -> void:
	_immersive_mode = on
	if _action_container != null:
		_action_container.visible = not on
	visible = true


# Keep button highlights in sync when speed changes via keyboard or code.
func sync_time_scale(ts: float) -> void:
	if _pause_btn == null:
		return
	if ts <= 0.0:
		_pause_btn.text = UiIcons.mobile_hud_label("play")
		for s in _speed_btns.keys():
			PanelTheme.style_hud_toggle_button(_speed_btns[s], false)
			_speed_btns[s].modulate = Color(0.65, 0.65, 0.65)
		return
	_pause_btn.text = UiIcons.mobile_hud_label("pause")
	var best_key: float = 1.0
	var best_diff: float = INF
	for s in _speed_btns.keys():
		var diff: float = absf(float(s) - ts)
		if diff < best_diff:
			best_diff = diff
			best_key = float(s)
	for s in _speed_btns.keys():
		_speed_btns[s].modulate = Color.WHITE
	_highlight_speed(best_key)


func _btn_size() -> Vector2:
	if not _is_mobile:
		return Vector2(44, 34)
	var dpi: float = float(DisplayServer.screen_get_dpi())
	var sc: float = 1.0
	if dpi > 0.0:
		sc = clampf(remap(dpi, 320.0, 160.0, 1.0, 1.6), 1.0, 1.6)
	return Vector2(56.0 * sc, 48.0 * sc)


func _font_size() -> int:
	if not _is_mobile:
		return 14
	var dpi: float = float(DisplayServer.screen_get_dpi())
	var sc: float = 1.0
	if dpi > 0.0:
		sc = clampf(remap(dpi, 320.0, 160.0, 1.0, 1.4), 1.0, 1.4)
	return int(round(18.0 * sc))


func _safe_area() -> Rect2:
	var area: Rect2i = DisplayServer.get_display_safe_area()
	var win: Vector2 = get_viewport().get_visible_rect().size
	if area.size.x <= 0 or area.size.y <= 0:
		var bottom_pad: float = 72.0 if _is_mobile else 16.0
		return Rect2(0, 24, win.x, win.y - bottom_pad)
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
	var slot: Node = get_node_or_null(footer_speed_slot) if footer_speed_slot != NodePath("") else null
	_speed_container = HBoxContainer.new()
	_speed_container.add_theme_constant_override("separation", 6)
	_speed_container.mouse_filter = Control.MOUSE_FILTER_STOP
	if slot != null:
		slot.add_child(_speed_container)
	else:
		add_child(_speed_container)

	_pause_btn = _make_btn(UiIcons.mobile_hud_label("pause"), Color8(220, 180, 80))
	_pause_btn.tooltip_text = "Pause / resume the simulation (P)"
	_pause_btn.pressed.connect(func():
		_buzz(18)
		pause_pressed.emit())
	_speed_container.add_child(_pause_btn)

	for entry in SPEED_STEPS:
		var btn := _make_btn(String(entry["label"]), Color8(180, 200, 220))
		var s: float = float(entry["scale"])
		btn.tooltip_text = "Run sim at %s speed" % String(entry["label"])
		btn.pressed.connect(func():
			_buzz(12)
			speed_pressed.emit(s))
		_speed_container.add_child(btn)
		_speed_btns[s] = btn
	_highlight_speed(1.0)


func _build_action_row() -> void:
	_action_container = HBoxContainer.new()
	_action_container.add_theme_constant_override("separation", 6)
	_action_container.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_action_container)

	_camera_views_btn = _make_btn("CAM", Color8(180, 210, 240))
	_camera_views_btn.tooltip_text = "Open Camera Views — presets, saved views, FOV, auto-orbit"
	_camera_views_btn.pressed.connect(func():
		_buzz(14)
		camera_views_pressed.emit())
	_action_container.add_child(_camera_views_btn)

	_residents_btn = _make_btn("👥", Color8(200, 200, 240))
	_residents_btn.tooltip_text = "Residents — follow & favorite your creatures"
	_residents_btn.pressed.connect(func():
		_buzz(14)
		residents_pressed.emit())
	_action_container.add_child(_residents_btn)

	_photo_btn = _make_btn(UiIcons.mobile_hud_label("photo"), Color8(150, 200, 170))
	_photo_btn.tooltip_text = "Take a screenshot of the tank"
	_photo_btn.pressed.connect(func():
		_buzz(25)
		photo_pressed.emit())
	_action_container.add_child(_photo_btn)

	_undo_btn = _make_btn(UiIcons.mobile_hud_label("undo"), Color8(220, 130, 130))
	_undo_btn.tooltip_text = "Undo the last aquascape change"
	_undo_btn.pressed.connect(func():
		_buzz(15)
		undo_pressed.emit())
	_undo_btn.visible = false
	_action_container.add_child(_undo_btn)


func _apply_layout() -> void:
	if _action_container == null:
		return
	var safe: Rect2 = _safe_area()
	var btn_size: Vector2 = _btn_size()
	var win: Vector2 = get_viewport().get_visible_rect().size
	var is_portrait: bool = _is_mobile and win.y > win.x
	var bottom_extra: float = PanelTheme.RAIL_BOTTOM_HEIGHT if is_portrait else 0.0
	# Sit above the FooterBar dock (speed controls live inside it).
	var footer_clearance: float = 52.0
	var bottom_y: float = safe.position.y + safe.size.y - footer_clearance - 12.0 - bottom_extra
	var right_x: float = safe.position.x + safe.size.x - 16.0
	_action_container.anchor_left = 0.0
	_action_container.anchor_top = 0.0
	_action_container.anchor_right = 0.0
	_action_container.anchor_bottom = 0.0
	var action_w: float = btn_size.x * 3.0 + 6.0 * 2.0 + 8.0
	_action_container.offset_left = right_x - action_w
	_action_container.offset_top = bottom_y - btn_size.y
	_action_container.offset_right = right_x
	_action_container.offset_bottom = bottom_y


func _make_btn(label: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = _btn_size()
	btn.add_theme_font_size_override("font_size", _font_size())
	btn.add_theme_color_override("font_color", color)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	PanelTheme.style_hud_toggle_button(btn, false)
	return btn


func _highlight_speed(active: float) -> void:
	for s in _speed_btns.keys():
		var btn: Button = _speed_btns[s]
		PanelTheme.style_hud_toggle_button(btn, is_equal_approx(float(s), active))


func set_aquascape_mode(on: bool) -> void:
	if _undo_btn != null:
		_undo_btn.visible = on


func _buzz(duration_ms: int) -> void:
	if _is_mobile:
		Input.vibrate_handheld(duration_ms)
