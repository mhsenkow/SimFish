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
# Music sync (tank ↔ Spotify / local audio)
var _sync_enable_check: CheckBox
var _sync_intensity_slider: HSlider
var _sync_intensity_label: Label
var _sync_status_label: Label
var _sync_now_playing: Label
var _sync_search_edit: LineEdit
var _sync_url_edit: LineEdit
var _sync_client_id_edit: LineEdit
var _sync_client_secret_edit: LineEdit
var _sync_results: ItemList
var _sync_bars: Array[ColorRect] = []
var _sync_channel_checks: Dictionary = {}
var _spotify_block: VBoxContainer
var _spotify_toggle_btn: Button
var _tabs: TabContainer
var _tank_score_body: VBoxContainer
var _tank_score_paused: VBoxContainer
var _calibrate_latency_label: Label
var _bar_legend: Label

# Bundled demo tracks — secondary ghost buttons under the primary upload CTA.
const DEMO_TRACKS: Array = [
	{
		"path": "res://assets/audio/demos/demo_dirt.mp3",
		"label": "Dirt",
		"desc": "Mid-tempo pocket — calmer sway.",
		"values": {"music_dance_style": "sway", "music_showiness": 0.48},
	},
	{
		"path": "res://assets/audio/demos/demo_synthetic_love.wav",
		"label": "Synthetic Love",
		"desc": "Warm synth groove.",
		"values": {"music_dance_style": "sway", "music_showiness": 0.52},
	},
	{
		"path": "res://assets/audio/demos/demo_patterns.wav",
		"label": "Patterns",
		"desc": "Acoustic build — layered phrase arc.",
		"values": {"music_dance_style": "stately", "music_showiness": 0.55},
	},
	{
		"path": "res://assets/audio/demos/demo_kissed_backend.wav",
		"label": "I Kissed the Backend",
		"desc": "Playful bounce — steady four-on-the-floor.",
		"values": {"music_dance_style": "bounce", "music_showiness": 0.58},
	},
	{
		"path": "res://assets/audio/demos/demo_tech.mp3",
		"label": "In da Tech",
		"desc": "Tech-house drive — steady groove.",
		"values": {"music_dance_style": "bounce", "music_showiness": 0.55},
	},
	{
		"path": "res://assets/audio/demos/demo_byte.wav",
		"label": "Byte",
		"desc": "Electronic pulse — sync-friendly.",
		"values": {"music_dance_style": "sync", "music_showiness": 0.6},
	},
]

