# Sound Studio — dedicated procedural music panel.
#
# Exposes tank-reactive music parameters, live ecosystem readout, vibe
# presets (festival / lo-fi / ambient / tank-driven) and randomize.
# Toggle with M key or the ♪ HUD button.

extends PanelContainer

var _live_label: Label
var _state_badge: Label
var _mood_option: OptionButton
var _style_option: OptionButton
var _form_option: OptionButton
var _scale_option: OptionButton
var _persona_option: OptionButton
var _slider_rows: Dictionary = {}
var _check_rows: Dictionary = {}
var _telemetry_t: float = 0.0
var _record_button: Button
var _record_label: Label

# Slider definitions — each `key` lines up with a TankConfig var.
# `pct` shows the value as percent; otherwise raw 2-decimal float.
const SLIDERS: Dictionary = {
	# Vibe / master character
	"master": [
		{"key": "music_volume", "label": "Master volume", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_energy", "label": "Energy (BPM & drive)", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_complexity", "label": "Bed density", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_reactivity", "label": "Ecosystem reactivity", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	],
	# The festival/EDC moments — build/drop architecture & lead voice
	"drops": [
		{"key": "music_drop_intensity", "label": "Drop intensity", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_breakdown_depth", "label": "Breakdown depth", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_build_drama", "label": "Build dramaturgy", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_lead_mix", "label": "Supersaw lead level", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_lead_detune", "label": "Lead detune spread", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_offbeat_hat", "label": "Off-beat 8th hat", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_reverb_send", "label": "Reverb send", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	],
	# Groove — feel & humanity
	"groove": [
		{"key": "music_swing", "label": "Swing (lo-fi shuffle)", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_humanize", "label": "Humanize", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_breathe_lfo", "label": "Master breathe LFO", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	],
	# Lo-fi character
	"lofi": [
		{"key": "music_vinyl_crackle", "label": "Vinyl crackle", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_tape_wow", "label": "Tape wow / flutter", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_jazziness", "label": "Jazziness (chord spice)", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	],
	# Extra voices that layer under the bed
	"voices": [
		{"key": "music_sub_bass_mix", "label": "Sub-bass (40–80 Hz)", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_offbeat_bass_mix", "label": "PWM off-beat bass", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_granular_pad", "label": "Granular shimmer", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_vocoder_pad", "label": "Vocoded 'aah' choir", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_shaker_mix", "label": "Polyrhythmic shaker", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_clap_mix", "label": "Clap on 2 & 4", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	],
	# Tank state → sound (auto-tied via knobs)
	"tank_state": [
		{"key": "music_bitcrush_algae", "label": "Algae → bitcrush", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_bass_grit", "label": "Aggression → bass grit", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_pump_gate", "label": "Aeration → kick gate", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_key_mod", "label": "Key shift per in-game day", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	],
	# Tank coupling — how the live ecosystem steers the bed
	"coupling": [
		{"key": "music_coupling_floor", "label": "Min tank coupling", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_smooth_rate", "label": "Follow speed", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_phrase_churn", "label": "Phrase sensitivity", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_tempo_follow", "label": "Tempo ↔ vitality", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_accent_density", "label": "Accent density", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	],
	# Layer mix levels + per-layer FX
	"mix": [
		{"key": "music_event_volume", "label": "Event prominence", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_kick_mix", "label": "Kick level", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_bass_mix", "label": "Bass level", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_arp_mix", "label": "Arp level", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_pad_mix", "label": "Pad level", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_hat_mix", "label": "Hi-hat level", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_sidechain", "label": "Sidechain pump", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_filter_open", "label": "Filter brightness", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_delay_amount", "label": "Delay send", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	],
	# How strongly each live metric steers harmony / rhythm / timbre
	"influence": [
		{"key": "music_influence_fish", "label": "Fish → music", "min": 0.0, "max": 1.5, "step": 0.05, "pct": false},
		{"key": "music_influence_plants", "label": "Plants → music", "min": 0.0, "max": 1.5, "step": 0.05, "pct": false},
		{"key": "music_influence_bloom", "label": "Bloom → music", "min": 0.0, "max": 1.5, "step": 0.05, "pct": false},
		{"key": "music_influence_o2", "label": "O₂ → music", "min": 0.0, "max": 1.5, "step": 0.05, "pct": false},
		{"key": "music_influence_day", "label": "Daylight → music", "min": 0.0, "max": 1.5, "step": 0.05, "pct": false},
		{"key": "music_influence_aeration", "label": "Aeration → music", "min": 0.0, "max": 1.5, "step": 0.05, "pct": false},
		{"key": "music_influence_biomass", "label": "Biomass → music", "min": 0.0, "max": 1.5, "step": 0.05, "pct": false},
		{"key": "music_species_palette", "label": "Species palette", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
	],
}

# Snap-the-vibe presets. Each one stamps a coherent mood across many params at
# once — picking a preset is way more discoverable than dialing 30 sliders.
const PRESETS: Array = [
	{
		"key": "festival",
		"label": "🎉 Festival",
		"desc": "ABGT-style build → drop, full lead, sidechain slam.",
		"values": {
			"music_style": "trance",
			"music_phrase_form": "trance",
			"music_mood": "auto",
			"music_energy": 0.78,
			"music_complexity": 0.72,
			"music_drop_intensity": 0.95,
			"music_breakdown_depth": 0.85,
			"music_build_drama": 0.95,
			"music_lead_mix": 0.85,
			"music_lead_detune": 0.65,
			"music_offbeat_hat": 0.9,
			"music_reverb_send": 0.55,
			"music_swing": 0.0,
			"music_humanize": 0.08,
			"music_jazziness": 0.2,
			"music_vinyl_crackle": 0.0,
			"music_tape_wow": 0.05,
			"music_sidechain": 0.85,
			"music_kick_mix": 0.85,
			"music_bass_mix": 0.85,
			"music_arp_mix": 0.75,
			"music_pad_mix": 0.7,
			"music_hat_mix": 0.7,
			"music_delay_amount": 0.45,
			"music_filter_open": 0.7,
			"music_tempo_follow": 0.9,
			"music_phrase_churn": 0.65,
			"music_sub_bass_mix": 0.85,
			"music_offbeat_bass_mix": 0.75,
			"music_clap_mix": 0.85,
			"music_shaker_mix": 0.4,
			"music_granular_pad": 0.2,
			"music_vocoder_pad": 0.15,
			"music_breathe_lfo": 0.18,
			"music_bitcrush_algae": 0.0,
			"music_bass_grit": 0.55,
			"music_pump_gate": 0.4,
			"music_key_mod": 0.35,
		},
	},
	{
		"key": "lofi",
		"label": "☕ Lo-fi",
		"desc": "Vinyl, tape wow, jazz voicings, gentle swing, Rhodes EP.",
		"values": {
			"music_style": "ambient",
			"music_phrase_form": "loop",
			"music_mood": "calm",
			"music_energy": 0.32,
			"music_complexity": 0.45,
			"music_drop_intensity": 0.18,
			"music_breakdown_depth": 0.3,
			"music_build_drama": 0.18,
			"music_lead_mix": 0.25,
			"music_lead_detune": 0.2,
			"music_offbeat_hat": 0.2,
			"music_reverb_send": 0.6,
			"music_swing": 0.45,
			"music_humanize": 0.4,
			"music_jazziness": 0.85,
			"music_vinyl_crackle": 0.65,
			"music_tape_wow": 0.5,
			"music_sidechain": 0.45,
			"music_kick_mix": 0.45,
			"music_bass_mix": 0.7,
			"music_arp_mix": 0.6,
			"music_pad_mix": 0.85,
			"music_hat_mix": 0.4,
			"music_delay_amount": 0.55,
			"music_filter_open": 0.35,
			"music_sub_bass_mix": 0.55,
			"music_offbeat_bass_mix": 0.1,
			"music_clap_mix": 0.15,
			"music_shaker_mix": 0.55,
			"music_granular_pad": 0.55,
			"music_vocoder_pad": 0.4,
			"music_breathe_lfo": 0.6,
			"music_bitcrush_algae": 0.35,
			"music_bass_grit": 0.15,
			"music_pump_gate": 0.25,
			"music_key_mod": 0.15,
		},
	},
	{
		"key": "ambient",
		"label": "🌊 Ambient",
		"desc": "Soft accents, slow phrases, deep reverb, vocoded choir.",
		"values": {
			"music_style": "ambient",
			"music_phrase_form": "free",
			"music_mood": "auto",
			"music_energy": 0.28,
			"music_complexity": 0.35,
			"music_drop_intensity": 0.25,
			"music_breakdown_depth": 0.5,
			"music_build_drama": 0.3,
			"music_lead_mix": 0.2,
			"music_lead_detune": 0.4,
			"music_offbeat_hat": 0.15,
			"music_reverb_send": 0.7,
			"music_swing": 0.15,
			"music_humanize": 0.32,
			"music_jazziness": 0.55,
			"music_vinyl_crackle": 0.18,
			"music_tape_wow": 0.22,
			"music_sidechain": 0.4,
			"music_kick_mix": 0.25,
			"music_bass_mix": 0.55,
			"music_arp_mix": 0.4,
			"music_pad_mix": 0.9,
			"music_hat_mix": 0.2,
			"music_delay_amount": 0.5,
			"music_filter_open": 0.42,
			"music_sub_bass_mix": 0.5,
			"music_offbeat_bass_mix": 0.05,
			"music_clap_mix": 0.05,
			"music_shaker_mix": 0.25,
			"music_granular_pad": 0.7,
			"music_vocoder_pad": 0.65,
			"music_breathe_lfo": 0.7,
			"music_bitcrush_algae": 0.15,
			"music_bass_grit": 0.05,
			"music_pump_gate": 0.45,
			"music_key_mod": 0.25,
		},
	},
	{
		"key": "tank",
		"label": "🐠 Tank-driven",
		"desc": "Default — auto-follows the live ecosystem.",
		"values": {
			"music_style": "hybrid",
			"music_phrase_form": "auto",
			"music_mood": "auto",
			"music_energy": 0.55,
			"music_complexity": 0.55,
			"music_drop_intensity": 0.7,
			"music_breakdown_depth": 0.7,
			"music_lead_mix": 0.55,
			"music_lead_detune": 0.55,
			"music_offbeat_hat": 0.55,
			"music_reverb_send": 0.45,
			"music_swing": 0.08,
			"music_humanize": 0.22,
			"music_jazziness": 0.4,
			"music_vinyl_crackle": 0.2,
			"music_tape_wow": 0.18,
			"music_sidechain": 0.72,
		},
	},
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
		if event.keycode == KEY_M and not event.shift_pressed:
			var main: Node = get_tree().current_scene
			if main != null and main.has_method("_ui_toggle_side"):
				main.call("_ui_toggle_side", "sound")
				get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	if not visible:
		set_process(false)
		return
	_telemetry_t -= dt
	if _telemetry_t <= 0.0:
		_telemetry_t = 0.18
		_refresh_live_readout()
		_refresh_recording_label()


func toggle() -> void:
	if visible:
		_close()
	else:
		visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_process(true)
		_pull_from_config()
		_refresh_live_readout()


func _close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_ui() -> void:
	custom_minimum_size = Vector2(460, 0)
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

	# --- Live tank → music readout (phrase state badge + telemetry) ---
	_add_section(vbox, "Live tank → music")
	_state_badge = Label.new()
	PanelTheme.as_mono(_state_badge, PanelTheme.SIZE_ITEM)
	_state_badge.text = "verse"
	vbox.add_child(_state_badge)
	_live_label = PanelTheme.make_description()
	_live_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_live_label)

	# --- Snap-the-vibe presets ---
	_add_section(vbox, "Vibe presets")
	var preset_desc := PanelTheme.make_description()
	preset_desc.text = "Pick a vibe — snaps the whole studio. Sliders below tune from there."
	vbox.add_child(preset_desc)
	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 6)
	vbox.add_child(preset_row)
	for preset in PRESETS:
		var btn := PanelTheme.make_secondary_button(String(preset["label"]))
		btn.tooltip_text = String(preset["desc"])
		var p: Dictionary = preset
		btn.pressed.connect(func(): _apply_preset(p))
		preset_row.add_child(btn)

	# --- Master & character ---
	_add_section(vbox, "Master & character")
	_add_check(vbox, "music_enabled", "Enable sound")
	_add_slider_group(vbox, SLIDERS["master"])
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

	# Persona — a named bundle that biases scale + rhythm feel + voices + how
	# events reshape the music. "None" leaves the engine fully tank-driven.
	_persona_option = PanelTheme.add_dropdown_row(vbox, "Persona")
	for entry in [
		{"key": "none", "label": "None (pure tank-driven)"},
		{"key": "monk", "label": "Thelonious Monk (jazz-blues)"},
		{"key": "abgt", "label": "ABGT / Anjuna (trance)"},
		{"key": "lofi", "label": "Lo-fi / Dilla"},
		{"key": "dub", "label": "Dub techno / deep"},
	]:
		_persona_option.add_item(String(entry["label"]))
		_persona_option.set_item_metadata(_persona_option.item_count - 1, entry["key"])
	_persona_option.item_selected.connect(func(idx):
		TankConfig.music_persona = _persona_option.get_item_metadata(idx))

	# Harmonic scale. "Auto" follows the tank (major/minor by daylight, O2,
	# bloom...); the rest force a fixed scale, incl. the blues / modal flavors.
	_scale_option = PanelTheme.add_dropdown_row(vbox, "Scale")
	for entry in [
		{"key": "auto", "label": "Auto (tank-driven)"},
		{"key": "major", "label": "Major"},
		{"key": "minor", "label": "Minor"},
		{"key": "deep", "label": "Deep (low register)"},
		{"key": "blues_minor", "label": "Minor blues"},
		{"key": "blues_major", "label": "Major blues"},
		{"key": "dorian", "label": "Dorian"},
		{"key": "mixolydian", "label": "Mixolydian"},
		{"key": "bebop", "label": "Bebop dominant"},
		{"key": "whole_tone", "label": "Whole tone"},
	]:
		_scale_option.add_item(String(entry["label"]))
		_scale_option.set_item_metadata(_scale_option.item_count - 1, entry["key"])
	_scale_option.item_selected.connect(func(idx):
		TankConfig.music_scale = _scale_option.get_item_metadata(idx))

	_form_option = PanelTheme.add_dropdown_row(vbox, "Phrase form")
	for entry in [
		{"key": "auto", "label": "Auto (vitality-driven)"},
		{"key": "trance", "label": "Trance (strict 16/4/16/8)"},
		{"key": "loop", "label": "Loop (no drops, chill)"},
		{"key": "free", "label": "Free (event-driven only)"},
	]:
		_form_option.add_item(String(entry["label"]))
		_form_option.set_item_metadata(_form_option.item_count - 1, entry["key"])
	_form_option.item_selected.connect(func(idx):
		TankConfig.music_phrase_form = _form_option.get_item_metadata(idx))

	# --- Drop & build (the festival moments) ---
	_add_section(vbox, "Drop & build")
	var drop_desc := PanelTheme.make_description()
	drop_desc.text = "Breeding triggers a build into a drop. Deaths trigger a breakdown."
	vbox.add_child(drop_desc)
	_add_slider_group(vbox, SLIDERS["drops"])

	# --- Groove (feel & humanity) ---
	_add_section(vbox, "Groove")
	_add_slider_group(vbox, SLIDERS["groove"])

	# --- Lo-fi (character & texture) ---
	_add_section(vbox, "Lo-fi character")
	var lofi_desc := PanelTheme.make_description()
	lofi_desc.text = "Vinyl & tape wow tip the bed toward background-coffee-shop. Jazziness extends pad chords. Master breathe sweeps the cutoff across a slow LFO."
	vbox.add_child(lofi_desc)
	_add_slider_group(vbox, SLIDERS["lofi"])

	# --- Extra voices ---
	_add_section(vbox, "Extra voices")
	var voices_desc := PanelTheme.make_description()
	voices_desc.text = "Sub-bass adds depth; PWM bass plays \"&\"s between kicks; granular shimmer layers past pad echoes; vocoder turns the bubble env into an 'aah' choir; polyrhythmic shaker tracks creature movement."
	vbox.add_child(voices_desc)
	_add_slider_group(vbox, SLIDERS["voices"])

	# --- Tank-state coupling (FX driven by the live tank) ---
	_add_section(vbox, "Tank state → sound")
	var tank_state_desc := PanelTheme.make_description()
	tank_state_desc.text = "Algae bloom bitcrushes the synth; aggression hardens the bass clip; aeration low cuts the kick like the pump is the metronome; key shifts every in-game day."
	vbox.add_child(tank_state_desc)
	_add_slider_group(vbox, SLIDERS["tank_state"])

	# --- Layers + mix ---
	_add_section(vbox, "Layers")
	_add_check(vbox, "music_ambient_enabled", "Ambient accents")
	_add_check(vbox, "music_events_enabled", "Creature & plant events")
	_add_check(vbox, "music_environment_enabled", "Environment (bubbles, flow)")
	_add_slider_group(vbox, SLIDERS["mix"])

	# --- Tank coupling ---
	_add_section(vbox, "Tank coupling")
	_add_slider_group(vbox, SLIDERS["coupling"])

	# --- Metric influence ---
	_add_section(vbox, "Metric influence")
	var desc := PanelTheme.make_description()
	desc.text = "How strongly each live tank metric steers harmony, rhythm, and timbre. Species palette: 0 = all fish sound alike, 1 = max per-species coloring."
	vbox.add_child(desc)
	_add_slider_group(vbox, SLIDERS["influence"])

	# --- Recording (export to WAV) ---
	outer.add_child(PanelTheme.make_rule())
	_add_section(outer, "Record this jam")
	var rec_desc := PanelTheme.make_description()
	rec_desc.text = "Capture the current performance to a stereo WAV. Saves to user://recordings/ — up to 4 minutes."
	outer.add_child(rec_desc)
	var rec_row := HBoxContainer.new()
	rec_row.add_theme_constant_override("separation", 8)
	outer.add_child(rec_row)
	_record_button = PanelTheme.make_primary_button("⏺ Record")
	_record_button.tooltip_text = "Start / stop recording the master output."
	_record_button.pressed.connect(_on_toggle_recording)
	rec_row.add_child(_record_button)
	_record_label = Label.new()
	_record_label.text = "—"
	rec_row.add_child(_record_label)

	# --- Footer actions ---
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
		_slider_rows[key] = {"slider": slider, "label": label, "pct": not not def.get("pct", false)}


func _pull_from_config() -> void:
	for key in _check_rows.keys():
		(_check_rows[key] as CheckBox).button_pressed = not not TankConfig.get(key)
	for key in _slider_rows.keys():
		var row: Dictionary = _slider_rows[key]
		(row["slider"] as HSlider).value = float(TankConfig.get(key))
		_update_slider_label(key)
	_sync_option(_mood_option, String(TankConfig.music_mood))
	_sync_option(_style_option, String(TankConfig.music_style))
	_sync_option(_persona_option, String(TankConfig.music_persona))
	_sync_option(_scale_option, String(TankConfig.music_scale))
	_sync_option(_form_option, String(TankConfig.music_phrase_form))


func _sync_option(opt: OptionButton, value: String) -> void:
	if opt == null:
		return
	for i in opt.item_count:
		if String(opt.get_item_metadata(i)) == value:
			opt.select(i)
			return


func _update_slider_label(key: String) -> void:
	if not _slider_rows.has(key):
		return
	var row: Dictionary = _slider_rows[key]
	var v: float = float((row["slider"] as HSlider).value)
	var lbl: Label = row["label"] as Label
	if row["pct"]:
		lbl.text = "%d%%" % int(v * 100.0)
	else:
		lbl.text = "%.2f" % v


# A small visual cue colored by phrase state. Quick to scan at a glance.
func _state_badge_style(state_name: String) -> String:
	match state_name:
		"build":     return "▲ BUILD"
		"drop":      return "● DROP"
		"breakdown": return "▽ BREAKDOWN"
		"chorus":    return "★ CHORUS"
		"verse":     return "○ verse"
		_:           return "— —"


func _state_badge_color(state_name: String) -> Color:
	match state_name:
		"build":     return Color(1.0, 0.78, 0.32)
		"drop":      return Color(1.0, 0.42, 0.32)
		"breakdown": return Color(0.55, 0.55, 0.82)
		"chorus":    return Color(0.42, 1.0, 0.78)
		"verse":     return Color(0.85, 0.85, 0.92)
		_:           return Color(0.6, 0.6, 0.7)


func _refresh_live_readout() -> void:
	var amb := _ambient()
	var status: Dictionary = amb.get_live_status() if amb != null and amb.has_method("get_live_status") else {}
	var bpm: float = float(status.get("bpm", 0.0))
	var vit: float = float(status.get("vitality", 0.0))
	var zone: String = "day" if int(status.get("day_zone", 1)) == 1 else "night"
	var state_name: String = String(status.get("phrase_state_name", "verse"))
	var bars_left: int = int(status.get("phrase_state_bars_left", 0))
	if _state_badge != null:
		_state_badge.text = "%s   ·   %d bars left   ·   %.0f BPM" % [
			_state_badge_style(state_name),
			bars_left,
			bpm,
		]
		_state_badge.add_theme_color_override("font_color", _state_badge_color(state_name))
	if _live_label != null:
		_live_label.text = (
			"vitality %.0f%%  ·  %s phrase\n" % [vit * 100.0, zone]
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


func _apply_preset(preset: Dictionary) -> void:
	var values: Dictionary = preset.get("values", {})
	for key in values.keys():
		TankConfig.set(key, values[key])
	# Re-seed only on explicit randomize, not on preset.
	_pull_from_config()
	var amb := _ambient()
	if amb != null and amb.has_method("randomize_performance"):
		# Reset performance state so the new vibe lands cleanly.
		amb.randomize_performance()
	_refresh_live_readout()


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


func _on_toggle_recording() -> void:
	var amb := _ambient()
	if amb == null:
		return
	if amb.has_method("is_recording") and bool(amb.is_recording()):
		if amb.has_method("stop_recording_and_save"):
			var path: String = String(amb.stop_recording_and_save())
			if path == "":
				_record_label.text = "Save failed."
			else:
				# Show just the filename — user://… is shell-meaningless.
				var fname: String = path.get_file()
				_record_label.text = "Saved %s" % fname
		_record_button.text = "⏺ Record"
	else:
		if amb.has_method("start_recording"):
			amb.start_recording()
			_record_button.text = "⏹ Stop"
			_record_label.text = "Recording…"


func _refresh_recording_label() -> void:
	var amb := _ambient()
	if amb == null or _record_label == null:
		return
	if amb.has_method("is_recording") and bool(amb.is_recording()):
		var len_s: float = 0.0
		if amb.has_method("recording_length"):
			len_s = float(amb.recording_length())
		_record_label.text = "Recording  %.1f s" % len_s
