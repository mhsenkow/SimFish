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
var _light_caustics_check: CheckBox
var _music_enabled_check: CheckBox
var _sound_studio_btn: Button
var _substrate_option: OptionButton
var _substrate_desc: Label
var _aeration_option: OptionButton
var _aeration_desc: Label
var _aeration_strength: HSlider
var _aeration_strength_label: Label
var _environment_option: OptionButton
var _environment_desc: Label
var _aeration_x: HSlider
var _aeration_x_label: Label
var _auto_respawn_check: CheckBox
var _auto_feed_check: CheckBox
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
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_O or event.keycode == KEY_ESCAPE:
			visible = false
			mouse_filter = Control.MOUSE_FILTER_IGNORE


func toggle() -> void:
	visible = not visible
	if visible:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_pull_from_config()
	else:
		mouse_filter = Control.MOUSE_FILTER_IGNORE


# Build the inner control tree once. Layout is a VBoxContainer with a title
# row, a scrolling body of section + form rows, and a pinned footer with
# Close / Apply. All visual styling goes through PanelTheme so the panel
# matches Render and Fish-Store side-by-side.
func _build_ui() -> void:
	custom_minimum_size = Vector2(460, 0)
	PanelTheme.apply_panel_chrome(self)

	# Outer layout: title at the top, scrolling section list in the middle,
	# always-visible footer (Close / Apply) at the bottom. Separation of 8
	# gives the title room to breathe before the scroll body begins.
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)

	outer.add_child(PanelTheme.make_title("Settings"))
	outer.add_child(PanelTheme.make_rule())

	# Scrolling body. The section vbox lives inside this so when there are
	# more controls than fit on screen, the user can scroll — and the Apply
	# button stays reachable at the bottom of the panel.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	# Row separation = 8 (was 6) so form rows aren't crammed against each other.
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# -- Tank section --
	_add_section(vbox, "Tank")
	_shape_option = PanelTheme.add_dropdown_row(vbox, "Shape")
	for entry in [
			{"key": "box",      "label": "Box (rectangle)"},
			{"key": "cube",     "label": "Cube (square)"},
			{"key": "hex",      "label": "Hexagon"},
			{"key": "triangle", "label": "Triangle"},
			{"key": "cylinder", "label": "Cylinder (round)"},
			{"key": "sphere",   "label": "Sphere (dome bowl)"},
		]:
		_shape_option.add_item(String(entry["label"]))
		_shape_option.set_item_metadata(_shape_option.item_count - 1, entry["key"])
	_shape_option.item_selected.connect(func(idx):
		TankConfig.tank_shape = _shape_option.get_item_metadata(idx))

	_w_label = Label.new()
	_w_slider = PanelTheme.add_slider_row(vbox, "Width", 4.0, 24.0, 0.5, _w_label)
	_w_slider.value_changed.connect(func(v): _on_w(v))

	_d_label = Label.new()
	_d_slider = PanelTheme.add_slider_row(vbox, "Depth", 2.0, 14.0, 0.5, _d_label)
	_d_slider.value_changed.connect(func(v): _on_d(v))

	_h_label = Label.new()
	_h_slider = PanelTheme.add_slider_row(vbox, "Height", 4.0, 20.0, 0.5, _h_label)
	_h_slider.value_changed.connect(func(v): _on_h(v))

	# -- Light section --
	_add_section(vbox, "Light")
	_light_energy_label = Label.new()
	_light_energy = PanelTheme.add_slider_row(vbox, "Intensity", 0.0, 1.0, 0.05, _light_energy_label)
	_light_energy.value_changed.connect(func(v): _on_light_energy(v))

	_light_yaw_label = Label.new()
	_light_yaw = PanelTheme.add_slider_row(vbox, "Direction (yaw)", 0.0, 1.0, 0.05, _light_yaw_label)
	_light_yaw.value_changed.connect(func(v): _on_light_yaw(v))

	_light_pitch_label = Label.new()
	_light_pitch = PanelTheme.add_slider_row(vbox, "Direction (pitch)", 0.0, 1.0, 0.05, _light_pitch_label)
	_light_pitch.value_changed.connect(func(v): _on_light_pitch(v))

	_light_warmth_label = Label.new()
	_light_warmth = PanelTheme.add_slider_row(vbox, "Warmth (cool→warm)", 0.0, 1.0, 0.05, _light_warmth_label)
	_light_warmth.value_changed.connect(func(v): _on_light_warmth(v))

	# Fixture selection (bar vs spotlight).
	_light_fixture_option = PanelTheme.add_dropdown_row(vbox, "Fixture")
	_light_fixture_option.add_item("Bar (long LED)")
	_light_fixture_option.set_item_metadata(0, "bar")
	_light_fixture_option.add_item("Spotlight (pendant)")
	_light_fixture_option.set_item_metadata(1, "spotlight")
	_light_fixture_option.item_selected.connect(func(idx): _on_fixture(idx))

	_light_height_label = Label.new()
	_light_height = PanelTheme.add_slider_row(vbox, "Fixture height", 0.5, 4.0, 0.1, _light_height_label)
	_light_height.value_changed.connect(func(v): _on_light_height(v))

	_light_size_label = Label.new()
	_light_size = PanelTheme.add_slider_row(vbox, "Fixture size", 0.3, 1.0, 0.05, _light_size_label)
	_light_size.value_changed.connect(func(v): _on_light_size(v))

	# Beams toggle.
	_light_volumetric_check = CheckBox.new()
	_light_volumetric_check.text = "Show light beams (god rays)"
	_light_volumetric_check.toggled.connect(func(v): _on_volumetric(v))
	vbox.add_child(_light_volumetric_check)

	# Caustics toggle.
	_light_caustics_check = CheckBox.new()
	_light_caustics_check.text = "Show surface caustics"
	_light_caustics_check.toggled.connect(func(v): _on_caustics(v))
	vbox.add_child(_light_caustics_check)

	# -- Sound (quick access; full studio is the ♪ panel) --
	_add_section(vbox, "Sound & Music")

	_music_enabled_check = CheckBox.new()
	_music_enabled_check.text = "Enable sound"
	_music_enabled_check.toggled.connect(func(v): _on_music_enabled(v))
	vbox.add_child(_music_enabled_check)

	var sound_hint := PanelTheme.make_description()
	sound_hint.text = "Open Sound Studio (♪ or M) for layers, tank coupling, influences, and randomize."
	vbox.add_child(sound_hint)

	_sound_studio_btn = PanelTheme.make_primary_button("Open Sound Studio…")
	_sound_studio_btn.pressed.connect(_open_sound_studio)
	vbox.add_child(_sound_studio_btn)

	# -- Stocking preset section --
	_add_section(vbox, "Stocking preset")

	_auto_respawn_check = CheckBox.new()
	_auto_respawn_check.text = "Auto-respawn extinct creatures (10 per species)"
	_auto_respawn_check.toggled.connect(func(v): TankConfig.auto_respawn_fauna = v)
	vbox.add_child(_auto_respawn_check)

	_auto_feed_check = CheckBox.new()
	_auto_feed_check.text = "Auto-feed surface (simulate manual feeding)"
	_auto_feed_check.toggled.connect(func(v): TankConfig.auto_feed_fauna = v)
	vbox.add_child(_auto_feed_check)

	_preset_option = OptionButton.new()
	_preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_option.custom_minimum_size = Vector2(0, 30)
	for key in TankConfig.TANK_PRESETS.keys():
		var label: String = TankConfig.TANK_PRESETS[key]["label"]
		_preset_option.add_item(label)
		_preset_option.set_item_metadata(_preset_option.item_count - 1, key)
	_preset_option.item_selected.connect(func(idx): _on_preset(idx))
	vbox.add_child(_preset_option)
	_preset_desc = PanelTheme.make_description()
	vbox.add_child(_preset_desc)

	# -- Substrate section --
	_add_section(vbox, "Substrate")
	_substrate_option = OptionButton.new()
	_substrate_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_substrate_option.custom_minimum_size = Vector2(0, 30)
	for key in TankConfig.SUBSTRATE_PROFILES.keys():
		var label: String = TankConfig.SUBSTRATE_PROFILES[key]["label"]
		_substrate_option.add_item(label)
		_substrate_option.set_item_metadata(_substrate_option.item_count - 1, key)
	_substrate_option.item_selected.connect(func(idx): _on_substrate(idx))
	vbox.add_child(_substrate_option)
	_substrate_desc = PanelTheme.make_description()
	vbox.add_child(_substrate_desc)

	# -- Aeration section --
	# Picks a fixture type (disk / stick / filter / none) which is rebuilt on
	# Apply, plus strength + lateral position that the rebuild reads from
	# TankConfig.
	_add_section(vbox, "Aeration")
	_aeration_option = OptionButton.new()
	_aeration_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_aeration_option.custom_minimum_size = Vector2(0, 30)
	for key in TankConfig.AERATION_PROFILES.keys():
		var label: String = TankConfig.AERATION_PROFILES[key]["label"]
		_aeration_option.add_item(label)
		_aeration_option.set_item_metadata(_aeration_option.item_count - 1, key)
	_aeration_option.item_selected.connect(func(idx): _on_aeration(idx))
	vbox.add_child(_aeration_option)
	_aeration_desc = PanelTheme.make_description()
	vbox.add_child(_aeration_desc)
	_aeration_strength_label = Label.new()
	_aeration_strength = PanelTheme.add_slider_row(vbox, "Air strength", 0.0, 1.0, 0.05,
		_aeration_strength_label)
	_aeration_strength.value_changed.connect(func(v): _on_aeration_strength(v))
	_aeration_x_label = Label.new()
	_aeration_x = PanelTheme.add_slider_row(vbox, "Position (left↔right)", -1.0, 1.0, 0.05,
		_aeration_x_label)
	_aeration_x.value_changed.connect(func(v): _on_aeration_x(v))

	# -- Room environment --
	# The "scene" around the tank — desk, wall, lamp, plant. Default is
	# "void" (no room) to preserve the classic isolated look; other
	# presets dress up the tank for a cozier feel.
	_add_section(vbox, "Room")
	_environment_option = OptionButton.new()
	_environment_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_environment_option.custom_minimum_size = Vector2(0, 30)
	for key in TankConfig.ENVIRONMENT_PRESETS.keys():
		var label: String = TankConfig.ENVIRONMENT_PRESETS[key]["label"]
		_environment_option.add_item(label)
		_environment_option.set_item_metadata(_environment_option.item_count - 1, key)
	_environment_option.item_selected.connect(func(idx): _on_environment(idx))
	vbox.add_child(_environment_option)
	_environment_desc = PanelTheme.make_description()
	vbox.add_child(_environment_desc)

	# -- Species & diet chart --
	# Read-only listing showing which species in the library hunt what. Lets
	# the player understand WHY their puffer is eating their snails or their
	# cory is grazing algae rather than pellets — and pick presets accordingly.
	# Built as a RichTextLabel so the trophic / habitat / size tags can be
	# color-tinted; the previous plain-Label version produced lines that
	# read identically (e.g. all "omnivore, mid-water") for half the library.
	_add_section(vbox, "Species & diet")
	var diet_chart := RichTextLabel.new()
	diet_chart.bbcode_enabled = true
	diet_chart.fit_content = true
	diet_chart.scroll_active = false
	diet_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diet_chart.add_theme_color_override("default_color", Color(0.86, 0.90, 0.96, 0.95))
	diet_chart.add_theme_font_size_override("normal_font_size", 11)
	diet_chart.text = _build_diet_chart()
	vbox.add_child(diet_chart)

	# Footer buttons — attached to `outer` (NOT `vbox`) so they stay pinned at
	# the bottom of the panel below the scroll area. Without this, when the
	# section list grew past the screen height the Apply button scrolled off
	# the bottom and became unreachable.
	outer.add_child(PanelTheme.make_rule())
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 8)
	outer.add_child(hb)
	var close := PanelTheme.make_secondary_button("Close")
	close.pressed.connect(func(): visible = false)
	hb.add_child(close)
	var apply := PanelTheme.make_primary_button("Apply (reload tank)")
	apply.pressed.connect(_on_apply)
	hb.add_child(apply)