# Slider definitions — each `key` lines up with a TankConfig var.
# `pct` shows the value as percent; otherwise raw 2-decimal float.
const SLIDERS: Dictionary = {
	# Vibe / master character
	"master": [
		{"key": "music_volume", "label": "Master volume", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_energy", "label": "Energy (BPM & drive)", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_complexity", "label": "Bed density", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_reactivity", "label": "Ecosystem reactivity", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
		{"key": "music_showiness", "label": "Dance showiness", "min": 0.0, "max": 1.0, "step": 0.05, "pct": true},
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

# Choreography presets — lock dance language independent of vibe.
const DANCE_PRESETS: Array = [
	{
		"key": "demo_dance",
		"label": "✨ Demo dance",
		"desc": "Festival trance + full showiness — the wow preset.",
		"values": {
			"music_persona": "abgt",
			"music_style": "trance",
			"music_phrase_form": "trance",
			"music_showiness": 1.0,
			"music_energy": 0.82,
			"music_drop_intensity": 1.0,
			"music_build_drama": 0.95,
			"music_dance_style": "sync",
			"music_reactivity": 0.85,
		},
	},
	{"key": "auto", "label": "🎯 Auto", "desc": "Genre from the track.", "values": {"music_dance_style": "auto"}},
	{"key": "ballet", "label": "🩰 Ballet", "desc": "Slow wide arcs.", "values": {"music_dance_style": "ballet"}},
	{"key": "frenzy", "label": "⚡ Frenzy", "desc": "DnB scatter energy.", "values": {"music_dance_style": "frenzy"}},
	{"key": "sway", "label": "🌙 Sway", "desc": "Lo-fi lazy groove.", "values": {"music_dance_style": "sway"}},
	{"key": "stately", "label": "🎻 Stately", "desc": "Orchestral formations.", "values": {"music_dance_style": "stately"}},
]

const CONDUCT_MOVES: Array = [
	{"move": "wave", "formation": "line", "label": "〜 Wave"},
	{"move": "vortex", "formation": "circle", "label": "◎ Vortex"},
	{"move": "starburst", "formation": "scatter", "label": "✦ Burst"},
	{"move": "carousel", "formation": "v", "label": "↻ Carousel"},
]


func _ready() -> void:
	_build_ui()
	_pull_from_config()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mr := _music_reactive()
	if mr != null:
		if not mr.search_results_ready.is_connected(_on_sync_search_results):
			mr.search_results_ready.connect(_on_sync_search_results)
		if not mr.status_message.is_connected(_on_sync_status):
			mr.status_message.connect(_on_sync_status)
		if not mr.track_changed.is_connected(_on_sync_track_changed):
			mr.track_changed.connect(_on_sync_track_changed)


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
		_refresh_sync_visualizer()
		_update_panel_mode()
		_refresh_calibrate_label()


func toggle() -> void:
	if visible:
		_close()
	else:
		visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_process(true)
		_pull_from_config()
		_refresh_live_readout()
		_update_panel_mode()
		if _tabs != null and _external_sync_live():
			_tabs.current_tab = 0


func _close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_ui() -> void:
	custom_minimum_size = Vector2(500, 0)
	PanelTheme.apply_panel_chrome(self)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)

	outer.add_child(PanelTheme.make_title("Sound Studio"))
	var subtitle := PanelTheme.make_description()
	subtitle.text = "Now Playing for your track · Tank score for procedural ambient · Choreography for the dance."
	outer.add_child(subtitle)
	outer.add_child(PanelTheme.make_rule())

	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_tabs)

	var now_playing := _new_tab_scroll(_tabs, "Now Playing")
	_build_now_playing_tab(now_playing)

	var tank_score := _new_tab_scroll(_tabs, "Tank score")
	_build_tank_score_tab(tank_score)

	var choreography := _new_tab_scroll(_tabs, "Choreography")
	_build_choreography_tab(choreography)

	var save := PanelTheme.make_primary_button("Save")
	save.pressed.connect(_on_save)
	outer.add_child(PanelTheme.make_panel_footer(_close, save))


func _new_tab_scroll(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	return vbox


func _build_now_playing_tab(vbox: VBoxContainer) -> void:
	_build_music_sync_section(vbox)


func _build_tank_score_tab(vbox: VBoxContainer) -> void:
	_tank_score_paused = VBoxContainer.new()
	_tank_score_paused.add_theme_constant_override("separation", 8)
	_tank_score_paused.visible = false
	vbox.add_child(_tank_score_paused)
	var paused_desc := PanelTheme.make_description()
	paused_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	paused_desc.text = (
		"A track is playing — the procedural tank score is muted so it doesn't fight your file. "
		+ "Open the Tank score tab after you stop, or tap below to tune the bed anyway."
	)
	_tank_score_paused.add_child(paused_desc)
	var show_score_btn := PanelTheme.make_secondary_button("Show tank score anyway")
	show_score_btn.pressed.connect(func():
		if _tank_score_body != null:
			_tank_score_body.visible = true
		if _tank_score_paused != null:
			_tank_score_paused.visible = false)
	_tank_score_paused.add_child(show_score_btn)

	_tank_score_body = VBoxContainer.new()
	_tank_score_body.add_theme_constant_override("separation", 10)
	vbox.add_child(_tank_score_body)

	_add_section(_tank_score_body, "Vibe presets")
	var preset_desc := PanelTheme.make_description()
	preset_desc.text = "Pick a vibe — snaps the whole studio. Sliders below tune from there."
	_tank_score_body.add_child(preset_desc)
	var preset_flow := FlowContainer.new()
	preset_flow.add_theme_constant_override("h_separation", 6)
	preset_flow.add_theme_constant_override("v_separation", 6)
	_tank_score_body.add_child(preset_flow)
	for preset in PRESETS:
		var btn := PanelTheme.make_secondary_button(String(preset["label"]))
		btn.tooltip_text = String(preset["desc"])
		var p: Dictionary = preset
		btn.pressed.connect(func(): _apply_preset(p))
		preset_flow.add_child(btn)

	_add_section(_tank_score_body, "Master & character")
	_add_check(_tank_score_body, "music_enabled", "Enable procedural sound")
	for def in SLIDERS["master"]:
		if String(def["key"]) == "music_showiness":
			continue
		_add_slider_group(_tank_score_body, [def])
	_mood_option = PanelTheme.add_dropdown_row(_tank_score_body, "Mood")
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

	_style_option = PanelTheme.add_dropdown_row(_tank_score_body, "Style")
	for entry in [
		{"key": "ambient", "label": "Ambient (soft accents)"},
		{"key": "hybrid", "label": "Hybrid (bed + events)"},
		{"key": "trance", "label": "Trance (pulse, arp, pad)"},
	]:
		_style_option.add_item(String(entry["label"]))
		_style_option.set_item_metadata(_style_option.item_count - 1, entry["key"])
	_style_option.item_selected.connect(func(idx):
		TankConfig.music_style = _style_option.get_item_metadata(idx))

	_persona_option = PanelTheme.add_dropdown_row(_tank_score_body, "Persona")
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

	_scale_option = PanelTheme.add_dropdown_row(_tank_score_body, "Scale")
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

	_form_option = PanelTheme.add_dropdown_row(_tank_score_body, "Phrase form")
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

	_add_section(_tank_score_body, "Drop & build")
	var drop_desc := PanelTheme.make_description()
	drop_desc.text = "Breeding triggers a build into a drop. Deaths trigger a breakdown."
	_tank_score_body.add_child(drop_desc)
	_add_slider_group(_tank_score_body, SLIDERS["drops"])

	_add_section(_tank_score_body, "Groove")
	_add_slider_group(_tank_score_body, SLIDERS["groove"])

	_add_section(_tank_score_body, "Lo-fi character")
	var lofi_desc := PanelTheme.make_description()
	lofi_desc.text = "Vinyl & tape wow tip the bed toward background-coffee-shop. Jazziness extends pad chords. Master breathe sweeps the cutoff across a slow LFO."
	_tank_score_body.add_child(lofi_desc)
	_add_slider_group(_tank_score_body, SLIDERS["lofi"])

	_add_section(_tank_score_body, "Extra voices")
	var voices_desc := PanelTheme.make_description()
	voices_desc.text = "Sub-bass adds depth; PWM bass plays \"&\"s between kicks; granular shimmer layers past pad echoes; vocoder turns the bubble env into an 'aah' choir; polyrhythmic shaker tracks creature movement."
	_tank_score_body.add_child(voices_desc)
	_add_slider_group(_tank_score_body, SLIDERS["voices"])

	_add_section(_tank_score_body, "Tank state → sound")
	var tank_state_desc := PanelTheme.make_description()
	tank_state_desc.text = "Algae bloom bitcrushes the synth; aggression hardens the bass clip; aeration low cuts the kick like the pump is the metronome; key shifts every in-game day."
	_tank_score_body.add_child(tank_state_desc)
	_add_slider_group(_tank_score_body, SLIDERS["tank_state"])

	_add_section(_tank_score_body, "Layers")
	_add_check(_tank_score_body, "music_ambient_enabled", "Ambient accents")
	_add_check(_tank_score_body, "music_events_enabled", "Creature & plant events")
	_add_check(_tank_score_body, "music_environment_enabled", "Environment (bubbles, flow)")
	_add_slider_group(_tank_score_body, SLIDERS["mix"])

	_add_section(_tank_score_body, "Tank coupling")
	_add_slider_group(_tank_score_body, SLIDERS["coupling"])

	_add_section(_tank_score_body, "Metric influence")
	var infl_desc := PanelTheme.make_description()
	infl_desc.text = "How strongly each live tank metric steers harmony, rhythm, and timbre. Species palette: 0 = all fish sound alike, 1 = max per-species coloring."
	_tank_score_body.add_child(infl_desc)
	_add_slider_group(_tank_score_body, SLIDERS["influence"])

	_add_section(_tank_score_body, "Record this jam")
	var rec_desc := PanelTheme.make_description()
	rec_desc.text = "Capture the procedural performance to a stereo WAV. Saves to user://recordings/ — up to 4 minutes."
	_tank_score_body.add_child(rec_desc)
	var rec_row := HBoxContainer.new()
	rec_row.add_theme_constant_override("separation", 8)
	_tank_score_body.add_child(rec_row)
	_record_button = PanelTheme.make_primary_button("⏺ Record")
	_record_button.tooltip_text = "Start / stop recording the master output."
	_record_button.pressed.connect(_on_toggle_recording)
	rec_row.add_child(_record_button)
	_record_label = Label.new()
	_record_label.text = "—"
	rec_row.add_child(_record_label)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	_tank_score_body.add_child(action_row)
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


func _build_choreography_tab(vbox: VBoxContainer) -> void:
	_add_section(vbox, "Live readout")
	_state_badge = Label.new()
	PanelTheme.as_mono(_state_badge, PanelTheme.SIZE_ITEM)
	_state_badge.text = "verse"
	vbox.add_child(_state_badge)
	_live_label = PanelTheme.make_description()
	_live_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_live_label)

	_add_section(vbox, "Dance style")
	var dance_desc := PanelTheme.make_description()
	dance_desc.text = "How the school moves — auto follows the track genre, or lock a style."
	vbox.add_child(dance_desc)
	var dance_flow := FlowContainer.new()
	dance_flow.add_theme_constant_override("h_separation", 6)
	dance_flow.add_theme_constant_override("v_separation", 6)
	vbox.add_child(dance_flow)
	for dp in DANCE_PRESETS:
		var dbtn := PanelTheme.make_secondary_button(String(dp["label"]))
		dbtn.tooltip_text = String(dp["desc"])
		var d: Dictionary = dp
		dbtn.pressed.connect(func(): _apply_preset(d))
		dance_flow.add_child(dbtn)

	_add_section(vbox, "Conduct on the beat")
	var conduct_flow := FlowContainer.new()
	conduct_flow.add_theme_constant_override("h_separation", 6)
	conduct_flow.add_theme_constant_override("v_separation", 6)
	vbox.add_child(conduct_flow)
	for cm in CONDUCT_MOVES:
		var cbtn := PanelTheme.make_secondary_button(String(cm["label"]))
		var c: Dictionary = cm
		cbtn.pressed.connect(func(): _conduct_move(c))
		conduct_flow.add_child(cbtn)

	var capture_btn := PanelTheme.make_secondary_button("📸 Capture dance")
	capture_btn.tooltip_text = "Save a 2s PNG burst + hero frame while the tank dances."
	capture_btn.pressed.connect(_on_capture_dance)
	vbox.add_child(capture_btn)


func _build_music_sync_section(vbox: VBoxContainer) -> void:
	_add_section(vbox, "Your track")
	var intro := PanelTheme.make_description()
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.text = (
		"Pick a file or demo — the tank reads the beat and the school dances to it. "
		+ "Upload stays in the background; this tab is transport and performance tuning."
	)
	vbox.add_child(intro)

	var sync_top := HBoxContainer.new()
	sync_top.add_theme_constant_override("separation", 12)
	vbox.add_child(sync_top)
	_sync_enable_check = CheckBox.new()
	_sync_enable_check.text = "Sync tank to music"
	_sync_enable_check.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_sync_enable_check.toggled.connect(_on_sync_enabled_toggled)
	sync_top.add_child(_sync_enable_check)
	var intensity_box := VBoxContainer.new()
	intensity_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sync_top.add_child(intensity_box)
	_sync_intensity_label = Label.new()
	_sync_intensity_slider = PanelTheme.add_slider_row(
		intensity_box, "Sync intensity", 0.0, 1.0, 0.05, _sync_intensity_label)
	_sync_intensity_slider.value_changed.connect(func(v: float):
		TankConfig.music_sync_intensity = v
		_sync_intensity_label.text = "%.0f%%" % (v * 100.0)
		var mr := _music_reactive()
		if mr != null:
			mr.set_intensity(v))

	var perf_box := VBoxContainer.new()
	vbox.add_child(perf_box)
	var showiness_label := Label.new()
	var showiness_slider: HSlider = PanelTheme.add_slider_row(
		perf_box, "Dance showiness", 0.0, 1.0, 0.05, showiness_label)
	showiness_slider.value_changed.connect(func(v: float):
		TankConfig.music_showiness = v
		showiness_label.text = "%d%%" % int(v * 100.0))
	_slider_rows["music_showiness"] = {"slider": showiness_slider, "label": showiness_label, "pct": true}

	var load_btn := PanelTheme.make_primary_button("Choose audio file…")
	load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_btn.tooltip_text = "Pick MP3, OGG, or WAV from your computer."
	load_btn.pressed.connect(_on_sync_local_file)
	vbox.add_child(load_btn)

	var demo_label := PanelTheme.make_description()
	demo_label.text = "Example demos — tap to play a bundled track:"
	vbox.add_child(demo_label)
	var demo_grid := GridContainer.new()
	demo_grid.columns = 2
	demo_grid.add_theme_constant_override("h_separation", 8)
	demo_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(demo_grid)
	for demo in DEMO_TRACKS:
		var dbtn := PanelTheme.make_chip_button("▶ %s" % String(demo["label"]))
		dbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dbtn.tooltip_text = String(demo["desc"])
		var d: Dictionary = demo
		dbtn.pressed.connect(func(): _on_play_demo_track(d))
		demo_grid.add_child(dbtn)

	var transport_row := HBoxContainer.new()
	transport_row.add_theme_constant_override("separation", 6)
	vbox.add_child(transport_row)
	var pause_btn := PanelTheme.make_secondary_button("Pause")
	pause_btn.pressed.connect(func():
		var mr := _music_reactive()
		if mr != null:
			mr.toggle_pause())
	transport_row.add_child(pause_btn)
	var stop_btn := PanelTheme.make_secondary_button("Stop")
	stop_btn.pressed.connect(func():
		var mr := _music_reactive()
		if mr != null:
			mr.stop())
	transport_row.add_child(stop_btn)

	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 4)
	bar_row.custom_minimum_size.y = 36.0
	vbox.add_child(bar_row)
	for i in 4:
		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(0, 28)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.color = Color(0.2, 0.25, 0.35, 0.85)
		bar_row.add_child(bar)
		_sync_bars.append(bar)

	_bar_legend = PanelTheme.make_description()
	_bar_legend.text = "Bass · Mid · Treble · Beat"
	vbox.add_child(_bar_legend)

	var calibrate_desc := PanelTheme.make_description()
	calibrate_desc.text = "Calibrate this track (session only — not saved):"
	vbox.add_child(calibrate_desc)
	var calibrate_row := HBoxContainer.new()
	calibrate_row.add_theme_constant_override("separation", 6)
	vbox.add_child(calibrate_row)
	var reset_meters_btn := PanelTheme.make_secondary_button("Reset meters")
	reset_meters_btn.tooltip_text = "Re-learn auto-gain for bass/mid/treble on this track."
	reset_meters_btn.pressed.connect(_on_calibrate_reset_meters)
	calibrate_row.add_child(reset_meters_btn)
	var lat_down := PanelTheme.make_secondary_button("−20 ms")
	lat_down.pressed.connect(func(): _on_calibrate_latency(-20.0))
	calibrate_row.add_child(lat_down)
	var lat_up := PanelTheme.make_secondary_button("+20 ms")
	lat_up.pressed.connect(func(): _on_calibrate_latency(20.0))
	calibrate_row.add_child(lat_up)
	var lat_reset := PanelTheme.make_ghost_button("Reset timing")
	lat_reset.pressed.connect(_on_calibrate_reset_timing)
	calibrate_row.add_child(lat_reset)
	_calibrate_latency_label = PanelTheme.make_description()
	vbox.add_child(_calibrate_latency_label)

	_sync_now_playing = Label.new()
	PanelTheme.as_serif(_sync_now_playing, PanelTheme.SIZE_ITEM)
	_sync_now_playing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sync_now_playing.text = "—"
	vbox.add_child(_sync_now_playing)

	_sync_status_label = PanelTheme.make_description()
	_sync_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_sync_status_label)

	var channel_row := FlowContainer.new()
	channel_row.add_theme_constant_override("h_separation", 10)
	channel_row.add_theme_constant_override("v_separation", 4)
	vbox.add_child(channel_row)
	for entry in [
		{"key": "music_sync_fish", "label": "Fish"},
		{"key": "music_sync_lights", "label": "Lights"},
		{"key": "music_sync_color", "label": "Color"},
		{"key": "music_sync_plants", "label": "Plants"},
		{"key": "music_sync_bubbles", "label": "Bubbles"},
	]:
		var cb := CheckBox.new()
		cb.text = String(entry["label"])
		var k: String = String(entry["key"])
		cb.toggled.connect(func(v: bool): TankConfig.set(k, v))
		_sync_channel_checks[k] = cb
		channel_row.add_child(cb)

	_spotify_toggle_btn = PanelTheme.make_ghost_button("▸ Spotify previews (experimental, often flaky)")
	_spotify_toggle_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_spotify_toggle_btn.pressed.connect(_toggle_spotify_section)
	vbox.add_child(_spotify_toggle_btn)

	_spotify_block = VBoxContainer.new()
	_spotify_block.add_theme_constant_override("separation", 6)
	_spotify_block.visible = false
	vbox.add_child(_spotify_block)

	var spotify_note := PanelTheme.make_description()
	spotify_note.text = (
		"Spotify only exposes 30-second preview clips and needs developer API keys. "
		+ "Local files work much better for full-track dancing."
	)
	spotify_note.add_theme_color_override("font_color", PanelTheme.DIM_FG.darkened(0.08))
	_spotify_block.add_child(spotify_note)

	var cred_row := HBoxContainer.new()
	cred_row.add_theme_constant_override("separation", 6)
	_spotify_block.add_child(cred_row)
	_sync_client_id_edit = LineEdit.new()
	_sync_client_id_edit.placeholder_text = "Spotify Client ID"
	_sync_client_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sync_client_id_edit.text_submitted.connect(func(_t): _save_spotify_creds())
	cred_row.add_child(_sync_client_id_edit)
	_sync_client_secret_edit = LineEdit.new()
	_sync_client_secret_edit.placeholder_text = "Client Secret"
	_sync_client_secret_edit.secret = true
	_sync_client_secret_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sync_client_secret_edit.text_submitted.connect(func(_t): _save_spotify_creds())
	cred_row.add_child(_sync_client_secret_edit)

	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 6)
	_spotify_block.add_child(search_row)
	_sync_search_edit = LineEdit.new()
	_sync_search_edit.placeholder_text = "Search Spotify…"
	_sync_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sync_search_edit.text_submitted.connect(_on_sync_search)
	search_row.add_child(_sync_search_edit)
	var search_btn := PanelTheme.make_ghost_button("Search")
	search_btn.pressed.connect(_on_sync_search)
	search_row.add_child(search_btn)

	_sync_results = ItemList.new()
	_sync_results.custom_minimum_size.y = 72.0
	_sync_results.item_activated.connect(_on_sync_result_picked)
	_spotify_block.add_child(_sync_results)

	_sync_url_edit = LineEdit.new()
	_sync_url_edit.placeholder_text = "Or paste open.spotify.com/track/…"
	_sync_url_edit.text_submitted.connect(_on_sync_url_play)
	_spotify_block.add_child(_sync_url_edit)

	var spotify_play_row := HBoxContainer.new()
	spotify_play_row.add_theme_constant_override("separation", 6)
	_spotify_block.add_child(spotify_play_row)
	var url_btn := PanelTheme.make_ghost_button("Play link")
	url_btn.pressed.connect(_on_sync_url_play)
	spotify_play_row.add_child(url_btn)


