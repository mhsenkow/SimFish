# Settings panel.
#
# Toggled by the O key (or click the gear). Pushes values into the TankConfig
# autoload as the user drags sliders, then Apply reloads the scene so the
# new tank dimensions / substrate / light are actually rebuilt.
#
# Layout is created procedurally so we don't have to maintain a fragile
# tscn node tree of dozens of UI nodes.

extends PanelContainer

signal apply_requested

var _shape_option: OptionButton
var _w_slider: HSlider
var _d_slider: HSlider
var _h_slider: HSlider
var _light_energy: HSlider
var _light_yaw: HSlider
var _light_pitch: HSlider
var _light_warmth: HSlider
var _light_fixture_option: OptionButton
var _light_height: HSlider
var _light_size: HSlider
var _light_height_label: Label
var _light_size_label: Label
var _light_volumetric_check: CheckBox
var _substrate_option: OptionButton
var _substrate_desc: Label
var _preset_option: OptionButton
var _preset_desc: Label
var _w_label: Label
var _d_label: Label
var _h_label: Label
var _light_energy_label: Label
var _light_yaw_label: Label
var _light_pitch_label: Label
var _light_warmth_label: Label


func _ready() -> void:
	_build_ui()
	_pull_from_config()
	visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_O:
			toggle()


func toggle() -> void:
	visible = not visible
	if visible:
		_pull_from_config()