# Section header with a 4-px spacer above so each group reads as a chunk
# instead of running into the previous slider row.
func _add_section(parent: Node, label: String) -> void:
	parent.add_child(PanelTheme.make_spacer(4))
	parent.add_child(PanelTheme.make_section(label))


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
	_light_caustics_check.button_pressed = TankConfig.light_caustics
	_music_enabled_check.button_pressed = TankConfig.music_enabled
	# Pick the fixture option matching current type.
	for i in _light_fixture_option.item_count:
		if _light_fixture_option.get_item_metadata(i) == TankConfig.light_fixture:
			_light_fixture_option.select(i)
			break
	_update_value_labels()
	# Heal legacy save data: if the current preset forces a substrate (e.g.
	# reef → ocean_sand) but TankConfig.substrate_type doesn't match, fix it
	# silently. This catches old saves written before the cascade existed.
	# _sync_substrate_dropdown then selects + locks + describes in one pass.
	var cur_preset: Dictionary = TankConfig.TANK_PRESETS.get(TankConfig.tank_preset, {})
	var forced_sub: String = String(cur_preset.get("substrate", ""))
	if forced_sub != "" and TankConfig.SUBSTRATE_PROFILES.has(forced_sub) \
			and TankConfig.substrate_type != forced_sub:
		TankConfig.substrate_type = forced_sub
	_sync_substrate_dropdown()
	# Aeration.
	for i in _aeration_option.item_count:
		if _aeration_option.get_item_metadata(i) == TankConfig.aeration_type:
			_aeration_option.select(i)
			break
	_aeration_strength.value = TankConfig.aeration_strength
	_aeration_x.value = TankConfig.aeration_x_frac
	_update_aeration_desc()
	_aeration_strength_label.text = "%.2f" % _aeration_strength.value
	_aeration_x_label.text = "%.2f" % _aeration_x.value
	# Sync the environment dropdown to the saved preset.
	if _environment_option != null:
		for i in _environment_option.item_count:
			if _environment_option.get_item_metadata(i) == TankConfig.environment_preset:
				_environment_option.select(i)
				break
		_update_environment_desc()
	_auto_respawn_check.button_pressed = TankConfig.auto_respawn_fauna
	_auto_feed_check.button_pressed = TankConfig.auto_feed_fauna
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