func _external_sync_live() -> bool:
	var mr := _music_reactive()
	return mr != null and mr.has_method("is_external_playing") and mr.is_external_playing()


func _update_panel_mode() -> void:
	if _tank_score_body == null or _tank_score_paused == null:
		return
	var hide_score := TankConfig.music_sync_enabled and _external_sync_live()
	if hide_score:
		_tank_score_paused.visible = true
		_tank_score_body.visible = false
	else:
		_tank_score_paused.visible = false
		_tank_score_body.visible = true


func _refresh_calibrate_label() -> void:
	if _calibrate_latency_label == null:
		return
	var mr := _music_reactive()
	var base: float = float(TankConfig.music_sync_latency_ms)
	var offset: float = 0.0
	var total: float = base
	if mr != null and mr.has_method("session_latency_ms"):
		total = float(mr.session_latency_ms())
		if mr.has_method("session_latency_offset_ms"):
			offset = float(mr.session_latency_offset_ms())
	if absf(offset) < 0.5:
		_calibrate_latency_label.text = "Beat timing: %.0f ms (saved default)" % base
	else:
		_calibrate_latency_label.text = "Beat timing: %.0f ms (%+.0f ms this session)" % [total, offset]


func _on_calibrate_reset_meters() -> void:
	var mr := _music_reactive()
	if mr != null and mr.has_method("reset_meter_calibration"):
		mr.reset_meter_calibration()
	_on_sync_status("Meters recalibrated for this track.", false)