# Build the inner control tree once. We use a VBoxContainer with rows of
# labels + sliders, plus a small header and the apply / close buttons.
func _build_ui() -> void:
	custom_minimum_size = Vector2(420, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	_add_section(vbox, "Tank")
	# Tank shape dropdown.
	var shape_row := HBoxContainer.new()
	vbox.add_child(shape_row)
	var sl := Label.new()
	sl.text = "Shape"
	sl.custom_minimum_size = Vector2(140, 0)
	shape_row.add_child(sl)
	_shape_option = OptionButton.new()
	for entry in [
			{"key": "box",      "label": "Box (rectangle)"},
			{"key": "cube",     "label": "Cube (square)"},
			{"key": "hex",      "label": "Hexagon"},
			{"key": "triangle", "label": "Triangle"},
		]:
		_shape_option.add_item(String(entry["label"]))
		_shape_option.set_item_metadata(_shape_option.item_count - 1, entry["key"])
	_shape_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shape_option.item_selected.connect(func(idx): TankConfig.tank_shape = _shape_option.get_item_metadata(idx))
	shape_row.add_child(_shape_option)

	_w_label = Label.new()
	_w_slider = _add_slider_row(vbox, "Width", 4.0, 24.0, 0.5, _w_label)
	_w_slider.value_changed.connect(func(v): _on_w(v))

	_d_label = Label.new()
	_d_slider = _add_slider_row(vbox, "Depth", 2.0, 14.0, 0.5, _d_label)
	_d_slider.value_changed.connect(func(v): _on_d(v))

	_h_label = Label.new()
	_h_slider = _add_slider_row(vbox, "Height", 4.0, 20.0, 0.5, _h_label)
	_h_slider.value_changed.connect(func(v): _on_h(v))

	_add_section(vbox, "Light")
	_light_energy_label = Label.new()
	_light_energy = _add_slider_row(vbox, "Intensity", 0.0, 1.0, 0.05, _light_energy_label)
	_light_energy.value_changed.connect(func(v): _on_light_energy(v))

	_light_yaw_label = Label.new()
	_light_yaw = _add_slider_row(vbox, "Direction (yaw)", 0.0, 1.0, 0.05, _light_yaw_label)
	_light_yaw.value_changed.connect(func(v): _on_light_yaw(v))

	_light_pitch_label = Label.new()
	_light_pitch = _add_slider_row(vbox, "Direction (pitch)", 0.0, 1.0, 0.05, _light_pitch_label)
	_light_pitch.value_changed.connect(func(v): _on_light_pitch(v))

	_light_warmth_label = Label.new()
	_light_warmth = _add_slider_row(vbox, "Warmth (cool->warm)", 0.0, 1.0, 0.05, _light_warmth_label)
	_light_warmth.value_changed.connect(func(v): _on_light_warmth(v))

	# Fixture selection (bar vs spotlight).
	var fixture_row := HBoxContainer.new()
	vbox.add_child(fixture_row)
	var fl := Label.new()
	fl.text = "Fixture"
	fl.custom_minimum_size = Vector2(140, 0)
	fixture_row.add_child(fl)
	_light_fixture_option = OptionButton.new()
	_light_fixture_option.add_item("Bar (long LED)")
	_light_fixture_option.set_item_metadata(0, "bar")
	_light_fixture_option.add_item("Spotlight (pendant)")
	_light_fixture_option.set_item_metadata(1, "spotlight")
	_light_fixture_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_light_fixture_option.item_selected.connect(func(idx): _on_fixture(idx))
	fixture_row.add_child(_light_fixture_option)

	_light_height_label = Label.new()
	_light_height = _add_slider_row(vbox, "Fixture height", 0.5, 4.0, 0.1, _light_height_label)
	_light_height.value_changed.connect(func(v): _on_light_height(v))

	_light_size_label = Label.new()
	_light_size = _add_slider_row(vbox, "Fixture size", 0.3, 1.0, 0.05, _light_size_label)
	_light_size.value_changed.connect(func(v): _on_light_size(v))

	# Beams toggle.
	_light_volumetric_check = CheckBox.new()
	_light_volumetric_check.text = "Show light beams (god rays)"
	_light_volumetric_check.toggled.connect(func(v): _on_volumetric(v))
	vbox.add_child(_light_volumetric_check)

	# Tank preset selection.
	_add_section(vbox, "Stocking preset")
	_preset_option = OptionButton.new()
	for key in TankConfig.TANK_PRESETS.keys():
		var label: String = TankConfig.TANK_PRESETS[key]["label"]
		_preset_option.add_item(label)
		_preset_option.set_item_metadata(_preset_option.item_count - 1, key)
	_preset_option.item_selected.connect(func(idx): _on_preset(idx))
	vbox.add_child(_preset_option)
	_preset_desc = Label.new()
	_preset_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preset_desc.add_theme_font_size_override("font_size", 11)
	_preset_desc.modulate = Color(1, 1, 1, 0.7)
	vbox.add_child(_preset_desc)

	_add_section(vbox, "Substrate")
	_substrate_option = OptionButton.new()
	for key in TankConfig.SUBSTRATE_PROFILES.keys():
		var label: String = TankConfig.SUBSTRATE_PROFILES[key]["label"]
		_substrate_option.add_item(label)
		_substrate_option.set_item_metadata(_substrate_option.item_count - 1, key)
	_substrate_option.item_selected.connect(func(idx): _on_substrate(idx))
	vbox.add_child(_substrate_option)
	_substrate_desc = Label.new()
	_substrate_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_substrate_desc.add_theme_font_size_override("font_size", 11)
	_substrate_desc.modulate = Color(1, 1, 1, 0.7)
	vbox.add_child(_substrate_desc)

	# Footer buttons.
	var sep := HSeparator.new()
	vbox.add_child(sep)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(hb)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): visible = false)
	hb.add_child(close)
	var apply := Button.new()
	apply.text = "Apply (reload tank)"
	apply.pressed.connect(_on_apply)
	hb.add_child(apply)


func _add_section(parent: Node, label: String) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 13)
	l.modulate = Color(0.8, 0.85, 1.0)
	parent.add_child(l)


