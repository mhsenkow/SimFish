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

var _w_slider: HSlider
var _d_slider: HSlider
var _h_slider: HSlider
var _light_energy: HSlider
var _light_yaw: HSlider
var _light_pitch: HSlider
var _light_warmth: HSlider
var _substrate_option: OptionButton
var _substrate_desc: Label
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
	_w_label = Label.new()
	_w_slider = _add_slider_row(vbox, "Width", 4.0, 16.0, 0.5, _w_label)
	_w_slider.value_changed.connect(func(v): _on_w(v))

	_d_label = Label.new()
	_d_slider = _add_slider_row(vbox, "Depth", 2.0, 8.0, 0.5, _d_label)
	_d_slider.value_changed.connect(func(v): _on_d(v))

	_h_label = Label.new()
	_h_slider = _add_slider_row(vbox, "Height", 4.0, 12.0, 0.5, _h_label)
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
	_w_slider.value = TankConfig.tank_half_w * 2.0
	_d_slider.value = TankConfig.tank_half_d * 2.0
	_h_slider.value = TankConfig.tank_height
	_light_energy.value = TankConfig.light_energy
	_light_yaw.value = TankConfig.light_yaw
	_light_pitch.value = TankConfig.light_pitch
	_light_warmth.value = TankConfig.light_warmth
	_update_value_labels()
	# Pick the option matching current substrate.
	for i in _substrate_option.item_count:
		if _substrate_option.get_item_metadata(i) == TankConfig.substrate_type:
			_substrate_option.select(i)
			break
	_update_substrate_desc()


func _update_value_labels() -> void:
	_w_label.text = "%.1f" % _w_slider.value
	_d_label.text = "%.1f" % _d_slider.value
	_h_label.text = "%.1f" % _h_slider.value
	_light_energy_label.text = "%.2f" % _light_energy.value
	_light_yaw_label.text = "%.2f" % _light_yaw.value
	_light_pitch_label.text = "%.2f" % _light_pitch.value
	_light_warmth_label.text = "%.2f" % _light_warmth.value


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


func _on_apply() -> void:
	TankConfig.save_to_disk()
	apply_requested.emit()
	# Reload the entire main scene - the world rebuilds from TankConfig.
	get_tree().reload_current_scene()
