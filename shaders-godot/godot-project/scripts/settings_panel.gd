# Settings panel.
#
# Toggled by the O key (or click the gear). Pushes values into the TankConfig
# autoload as the user drags sliders, then Apply reloads the scene so the
# new tank dimensions / substrate / light are actually rebuilt.
#
# Layout is created procedurally so we don't have to maintain a fragile
# tscn node tree of dozens of UI nodes.

extends PanelContainer

# Preloaded for the same reason ai_director.gd / fish.gd do — the global
# class_name registry isn't reliable before the editor scan completes.
const OllamaOnboarding = preload("res://scripts/ollama_onboarding.gd")
const MindNarrator = preload("res://scripts/mind_narrator.gd")
const KeeperInput = preload("res://scripts/keeper_input.gd")

signal apply_requested

var _shape_option: OptionButton
var _vessel_option: OptionButton
var _vessel_desc: Label
var _new_tank_fit_option: OptionButton
var _w_slider: HSlider
var _d_slider: HSlider
var _h_slider: HSlider
var _light_fixture_option: OptionButton
var _light_height: HSlider
var _light_size: HSlider
var _light_height_label: Label
var _light_size_label: Label
var _light_volumetric_check: CheckBox
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
# Performance / mobile battery controls (Advanced tab).
var _battery_saver_check: CheckBox
var _fps_cap_option: OptionButton
var _fauna_schooling_slider: HSlider
var _fauna_schooling_label: Label
var _fauna_separation_slider: HSlider
var _fauna_separation_label: Label
var _fauna_pulse_check: CheckBox
var _fauna_pulse_amp_slider: HSlider
var _fauna_pulse_amp_label: Label
var _fauna_wander_slider: HSlider
var _fauna_wander_label: Label
var _fauna_speed_slider: HSlider
var _fauna_speed_label: Label
var _fauna_mourning_check: CheckBox
var _fauna_glance_check: CheckBox
var _preset_option: OptionButton
var _preset_desc: Label
var _diet_chart: RichTextLabel
var _w_label: Label
var _d_label: Label
var _h_label: Label
# AI companion widgets
var _ai_enabled_check: CheckBox
var _ai_chronicle_check: CheckBox
var _ai_embedded_check: CheckBox
var _ai_embedded_endpoint_edit: LineEdit
var _ai_embedded_model_edit: LineEdit
var _guardian_voice_check: CheckBox
var _fish_thought_voice_check: CheckBox
var _keeper_ears_check: CheckBox
var _keeper_gaze_check: CheckBox
var _keeper_mic_check: CheckBox
var _sentience_voice_off_check: CheckBox
var _voice_language_option: OptionButton
var _guardian_dl_progress_label: Label
var _voice_detail_box: VBoxContainer
var _ai_endpoint_edit: LineEdit
var _ai_model_edit: LineEdit
var _ai_theme_edit: LineEdit
var _ai_status_label: Label
var _ai_status_timer: float = 0.0
var _co2_slider: HSlider
var _co2_label: Label
var _spectrum_slider: HSlider
var _spectrum_label: Label
var _plant_limit_overlay_check: CheckBox
var _debug_growth_check: CheckBox
var _aquascape_feedback: Label
# Snapshot taken when the panel opens. Preset/substrate stay staged here until
# Apply so autosave can't write a new preset header over an old fauna list.
var _panel_snapshot: Dictionary = {}
var _pending_preset: String = "community"
var _pending_substrate: String = "aquasoil"


func _ready() -> void:
	_build_ui()
	_pull_from_config()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_revert_staged_stocking()
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_O or event.keycode == KEY_ESCAPE:
			_revert_staged_stocking()
			visible = false
			mouse_filter = Control.MOUSE_FILTER_IGNORE