func _on_caustics(v: bool) -> void:
	TankConfig.light_caustics = v


func _on_music_enabled(v: bool) -> void:
	TankConfig.music_enabled = v
	var amb = get_tree().current_scene.get_node_or_null("AmbientAudio")
	if amb != null and amb.has_method("silence_immediately"):
		amb.silence_immediately()


func _open_sound_studio() -> void:
	var main := get_tree().current_scene
	if main == null:
		return
	var panel := main.get_node_or_null("SoundPanel")
	if panel != null and panel.has_method("toggle"):
		panel.toggle()


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


func _on_aeration(idx: int) -> void:
	TankConfig.aeration_type = _aeration_option.get_item_metadata(idx)
	_update_aeration_desc()


func _on_environment(idx: int) -> void:
	TankConfig.environment_preset = _environment_option.get_item_metadata(idx)
	_update_environment_desc()


func _update_environment_desc() -> void:
	var key: String = TankConfig.environment_preset
	var preset: Dictionary = TankConfig.ENVIRONMENT_PRESETS.get(key, {})
	if _environment_desc != null:
		_environment_desc.text = String(preset.get("description", ""))


func _on_aeration_strength(v: float) -> void:
	TankConfig.aeration_strength = v
	_aeration_strength_label.text = "%.2f" % v