func _on_calibrate_latency(delta_ms: float) -> void:
	var mr := _music_reactive()
	if mr != null and mr.has_method("nudge_session_latency"):
		mr.nudge_session_latency(delta_ms)
	_refresh_calibrate_label()


func _on_calibrate_reset_timing() -> void:
	var mr := _music_reactive()
	if mr != null and mr.has_method("reset_session_latency"):
		mr.reset_session_latency()
	_refresh_calibrate_label()
	_on_sync_status("Beat timing offset reset for this session.", false)


func _focus_now_playing_tab() -> void:
	if _tabs != null:
		_tabs.current_tab = 0
	_update_panel_mode()
	_refresh_calibrate_label()


func _on_sync_enabled_toggled(on: bool) -> void:
	TankConfig.music_sync_enabled = on
	var mr := _music_reactive()
	if mr != null:
		mr.set_enabled(on)


func _on_sync_search(_text: String = "") -> void:
	_save_spotify_creds()
	var mr := _music_reactive()
	if mr != null:
		mr.search_spotify(_sync_search_edit.text)


func _on_sync_url_play(_text: String = "") -> void:
	_save_spotify_creds()
	var mr := _music_reactive()
	if mr != null:
		mr.play_spotify_url(_sync_url_edit.text)


func _on_sync_local_file() -> void:
	var mr := _music_reactive()
	if mr != null:
		mr.pick_local_file()