func toggle() -> void:
	if visible:
		_revert_staged_stocking()
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		_pull_from_config()


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

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(tabs)

	var vbox_tank := _new_settings_tab(tabs, "Tank")
	var vbox_stock := _new_settings_tab(tabs, "Stocking")
	var vbox_env := _new_settings_tab(tabs, "Environment")
	var vbox_fauna := _new_settings_tab(tabs, "Fauna")
	var vbox_ai := _new_settings_tab(tabs, "AI")
	var vbox_adv := _new_settings_tab(tabs, "Advanced")

	# -- Tank tab --
	_add_section(vbox_tank, "Shape & size")
	_vessel_option = PanelTheme.add_dropdown_row(vbox_tank, "Vessel preset")
	for key in TankConfig.VESSEL_PRESETS.keys():
		var vlabel: String = TankConfig.VESSEL_PRESETS[key]["label"]
		_vessel_option.add_item(vlabel)
		_vessel_option.set_item_metadata(_vessel_option.item_count - 1, key)
	_vessel_option.item_selected.connect(func(idx): _on_vessel(idx))
	_vessel_desc = PanelTheme.make_description()
	vbox_tank.add_child(_vessel_desc)

	_shape_option = PanelTheme.add_dropdown_row(vbox_tank, "Shape")
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
		TankConfig.tank_shape = _shape_option.get_item_metadata(idx)
		TankConfig.vessel_preset = "custom"
		_sync_vessel_dropdown())

	_new_tank_fit_option = PanelTheme.add_dropdown_row(vbox_tank, "New tank footprint")
	for entry in [
			{"key": "auto", "label": "Auto (screen + orientation)"},
			{"key": "rect", "label": "Rectangle (tall/wide box)"},
			{"key": "round", "label": "Round (cylinder)"},
		]:
		_new_tank_fit_option.add_item(String(entry["label"]))
		_new_tank_fit_option.set_item_metadata(_new_tank_fit_option.item_count - 1, entry["key"])
	_new_tank_fit_option.item_selected.connect(func(idx):
		TankConfig.new_tank_fit = _new_tank_fit_option.get_item_metadata(idx))
	var fit_hint := PanelTheme.make_description()
	fit_hint.text = "Used when you create a new tank. Auto picks a tall cylinder in portrait and a wide box in landscape; desktop defaults are larger."
	vbox_tank.add_child(fit_hint)

	_w_label = Label.new()
	_w_slider = PanelTheme.add_slider_row(vbox_tank, "Width", 4.0, 24.0, 0.5, _w_label)
	_w_slider.value_changed.connect(func(v): _on_w(v))

	_d_label = Label.new()
	_d_slider = PanelTheme.add_slider_row(vbox_tank, "Depth", 2.0, 14.0, 0.5, _d_label)
	_d_slider.value_changed.connect(func(v): _on_d(v))

	_h_label = Label.new()
	_h_slider = PanelTheme.add_slider_row(vbox_tank, "Height", 4.0, 20.0, 0.5, _h_label)
	_h_slider.value_changed.connect(func(v): _on_h(v))

	var reload_badge := PanelTheme.make_description()
	reload_badge.text = "Width / depth / height need Apply (reload) to rebuild the tank."
	vbox_tank.add_child(reload_badge)

	# -- Light fixture (tank setup) --
	# Intensity, warmth, caustics, and the tank-lights toggle live in the
	# always-visible Light rail popup (💡). Keep the structural fixture
	# placement controls here since they're "tank setup" rather than
	# moment-to-moment lighting feel.
	_add_section(vbox_tank, "Light fixture")

	# (Sun direction moved to the Light panel's 2D pad — see _make_sun_direction_pad
	# in main.gd. Yaw/pitch sliders deleted here so there's only one place to
	# touch them.)

	# Fixture selection (bar vs spotlight).
	_light_fixture_option = PanelTheme.add_dropdown_row(vbox_tank, "Fixture")
	_light_fixture_option.add_item("Bar (long LED)")
	_light_fixture_option.set_item_metadata(0, "bar")
	_light_fixture_option.add_item("Spotlight (pendant)")
	_light_fixture_option.set_item_metadata(1, "spotlight")
	_light_fixture_option.item_selected.connect(func(idx): _on_fixture(idx))

	_light_height_label = Label.new()
	_light_height = PanelTheme.add_slider_row(vbox_tank, "Fixture height", 0.5, 4.0, 0.1, _light_height_label)
	_light_height.value_changed.connect(func(v): _on_light_height(v))

	_light_size_label = Label.new()
	_light_size = PanelTheme.add_slider_row(vbox_tank, "Fixture size", 0.3, 1.0, 0.05, _light_size_label)
	_light_size.value_changed.connect(func(v): _on_light_size(v))

	_light_volumetric_check = CheckBox.new()
	_light_volumetric_check.text = "Show light beams (god rays)"
	_light_volumetric_check.toggled.connect(func(v): _on_volumetric(v))
	vbox_tank.add_child(_light_volumetric_check)

	var look_hint := PanelTheme.make_description()
	look_hint.text = "Sun, warmth, and post-process live in Look → Lighting on the right rail."
	vbox_tank.add_child(look_hint)

	# -- Stocking tab --
	_add_section(vbox_stock, "Preset")

	_preset_option = OptionButton.new()
	_preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_option.custom_minimum_size = Vector2(0, 30)
	for key in TankConfig.TANK_PRESETS.keys():
		var label: String = TankConfig.TANK_PRESETS[key]["label"]
		_preset_option.add_item(label)
		_preset_option.set_item_metadata(_preset_option.item_count - 1, key)
	_preset_option.item_selected.connect(func(idx): _on_preset(idx))
	vbox_stock.add_child(_preset_option)
	_preset_desc = PanelTheme.make_description()
	vbox_stock.add_child(_preset_desc)

	_add_section(vbox_stock, "Species & diet")
	_diet_chart = RichTextLabel.new()
	_diet_chart.bbcode_enabled = true
	_diet_chart.fit_content = true
	_diet_chart.scroll_active = false
	_diet_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_diet_chart.add_theme_color_override("default_color", Color(0.86, 0.90, 0.96, 0.95))
	_diet_chart.add_theme_font_size_override("normal_font_size", 11)
	vbox_stock.add_child(_diet_chart)

	# -- Environment tab --
	_add_section(vbox_env, "Substrate")
	_substrate_option = OptionButton.new()
	_substrate_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_substrate_option.custom_minimum_size = Vector2(0, 30)
	for key in TankConfig.SUBSTRATE_PROFILES.keys():
		var label: String = TankConfig.SUBSTRATE_PROFILES[key]["label"]
		_substrate_option.add_item(label)
		_substrate_option.set_item_metadata(_substrate_option.item_count - 1, key)
	_substrate_option.item_selected.connect(func(idx): _on_substrate(idx))
	vbox_env.add_child(_substrate_option)
	_substrate_desc = PanelTheme.make_description()
	vbox_env.add_child(_substrate_desc)

	# -- Aeration --
	# Picks a fixture type (disk / stick / filter / none) which is rebuilt on
	# Apply, plus strength + lateral position that the rebuild reads from
	# TankConfig.
	_add_section(vbox_env, "Aeration")
	_aeration_option = OptionButton.new()
	_aeration_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_aeration_option.custom_minimum_size = Vector2(0, 30)
	for key in TankConfig.AERATION_PROFILES.keys():
		var label: String = TankConfig.AERATION_PROFILES[key]["label"]
		_aeration_option.add_item(label)
		_aeration_option.set_item_metadata(_aeration_option.item_count - 1, key)
	_aeration_option.item_selected.connect(func(idx): _on_aeration(idx))
	vbox_env.add_child(_aeration_option)
	_aeration_desc = PanelTheme.make_description()
	vbox_env.add_child(_aeration_desc)
	_aeration_strength_label = Label.new()
	_aeration_strength = PanelTheme.add_slider_row(vbox_env, "Air strength", 0.0, 1.0, 0.05,
		_aeration_strength_label)
	_aeration_strength.value_changed.connect(func(v): _on_aeration_strength(v))
	_aeration_x_label = Label.new()
	_aeration_x = PanelTheme.add_slider_row(vbox_env, "Position (left↔right)", -1.0, 1.0, 0.05,
		_aeration_x_label)
	_aeration_x.value_changed.connect(func(v): _on_aeration_x(v))

	# -- Aquascape templates --
	# One-click planting layouts from curated real-world styles. Each pulls
	# from RealSpeciesLibrary so the planting reads as a coordinated theme
	# rather than a random scatter. The template ADDS plants live (no
	# reload required) and immediately autosaves so the new plants survive
	# the next Apply / reload of the scene.
	_add_section(vbox_env, "Plants — Aquascape Templates")
	var aq_desc := PanelTheme.make_description()
	aq_desc.text = "Drop a curated planting from a real aquascape style. Adds plants live — no Apply needed."
	vbox_env.add_child(aq_desc)
	var aq_row1 := HBoxContainer.new()
	aq_row1.add_theme_constant_override("separation", 6)
	vbox_env.add_child(aq_row1)
	for tpl in [["nature", "🌿 Nature"], ["iwagumi", "🪨 Iwagumi"], ["dutch", "🌹 Dutch"]]:
		var b := PanelTheme.make_secondary_button(tpl[1])
		var tname: String = tpl[0]
		b.tooltip_text = _aquascape_template_tooltip(tname)
		b.pressed.connect(func(): _apply_aquascape_template(tname))
		aq_row1.add_child(b)
	var aq_row2 := HBoxContainer.new()
	aq_row2.add_theme_constant_override("separation", 6)
	vbox_env.add_child(aq_row2)
	for tpl2 in [["jungle", "🌳 Jungle"], ["shrimp_tank", "🦐 Shrimp Tank"]]:
		var b2 := PanelTheme.make_secondary_button(tpl2[1])
		var tname2: String = tpl2[0]
		b2.tooltip_text = _aquascape_template_tooltip(tname2)
		b2.pressed.connect(func(): _apply_aquascape_template(tname2))
		aq_row2.add_child(b2)
	# Inline feedback label — sits directly under the buttons so the
	# "X plants placed" toast is actually visible. Previously the toast
	# went to the AI status label, which was scrolled off-screen.
	_aquascape_feedback = Label.new()
	_aquascape_feedback.add_theme_font_size_override("font_size", 11)
	_aquascape_feedback.add_theme_color_override("font_color", Color8(180, 195, 220))
	_aquascape_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_aquascape_feedback.text = ""
	vbox_env.add_child(_aquascape_feedback)

	# -- CO2 dosing --
	# Drives plant growth rate floors, red-pigment intensification, and
	# pearling bubble streams. Off = passive equilibrium; high = a
	# pressurized dosing rig supporting demanding species like Rotala
	# macrandra and HC Cuba.
	_add_section(vbox_env, "Plants — CO2 dosing")
	_co2_label = Label.new()
	_co2_slider = PanelTheme.add_slider_row(vbox_env, "CO2 level", 0.0, 1.0, 0.05, _co2_label)
	_co2_slider.value_changed.connect(_on_co2_level_changed)
	var co2_desc := PanelTheme.make_description()
	co2_desc.text = "0 = off · 0.3 = passive · 0.6 = medium · 1.0 = pressurized. Higher CO2 makes red plants redden and stems pearl visibly."
	vbox_env.add_child(co2_desc)
	# Light spectrum slider — cool↔warm LED tuning. Real aquascapers swap
	# bulbs to bring out reds or greens; we expose the same lever.
	_spectrum_label = Label.new()
	_spectrum_slider = PanelTheme.add_slider_row(vbox_env, "Light spectrum",
		0.0, 1.0, 0.05, _spectrum_label)
	_spectrum_slider.value_changed.connect(_on_light_spectrum_changed)
	var sp_desc := PanelTheme.make_description()
	sp_desc.text = "0 = cool / blue (boosts greens) · 0.5 = neutral · 1.0 = warm / red (boosts reds)."
	vbox_env.add_child(sp_desc)
	_plant_limit_overlay_check = CheckBox.new()
	_plant_limit_overlay_check.text = "Plant limiting-factor tint (light / CO₂ / nutrient)"
	_plant_limit_overlay_check.toggled.connect(func(v): TankConfig.plant_limit_overlay = v)
	vbox_env.add_child(_plant_limit_overlay_check)
	_debug_growth_check = CheckBox.new()
	_debug_growth_check.text = "Log growth diagnostics (seconds per voxel, every ~10 s)"
	_debug_growth_check.toggled.connect(func(v): TankConfig.debug_growth_logging = v)
	vbox_env.add_child(_debug_growth_check)

	# -- Room --
	# The "scene" around the tank — desk, wall, lamp, plant. Default is
	# "void" (no room) to preserve the classic isolated look; other
	# presets dress up the tank for a cozier feel.
	_add_section(vbox_env, "Room")
	_environment_option = OptionButton.new()
	_environment_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_environment_option.custom_minimum_size = Vector2(0, 30)
	for key in TankConfig.ENVIRONMENT_PRESETS.keys():
		var label: String = TankConfig.ENVIRONMENT_PRESETS[key]["label"]
		_environment_option.add_item(label)
		_environment_option.set_item_metadata(_environment_option.item_count - 1, key)
	_environment_option.item_selected.connect(func(idx): _on_environment(idx))
	vbox_env.add_child(_environment_option)
	_environment_desc = PanelTheme.make_description()
	vbox_env.add_child(_environment_desc)

	# -- Fauna tab (live swim/grouping — no Apply/reload required) --
	_add_section(vbox_fauna, "Schooling")
	var fauna_school_hint := PanelTheme.make_description()
	fauna_school_hint.text = "Adjust how tightly fish school and spread through the tank. Changes apply immediately."
	vbox_fauna.add_child(fauna_school_hint)
	_fauna_schooling_label = Label.new()
	_fauna_schooling_slider = PanelTheme.add_slider_row(
		vbox_fauna, "Schooling intensity", 0.0, 2.0, 0.05, _fauna_schooling_label)
	_fauna_schooling_slider.value_changed.connect(func(v):
		TankConfig.fauna_schooling_mult = v
		_fauna_schooling_label.text = "%.2f" % v)
	_fauna_separation_label = Label.new()
	_fauna_separation_slider = PanelTheme.add_slider_row(
		vbox_fauna, "Personal space", 0.5, 2.0, 0.05, _fauna_separation_label)
	_fauna_separation_slider.value_changed.connect(func(v):
		TankConfig.fauna_separation_mult = v
		_fauna_separation_label.text = "%.2f" % v)
	_fauna_pulse_check = CheckBox.new()
	_fauna_pulse_check.text = "School breathing pulse (synchronized tighten/loosen)"
	_fauna_pulse_check.toggled.connect(func(v): TankConfig.fauna_school_pulse_enabled = v)
	vbox_fauna.add_child(_fauna_pulse_check)
	_fauna_pulse_amp_label = Label.new()
	_fauna_pulse_amp_slider = PanelTheme.add_slider_row(
		vbox_fauna, "Pulse amplitude", 0.0, 0.3, 0.01, _fauna_pulse_amp_label)
	_fauna_pulse_amp_slider.value_changed.connect(func(v):
		TankConfig.fauna_school_pulse_amplitude = v
		_fauna_pulse_amp_label.text = "%.2f" % v)

	_add_section(vbox_fauna, "Movement")
	_fauna_wander_label = Label.new()
	_fauna_wander_slider = PanelTheme.add_slider_row(
		vbox_fauna, "Wander / roam", 0.0, 2.0, 0.05, _fauna_wander_label)
	_fauna_wander_slider.value_changed.connect(func(v):
		TankConfig.fauna_wander_mult = v
		_fauna_wander_label.text = "%.2f" % v)
	_fauna_speed_label = Label.new()
	_fauna_speed_slider = PanelTheme.add_slider_row(
		vbox_fauna, "Swim speed", 0.5, 2.0, 0.05, _fauna_speed_label)
	_fauna_speed_slider.value_changed.connect(func(v):
		TankConfig.fauna_speed_mult = v
		_fauna_speed_label.text = "%.2f" % v)

	_add_section(vbox_fauna, "Social reactions")
	_fauna_mourning_check = CheckBox.new()
	_fauna_mourning_check.text = "Mourning behavior after deaths (school tightens + slows)"
	_fauna_mourning_check.toggled.connect(func(v): TankConfig.fauna_mourning_enabled = v)
	vbox_fauna.add_child(_fauna_mourning_check)
	_fauna_glance_check = CheckBox.new()
	_fauna_glance_check.text = "Player attention (bold fish drift toward camera stare)"
	_fauna_glance_check.toggled.connect(func(v): TankConfig.fauna_player_glance_enabled = v)
	vbox_fauna.add_child(_fauna_glance_check)

	# -- Advanced tab --
	_add_section(vbox_adv, "Automation")
	_auto_respawn_check = CheckBox.new()
	_auto_respawn_check.text = "Auto-respawn extinct creatures (10 per species)"
	_auto_respawn_check.toggled.connect(func(v): TankConfig.auto_respawn_fauna = v)
	vbox_adv.add_child(_auto_respawn_check)

	_auto_feed_check = CheckBox.new()
	_auto_feed_check.text = "Auto-feed (screensaver mode — simulates ⌘+click feeding)"
	_auto_feed_check.toggled.connect(func(v): TankConfig.auto_feed_fauna = v)
	vbox_adv.add_child(_auto_feed_check)
	var _guardian_autofeed_check := CheckBox.new()
	_guardian_autofeed_check.text = "Guardian may turn on auto-feed when starving"
	_guardian_autofeed_check.button_pressed = TankConfig.guardian_may_enable_autofeed
	_guardian_autofeed_check.toggled.connect(func(v): TankConfig.guardian_may_enable_autofeed = v)
	vbox_adv.add_child(_guardian_autofeed_check)

	_add_section(vbox_adv, "Sound")
	var sound_hint := PanelTheme.make_description()
	sound_hint.text = "Enable sound and mix layers in Sound Studio (Look → Sound, or M)."
	vbox_adv.add_child(sound_hint)
	_sound_studio_btn = PanelTheme.make_primary_button("Open Sound Studio…")
	_sound_studio_btn.pressed.connect(_open_sound_studio)
	vbox_adv.add_child(_sound_studio_btn)

	# Performance / battery. Surfaced everywhere but most relevant on mobile.
	# Battery Saver forces fps_cap to 30 and reduces visual overhead; the
	# user can also pick a specific cap (Off / 30 / 60 / 120) for finer
	# control. Saved via TankConfig so it persists across sessions and is
	# applied at scene-load by main._apply_fps_cap().
	_add_section(vbox_adv, "Performance")
	_battery_saver_check = CheckBox.new()
	_battery_saver_check.text = "Battery saver (caps at 30fps, lighter visuals)"
	_battery_saver_check.toggled.connect(func(v):
		TankConfig.battery_saver = v
		if v:
			TankConfig.fps_cap = 30
			_select_fps_option(30)
		TankConfig.save_to_disk()
		_apply_fps_cap_live()
		# Live-apply the visual side too — the main scene owns the display
		# ShaderMaterial. Without this the toggle would only take effect
		# after a scene reload.
		var main := get_tree().current_scene
		if main != null and main.has_method("_apply_battery_saver_visuals"):
			main._apply_battery_saver_visuals())
	vbox_adv.add_child(_battery_saver_check)
	_fps_cap_option = PanelTheme.add_dropdown_row(vbox_adv, "Frame rate cap")
	for entry in [
			{"label": "Uncapped", "value": 0},
			{"label": "30 fps (best battery)", "value": 30},
			{"label": "60 fps", "value": 60},
			{"label": "120 fps (high-refresh)", "value": 120},
		]:
		_fps_cap_option.add_item(String(entry["label"]))
		_fps_cap_option.set_item_metadata(_fps_cap_option.item_count - 1, int(entry["value"]))
	_fps_cap_option.item_selected.connect(func(idx):
		var v: int = int(_fps_cap_option.get_item_metadata(idx))
		TankConfig.fps_cap = v
		# Choosing anything other than 30 implicitly turns battery saver off.
		if v != 30 and bool(TankConfig.battery_saver):
			TankConfig.battery_saver = false
			_battery_saver_check.set_pressed_no_signal(false)
		TankConfig.save_to_disk()
		_apply_fps_cap_live())

	# -- AI tab --
	# Voice first (on-device, private) — separate from optional Ollama names/chronicle.
	_add_section(vbox_ai, "Voice & thoughts (on-device)")
	var voice_desc := PanelTheme.make_description()
	voice_desc.text = (
		"Fish minds always run in the simulation — moods, memory, behavior. "
		+ "This section controls optional text: Guardian diary lines and fish thoughts when you follow them. "
		+ "Nothing leaves your machine.")
	vbox_ai.add_child(voice_desc)
	_sentience_voice_off_check = CheckBox.new()
	_sentience_voice_off_check.text = "Quiet mode — hide all voice text"
	_sentience_voice_off_check.toggled.connect(_on_sentience_voice_off_toggled)
	vbox_ai.add_child(_sentience_voice_off_check)
	_voice_detail_box = VBoxContainer.new()
	_voice_detail_box.add_theme_constant_override("separation", 6)
	vbox_ai.add_child(_voice_detail_box)
	_guardian_voice_check = CheckBox.new()
	_guardian_voice_check.text = "Guardian diary lines (built-in model when available)"
	_guardian_voice_check.toggled.connect(_on_guardian_voice_toggled)
	_voice_detail_box.add_child(_guardian_voice_check)
	_fish_thought_voice_check = CheckBox.new()
	_fish_thought_voice_check.text = "Fish thoughts when following or inspecting"
	_fish_thought_voice_check.toggled.connect(_on_fish_thought_voice_toggled)
	_voice_detail_box.add_child(_fish_thought_voice_check)
	_add_section(vbox_ai, "Keeper ears (local)")
	var keeper_desc := PanelTheme.make_description()
	keeper_desc.text = (
		"Your words reach the followed fish as feeling, never commands. "
		+ "Gaze and cursor are optional social signals. Mic uses volume only — no speech-to-text.")
	vbox_ai.add_child(keeper_desc)
	_keeper_ears_check = CheckBox.new()
	_keeper_ears_check.text = "Text channel to followed fish"
	_keeper_ears_check.toggled.connect(_on_keeper_ears_toggled)
	vbox_ai.add_child(_keeper_ears_check)
	_keeper_gaze_check = CheckBox.new()
	_keeper_gaze_check.text = "Sustained gaze as social signal"
	_keeper_gaze_check.toggled.connect(_on_keeper_gaze_toggled)
	vbox_ai.add_child(_keeper_gaze_check)
	_keeper_mic_check = CheckBox.new()
	_keeper_mic_check.text = "Microphone room presence (opt-in)"
	_keeper_mic_check.toggled.connect(_on_keeper_mic_toggled)
	vbox_ai.add_child(_keeper_mic_check)
	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 6)
	_voice_detail_box.add_child(lang_row)
	var lang_lbl := Label.new()
	lang_lbl.text = "Voice language:"
	lang_lbl.add_theme_font_size_override("font_size", 11)
	lang_row.add_child(lang_lbl)
	_voice_language_option = OptionButton.new()
	_voice_language_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_voice_language_option.add_item("System default", 0)
	_voice_language_option.set_item_metadata(0, "")
	for code in ["en", "es", "fr", "de", "pt", "ja", "ko", "zh"]:
		var label: String = str(MindNarrator.LOCALE_LABELS.get(code, code))
		var idx: int = _voice_language_option.item_count
		_voice_language_option.add_item(label, idx)
		_voice_language_option.set_item_metadata(idx, code)
	_voice_language_option.item_selected.connect(_on_voice_language_selected)
	lang_row.add_child(_voice_language_option)
	var guardian_dl_desc := PanelTheme.make_description()
	guardian_dl_desc.text = "Steam builds include the model. Slim builds download once (~250MB, resumable)."
	_voice_detail_box.add_child(guardian_dl_desc)
	_guardian_dl_progress_label = Label.new()
	_guardian_dl_progress_label.add_theme_font_size_override("font_size", 11)
	_guardian_dl_progress_label.add_theme_color_override("font_color", Color8(180, 195, 220))
	_guardian_dl_progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_voice_detail_box.add_child(_guardian_dl_progress_label)
	var guardian_dl_btn := PanelTheme.make_secondary_button("Download Guardian mind")
	guardian_dl_btn.name = "GuardianDownloadBtn"
	guardian_dl_btn.pressed.connect(_on_guardian_download_pressed)
	_voice_detail_box.add_child(guardian_dl_btn)

	_add_section(vbox_ai, "AI Companion (optional Ollama)")
	# Local Ollama bridge. Off ships with the same offline name pool the AI
	# uses as fallback, so toggling this is purely additive — nothing breaks
	# when it's unreachable, players just keep the built-in experience.
	_ai_enabled_check = CheckBox.new()
	_ai_enabled_check.text = "Enable AI (local Ollama)"
	_ai_enabled_check.toggled.connect(_on_ai_enabled_toggled)
	vbox_ai.add_child(_ai_enabled_check)
	var ai_desc := PanelTheme.make_description()
	ai_desc.text = "Adds AI-generated names, moods, and (optional) tank chronicle lines. Runs locally — no data leaves your machine."
	vbox_ai.add_child(ai_desc)
	# Status line — driven by AIDirector.status_summary()
	_ai_status_label = Label.new()
	_ai_status_label.add_theme_font_size_override("font_size", 11)
	_ai_status_label.add_theme_color_override("font_color", Color8(180, 195, 220))
	_ai_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox_ai.add_child(_ai_status_label)
	var ai_row1 := HBoxContainer.new()
	ai_row1.add_theme_constant_override("separation", 6)
	vbox_ai.add_child(ai_row1)
	var ep_lbl := Label.new()
	ep_lbl.text = "Endpoint:"
	ep_lbl.add_theme_font_size_override("font_size", 11)
	ai_row1.add_child(ep_lbl)
	_ai_endpoint_edit = LineEdit.new()
	_ai_endpoint_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ai_endpoint_edit.placeholder_text = "http://localhost:11434"
	_ai_endpoint_edit.text_changed.connect(_on_ai_endpoint_changed)
	ai_row1.add_child(_ai_endpoint_edit)
	var ai_row2 := HBoxContainer.new()
	ai_row2.add_theme_constant_override("separation", 6)
	vbox_ai.add_child(ai_row2)
	var md_lbl := Label.new()
	md_lbl.text = "Model:"
	md_lbl.add_theme_font_size_override("font_size", 11)
	ai_row2.add_child(md_lbl)
	_ai_model_edit = LineEdit.new()
	_ai_model_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ai_model_edit.placeholder_text = "llama3.2:3b"
	_ai_model_edit.text_changed.connect(_on_ai_model_changed)
	ai_row2.add_child(_ai_model_edit)
	# Naming theme
	var ai_row3 := HBoxContainer.new()
	ai_row3.add_theme_constant_override("separation", 6)
	vbox_ai.add_child(ai_row3)
	var th_lbl := Label.new()
	th_lbl.text = "Naming theme:"
	th_lbl.add_theme_font_size_override("font_size", 11)
	ai_row3.add_child(th_lbl)
	_ai_theme_edit = LineEdit.new()
	_ai_theme_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ai_theme_edit.placeholder_text = "(optional) e.g. Greek gods, trees, planets"
	_ai_theme_edit.text_changed.connect(_on_ai_theme_changed)
	ai_row3.add_child(_ai_theme_edit)
	# Chronicle toggle
	_ai_chronicle_check = CheckBox.new()
	_ai_chronicle_check.text = "Write tank chronicle (ambient sentences)"
	_ai_chronicle_check.toggled.connect(_on_ai_chronicle_toggled)
	vbox_ai.add_child(_ai_chronicle_check)
	_add_section(vbox_ai, "Advanced: HTTP fallback (optional)")
	var embedded_desc := PanelTheme.make_description()
	embedded_desc.text = "Only if you run a separate /api/generate server. Normal play uses the built-in model above."
	vbox_ai.add_child(embedded_desc)
	_ai_embedded_check = CheckBox.new()
	_ai_embedded_check.text = "Enable HTTP embedded fallback"
	_ai_embedded_check.toggled.connect(_on_ai_embedded_toggled)
	vbox_ai.add_child(_ai_embedded_check)
	var embedded_row := HBoxContainer.new()
	embedded_row.add_theme_constant_override("separation", 6)
	vbox_ai.add_child(embedded_row)
	var emb_lbl := Label.new()
	emb_lbl.text = "Embedded endpoint:"
	emb_lbl.add_theme_font_size_override("font_size", 11)
	embedded_row.add_child(emb_lbl)
	_ai_embedded_endpoint_edit = LineEdit.new()
	_ai_embedded_endpoint_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ai_embedded_endpoint_edit.placeholder_text = "http://127.0.0.1:8080"
	_ai_embedded_endpoint_edit.text_changed.connect(_on_ai_embedded_endpoint_changed)
	embedded_row.add_child(_ai_embedded_endpoint_edit)
	var embedded_row2 := HBoxContainer.new()
	embedded_row2.add_theme_constant_override("separation", 6)
	vbox_ai.add_child(embedded_row2)
	var emb_md := Label.new()
	emb_md.text = "Embedded model:"
	emb_md.add_theme_font_size_override("font_size", 11)
	embedded_row2.add_child(emb_md)
	_ai_embedded_model_edit = LineEdit.new()
	_ai_embedded_model_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ai_embedded_model_edit.placeholder_text = "Qwen2.5-0.5B-Instruct-Q4_K_M"
	_ai_embedded_model_edit.text_changed.connect(_on_ai_embedded_model_changed)
	embedded_row2.add_child(_ai_embedded_model_edit)
	var ai_btn_row := HBoxContainer.new()
	ai_btn_row.add_theme_constant_override("separation", 6)
	vbox_ai.add_child(ai_btn_row)
	var test_btn := PanelTheme.make_secondary_button("Test connection")
	test_btn.pressed.connect(_on_ai_test_pressed)
	ai_btn_row.add_child(test_btn)
	# "Use installed" auto-substitutes a sensible model from whatever the
	# user already has pulled. Removes the friction of typing model names
	# or downloading new ones when their Ollama already has llama3/qwen/etc.
	var pick_btn := PanelTheme.make_secondary_button("Use installed model")
	pick_btn.pressed.connect(_on_ai_pick_installed)
	ai_btn_row.add_child(pick_btn)
	var onboard_btn := PanelTheme.make_secondary_button("Install Ollama…")
	onboard_btn.pressed.connect(_on_ai_onboard_pressed)
	ai_btn_row.add_child(onboard_btn)

	# Footer buttons — attached to `outer` so they stay pinned at
	# the bottom of the panel below the scroll area. Without this, when the
	# section list grew past the screen height the Apply button scrolled off
	# the bottom and became unreachable.
	var apply := PanelTheme.make_primary_button("Apply (reload tank)")
	apply.pressed.connect(_on_apply)
	outer.add_child(PanelTheme.make_panel_footer(func():
		_revert_staged_stocking()
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE, apply))