func _on_aeration_x(v: float) -> void:
	TankConfig.aeration_x_frac = v
	_aeration_x_label.text = "%.2f" % v


func _update_aeration_desc() -> void:
	var key: String = TankConfig.aeration_type
	var profile: Dictionary = TankConfig.AERATION_PROFILES.get(key, {})
	_aeration_desc.text = profile.get("description", "")


func _on_preset(idx: int) -> void:
	var new_key: String = _preset_option.get_item_metadata(idx)
	TankConfig.tank_preset = new_key
	# Some presets force a specific substrate (e.g. "reef" → "ocean_sand").
	# Cascade that choice into TankConfig.substrate_type so the UI doesn't
	# claim "aquasoil" while the world is built with ocean sand. Without
	# this, saved state.json's substrate_type drifted from what the world
	# actually contained, and the save-compatibility check passed for tanks
	# that ecologically shouldn't load (saltwater corals into a freshwater
	# spawn). Whether or not the new preset forces a substrate, re-sync the
	# dropdown — its disabled state depends on the preset.
	var preset: Dictionary = TankConfig.TANK_PRESETS.get(new_key, {})
	var forced: String = String(preset.get("substrate", ""))
	if forced != "" and TankConfig.SUBSTRATE_PROFILES.has(forced):
		TankConfig.substrate_type = forced
	_sync_substrate_dropdown()
	_update_preset_desc()