func _on_play_demo_track(demo: Dictionary) -> void:
	var values: Dictionary = demo.get("values", {})
	for key in values.keys():
		TankConfig.set(String(key), values[key])
		if _slider_rows.has(key):
			var row: Dictionary = _slider_rows[key]
			(row["slider"] as HSlider).value = float(values[key])
			_update_slider_label(String(key))
	if not TankConfig.music_sync_enabled:
		TankConfig.music_sync_enabled = true
		if _sync_enable_check != null:
			_sync_enable_check.button_pressed = true
	var mr := _music_reactive()
	if mr != null:
		mr.set_enabled(true)
		mr.play_res_path(
			String(demo["path"]),
			String(demo["label"]),
			"Bundled demo")
	_focus_now_playing_tab()


func _toggle_spotify_section() -> void:
	if _spotify_block == null or _spotify_toggle_btn == null:
		return
	_spotify_block.visible = not _spotify_block.visible
	_spotify_toggle_btn.text = (
		"▾ Spotify previews (experimental, often flaky)"
		if _spotify_block.visible
		else "▸ Spotify previews (experimental, often flaky)"
	)


func _on_sync_result_picked(index: int) -> void:
	var mr := _music_reactive()
	if mr != null:
		mr.play_search_result(index)


func _on_sync_search_results(results: Array) -> void:
	if _sync_results == null:
		return
	_sync_results.clear()
	for item in results:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		_sync_results.add_item("%s — %s" % [item.get("name", "?"), item.get("artists", "")])


