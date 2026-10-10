extends SceneTree

# Exercise the actual Light panel and its signals without booting World.
# Opening the panel must not change a preset, clamp its intensity, or leave
# newly enabled lights at an invisible zero. Run in isolated user data.


class LightClock extends Node:
	var day_phase: float = 0.25
	var solar: float = 1.0

	func daylight() -> float:
		return solar


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_lighting_controls_ui")
	var cfg: Node = root.get_node("TankConfig")
	cfg.set("capture_mode", true)
	cfg.call("reset_to_defaults")
	var english: Translation = load("res://assets/i18n/strings.en.translation")
	var localized_keys: Array[String] = [
		"Aquarium lamp on", "Follow daylight cycle", "Visible light shafts",
		"Shaft opacity", "Rear foliage light", "Dim the room",
		"Lamp resting for the night. Automatic light returns at dawn.",
		"Aquarium lighting switched off at the master control.",
	]
	var presets: Dictionary = (cfg.get_script() as GDScript).get_script_constant_map()["LIGHTING_PRESETS"]
	for preset in presets.values():
		localized_keys.append(String(preset.get("label", "")))
	for key in localized_keys:
		t.equals(String(english.get_message(key)), key,
			"compiled English catalog includes lighting key: " + key)
	var main_script: GDScript = load("res://scripts/main.gd")
	var defaults: Dictionary = main_script.get_script_constant_map()["_LIGHT_DEFAULTS"]
	for key: String in defaults:
		t.equals(cfg.get(key), defaults[key], "individual UI reset matches whole-settings reset: " + key)
	var host: Node = main_script.new()
	host.call("_ensure_light_panel")
	var panel: PanelContainer = host.get("_light_panel")
	var picker: OptionButton = host.get("_light_preset_option")
	t.check(panel != null and picker != null, "the real Light panel builds")
	if panel == null or picker == null:
		host.free()
		quit(t.finish())
		return
	host.remove_child(panel)
	root.add_child(panel)
	panel.show()
	panel.size = Vector2(360, 720)
	for frame in 4:
		await process_frame

	var intensity: HSlider = host.get("_light_fixture_intensity_slider")
	t.approx(intensity.max_value, 1.5, "fixture slider includes the curated 1.15 spot preset")
	# Selecting each preset then reopening/syncing must keep its exact values.
	for index in range(1, picker.item_count):
		var slug: String = String(picker.get_item_metadata(index))
		picker.item_selected.emit(index)
		t.equals(String(cfg.get("lighting_preset")), slug, "preset applies: " + slug)
		var expected: float = float(cfg.get("tank_fixture_intensity"))
		host.call("_pull_light_panel_values")
		t.approx(intensity.value, expected, "preset intensity displayed without clamping: " + slug)
		t.equals(String(cfg.get("lighting_preset")), slug, "sync preserves preset: " + slug)
		t.equals(String(picker.get_item_metadata(picker.selected)), slug,
			"selector reflects preset: " + slug)
	cfg.set("lighting_preset", "removed_legacy_look")
	host.call("_pull_light_panel_values")
	t.equals(picker.selected, 0, "an unavailable saved preset displays Custom rather than a previous look")
	t.equals(String(cfg.get("lighting_preset")), "removed_legacy_look", "sync preserves imported settings")
	host.call("_on_lighting_preset_selected", -1)
	host.call("_on_lighting_preset_selected", picker.item_count)
	t.equals(String(cfg.get("lighting_preset")), "removed_legacy_look", "invalid stale preset indices cannot mutate config")

	var fixture: CheckBox = host.get("_light_tank_check")
	cfg.set("tank_lights_on", true)
	cfg.set("lighting_preset", "planted")
	host.call("_pull_light_panel_values")
	fixture.button_pressed = false
	t.check(not bool(cfg.get("tank_lights_on")), "fixture toggle changes live config")
	t.equals(String(cfg.get("lighting_preset")), "custom", "fixture toggle marks preset custom")
	t.equals(picker.selected, 0, "fixture toggle updates preset selector")
	t.check(not "night" in fixture.text.to_lower(), "fixture toggle does not imply night-only operation")
	_reset_for(fixture).pressed.emit()
	t.check(bool(cfg.get("tank_lights_on")), "inline toggle reset restores the fixture")

	var cycle: CheckBox = host.get("_light_fixture_cycle_check")
	cycle.button_pressed = false
	t.check(not bool(cfg.get("fixture_follow_day_cycle")), "manual lamp mode is selectable")
	_reset_for(cycle).pressed.emit()
	t.check(bool(cfg.get("fixture_follow_day_cycle")), "photoperiod reset restores automatic daylight mode")
	var clock := LightClock.new()
	host.set("_sim", clock)
	clock.solar = 0.0
	cfg.set("day_cycle_enabled", false)
	host.call("_refresh_light_panel_live")
	var status: Label = host.get("_light_fixture_status")
	t.check("resting for the night" in status.text,
		"paused night explains the automatic lamp's scheduled darkness")
	cycle.button_pressed = false
	t.check("continuously" in status.text, "manual night light clearly reports its active state")
	cycle.button_pressed = true
	clock.solar = 1.0
	host.call("_refresh_light_panel_live")
	t.check("daylight schedule" in status.text, "paused daylight still refreshes lamp status")
	clock.solar = 0.25
	host.call("_refresh_light_panel_live")
	t.check("fade" in status.text, "twilight reports the scheduled fade")
	var master: CheckBox = host.get("_light_master_check")
	master.button_pressed = false
	t.check("master control" in status.text, "master blackout is distinguished from scheduled darkness")
	master.button_pressed = true
	var phase_slider: HSlider = host.get("_light_day_phase_slider")
	phase_slider.grab_focus()
	cfg.set("day_cycle_enabled", true)
	clock.day_phase = 0.32
	host.call("_refresh_light_panel_live")
	t.approx(phase_slider.value, 0.32, "focused time slider still follows the running clock after dragging")
	phase_slider.drag_started.emit()
	clock.day_phase = 0.36
	host.call("_refresh_light_panel_live")
	t.approx(phase_slider.value, 0.32, "active dragging retains the user's thumb position")
	phase_slider.drag_ended.emit(false)
	host.call("_refresh_light_panel_live")
	t.approx(phase_slider.value, 0.36, "clock mirroring resumes when the drag ends")
	host.call("_on_day_phase_changed", 1.0)
	t.approx(clock.day_phase, 0.0, "the next dawn endpoint wraps biological time to zero")
	t.approx(phase_slider.value, 0.0, "the next dawn endpoint wraps the displayed slider too")

	var beams: CheckBox = host.get("_light_beams_check")
	beams.button_pressed = false
	t.check(not bool(cfg.get("light_volumetric")), "shaft toggle changes live config")
	var beam_strength: HSlider = host.get("_light_beam_strength_slider")
	beam_strength.value = 0.35
	await process_frame
	t.approx(float(cfg.get("beam_strength")), 0.35, "shaft opacity has a live value")
	_reset_for(beam_strength).pressed.emit()
	t.approx(float(cfg.get("beam_strength")), 1.0, "shaft opacity reset matches config default")
	var room_dark: HSlider = host.get("_light_room_darkness_slider")
	room_dark.value = 0.65
	await process_frame
	t.approx(float(cfg.get("room_darkness")), 0.65, "room dimming has a live value")
	_reset_for(room_dark).pressed.emit()
	t.approx(float(cfg.get("room_darkness")), 0.0, "room dimming resets independently")

	var rear: CheckBox = host.get("_light_backlight_check")
	cfg.set("backlight_enabled", false)
	cfg.set("backlight_intensity", 0.0)
	host.call("_pull_light_panel_values")
	rear.button_pressed = true
	t.check(bool(cfg.get("backlight_enabled")), "rear light is reachable from Light panel")
	t.approx(float(cfg.get("backlight_intensity")), 0.45,
		"enabling an unused rear light produces a gentle visible intensity")
	var rear_intensity: HSlider = host.get("_light_backlight_intensity_slider")
	t.approx(rear_intensity.value, 0.45, "rear slider reflects first-use intensity")
	rear_intensity.value = 0.70
	await process_frame
	rear.button_pressed = false
	rear.button_pressed = true
	t.approx(float(cfg.get("backlight_intensity")), 0.70, "rear toggle preserves an existing personal intensity")
	var rear_color: ColorPickerButton = host.get("_light_backlight_color_picker")
	var tint := Color(0.4, 0.7, 0.9)
	rear_color.color_changed.emit(tint)
	t.equals(cfg.get("backlight_color"), tint, "rear light color writes live config")
	_reset_for(rear_color).pressed.emit()
	t.equals(cfg.get("backlight_color"), Color(1.0, 0.62, 0.28), "rear color reset is warm amber")
	# Round-trip the actual config writer and reader. This is a scratch slot;
	# capture mode blocks background autosaves while the fixture is checked.
	var roundtrip: Dictionary = {
		"fixture_follow_day_cycle": false, "tank_lights_on": true,
		"light_volumetric": false, "beam_strength": 0.35,
		"backlight_enabled": true, "backlight_intensity": 0.65,
		"backlight_color": Color(0.4, 0.7, 0.9), "room_darkness": 0.55,
		"tank_fixture_intensity": 1.15, "lighting_preset": "custom",
	}
	for key: String in roundtrip:
		cfg.set(key, roundtrip[key])
	var saved: ConfigFile = cfg.call("_build_save_config_file")
	var config_path: String = cfg.call("_current_save_path")
	DirAccess.make_dir_recursive_absolute(config_path.get_base_dir())
	t.equals(saved.save(config_path), OK, "lighting fixture snapshot saves in isolated slot")
	cfg.call("reset_to_defaults")
	cfg.call("load_from_disk")
	for key: String in roundtrip:
		t.equals(cfg.get(key), roundtrip[key], "lighting UI setting survives restart: " + key)
	host.call("_pull_light_panel_values")
	t.approx(intensity.value, 1.15, "reloaded high intensity still fits the actual control")
	# Old tanks already stored tank_on but had no photoperiod property. They
	# should retain their old continuously lit look; new tanks default auto.
	saved.erase_section_key("light", "fixture_follow_day_cycle")
	t.equals(saved.save(config_path), OK, "legacy fixture snapshot saves")
	cfg.call("reset_to_defaults")
	cfg.call("load_from_disk")
	t.check(not bool(cfg.get("fixture_follow_day_cycle")), "legacy lamp saves retain manual mode")

	# Every checkbox's reset belongs to its own row, not the whole section.
	for node in panel.find_children("*", "CheckBox", true, false):
		var toggle: CheckBox = node
		t.check(toggle.get_parent() is HBoxContainer, "toggle reset is inline: " + toggle.text)
		t.check(_reset_for(toggle) != null, "toggle owns one reset: " + toggle.text)

	# Exercise actual container minimums at the narrow supported panel size.
	panel.size = Vector2(360, 720)
	for frame in 4:
		await process_frame
	t.check(panel.size.x <= 360.5, "Light controls fit a 360 px panel: %s" % panel.size)
	var scroll: ScrollContainer = panel.find_child("LightControlsScroll", true, false)
	t.check(scroll.get_v_scroll_bar().max_value > scroll.size.y,
		"overflowing sections remain scrollable: range=%s height=%s child=%s minimum=%s" % [scroll.get_v_scroll_bar().max_value, scroll.size.y,
		(scroll.get_child(0) as Control).size, (scroll.get_child(0) as Control).get_combined_minimum_size()])

	var reset_row := HBoxContainer.new()
	root.add_child(reset_row)
	var removed_slider := HSlider.new()
	reset_row.add_child(removed_slider)
	host.call("_attach_reset", removed_slider, "tank_fixture_intensity")
	var obsolete_reset: Button = _reset_for(removed_slider)
	removed_slider.free()
	obsolete_reset.pressed.emit()
	t.approx(float(cfg.get("tank_fixture_intensity")), 1.15, "a detached reset cannot act on a freed control")
	reset_row.free()
	panel.free()
	clock.free()
	host.call("_refresh_light_panel_live")
	host.call("_pull_light_panel_values")
	host.call("_on_fixture_intensity_changed", 0.75)
	t.approx(float(cfg.get("tank_fixture_intensity")), 0.75,
		"late lighting callback updates config safely after panel and simulation disposal")
	host.call("_ensure_light_panel")
	t.check(is_instance_valid(host.get("_light_fixture_intensity_slider")), "a disposed lighting panel reconstructs fresh widgets")
	host.free()
	quit(t.finish())


func _reset_for(control: Control) -> Button:
	for sibling in control.get_parent().get_children():
		if sibling is Button and sibling != control and (sibling as Button).text == "↻":
			return sibling as Button
	return null