func _new_settings_tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	return vbox


# Section header with a 4-px spacer above so each group reads as a chunk
# instead of running into the previous slider row.
func _add_section(parent: Node, label: String) -> void:
	parent.add_child(PanelTheme.make_spacer(4))
	parent.add_child(PanelTheme.make_section(label))


# ---- Push/pull TankConfig ----

func _pull_from_config() -> void:
	_panel_snapshot = {
		"tank_preset": TankConfig.tank_preset,
		"substrate_type": TankConfig.substrate_type,
	}
	_pending_preset = TankConfig.tank_preset
	_pending_substrate = TankConfig.substrate_type
	# Tank shape dropdown.
	for i in _vessel_option.item_count:
		if _vessel_option.get_item_metadata(i) == TankConfig.vessel_preset:
			_vessel_option.select(i)
			break
	_update_vessel_desc()
	for i in _shape_option.item_count:
		if _shape_option.get_item_metadata(i) == TankConfig.tank_shape:
			_shape_option.select(i)
			break
	if _new_tank_fit_option != null:
		for i in _new_tank_fit_option.item_count:
			if _new_tank_fit_option.get_item_metadata(i) == TankConfig.new_tank_fit:
				_new_tank_fit_option.select(i)
				break
	_w_slider.value = TankConfig.tank_half_w * 2.0
	_d_slider.value = TankConfig.tank_half_d * 2.0
	_h_slider.value = TankConfig.tank_height
	_light_height.value = TankConfig.light_height
	_light_size.value = TankConfig.light_size
	_light_volumetric_check.button_pressed = TankConfig.light_volumetric
	if _music_enabled_check != null:
		_music_enabled_check.button_pressed = TankConfig.music_enabled
	# Pick the fixture option matching current type.
	for i in _light_fixture_option.item_count:
		if _light_fixture_option.get_item_metadata(i) == TankConfig.light_fixture:
			_light_fixture_option.select(i)
			break
	_update_value_labels()
	# Heal legacy save data: if the staged preset forces a substrate (e.g.
	# reef → ocean_sand) but pending substrate doesn't match, fix the staging
	# silently so the UI matches what Apply will build.
	var cur_preset: Dictionary = TankConfig.TANK_PRESETS.get(_pending_preset, {})
	var forced_sub: String = String(cur_preset.get("substrate", ""))
	if forced_sub != "" and TankConfig.SUBSTRATE_PROFILES.has(forced_sub) \
			and _pending_substrate != forced_sub:
		_pending_substrate = forced_sub
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
	if _battery_saver_check != null:
		_battery_saver_check.button_pressed = bool(TankConfig.battery_saver)
	if _fps_cap_option != null:
		_select_fps_option(int(TankConfig.fps_cap))
	if _fauna_schooling_slider != null:
		_fauna_schooling_slider.set_block_signals(true)
		_fauna_schooling_slider.value = TankConfig.fauna_schooling_mult
		_fauna_schooling_slider.set_block_signals(false)
		_fauna_schooling_label.text = "%.2f" % TankConfig.fauna_schooling_mult
	if _fauna_separation_slider != null:
		_fauna_separation_slider.set_block_signals(true)
		_fauna_separation_slider.value = TankConfig.fauna_separation_mult
		_fauna_separation_slider.set_block_signals(false)
		_fauna_separation_label.text = "%.2f" % TankConfig.fauna_separation_mult
	if _fauna_pulse_check != null:
		_fauna_pulse_check.button_pressed = TankConfig.fauna_school_pulse_enabled
	if _fauna_pulse_amp_slider != null:
		_fauna_pulse_amp_slider.set_block_signals(true)
		_fauna_pulse_amp_slider.value = TankConfig.fauna_school_pulse_amplitude
		_fauna_pulse_amp_slider.set_block_signals(false)
		_fauna_pulse_amp_label.text = "%.2f" % TankConfig.fauna_school_pulse_amplitude
	if _fauna_wander_slider != null:
		_fauna_wander_slider.set_block_signals(true)
		_fauna_wander_slider.value = TankConfig.fauna_wander_mult
		_fauna_wander_slider.set_block_signals(false)
		_fauna_wander_label.text = "%.2f" % TankConfig.fauna_wander_mult
	if _fauna_speed_slider != null:
		_fauna_speed_slider.set_block_signals(true)
		_fauna_speed_slider.value = TankConfig.fauna_speed_mult
		_fauna_speed_slider.set_block_signals(false)
		_fauna_speed_label.text = "%.2f" % TankConfig.fauna_speed_mult
	if _fauna_mourning_check != null:
		_fauna_mourning_check.button_pressed = TankConfig.fauna_mourning_enabled
	if _fauna_glance_check != null:
		_fauna_glance_check.button_pressed = TankConfig.fauna_player_glance_enabled
	# Pick the option matching current preset. Block signals so select()
	# can't fire _on_preset and mutate TankConfig while we're syncing UI.
	_preset_option.set_block_signals(true)
	for i in _preset_option.item_count:
		if _preset_option.get_item_metadata(i) == _pending_preset:
			_preset_option.select(i)
			break
	_preset_option.set_block_signals(false)
	_update_preset_desc()
	# CO2 slider
	if _co2_slider != null:
		_co2_slider.set_block_signals(true)
		_co2_slider.value = float(TankConfig.co2_level)
		_co2_slider.set_block_signals(false)
		if _co2_label != null:
			_co2_label.text = "%.2f" % TankConfig.co2_level
	# Light spectrum slider
	if _spectrum_slider != null:
		_spectrum_slider.set_block_signals(true)
		_spectrum_slider.value = float(TankConfig.light_spectrum)
		_spectrum_slider.set_block_signals(false)
		if _spectrum_label != null:
			_spectrum_label.text = "%.2f" % TankConfig.light_spectrum
	if _plant_limit_overlay_check != null:
		_plant_limit_overlay_check.button_pressed = TankConfig.plant_limit_overlay
	if _debug_growth_check != null:
		_debug_growth_check.button_pressed = TankConfig.debug_growth_logging
	# AI Companion widgets
	if _ai_enabled_check != null:
		_ai_enabled_check.set_block_signals(true)
		_ai_enabled_check.button_pressed = TankConfig.ai_enabled
		_ai_enabled_check.set_block_signals(false)
	if _ai_chronicle_check != null:
		_ai_chronicle_check.set_block_signals(true)
		_ai_chronicle_check.button_pressed = TankConfig.ai_chronicle
		_ai_chronicle_check.set_block_signals(false)
	if _ai_embedded_check != null:
		_ai_embedded_check.set_block_signals(true)
		_ai_embedded_check.button_pressed = TankConfig.ai_embedded_enabled
		_ai_embedded_check.set_block_signals(false)
	if _guardian_voice_check != null:
		_guardian_voice_check.set_block_signals(true)
		_guardian_voice_check.button_pressed = TankConfig.guardian_voice_enabled
		_guardian_voice_check.set_block_signals(false)
	if _sentience_voice_off_check != null:
		_sentience_voice_off_check.set_block_signals(true)
		_sentience_voice_off_check.button_pressed = TankConfig.sentience_voice_off
		_sentience_voice_off_check.set_block_signals(false)
	_sync_voice_detail_enabled()
	if _voice_language_option != null:
		_voice_language_option.set_block_signals(true)
		var want: String = String(TankConfig.voice_language)
		for i in _voice_language_option.item_count:
			if String(_voice_language_option.get_item_metadata(i)) == want:
				_voice_language_option.select(i)
				break
		_voice_language_option.set_block_signals(false)
	if _fish_thought_voice_check != null:
		_fish_thought_voice_check.set_block_signals(true)
		_fish_thought_voice_check.button_pressed = TankConfig.fish_thought_voice_enabled
		_fish_thought_voice_check.set_block_signals(false)
	if _keeper_ears_check != null:
		_keeper_ears_check.set_block_signals(true)
		_keeper_ears_check.button_pressed = TankConfig.keeper_ears_enabled
		_keeper_ears_check.set_block_signals(false)
	if _keeper_gaze_check != null:
		_keeper_gaze_check.set_block_signals(true)
		_keeper_gaze_check.button_pressed = TankConfig.keeper_gaze_enabled
		_keeper_gaze_check.set_block_signals(false)
	if _keeper_mic_check != null:
		_keeper_mic_check.set_block_signals(true)
		_keeper_mic_check.button_pressed = TankConfig.keeper_mic_enabled
		_keeper_mic_check.set_block_signals(false)
	if _ai_embedded_endpoint_edit != null:
		_ai_embedded_endpoint_edit.text = TankConfig.ai_embedded_endpoint
	if _ai_embedded_model_edit != null:
		_ai_embedded_model_edit.text = TankConfig.ai_embedded_model
	_sync_guardian_download_button()
	if _ai_endpoint_edit != null:
		_ai_endpoint_edit.text = TankConfig.ai_endpoint
	if _ai_model_edit != null:
		_ai_model_edit.text = TankConfig.ai_model
	if _ai_theme_edit != null:
		_ai_theme_edit.text = TankConfig.ai_naming_theme
	_refresh_ai_status()