# Re-select the substrate dropdown item that matches TankConfig.substrate_type
# AND lock the dropdown if the current preset forces a specific substrate (so
# the user can't pick a conflicting one — they'd need to change preset first).
# Pulled out of _pull_from_config so _on_preset can call it after a cascade.
func _sync_substrate_dropdown() -> void:
	if _substrate_option == null:
		return
	for i in _substrate_option.item_count:
		if _substrate_option.get_item_metadata(i) == TankConfig.substrate_type:
			_substrate_option.select(i)
			break
	var preset: Dictionary = TankConfig.TANK_PRESETS.get(TankConfig.tank_preset, {})
	var forced: String = String(preset.get("substrate", ""))
	_substrate_option.disabled = forced != ""
	# A muted hint reminds the player why the control is locked.
	if _substrate_desc != null:
		if forced != "":
			var preset_label: String = String(preset.get("label", TankConfig.tank_preset))
			var profile: Dictionary = TankConfig.SUBSTRATE_PROFILES.get(forced, {})
			_substrate_desc.text = "%s\n(locked by preset: %s)" % [
				String(profile.get("description", "")),
				preset_label,
			]
		else:
			var cur_profile: Dictionary = TankConfig.SUBSTRATE_PROFILES.get(
				TankConfig.substrate_type, {})
			_substrate_desc.text = String(cur_profile.get("description", ""))


