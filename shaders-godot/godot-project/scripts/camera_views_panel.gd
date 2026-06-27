# Camera Views panel.
#
# Compact docked panel that exposes camera-framing controls in one place:
#   - Preset views (Front, Side, Top, 3/4, Reset)
#   - 3 user-saveable view slots ("Save A / B / C" + "Recall A / B / C")
#   - Auto-orbit toggle + speed slider
#   - FOV slider
#   - Follow random fish / stop following
#
# Owned by main.gd; the panel calls back into main via a small API surface
# (apply_preset / save_view_slot / recall_view_slot / set_auto_orbit /
# set_fov / follow_random_fish / clear_follow). All view state lives in
# main.gd's camera vars; the panel is a thin UI layer with no sim refs.
#
# Layout adapts to portrait/landscape: in portrait the panel docks at the
# bottom of the safe area, with controls in a vertical stack; in landscape
# it's a sidebar that doesn't fight the existing settings/render panels.

extends PanelContainer
class_name CameraViewsPanel

const PRESET_FRONT := "front"
const PRESET_SIDE := "side"
const PRESET_TOP := "top"
const PRESET_THREE_QUARTER := "three_quarter"
const PRESET_RESET := "reset"

const PROJECTION_PERSPECTIVE := "perspective"
const PROJECTION_ORTHOGRAPHIC := "orthographic"
const PROJECTION_ISOMETRIC := "isometric"
const PROJECTION_DIMETRIC := "dimetric"
const PROJECTION_TOP_DOWN := "top_down_ortho"

const NUM_VIEW_SLOTS: int = 3

# Reference to main.gd. Set by main on instantiation. The panel talks back
# through duck-typed method calls so we don't drag a class dependency here.
var main_ref: Node = null

var _auto_orbit_check: CheckBox = null
var _auto_orbit_speed: HSlider = null
var _fov_slider: HSlider = null
var _fov_label: Label = null
var _fov_row_label: Label = null
var _follow_check: CheckBox = null
var _projection_option: OptionButton = null