func _refresh_ai_status() -> void:
	if _ai_status_label == null:
		return
	var ai := get_node_or_null("/root/AIDirector")
	if ai == null:
		_ai_status_label.text = "AI Director unavailable."
	else:
		_ai_status_label.text = String(ai.status_summary())
	_sync_guardian_download_button()
	_sync_guardian_download_progress()


func _sync_guardian_download_progress() -> void:
	if _guardian_dl_progress_label == null:
		return
	var glm := get_node_or_null("/root/GuardianLlm")
	if glm == null:
		_guardian_dl_progress_label.text = ""
		return
	var st: String = String(glm.call("status_summary")) if glm.has_method("status_summary") else ""
	if st.to_lower().contains("download"):
		_guardian_dl_progress_label.text = st
	else:
		_guardian_dl_progress_label.text = ""


func _process(_dt: float) -> void:
	if not visible:
		return
	# Refresh AI status periodically while the panel is open (cheap;
	# AIDirector.status_summary is a single string format).
	_ai_status_timer += _dt
	if _ai_status_timer >= 1.0:
		_ai_status_timer = 0.0
		_refresh_ai_status()


func _push_ai_to_director() -> void:
	var ai := get_node_or_null("/root/AIDirector")
	if ai == null:
		return
	ai.apply_config({
		"ai_enabled": TankConfig.ai_enabled,
		"ai_endpoint": TankConfig.ai_endpoint,
		"ai_model": TankConfig.ai_model,
		"ai_naming_theme": TankConfig.ai_naming_theme,
		"ai_chronicle": TankConfig.ai_chronicle,
		"ai_embedded_enabled": TankConfig.ai_embedded_enabled,
		"ai_embedded_endpoint": TankConfig.ai_embedded_endpoint,
		"ai_embedded_model": TankConfig.ai_embedded_model,
		"guardian_voice_enabled": TankConfig.guardian_voice_enabled,
		"fish_thought_voice_enabled": TankConfig.fish_thought_voice_enabled,
		"sentience_voice_off": TankConfig.sentience_voice_off,
		"voice_language": TankConfig.voice_language,
	})