func _build_diet_chart() -> String:
	# Per-species diet summary, sorted by water-column position so the
	# eye walks top→bottom of the tank as it reads the list. Each line
	# is BBCode-tinted: the species label in a neutral tone, then a
	# trophic chip (green/yellow/red), then habitat + size/social tags
	# in muted gray. Without the extra size + schooling dimensions, half
	# the library (glassdart, danio, guppy, angelfish, reef_fish) all
	# collapsed to "omnivore, mid-water" and looked identical here.
	var c_herb := "#86c084"
	var c_omni := "#d6b070"
	var c_carn := "#e07070"
	var c_special := "#e0c060"  # snail-hunter / algae-grazer
	var c_dim := "#9aa8c8"
	var entries: Array = []
	for key in TankConfig.SPECIES_LIBRARY.keys():
		var entry: Dictionary = TankConfig.SPECIES_LIBRARY[key]
		var g: Dictionary = entry.get("genome", {})
		var py: float = float(g.get("preferred_y", 3.5))
		entries.append({"key": key, "label": entry.get("label", key), "g": g, "py": py})
	# Sort surface → bottom so the chart reads like a tank cross-section.
	entries.sort_custom(func(a, b): return float(a["py"]) > float(b["py"]))

	var lines: Array[String] = []
	for e in entries:
		var label: String = String(e["label"])
		var g: Dictionary = e["g"]
		var py: float = float(e["py"])

		# Trophic chip — color = diet category.
		var herb: float = float(g.get("herbivory", 0.0))
		var trophic: String
		if herb >= 0.9:
			trophic = "[color=%s]herbivore[/color]" % c_herb
		elif herb >= 0.4:
			trophic = "[color=%s]omnivore[/color]" % c_omni
		else:
			trophic = "[color=%s]carnivore[/color]" % c_carn

		# Habitat (water column).
		var habitat: String
		if py >= 4.8:
			habitat = "surface"
		elif py <= 2.5:
			habitat = "bottom"
		else:
			habitat = "mid"

		# Size class — uses adult_voxel_scale because it's the field that
		# actually drives rendered fish size. Distinguishes tiny guppies
		# from large angelfish even when their other tags collide.
		var sz: float = float(g.get("adult_voxel_scale", 0.18))
		var size_class: String
		if sz < 0.14:
			size_class = "tiny"
		elif sz < 0.20:
			size_class = "small"
		elif sz < 0.25:
			size_class = "medium"
		else:
			size_class = "large"

		# Social mode — schooling vs. solitary. Driven by schooling_strength
		# which the brain uses for flock cohesion. Adds visible variation
		# between schoolers (glassdart, danio) and loners (betta, puffer).
		var sch: float = float(g.get("schooling_strength", 0.5))
		var social: String
		if sch >= 1.2:
			social = "school"
		elif sch >= 0.5:
			social = "shoal"
		else:
			social = "solo"

		# Specialist tags (snail-hunter / algae-grazer) get the warm
		# accent color so the eye picks them out — they're load-bearing
		# for picking presets (don't put snails in with puffers).
		var specials: Array[String] = []
		if bool(g.get("snail_predator", false)):
			specials.append("[color=%s]snail-hunter[/color]" % c_special)
		if bool(g.get("algae_grazer", false)):
			specials.append("[color=%s]algae-grazer[/color]" % c_special)
		if bool(g.get("mixed_morphs", false)):
			specials.append("[color=%s]mixed morphs[/color]" % c_special)

		var dim_tags: String = "[color=%s]%s · %s · %s[/color]" % [
			c_dim, habitat, size_class, social,
		]
		var special_str: String = ""
		if not specials.is_empty():
			special_str = "  " + " ".join(specials)
		lines.append("• %s  %s  %s%s" % [label, trophic, dim_tags, special_str])
	return "\n".join(lines)


func _update_preset_desc() -> void:
	var key: String = TankConfig.tank_preset
	var preset: Dictionary = TankConfig.TANK_PRESETS.get(key, {})
	var desc: String = preset.get("description", "")
	if key != "custom":
		# Build the stocking summary by iterating the preset's stocking dict
		# (species_name -> count). Use the friendly label from the species
		# library so the panel reads "Glassdart tetra 12" rather than
		# "glassdart 12". Shrimp is special-cased - it doesn't live in the
		# species library.
		var stocking_dict: Dictionary = preset.get("stocking", {})
		var stocking_parts: Array[String] = []
		for species_name in stocking_dict.keys():
			var count: int = int(stocking_dict[species_name])
			if count <= 0:
				continue
			var label: String = species_name.capitalize()
			if species_name == "shrimp":
				label = "Shrimp"
			elif TankConfig.SPECIES_LIBRARY.has(species_name):
				label = TankConfig.SPECIES_LIBRARY[species_name]["label"]
			stocking_parts.append("%s %d" % [label, count])
		var stocking: String = "Stocking: " + ", ".join(stocking_parts)
		var spread: String = "Phenotype spread: %.1f×" % float(preset.get("phenotype_spread", 1.0))
		desc = desc + "\n" + stocking + "\n" + spread
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