func _on_sync_status(text: String, is_error: bool) -> void:
	if _sync_status_label == null:
		return
	_sync_status_label.text = text
	_sync_status_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.55, 0.5) if is_error else PanelTheme.DIM_FG)


func _on_sync_track_changed(meta: Dictionary) -> void:
	if _sync_now_playing == null:
		return
	_sync_now_playing.text = "%s\n%s" % [meta.get("name", "—"), meta.get("artists", "")]
	if _sync_enable_check != null and TankConfig.music_sync_enabled:
		_sync_enable_check.set_block_signals(true)
		_sync_enable_check.button_pressed = true
		_sync_enable_check.set_block_signals(false)
	_focus_now_playing_tab()


func _save_spotify_creds() -> void:
	if _sync_client_id_edit != null:
		TankConfig.spotify_client_id = _sync_client_id_edit.text.strip_edges()
	if _sync_client_secret_edit != null:
		TankConfig.spotify_client_secret = _sync_client_secret_edit.text.strip_edges()


func _refresh_sync_visualizer() -> void:
	var mr := _music_reactive()
	if mr == null or _sync_bars.is_empty():
		return
	var levels: Dictionary = mr.get_meter_levels() if mr.has_method("get_meter_levels") else mr.get_drive()
	var vals: Array = [
		float(levels.get("bass", 0.0)),
		float(levels.get("mid", 0.0)),
		float(levels.get("high", 0.0)),
		float(levels.get("beat", 0.0)),
	]
	var colors: Array = [
		Color(0.95, 0.35, 0.45),
		Color(0.45, 0.85, 0.95),
		Color(0.75, 0.55, 1.0),
		Color(1.0, 0.82, 0.35),
	]
	for i in mini(_sync_bars.size(), vals.size()):
		var raw: float = clampf(float(vals[i]), 0.0, 1.0)
		# Beat is a transient pulse; bands are sustained — use sqrt so quiet bands still read.
		var h: float = sqrt(raw) if i < 3 else raw
		if raw > 0.015:
			h = maxf(h, 0.12)
		_sync_bars[i].custom_minimum_size.y = 8.0 + h * 28.0
		_sync_bars[i].color = (colors[i] as Color).lerp(Color(0.15, 0.18, 0.25), 1.0 - h)