func _apply_aquascape_template(template_name: String) -> void:
	# Param renamed from `name` (shadows Node.name) so the editor stops
	# flagging this on every reload.
	var world: Node = get_tree().root.find_child("World", true, false)
	if world == null:
		_set_aquascape_feedback("World not found — can't place plants.", false)
		return
	if not world.has_method("apply_aquascape_template"):
		_set_aquascape_feedback("Template support missing — restart the app.", false)
		return
	var planted: int = int(world.apply_aquascape_template(template_name))
	# Force an immediate autosave so the new plants survive the next
	# scene reload (Apply, autosave, tank-switch). Without this, hitting
	# Apply right after templating wipes the plants because save_state
	# hadn't captured them yet.
	var main: Node = get_tree().current_scene
	if main != null and main.has_method("save_active_tank"):
		main.save_active_tank(true)  # skip_thumbnail
	var label: String
	if planted > 0:
		label = "✓ %s template — %d plants added live. Already saved." % [
			template_name.capitalize(), planted]
		_set_aquascape_feedback(label, true)
	else:
		label = "%s template — no plants placed (tank may be full or hardscape missing)." \
			% template_name.capitalize()
		_set_aquascape_feedback(label, false)


func _set_aquascape_feedback(text: String, ok: bool) -> void:
	if _aquascape_feedback == null:
		return
	var col: Color = Color8(150, 230, 150) if ok else Color8(230, 165, 120)
	_aquascape_feedback.add_theme_color_override("font_color", col)
	_aquascape_feedback.text = text