func _ready() -> void:
	PanelTheme.apply_panel_chrome(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(260, 0)
	_build_ui()
	visible = false


func _build_ui() -> void:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)

	outer.add_child(PanelTheme.make_title("Camera Views"))
	outer.add_child(PanelTheme.make_rule())

	# --- Preset row 1: Front / Side ---
	_add_section_label(outer, "Presets")
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	outer.add_child(row1)
	row1.add_child(_make_preset_btn("Front", PRESET_FRONT))
	row1.add_child(_make_preset_btn("Side", PRESET_SIDE))
	# Row 2: Top / 3/4
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	outer.add_child(row2)
	row2.add_child(_make_preset_btn("Top", PRESET_TOP))
	row2.add_child(_make_preset_btn("3/4", PRESET_THREE_QUARTER))
	# Reset on its own row, slightly emphasized.
	var reset := PanelTheme.make_primary_button("Reset view")
	reset.tooltip_text = "Frame the tank using the default for its shape and orientation"
	reset.pressed.connect(_on_reset_pressed)
	outer.add_child(reset)

	# --- Projection mode ---
	# Perspective is the classic 3D look. Orthographic is parallel
	# projection (no foreshortening) — useful for diagram-style or
	# pixel-art looks. Isometric is orthographic with a fixed 30°/45°
	# camera, the classic game-art angle where all 3 axes foreshorten
	# equally. Dimetric is similar but 2:1 (the SNES/Diablo look).
	# Top-down ortho is bird's-eye in parallel projection — clean for
	# cylinder tanks. Each projection mode also adjusts the FOV/size
	# slider's meaning (size in world units for ortho).
	outer.add_child(PanelTheme.make_rule())
	_add_section_label(outer, "Projection")
	_projection_option = OptionButton.new()
	_projection_option.tooltip_text = "Switch how the 3D scene is flattened to 2D"
	_projection_option.add_item("Perspective (default)")
	_projection_option.set_item_metadata(0, PROJECTION_PERSPECTIVE)
	_projection_option.add_item("Orthographic (parallel)")
	_projection_option.set_item_metadata(1, PROJECTION_ORTHOGRAPHIC)
	_projection_option.add_item("Isometric (30°/45°)")
	_projection_option.set_item_metadata(2, PROJECTION_ISOMETRIC)
	_projection_option.add_item("Dimetric (2:1 game-art)")
	_projection_option.set_item_metadata(3, PROJECTION_DIMETRIC)
	_projection_option.add_item("Top-down (orthographic)")
	_projection_option.set_item_metadata(4, PROJECTION_TOP_DOWN)
	_projection_option.item_selected.connect(_on_projection_selected)
	outer.add_child(_projection_option)

	# --- Saved view slots ---
	outer.add_child(PanelTheme.make_rule())
	_add_section_label(outer, "Saved views")
	for i in NUM_VIEW_SLOTS:
		var slot_row := HBoxContainer.new()
		slot_row.add_theme_constant_override("separation", 6)
		outer.add_child(slot_row)
		var slot_label := Label.new()
		slot_label.text = "Slot %s" % char(65 + i)
		slot_label.custom_minimum_size = Vector2(56, 0)
		slot_label.add_theme_font_size_override("font_size", 13)
		slot_row.add_child(slot_label)
		var save_btn := PanelTheme.make_secondary_button("Save")
		save_btn.tooltip_text = "Save the current camera framing to slot %s" % char(65 + i)
		var slot_idx_save: int = i
		save_btn.pressed.connect(func(): _on_save_slot(slot_idx_save))
		slot_row.add_child(save_btn)
		var recall_btn := PanelTheme.make_secondary_button("Recall")
		recall_btn.tooltip_text = "Jump to the view saved in slot %s" % char(65 + i)
		var slot_idx_recall: int = i
		recall_btn.pressed.connect(func(): _on_recall_slot(slot_idx_recall))
		slot_row.add_child(recall_btn)

	# --- Motion: auto-orbit + follow ---
	outer.add_child(PanelTheme.make_rule())
	_add_section_label(outer, "Motion")
	_auto_orbit_check = CheckBox.new()
	_auto_orbit_check.text = "Auto-orbit (cinematic spin)"
	_auto_orbit_check.tooltip_text = "Slowly rotate the camera around the tank"
	_auto_orbit_check.toggled.connect(_on_auto_orbit_toggled)
	outer.add_child(_auto_orbit_check)
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 6)
	outer.add_child(speed_row)
	var speed_lbl := Label.new()
	speed_lbl.text = "Speed"
	speed_lbl.custom_minimum_size = Vector2(56, 0)
	speed_lbl.add_theme_font_size_override("font_size", 13)
	speed_row.add_child(speed_lbl)
	_auto_orbit_speed = HSlider.new()
	_auto_orbit_speed.min_value = 0.02
	_auto_orbit_speed.max_value = 0.4
	_auto_orbit_speed.step = 0.01
	_auto_orbit_speed.value = 0.08
	_auto_orbit_speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_auto_orbit_speed.value_changed.connect(_on_auto_orbit_speed_changed)
	speed_row.add_child(_auto_orbit_speed)

	_follow_check = CheckBox.new()
	_follow_check.text = "Follow a random fish"
	_follow_check.tooltip_text = "Camera tracks a random fish; uncheck to release"
	_follow_check.toggled.connect(_on_follow_toggled)
	outer.add_child(_follow_check)

	# --- Lens ---
	outer.add_child(PanelTheme.make_rule())
	_add_section_label(outer, "Lens")
	var fov_row := HBoxContainer.new()
	fov_row.add_theme_constant_override("separation", 6)
	outer.add_child(fov_row)
	_fov_row_label = Label.new()
	_fov_row_label.text = "FOV"
	_fov_row_label.custom_minimum_size = Vector2(56, 0)
	_fov_row_label.add_theme_font_size_override("font_size", 13)
	fov_row.add_child(_fov_row_label)
	_fov_slider = HSlider.new()
	_fov_slider.min_value = 24.0
	_fov_slider.max_value = 90.0
	_fov_slider.step = 1.0
	_fov_slider.value = 55.0
	_fov_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fov_slider.value_changed.connect(_on_fov_changed)
	fov_row.add_child(_fov_slider)
	_fov_label = Label.new()
	_fov_label.text = "55°"
	_fov_label.custom_minimum_size = Vector2(40, 0)
	_fov_label.add_theme_font_size_override("font_size", 12)
	fov_row.add_child(_fov_label)

	# --- Close ---
	outer.add_child(PanelTheme.make_rule())
	var close := PanelTheme.make_close_button(func(): visible = false)
	outer.add_child(close)


func _add_section_label(parent: Node, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text.to_upper()
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color8(140, 170, 210))
	parent.add_child(lbl)


func _make_preset_btn(label: String, preset_id: String) -> Button:
	var b := PanelTheme.make_secondary_button(label)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = "Snap the camera to the %s view" % label.to_lower()
	b.pressed.connect(func(): _on_preset_pressed(preset_id))
	return b


