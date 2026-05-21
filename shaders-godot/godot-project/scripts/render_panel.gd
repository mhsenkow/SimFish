# Render parameters panel.
#
# Sibling to settings_panel.gd - exposes the 3D rendering pipeline knobs:
# SubViewport resolution, dither strength, palette toggle, fog parameters,
# camera FOV, MSAA. Most apply via scene reload (Apply button); a few like
# fog density + FOV update live as you drag.

extends PanelContainer


var _res_option: OptionButton
var _dither: HSlider
var _dither_label: Label
var _palette_check: CheckBox
var _fog_density: HSlider
var _fog_density_label: Label
var _fog_anisotropy: HSlider
var _fog_anisotropy_label: Label
var _fog_ambient: HSlider
var _fog_ambient_label: Label
var _fov: HSlider
var _fov_label: Label
var _msaa_option: OptionButton

const RESOLUTIONS: Array = [
	{"label": "256x144 (chunky)", "w": 256, "h": 144},
	{"label": "384x216", "w": 384, "h": 216},
	{"label": "512x288 (default)", "w": 512, "h": 288},
	{"label": "768x432", "w": 768, "h": 432},
	{"label": "1024x576 (smooth)", "w": 1024, "h": 576},
]
const MSAA_LABELS: Array[String] = ["Off", "2x", "4x", "8x"]


func _ready() -> void:
	_build_ui()
	_pull_from_config()
	visible = false


func _input(event: InputEvent) -> void:
	# R toggles this panel. (O toggles the settings panel.) We use unhandled
	# input so the corner button can still toggle programmatically.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			toggle()


func toggle() -> void:
	visible = not visible
	if visible:
		_pull_from_config()


func _build_ui() -> void:
	custom_minimum_size = Vector2(380, 0)
	# Outer layout: title at the top, scrolling section list in the middle,
	# always-visible footer (Close / Apply) at the bottom. The PanelContainer
	# anchors to fill the screen vertically so the scroll area gets as much
	# height as possible.
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)

	var title := Label.new()
	title.text = "Rendering"
	title.add_theme_font_size_override("font_size", 18)
	outer.add_child(title)

	# Scrolling body.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Internal resolution.
	_add_section(vbox, "Resolution")
	_res_option = OptionButton.new()
	for r in RESOLUTIONS:
		_res_option.add_item(String(r["label"]))
	_res_option.item_selected.connect(func(idx): _on_resolution(idx))
	vbox.add_child(_res_option)

	# Palette / dither section.
	_add_section(vbox, "Palette quantize")
	_palette_check = CheckBox.new()
	_palette_check.text = "Enable palette quantization"
	_palette_check.toggled.connect(func(v): TankConfig.palette_enabled = v)
	vbox.add_child(_palette_check)
	_dither_label = Label.new()
	_dither = _add_slider_row(vbox, "Dither strength", 0.0, 1.0, 0.05, _dither_label)
	_dither.value_changed.connect(func(v): _on_dither(v))

	# Fog section (volumetric).
	_add_section(vbox, "Volumetric fog")
	_fog_density_label = Label.new()
	_fog_density = _add_slider_row(vbox, "Density", 0.0, 0.08, 0.005, _fog_density_label)
	_fog_density.value_changed.connect(func(v): _on_fog_density(v))
	_fog_anisotropy_label = Label.new()
	_fog_anisotropy = _add_slider_row(vbox, "Anisotropy", -0.9, 0.9, 0.05, _fog_anisotropy_label)
	_fog_anisotropy.value_changed.connect(func(v): _on_fog_anisotropy(v))
	_fog_ambient_label = Label.new()
	_fog_ambient = _add_slider_row(vbox, "Ambient inject", 0.0, 0.5, 0.02, _fog_ambient_label)
	_fog_ambient.value_changed.connect(func(v): _on_fog_ambient(v))

	# Camera section.
	_add_section(vbox, "Camera")
	_fov_label = Label.new()
	_fov = _add_slider_row(vbox, "Field of view", 30.0, 90.0, 1.0, _fov_label)
	_fov.value_changed.connect(func(v): _on_fov(v))

	# Quality section.
	_add_section(vbox, "Quality")
	var msaa_row := HBoxContainer.new()
	vbox.add_child(msaa_row)
	var ml := Label.new()
	ml.text = "MSAA"
	ml.custom_minimum_size = Vector2(140, 0)
	msaa_row.add_child(ml)
	_msaa_option = OptionButton.new()
	for label in MSAA_LABELS:
		_msaa_option.add_item(label)
	_msaa_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msaa_option.item_selected.connect(func(idx): TankConfig.msaa = idx)
	msaa_row.add_child(_msaa_option)

	# Footer buttons - attached to `outer` (NOT `vbox`) so Close + Apply
	# stay pinned at the bottom of the panel below the scroll area.
	var sep := HSeparator.new()
	outer.add_child(sep)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	outer.add_child(hb)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): visible = false)
	hb.add_child(close)
	var apply := Button.new()
	apply.text = "Apply (reload)"
	apply.pressed.connect(_on_apply)
	hb.add_child(apply)


