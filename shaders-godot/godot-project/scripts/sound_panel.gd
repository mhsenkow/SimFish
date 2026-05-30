# Sound Studio — dedicated procedural music panel.
#
# Exposes tank-reactive music parameters, live ecosystem readout, and randomize.
# Toggle with M key or the ♪ HUD button.

extends PanelContainer

var _live_label: Label
var _mood_option: OptionButton
var _style_option: OptionButton
var _slider_rows: Dictionary = {}
var _check_rows: Dictionary = {}
var _telemetry_t: float = 0.0

const SLIDERS: Array = [
	{"key": "music_volume", "label": "Master volume", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	{"key": "music_energy", "label": "Energy (BPM & drive)", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	{"key": "music_complexity", "label": "Bed density", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	{"key": "music_reactivity", "label": "Ecosystem reactivity", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	{"key": "music_coupling_floor", "label": "Min tank coupling", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	{"key": "music_smooth_rate", "label": "Follow speed", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	{"key": "music_phrase_churn", "label": "Phrase sensitivity", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	{"key": "music_tempo_follow", "label": "Tempo ↔ vitality", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	{"key": "music_accent_density", "label": "Accent density", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	{"key": "music_event_volume", "label": "Event prominence", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	{"key": "music_kick_mix", "label": "Kick level", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	{"key": "music_bass_mix", "label": "Bass level", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	{"key": "music_arp_mix", "label": "Arp level", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	{"key": "music_pad_mix", "label": "Pad level", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	{"key": "music_hat_mix", "label": "Hi-hat level", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	{"key": "music_sidechain", "label": "Sidechain pump", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	{"key": "music_filter_open", "label": "Filter brightness", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	{"key": "music_delay_amount", "label": "Delay send", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	{"key": "music_influence_fish", "label": "Fish → music", "min": 0.0, "max": 1.5, "step": 0.05, "pct": false},
	{"key": "music_influence_plants", "label": "Plants → music", "min": 0.0, "max": 1.5, "step": 0.05, "pct": false},
	{"key": "music_influence_bloom", "label": "Bloom → music", "min": 0.0, "max": 1.5, "step": 0.05, "pct": false},
	{"key": "music_influence_o2", "label": "O₂ → music", "min": 0.0, "max": 1.5, "step": 0.05, "pct": false},
	{"key": "music_influence_day", "label": "Daylight → music", "min": 0.0, "max": 1.5, "step": 0.05, "pct": false},
	{"key": "music_influence_aeration", "label": "Aeration → music", "min": 0.0, "max": 1.5, "step": 0.05, "pct": false},
	{"key": "music_influence_biomass", "label": "Biomass → music", "min": 0.0, "max": 1.5, "step": 0.05, "pct": false},
]


func _ready() -> void:
	_build_ui()
	_pull_from_config()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and visible:
		_close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M:
			toggle()


func _process(dt: float) -> void:
	if not visible:
		return
	_telemetry_t -= dt
	if _telemetry_t <= 0.0:
		_telemetry_t = 0.25
		_refresh_live_readout()


func toggle() -> void:
	if visible:
		_close()
	else:
		visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		_pull_from_config()
		_refresh_live_readout()


func _close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_ui() -> void:
	custom_minimum_size = Vector2(440, 0)
	PanelTheme.apply_panel_chrome(self)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)

	outer.add_child(PanelTheme.make_title("Sound Studio"))
	outer.add_child(PanelTheme.make_rule())

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	_add_section(vbox, "Live tank → music")
	_live_label = PanelTheme.make_description()
	_live_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_live_label)

	_add_section(vbox, "Master & character")
	_add_check(vbox, "music_enabled", "Enable sound")
	_add_slider_group(vbox, SLIDERS.slice(0, 4))

	_mood_option = PanelTheme.add_dropdown_row(vbox, "Mood")
	for entry in [
		{"key": "auto", "label": "Auto (follow tank)"},
		{"key": "calm", "label": "Calm (minor)"},
		{"key": "bright", "label": "Bright (major)"},
		{"key": "deep", "label": "Deep (low register)"},
	]:
		_mood_option.add_item(String(entry["label"]))
		_mood_option.set_item_metadata(_mood_option.item_count - 1, entry["key"])
	_mood_option.item_selected.connect(func(idx):
		TankConfig.music_mood = _mood_option.get_item_metadata(idx))

	_style_option = PanelTheme.add_dropdown_row(vbox, "Style")
	for entry in [
		{"key": "ambient", "label": "Ambient (soft accents)"},
		{"key": "hybrid", "label": "Hybrid (bed + events)"},
		{"key": "trance", "label": "Trance (pulse, arp, pad)"},
	]:
		_style_option.add_item(String(entry["label"]))
		_style_option.set_item_metadata(_style_option.item_count - 1, entry["key"])
	_style_option.item_selected.connect(func(idx):
		TankConfig.music_style = _style_option.get_item_metadata(idx))

	_add_section(vbox, "Tank coupling")
	_add_slider_group(vbox, SLIDERS.slice(4, 9))

	_add_section(vbox, "Layers")
	_add_check(vbox, "music_ambient_enabled", "Ambient accents")
	_add_check(vbox, "music_events_enabled", "Creature & plant events")
	_add_check(vbox, "music_environment_enabled", "Environment (bubbles, flow)")
	_add_slider_group(vbox, SLIDERS.slice(9, 18))

	_add_section(vbox, "Metric influence")
	var desc := PanelTheme.make_description()
	desc.text = "How strongly each live tank metric steers harmony, rhythm, and timbre."
	vbox.add_child(desc)
	_add_slider_group(vbox, SLIDERS.slice(18, 25))

	outer.add_child(PanelTheme.make_rule())
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	outer.add_child(action_row)

	var random_btn := PanelTheme.make_primary_button("🎲 Randomize")
	random_btn.tooltip_text = "Randomize sliders, style, and seed — still follows the live tank."
	random_btn.pressed.connect(_on_randomize)
	action_row.add_child(random_btn)

	var wild_btn := PanelTheme.make_secondary_button("🎲 Wild")
	wild_btn.tooltip_text = "Randomize everything including mood and style."
	wild_btn.pressed.connect(func(): _on_randomize(true))
	action_row.add_child(wild_btn)

	var nudge_btn := PanelTheme.make_secondary_button("↻ Nudge phrase")
	nudge_btn.tooltip_text = "Force a harmonic / arp shift from current tank state."
	nudge_btn.pressed.connect(_on_nudge_phrase)
	action_row.add_child(nudge_btn)

	outer.add_child(PanelTheme.make_rule())
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 8)
	outer.add_child(hb)
	var close := PanelTheme.make_secondary_button("Close")
	close.pressed.connect(_close)
	hb.add_child(close)
	var save := PanelTheme.make_primary_button("Save")
	save.pressed.connect(_on_save)
	hb.add_child(save)


func _add_section(parent: Node, label: String) -> void:
	parent.add_child(PanelTheme.make_spacer(4))
	parent.add_child(PanelTheme.make_section(label))


func _add_check(parent: Node, key: String, text: String) -> void:
	var cb := CheckBox.new()
	cb.text = text
	cb.toggled.connect(func(v):
		TankConfig.set(key, v)
		if key == "music_enabled" and not v:
			_silence_audio())
	_check_rows[key] = cb
	parent.add_child(cb)


func _add_slider_group(parent: Node, defs: Array) -> void:
	for def in defs:
		var key: String = String(def["key"])
		var label := Label.new()
		var slider: HSlider = PanelTheme.add_slider_row(
			parent,
			String(def["label"]),
			float(def["min"]),
			float(def["max"]),
			float(def["step"]),
			label,
		)
		slider.value_changed.connect(func(v: float):
			TankConfig.set(key, v)
			_update_slider_label(key))
		_slider_rows[key] = {"slider": slider, "label": label, "pct": bool(def.get("pct", false))}


func _pull_from_config() -> void:
	for key in _check_rows.keys():
		(_check_rows[key] as CheckBox).button_pressed = bool(TankConfig.get(key))
	for key in _slider_rows.keys():
		var row: Dictionary = _slider_rows[key]
		(row["slider"] as HSlider).value = float(TankConfig.get(key))
		_update_slider_label(key)
	for i in _mood_option.item_count:
		if _mood_option.get_item_metadata(i) == TankConfig.music_mood:
			_mood_option.select(i)
			break
	for i in _style_option.item_count:
		if _style_option.get_item_metadata(i) == TankConfig.music_style:
			_style_option.select(i)
			break


func _update_slider_label(key: String) -> void:
	if not _slider_rows.has(key):
		return
	var row: Dictionary = _slider_rows[key]
	var v: float = float((row["slider"] as HSlider).value)
	var lbl: Label = row["label"] as Label
	if bool(row["pct"]):
		lbl.text = "%d%%" % int(v * 100.0)
	else:
		lbl.text = "%.2f" % v


func _refresh_live_readout() -> void:
	var amb := _ambient()
	var status: Dictionary = amb.get_live_status() if amb != null and amb.has_method("get_live_status") else {}
	var bpm: float = float(status.get("bpm", 0.0))
	var vit: float = float(status.get("vitality", 0.0))
	var zone: String = "day" if int(status.get("day_zone", 1)) == 1 else "night"
	_live_label.text = (
		"BPM %.0f  ·  vitality %.0f%%  ·  %s phrase\n"
		% [bpm, vit * 100.0, zone]
		+ "fish %d  plants %d  biomass %d  bloom %.2f  O₂ %.2f  light %.0f%%\n"
		% [
			int(status.get("fish", 0)),
			int(status.get("plants", 0)),
			int(status.get("biomass", 0)),
			float(status.get("bloom", 0.0)),
			float(status.get("o2", 0.85)),
			float(status.get("daylight", 1.0)) * 100.0,
		]
		+ "chord %d  arp bank %d  phrase #%d  seed %d"
		% [
			int(status.get("chord_root", 0)),
			int(status.get("arp_idx", 0)),
			int(status.get("phrase", 0)),
			int(TankConfig.music_seed),
		]
	)


func _ambient() -> Node:
	var main := get_tree().current_scene
	if main == null:
		return null
	return main.get_node_or_null("AmbientAudio")


func _silence_audio() -> void:
	var amb := _ambient()
	if amb != null and amb.has_method("silence_immediately"):
		amb.silence_immediately()


func _on_randomize(wild: bool = false) -> void:
	TankConfig.randomize_music_params(wild)
	_pull_from_config()
	var amb := _ambient()
	if amb != null and amb.has_method("randomize_performance"):
		amb.randomize_performance()
	_refresh_live_readout()


func _on_nudge_phrase() -> void:
	var amb := _ambient()
	if amb != null and amb.has_method("randomize_performance"):
		amb.randomize_performance()
	_refresh_live_readout()


func _on_save() -> void:
	TankConfig.save_to_disk()