func _add_slider_row(parent: Node, name: String, min_val: float, max_val: float,
		step: float, value_label: Label) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := Label.new()
	l.text = name
	l.custom_minimum_size = Vector2(140, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = min_val
	s.max_value = max_val
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(s)
	value_label.custom_minimum_size = Vector2(50, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return s


# ---- Push/pull TankConfig ----

func _pull_from_config() -> void:
	# Tank shape dropdown.
	for i in _shape_option.item_count:
		if _shape_option.get_item_metadata(i) == TankConfig.tank_shape:
			_shape_option.select(i)
			break
	_w_slider.value = TankConfig.tank_half_w * 2.0
	_d_slider.value = TankConfig.tank_half_d * 2.0
	_h_slider.value = TankConfig.tank_height
	_light_energy.value = TankConfig.light_energy
	_light_yaw.value = TankConfig.light_yaw
	_light_pitch.value = TankConfig.light_pitch
	_light_warmth.value = TankConfig.light_warmth
	_light_height.value = TankConfig.light_height
	_light_size.value = TankConfig.light_size
	_light_volumetric_check.button_pressed = TankConfig.light_volumetric
	# Pick the fixture option matching current type.
	for i in _light_fixture_option.item_count:
		if _light_fixture_option.get_item_metadata(i) == TankConfig.light_fixture:
			_light_fixture_option.select(i)
			break
	_update_value_labels()
	# Pick the option matching current substrate.
	for i in _substrate_option.item_count:
		if _substrate_option.get_item_metadata(i) == TankConfig.substrate_type:
			_substrate_option.select(i)
			break
	_update_substrate_desc()
	# Pick the option matching current preset.
	for i in _preset_option.item_count:
		if _preset_option.get_item_metadata(i) == TankConfig.tank_preset:
			_preset_option.select(i)
			break
	_update_preset_desc()


func _update_value_labels() -> void:
	_w_label.text = "%.1f" % _w_slider.value
	_d_label.text = "%.1f" % _d_slider.value
	_h_label.text = "%.1f" % _h_slider.value
	_light_energy_label.text = "%.2f" % _light_energy.value
	_light_yaw_label.text = "%.2f" % _light_yaw.value
	_light_pitch_label.text = "%.2f" % _light_pitch.value
	_light_warmth_label.text = "%.2f" % _light_warmth.value
	_light_height_label.text = "%.1f" % _light_height.value
	_light_size_label.text = "%.2f" % _light_size.value


func _on_light_height(v: float) -> void:
	TankConfig.light_height = v
	_light_height_label.text = "%.1f" % v


func _on_light_size(v: float) -> void:
	TankConfig.light_size = v
	_light_size_label.text = "%.2f" % v


func _on_fixture(idx: int) -> void:
	TankConfig.light_fixture = _light_fixture_option.get_item_metadata(idx)


func _on_volumetric(v: bool) -> void:
	TankConfig.light_volumetric = v


func _update_substrate_desc() -> void:
	var key: String = TankConfig.substrate_type
	var profile: Dictionary = TankConfig.SUBSTRATE_PROFILES.get(key, {})
	_substrate_desc.text = profile.get("description", "")


func _on_w(v: float) -> void:
	TankConfig.tank_half_w = v * 0.5
	_w_label.text = "%.1f" % v


func _on_d(v: float) -> void:
	TankConfig.tank_half_d = v * 0.5
	_d_label.text = "%.1f" % v


func _on_h(v: float) -> void:
	TankConfig.tank_height = v
	_h_label.text = "%.1f" % v


func _on_light_energy(v: float) -> void:
	TankConfig.light_energy = v
	_light_energy_label.text = "%.2f" % v


func _on_light_yaw(v: float) -> void:
	TankConfig.light_yaw = v
	_light_yaw_label.text = "%.2f" % v


func _on_light_pitch(v: float) -> void:
	TankConfig.light_pitch = v
	_light_pitch_label.text = "%.2f" % v


func _on_light_warmth(v: float) -> void:
	TankConfig.light_warmth = v
	_light_warmth_label.text = "%.2f" % v


func _on_substrate(idx: int) -> void:
	TankConfig.substrate_type = _substrate_option.get_item_metadata(idx)
	_update_substrate_desc()


func _on_preset(idx: int) -> void:
	TankConfig.tank_preset = _preset_option.get_item_metadata(idx)
	_update_preset_desc()


func _update_preset_desc() -> void:
	var key: String = TankConfig.tank_preset
	var preset: Dictionary = TankConfig.TANK_PRESETS.get(key, {})
	var desc: String = preset.get("description", "")
	if key != "custom":
		var stocking: String = "Stocking: %d glassdarts, %d mudsifters, %d betta, %d shrimp" % [
			preset.get("glassdarts", 0),
			preset.get("mudsifters", 0),
			preset.get("betta", 0),
			preset.get("shrimp", 0),
		]
		var spread: String = "Phenotype spread: %.1f×" % float(preset.get("phenotype_spread", 1.0))
		desc = desc + "\n" + stocking + " · " + spread
	_preset_desc.text = desc


func _on_apply() -> void:
	# Preserve camera before the reload so the view doesn't snap back to
	# defaults. Main node has save_camera_state() that stashes yaw/pitch/etc
	# into TankConfig + saves to disk.
	var main := get_tree().current_scene
	if main != null and main.has_method("save_camera_state"):
		main.save_camera_state()
	TankConfig.save_to_disk()
	apply_requested.emit()
	get_tree().reload_current_scene()