func _music_reactive() -> Node:
	var main := get_tree().current_scene
	if main == null:
		return null
	return main.get_node_or_null("MusicReactive")


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
	if _sync_enable_check != null:
		_sync_enable_check.button_pressed = TankConfig.music_sync_enabled
	if _sync_intensity_slider != null:
		_sync_intensity_slider.value = float(TankConfig.music_sync_intensity)
		_sync_intensity_label.text = "%.0f%%" % (float(TankConfig.music_sync_intensity) * 100.0)
	if _slider_rows.has("music_showiness"):
		var show_row: Dictionary = _slider_rows["music_showiness"]
		(show_row["slider"] as HSlider).value = float(TankConfig.music_showiness)
		_update_slider_label("music_showiness")
	for key in _sync_channel_checks.keys():
		(_sync_channel_checks[key] as CheckBox).button_pressed = not not TankConfig.get(key)
	if _sync_client_id_edit != null:
		_sync_client_id_edit.text = String(TankConfig.spotify_client_id)
	if _sync_client_secret_edit != null:
		_sync_client_secret_edit.text = String(TankConfig.spotify_client_secret)
	var mr := _music_reactive()
	if mr != null:
		mr.apply_config()
	_refresh_calibrate_label()


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
	var mc := get_node_or_null("/root/MusicContext")
	var ctx: Dictionary = mc.get_context() if mc != null and mc.has_method("get_context") else {}
	var bpm: float = float(status.get("bpm", ctx.get("tempo", 0.0)))
	var vit: float = float(status.get("vitality", ctx.get("energy", 0.0)))
	var zone: String = "day" if int(status.get("day_zone", 1)) == 1 else "night"
	var state_name: String = String(ctx.get("phrase_state", status.get("phrase_state_name", "verse")))
	var bars_left: int = int(status.get("phrase_state_bars_left", ctx.get("phrase_bars_left", 0)))
	var dance_line: String = ""
	if not ctx.is_empty():
		dance_line = (
			"\ndance %s · %s/%s · bar %.0f%% · beat %.0f%% · %s %s · key %d · timbre %.0f%%"
			% [
				String(ctx.get("source", "—")),
				String(ctx.get("move", "sweep")),
				String(ctx.get("formation", "scatter")),
				float(ctx.get("bar_phase", 0.0)) * 100.0,
				float(ctx.get("beat_phase", 0.0)) * 100.0,
				String(ctx.get("genre", "—")),
				String(ctx.get("mode", "—")),
				int(ctx.get("key", 0)),
				float(ctx.get("timbre_sharp", 0.5)) * 100.0,
			]
		)
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
			+ "chord %d  arp bank %d  phrase #%d  seed %d%s"
			% [
				int(status.get("chord_root", 0)),
				int(status.get("arp_idx", 0)),
				int(status.get("phrase", 0)),
				int(TankConfig.music_seed),
				dance_line,
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


func _conduct_move(cmd: Dictionary) -> void:
	var mc := get_node_or_null("/root/MusicContext")
	if mc != null and mc.has_method("conduct"):
		mc.conduct(String(cmd.get("move", "wave")), String(cmd.get("formation", "")))


func _on_capture_dance() -> void:
	var main := get_tree().current_scene
	if main != null and main.has_method("capture_dance_moment"):
		main.capture_dance_moment()


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