# Human-readable tooltip describing what each template plants. Shown on
# button hover so the player knows the style before committing.
func _aquascape_template_tooltip(template_id: String) -> String:
	match template_id:
		"nature":
			return "Nature aquarium — Monte Carlo carpet (8), Cryptocoryne wendtii (3), Rotala rotundifolia (3), Anubias nana (2), Java fern (1)."
		"iwagumi":
			return "Iwagumi minimalist — Dwarf hairgrass carpet (12), Blyxa japonica (1). Pairs best with a few rocks."
		"dutch":
			return "Dutch street — Crypt wendtii brown (2), Rotala H'ra (4), Ludwigia Super Red (3), Alternanthera reineckii (2), Java fern (1). Red plant heaven."
		"jungle":
			return "Wild jungle — Amazon swords (2), Vallisneria curtain (4), Anubias barteri (3), Dwarf sagittaria (5)."
		"shrimp_tank":
			return "Shrimp playground — Monte Carlo (6), Bucephalandra kedagang (2), Java fern Windelov (1), Anubias petite (2), Christmas moss (3)."
		_:
			return "Aquascape template."


func _on_co2_level_changed(v: float) -> void:
	TankConfig.co2_level = clampf(v, 0.0, 1.0)
	if _co2_label != null:
		_co2_label.text = "%.2f" % v


func _on_light_spectrum_changed(v: float) -> void:
	TankConfig.light_spectrum = clampf(v, 0.0, 1.0)
	if _spectrum_label != null:
		_spectrum_label.text = "%.2f" % v


func _on_ai_enabled_toggled(on: bool) -> void:
	TankConfig.ai_enabled = on
	_push_ai_to_director()
	# If the user just turned it on and has never seen the onboarding
	# modal, pop it automatically — saves them hunting for the button.
	if on and not TankConfig.ai_onboarding_seen:
		_on_ai_onboard_pressed()


func _on_ai_chronicle_toggled(on: bool) -> void:
	TankConfig.ai_chronicle = on
	_push_ai_to_director()


func _on_ai_embedded_toggled(on: bool) -> void:
	TankConfig.ai_embedded_enabled = on
	_push_ai_to_director()


func _on_guardian_download_pressed() -> void:
	TankConfig.guardian_mind_consent = "accepted"
	TankConfig.guardian_voice_enabled = true
	if _guardian_voice_check != null:
		_guardian_voice_check.set_pressed_no_signal(true)
	TankConfig.save_to_disk()
	_push_ai_to_director()
	var glm := get_node_or_null("/root/GuardianLlm")
	if glm != null and glm.has_method("ensure_boot"):
		glm.call("ensure_boot")
	if glm != null and glm.has_method("_begin_load_if_needed"):
		glm.call("_begin_load_if_needed")
	_sync_guardian_download_button()


func _sync_guardian_download_button() -> void:
	var btn := find_child("GuardianDownloadBtn", true, false) as Button
	if btn == null:
		return
	var glm := get_node_or_null("/root/GuardianLlm")
	var llm_ready: bool = glm != null and glm.has_method("is_ready") and bool(glm.call("is_ready"))
	var declined: bool = str(TankConfig.guardian_mind_consent) == "declined"
	btn.visible = declined or (not llm_ready and str(TankConfig.guardian_mind_consent) != "accepted")


func _on_guardian_voice_toggled(on: bool) -> void:
	if on and TankConfig.sentience_voice_off:
		TankConfig.sentience_voice_off = false
		if _sentience_voice_off_check != null:
			_sentience_voice_off_check.set_pressed_no_signal(false)
		_sync_voice_detail_enabled()
	TankConfig.guardian_voice_enabled = on
	TankConfig.save_to_disk()
	_push_ai_to_director()
	var glm := get_node_or_null("/root/GuardianLlm")
	if glm != null and on and glm.has_method("ensure_boot"):
		glm.call("ensure_boot")
	if glm != null and on and glm.has_method("_begin_load_if_needed"):
		glm.call("_begin_load_if_needed")
	_sync_guardian_download_button()


func _on_fish_thought_voice_toggled(on: bool) -> void:
	if on and TankConfig.sentience_voice_off:
		TankConfig.sentience_voice_off = false
		if _sentience_voice_off_check != null:
			_sentience_voice_off_check.set_pressed_no_signal(false)
		_sync_voice_detail_enabled()
	TankConfig.fish_thought_voice_enabled = on
	TankConfig.save_to_disk()
	_push_ai_to_director()


func _on_keeper_ears_toggled(on: bool) -> void:
	TankConfig.keeper_ears_enabled = on
	TankConfig.save_to_disk()


func _on_keeper_gaze_toggled(on: bool) -> void:
	TankConfig.keeper_gaze_enabled = on
	TankConfig.save_to_disk()


func _on_keeper_mic_toggled(on: bool) -> void:
	TankConfig.keeper_mic_enabled = on
	if not on:
		KeeperInput.set_mic_rms(0.0)
	TankConfig.save_to_disk()


func _on_sentience_voice_off_toggled(on: bool) -> void:
	TankConfig.sentience_voice_off = on
	TankConfig.save_to_disk()
	_sync_voice_detail_enabled()
	_push_ai_to_director()