func _add_section(parent: Node, label: String) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 13)
	l.modulate = Color(0.85, 0.92, 1.0)
	parent.add_child(l)


func _add_slider_row(parent: Node, label: String, min_val: float, max_val: float,
		step: float, value_label: Label) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(140, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = min_val
	s.max_value = max_val
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(s)
	value_label.custom_minimum_size = Vector2(55, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return s


func _pull_from_config() -> void:
	# Resolution match.
	for i in RESOLUTIONS.size():
		var r: Dictionary = RESOLUTIONS[i]
		if int(r["w"]) == TankConfig.render_width and int(r["h"]) == TankConfig.render_height:
			_res_option.select(i)
			break
	_dither.value = TankConfig.dither_strength
	_palette_check.button_pressed = TankConfig.palette_enabled
	_fog_density.value = TankConfig.fog_density
	_fog_anisotropy.value = TankConfig.fog_anisotropy
	_fog_ambient.value = TankConfig.fog_ambient_inject
	_fov.value = TankConfig.camera_fov
	_msaa_option.select(int(TankConfig.msaa))
	_update_labels()


func _update_labels() -> void:
	_dither_label.text = "%.2f" % _dither.value
	_fog_density_label.text = "%.3f" % _fog_density.value
	_fog_anisotropy_label.text = "%.2f" % _fog_anisotropy.value
	_fog_ambient_label.text = "%.2f" % _fog_ambient.value
	_fov_label.text = "%d°" % int(_fov.value)


func _on_resolution(idx: int) -> void:
	var r: Dictionary = RESOLUTIONS[idx]
	TankConfig.render_width = int(r["w"])
	TankConfig.render_height = int(r["h"])


func _on_dither(v: float) -> void:
	TankConfig.dither_strength = v
	_dither_label.text = "%.2f" % v
	# Live update: push into the active display shader so the user sees it.
	var main := get_tree().current_scene
	if main != null:
		var display := main.get_node_or_null("Display")
		if display != null and display.material is ShaderMaterial:
			(display.material as ShaderMaterial).set_shader_parameter("dither_strength", v)


func _on_fog_density(v: float) -> void:
	TankConfig.fog_density = v
	_fog_density_label.text = "%.3f" % v
	_apply_fog_live()


func _on_fog_anisotropy(v: float) -> void:
	TankConfig.fog_anisotropy = v
	_fog_anisotropy_label.text = "%.2f" % v
	_apply_fog_live()


func _on_fog_ambient(v: float) -> void:
	TankConfig.fog_ambient_inject = v
	_fog_ambient_label.text = "%.2f" % v
	_apply_fog_live()


func _apply_fog_live() -> void:
	var main := get_tree().current_scene
	if main == null:
		return
	var we := main.get_node_or_null("SubViewport/World/WorldEnvironment")
	if we != null and we.environment != null:
		we.environment.volumetric_fog_density = TankConfig.fog_density
		we.environment.volumetric_fog_anisotropy = TankConfig.fog_anisotropy
		we.environment.volumetric_fog_ambient_inject = TankConfig.fog_ambient_inject


func _on_fov(v: float) -> void:
	TankConfig.camera_fov = v
	_fov_label.text = "%d°" % int(v)
	# Live: update the active camera.
	var main := get_tree().current_scene
	if main == null:
		return
	var cam := main.get_node_or_null("SubViewport/World/Camera3D")
	if cam != null:
		cam.fov = v


func _on_apply() -> void:
	# Preserve current camera view before the scene reload.
	var main := get_tree().current_scene
	if main != null and main.has_method("save_camera_state"):
		main.save_camera_state()
	TankConfig.save_to_disk()
	# Reload scene so resolution + MSAA + palette toggle take effect.
	get_tree().reload_current_scene()