# Pull live camera state from main into the panel widgets. Called when
# the panel becomes visible so the toggles reflect reality.
func sync_from_main() -> void:
	if main_ref == null:
		return
	var auto_orb: bool = bool(main_ref.get("_auto_orbit") if main_ref.get("_auto_orbit") != null else false)
	if _auto_orbit_check != null:
		_auto_orbit_check.set_pressed_no_signal(auto_orb)
	var fov_v: float = 55.0
	if main_ref.get("camera") != null and main_ref.camera != null:
		fov_v = float(main_ref.camera.fov)
	if _fov_slider != null:
		_fov_slider.set_value_no_signal(fov_v)
		_fov_label.text = "%d°" % int(fov_v)
	var following: bool = main_ref.get("_follow_target") != null
	if _follow_check != null:
		_follow_check.set_pressed_no_signal(following)
	# Projection: pull current mode and reflect it in the dropdown +
	# reconfigure the slider for degrees vs world units accordingly.
	if _projection_option != null and main_ref.has_method("get_camera_projection_id"):
		var proj_id: String = String(main_ref.get_camera_projection_id())
		for i in _projection_option.item_count:
			if String(_projection_option.get_item_metadata(i)) == proj_id:
				_projection_option.select(i)
				break
		_refresh_fov_slider_for_projection(proj_id)


# --- Button handlers — duck-typed calls into main ---

func _on_preset_pressed(preset_id: String) -> void:
	if main_ref == null:
		return
	if main_ref.has_method("apply_camera_preset"):
		main_ref.apply_camera_preset(preset_id)


func _on_reset_pressed() -> void:
	if main_ref != null and main_ref.has_method("_reset_camera_to_default"):
		main_ref._reset_camera_to_default()


func _on_save_slot(idx: int) -> void:
	if main_ref != null and main_ref.has_method("save_camera_view_slot"):
		main_ref.save_camera_view_slot(idx)


func _on_recall_slot(idx: int) -> void:
	if main_ref != null and main_ref.has_method("recall_camera_view_slot"):
		main_ref.recall_camera_view_slot(idx)


func _on_auto_orbit_toggled(on: bool) -> void:
	if main_ref == null:
		return
	main_ref.set("_auto_orbit", on)


func _on_auto_orbit_speed_changed(v: float) -> void:
	if main_ref != null and main_ref.has_method("set_auto_orbit_speed"):
		main_ref.set_auto_orbit_speed(v)


func _on_follow_toggled(on: bool) -> void:
	if main_ref == null:
		return
	if on and main_ref.has_method("follow_random_fish"):
		main_ref.follow_random_fish()
	elif not on and main_ref.has_method("clear_follow_target"):
		main_ref.clear_follow_target()


func _on_fov_changed(v: float) -> void:
	if main_ref == null:
		return
	# Slider doubles as ortho-size in non-perspective projections.
	var is_perspective: bool = true
	if main_ref.has_method("get_camera_projection_id"):
		is_perspective = String(main_ref.get_camera_projection_id()) == PROJECTION_PERSPECTIVE
	if is_perspective:
		if _fov_label != null:
			_fov_label.text = "%d°" % int(v)
		if main_ref.has_method("set_camera_fov"):
			main_ref.set_camera_fov(v)
	else:
		if _fov_label != null:
			_fov_label.text = "%.1f" % v
		if main_ref.has_method("set_camera_ortho_size"):
			main_ref.set_camera_ortho_size(v)


func _on_projection_selected(idx: int) -> void:
	if main_ref == null or _projection_option == null:
		return
	var proj_id: String = String(_projection_option.get_item_metadata(idx))
	if main_ref.has_method("apply_camera_projection"):
		main_ref.apply_camera_projection(proj_id)
	# Reconfigure the FOV slider for the new projection mode's units.
	_refresh_fov_slider_for_projection(proj_id)


# Switch the FOV/size slider between degrees (perspective) and world units
# (orthographic). Pulls the live value from the camera so the slider sits
# at the right starting position when the user opens the panel after an
# ortho switch.
func _refresh_fov_slider_for_projection(proj_id: String) -> void:
	if _fov_slider == null or main_ref == null:
		return
	var is_perspective: bool = proj_id == PROJECTION_PERSPECTIVE
	if is_perspective:
		_fov_slider.min_value = 24.0
		_fov_slider.max_value = 90.0
		_fov_slider.step = 1.0
		var cur_fov: float = 55.0
		if main_ref.get("camera") != null and main_ref.camera != null:
			cur_fov = float(main_ref.camera.fov)
		_fov_slider.set_value_no_signal(cur_fov)
		if _fov_row_label != null:
			_fov_row_label.text = "FOV"
		if _fov_label != null:
			_fov_label.text = "%d°" % int(cur_fov)
	else:
		_fov_slider.min_value = 4.0
		_fov_slider.max_value = 60.0
		_fov_slider.step = 0.5
		var cur_size: float = 18.0
		if main_ref.get("camera") != null and main_ref.camera != null:
			cur_size = float(main_ref.camera.size)
		_fov_slider.set_value_no_signal(cur_size)
		if _fov_row_label != null:
			_fov_row_label.text = "Size"
		if _fov_label != null:
			_fov_label.text = "%.1f" % cur_size