func _sync_voice_detail_enabled() -> void:
	var quiet: bool = TankConfig.sentience_voice_off
	if _voice_detail_box != null:
		_voice_detail_box.visible = not quiet
	if _guardian_voice_check != null:
		_guardian_voice_check.disabled = quiet
	if _fish_thought_voice_check != null:
		_fish_thought_voice_check.disabled = quiet
	if _voice_language_option != null:
		_voice_language_option.disabled = quiet


func _on_voice_language_selected(idx: int) -> void:
	if _voice_language_option == null:
		return
	TankConfig.voice_language = String(_voice_language_option.get_item_metadata(idx))
	TankConfig.save_to_disk()
	_push_ai_to_director()


func _on_ai_embedded_endpoint_changed(text: String) -> void:
	TankConfig.ai_embedded_endpoint = text.strip_edges()
	_push_ai_to_director()


func _on_ai_embedded_model_changed(text: String) -> void:
	TankConfig.ai_embedded_model = text.strip_edges()
	_push_ai_to_director()


func _on_ai_endpoint_changed(text: String) -> void:
	TankConfig.ai_endpoint = text.strip_edges()
	_push_ai_to_director()


func _on_ai_model_changed(text: String) -> void:
	TankConfig.ai_model = text.strip_edges()
	_push_ai_to_director()


func _on_ai_theme_changed(text: String) -> void:
	TankConfig.ai_naming_theme = text.strip_edges()
	_push_ai_to_director()


func _on_ai_test_pressed() -> void:
	_push_ai_to_director()
	var ai := get_node_or_null("/root/AIDirector")
	if ai != null:
		if not TankConfig.ai_enabled:
			TankConfig.ai_enabled = true
			_ai_enabled_check.button_pressed = true
			_push_ai_to_director()
		ai.test_connection()
		_refresh_ai_status()


func _on_ai_pick_installed() -> void:
	# Make sure we have a fresh list, then auto-swap the model field to
	# the best installed candidate. Two-step: if available_models is empty
	# (never tested), fire a test first and re-enter on the connection
	# signal; otherwise pick + apply + re-test immediately.
	var ai := get_node_or_null("/root/AIDirector")
	if ai == null:
		return
	if not TankConfig.ai_enabled:
		TankConfig.ai_enabled = true
		_ai_enabled_check.button_pressed = true
		_push_ai_to_director()
	if (ai.available_models as PackedStringArray).is_empty():
		# No model list yet — fire a test. The test response will populate
		# available_models; the user can click this button again afterward.
		# We also subscribe one-shot to the signal so the swap happens
		# automatically without a second click.
		_ai_status_label.add_theme_color_override("font_color", Color8(180, 195, 220))
		_ai_status_label.text = "Probing Ollama…"
		ai.test_connection()
		if not ai.connection_tested.is_connected(_on_ai_pick_after_probe):
			ai.connection_tested.connect(_on_ai_pick_after_probe, CONNECT_ONE_SHOT)
		return
	_apply_picked_model(ai)


func _on_ai_pick_after_probe(_success: bool, _msg: String) -> void:
	var ai := get_node_or_null("/root/AIDirector")
	if ai != null:
		_apply_picked_model(ai)


func _apply_picked_model(ai: Node) -> void:
	var pick: String = String(ai.pick_best_installed_model())
	if pick == "":
		_ai_status_label.add_theme_color_override("font_color", Color8(230, 120, 120))
		_ai_status_label.text = "No suitable installed model found. Try `ollama pull qwen2.5:3b` in a terminal."
		return
	TankConfig.ai_model = pick
	_ai_model_edit.text = pick
	_push_ai_to_director()
	ai.test_connection()
	_ai_status_label.add_theme_color_override("font_color", Color8(150, 230, 150))
	_ai_status_label.text = "Switched to `%s` and re-testing…" % pick


func _on_ai_onboard_pressed() -> void:
	TankConfig.ai_onboarding_seen = true
	# Attach the modal to the scene root. current_scene returns a generic
	# Node (main.gd extends Node, not Control) so we don't typecast it —
	# add_child works on any Node and the modal positions itself.
	var root: Node = get_tree().current_scene
	if root == null:
		return
	var modal: PanelContainer = OllamaOnboarding.new()
	root.add_child(modal)
	modal.z_index = 200
	modal.anchors_preset = Control.PRESET_CENTER
	# Re-centre after the layout pass so size is known. Use the window
	# size as the reference rect since the parent Node may not have a size.
	var win_size: Vector2 = Vector2(get_window().size)
	modal.call_deferred("set_position", (win_size - modal.size) * 0.5)
	if modal.has_signal("closed"):
		modal.closed.connect(_refresh_ai_status)


func _update_value_labels() -> void:
	_w_label.text = "%.1f" % _w_slider.value
	_d_label.text = "%.1f" % _d_slider.value
	_h_label.text = "%.1f" % _h_slider.value
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


func _on_music_enabled(v: bool) -> void:
	TankConfig.music_enabled = v
	var amb = get_tree().current_scene.get_node_or_null("AmbientAudio")
	if amb != null and amb.has_method("silence_immediately"):
		amb.silence_immediately()


func _open_sound_studio() -> void:
	var main := get_tree().current_scene
	if main == null:
		return
	if main.has_method("_ui_open_side"):
		main.call("_ui_open_side", "sound")


func _update_substrate_desc() -> void:
	var key: String = TankConfig.substrate_type
	var profile: Dictionary = TankConfig.SUBSTRATE_PROFILES.get(key, {})
	_substrate_desc.text = profile.get("description", "")


func _on_w(v: float) -> void:
	TankConfig.tank_half_w = v * 0.5
	TankConfig.vessel_preset = "custom"
	_sync_vessel_dropdown()
	_w_label.text = "%.1f" % v


func _on_d(v: float) -> void:
	TankConfig.tank_half_d = v * 0.5
	TankConfig.vessel_preset = "custom"
	_sync_vessel_dropdown()
	_d_label.text = "%.1f" % v


func _on_h(v: float) -> void:
	TankConfig.tank_height = v
	TankConfig.vessel_preset = "custom"
	_sync_vessel_dropdown()
	_h_label.text = "%.1f" % v


func _on_substrate(idx: int) -> void:
	_pending_substrate = _substrate_option.get_item_metadata(idx)
	_sync_substrate_dropdown()


func _on_aeration(idx: int) -> void:
	TankConfig.aeration_type = _aeration_option.get_item_metadata(idx)
	_update_aeration_desc()


func _on_vessel(idx: int) -> void:
	var slug: String = _vessel_option.get_item_metadata(idx)
	TankConfig.apply_vessel_preset(slug)
	_update_vessel_desc()
	# Push preset dimensions into sliders + shape dropdown without marking custom.
	for i in _shape_option.item_count:
		if _shape_option.get_item_metadata(i) == TankConfig.tank_shape:
			_shape_option.select(i)
			break
	_w_slider.value = TankConfig.tank_half_w * 2.0
	_d_slider.value = TankConfig.tank_half_d * 2.0
	_h_slider.value = TankConfig.tank_height
	_update_value_labels()


func _sync_vessel_dropdown() -> void:
	if _vessel_option == null:
		return
	for i in _vessel_option.item_count:
		if _vessel_option.get_item_metadata(i) == TankConfig.vessel_preset:
			_vessel_option.select(i)
			break
	_update_vessel_desc()


func _update_vessel_desc() -> void:
	var key: String = TankConfig.vessel_preset
	var preset: Dictionary = TankConfig.VESSEL_PRESETS.get(key, {})
	if _vessel_desc != null:
		_vessel_desc.text = String(preset.get("description", ""))


func _on_environment(idx: int) -> void:
	TankConfig.environment_preset = _environment_option.get_item_metadata(idx)
	_update_environment_desc()
	var suggested: String = TankConfig.suggested_lighting_for_environment(TankConfig.environment_preset)
	if suggested != "" and TankConfig.has_method("apply_lighting_preset"):
		TankConfig.apply_lighting_preset(suggested)


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
	_pending_preset = new_key
	# Some presets force a specific substrate (e.g. "reef" → "ocean_sand").
	# Stage that choice so autosave can't desync preset header from fauna.
	var preset: Dictionary = TankConfig.TANK_PRESETS.get(new_key, {})
	var forced: String = String(preset.get("substrate", ""))
	if forced != "" and TankConfig.SUBSTRATE_PROFILES.has(forced):
		_pending_substrate = forced
	_sync_substrate_dropdown()
	_update_preset_desc()
	_update_diet_chart()


# Re-select the substrate dropdown item that matches TankConfig.substrate_type
# AND lock the dropdown if the current preset forces a specific substrate (so
# the user can't pick a conflicting one — they'd need to change preset first).
# Pulled out of _pull_from_config so _on_preset can call it after a cascade.
func _sync_substrate_dropdown() -> void:
	if _substrate_option == null:
		return
	_substrate_option.set_block_signals(true)
	for i in _substrate_option.item_count:
		if _substrate_option.get_item_metadata(i) == _pending_substrate:
			_substrate_option.select(i)
			break
	_substrate_option.set_block_signals(false)
	var preset: Dictionary = TankConfig.TANK_PRESETS.get(_pending_preset, {})
	var forced: String = String(preset.get("substrate", ""))
	_substrate_option.disabled = forced != ""
	# A muted hint reminds the player why the control is locked.
	if _substrate_desc != null:
		if forced != "":
			var preset_label: String = String(preset.get("label", _pending_preset))
			var profile: Dictionary = TankConfig.SUBSTRATE_PROFILES.get(forced, {})
			_substrate_desc.text = "%s\n(locked by preset: %s)" % [
				String(profile.get("description", "")),
				preset_label,
			]
		else:
			var cur_profile: Dictionary = TankConfig.SUBSTRATE_PROFILES.get(
				_pending_substrate, {})
			_substrate_desc.text = String(cur_profile.get("description", ""))


func _update_diet_chart() -> void:
	if _diet_chart == null:
		return
	_diet_chart.text = _build_diet_chart()


func _preset_stocking_dict() -> Dictionary:
	var key: String = _pending_preset
	if key == "custom":
		return {
			"glassdart": TankConfig.custom_glassdart_count,
			"mudsifter": TankConfig.custom_mudsifter_count,
			"betta": 1,
			"shrimp": TankConfig.custom_shrimp_count,
		}
	var preset: Dictionary = TankConfig.TANK_PRESETS.get(key, {})
	return preset.get("stocking", {})


func _build_diet_chart() -> String:
	var c_dim := "#9aa8c8"
	var preset_key: String = _pending_preset
	var preset: Dictionary = TankConfig.TANK_PRESETS.get(preset_key, {})
	var stocking: Dictionary = _preset_stocking_dict()

	if preset_key == "empty":
		return "[color=%s]No preset fauna — stock by hand with the Creature Creator.[/color]" % c_dim

	if stocking.is_empty():
		return "[color=%s]This preset spawns no fish. Use the Creature Creator to add fauna.[/color]" % c_dim

	var preset_label: String = String(preset.get("label", preset_key))
	var header: String = "[color=%s]In \"%s\" preset:[/color]" % [c_dim, preset_label]
	return header + "\n" + _format_diet_lines(stocking)


func _format_diet_lines(stocking: Dictionary) -> String:
	# Per-species diet summary for the preset's stocking dict, sorted by
	# water-column position so the eye walks top→bottom of the tank.
	var c_herb := "#86c084"
	var c_omni := "#d6b070"
	var c_carn := "#e07070"
	var c_special := "#e0c060"
	var c_dim := "#9aa8c8"
	var entries: Array = []
	for species_name in stocking.keys():
		if species_name == "shrimp":
			continue
		if not TankConfig.SPECIES_LIBRARY.has(species_name):
			continue
		var entry: Dictionary = TankConfig.SPECIES_LIBRARY[species_name]
		var g: Dictionary = entry.get("genome", {})
		var py: float = float(g.get("preferred_y", 3.5))
		entries.append({
			"label": entry.get("label", species_name),
			"g": g,
			"py": py,
			"count": int(stocking[species_name]),
		})
	entries.sort_custom(func(a, b): return float(a["py"]) > float(b["py"]))

	var lines: Array[String] = []
	for e in entries:
		var count: int = int(e["count"])
		if count <= 0:
			continue
		var label: String = String(e["label"])
		var g: Dictionary = e["g"]
		var py: float = float(e["py"])

		var herb: float = float(g.get("herbivory", 0.0))
		var trophic: String
		if herb >= 0.9:
			trophic = "[color=%s]herbivore[/color]" % c_herb
		elif herb >= 0.4:
			trophic = "[color=%s]omnivore[/color]" % c_omni
		else:
			trophic = "[color=%s]carnivore[/color]" % c_carn

		var habitat: String
		if py >= 4.8:
			habitat = "surface"
		elif py <= 2.5:
			habitat = "bottom"
		else:
			habitat = "mid"

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

		var sch: float = float(g.get("schooling_strength", 0.5))
		var social: String
		if sch >= 1.2:
			social = "school"
		elif sch >= 0.5:
			social = "shoal"
		else:
			social = "solo"

		var specials: Array[String] = []
		if g.get("snail_predator", false):
			specials.append("[color=%s]snail-hunter[/color]" % c_special)
		if g.get("algae_grazer", false):
			specials.append("[color=%s]algae-grazer[/color]" % c_special)
		if g.get("mixed_morphs", false):
			specials.append("[color=%s]mixed morphs[/color]" % c_special)

		var dim_tags: String = "[color=%s]%s · %s · %s[/color]" % [
			c_dim, habitat, size_class, social,
		]
		var special_str: String = ""
		if not specials.is_empty():
			special_str = "  " + " ".join(specials)
		lines.append("• %s ×%d  %s  %s%s" % [label, count, trophic, dim_tags, special_str])

	if stocking.has("shrimp"):
		var shrimp_n: int = int(stocking["shrimp"])
		if shrimp_n > 0:
			lines.append(
				"• Shrimp ×%d  [color=%s]omnivore[/color]  [color=%s]bottom · tiny · shoal[/color]"
				% [shrimp_n, c_omni, c_dim]
			)

	if lines.is_empty():
		return "[color=%s](no fish in this preset)[/color]" % c_dim
	return "\n".join(lines)


func _update_preset_desc() -> void:
	var key: String = _pending_preset
	var preset: Dictionary = TankConfig.TANK_PRESETS.get(key, {})
	var desc: String = preset.get("description", "")
	if key != "custom":
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
		var stocking: String = "Initial stocking: " + ", ".join(stocking_parts)
		var spread: String = "Phenotype spread: %.1f×" % float(preset.get("phenotype_spread", 1.0))
		var forced_sub: String = String(preset.get("substrate", ""))
		var snail_note: String = ""
		if forced_sub == "ocean_sand":
			snail_note = "\nAlso spawns 8 marine founder snails on glass/substrate."
		elif not stocking_dict.is_empty():
			snail_note = "\nAlso spawns 6 founder snails on glass/substrate."
		desc = desc + "\n" + stocking + snail_note + "\n" + spread
		desc += "\nApply reloads the tank; population may differ if a save is restored."
	_preset_desc.text = desc
	_update_diet_chart()


func _commit_staged_stocking() -> void:
	TankConfig.tank_preset = _pending_preset
	TankConfig.substrate_type = _pending_substrate


func _revert_staged_stocking() -> void:
	if _panel_snapshot.is_empty():
		return
	TankConfig.tank_preset = String(_panel_snapshot.get("tank_preset", TankConfig.tank_preset))
	TankConfig.substrate_type = String(_panel_snapshot.get("substrate_type", TankConfig.substrate_type))


func _stocking_settings_changed() -> bool:
	return _pending_preset != String(_panel_snapshot.get("tank_preset", "")) \
		or _pending_substrate != String(_panel_snapshot.get("substrate_type", ""))


func _on_apply() -> void:
	# Preserve camera before the reload so the view doesn't snap back to
	# defaults. Main node has save_camera_state() that stashes yaw/pitch/etc
	# into TankConfig + saves to disk.
	var main := get_tree().current_scene
	if main != null and main.has_method("save_camera_state"):
		main.save_camera_state()
	_commit_staged_stocking()
	# Drop stale fauna whenever stocking/substrate changed in this panel OR
	# the on-disk save's header doesn't match what we're applying. Without
	# staging, autosave could rewrite tank_preset while keeping old fish.
	var saves := get_node_or_null("/root/TankSaves")
	if saves != null:
		var clear_save: bool = _stocking_settings_changed()
		if not clear_save and saves.has_method("is_active_save_compatible"):
			clear_save = not saves.is_active_save_compatible()
		if not clear_save and saves.has_method("is_stocking_fauna_compatible"):
			clear_save = not saves.is_stocking_fauna_compatible(
				TankConfig.tank_preset, TankConfig.substrate_type)
		if clear_save and saves.has_method("clear_active_state"):
			saves.clear_active_state()
	TankConfig.rebuild_terrain_on_load = true
	TankConfig.save_to_disk()
	_panel_snapshot = {}
	apply_requested.emit()
	get_tree().reload_current_scene()


# --- Performance helpers ---
# Select the dropdown item whose metadata matches the given cap value.
# Falls back to "Uncapped" if none match.
func _select_fps_option(cap: int) -> void:
	for i in _fps_cap_option.item_count:
		if int(_fps_cap_option.get_item_metadata(i)) == cap:
			_fps_cap_option.select(i)
			return
	_fps_cap_option.select(0)


# Apply the chosen fps cap immediately so the user sees the change without
# reloading the scene. Engine.max_fps = 0 means uncapped.
func _apply_fps_cap_live() -> void:
	Engine.max_fps = int(TankConfig.fps_cap)
