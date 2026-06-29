# Runtime onboarding: nudges, captions, check-ins, help panel, tour hooks.
extends Node

var _main: Node = null
var _sim: Node = null
var _resume_btn: Button = null
var _help_overlay: Control = null
var _nudge_panel: PanelContainer = null
var _caption_label: Label = null

var _last_mood: float = 1.0
var _last_alert_kind: String = ""
var _nudge_cooldown: float = 0.0
var _thriving_days: float = 0.0
var _ignored_nudges: int = 0
var _active_nudge_id: String = ""
var _chip_keys_primary: Array[String] = ["mood", "water", "fish"]
var _chip_keys_all: Array[String] = [
	"state", "water", "mood", "fish", "flora", "alert", "shrimp", "snails", "morphs",
]


func setup(main_ref: Node) -> void:
	_main = main_ref
	set_process(true)


func bind_sim(sim: Node) -> void:
	_sim = sim


func on_stats(stats: Dictionary) -> void:
	if _main == null:
		return
	_update_status_glance(stats)
	_update_chip_visibility(stats)
	_tick_nudges(stats)
	_tick_cue_watch(stats)
	_tick_check_ins(stats)
	_tick_recovery(stats)
	_pulse_changed_chips(stats)
	_refresh_controls_hint(stats)


func on_eco_event(kind: String, _text: String) -> void:
	if kind == "reef":
		# Reef toasts already cover warmth/O₂ stress — don't stack the O₂ nudge.
		_nudge_cooldown = maxf(_nudge_cooldown, 180.0)
	if kind == "death" and not bool(OnboardingLegibility.global_pref("first_death_seen", false)):
		OnboardingLegibility.set_global_pref("first_death_seen", true)
		if _sim != null and _sim.has_method("log_story_event"):
			_sim.log_story_event(
				"Fish don't live forever — this one lived a full life. Its body will feed the tank.")
	if kind == "pearling" and not bool(OnboardingLegibility.global_pref("pearling_explained", false)):
		_show_caption("Pearling — bubbles on leaves mean plants are thriving.")
		OnboardingLegibility.set_global_pref("pearling_explained", true)
	if kind == "courtship" and not bool(OnboardingLegibility.global_pref("breeding_intro_seen", false)):
		_show_card("A pair is forming", "Tap fish to follow courtship — fry and lineages live in the Life Library.")
		OnboardingLegibility.set_global_pref("breeding_intro_seen", true)


func on_first_feed() -> void:
	if bool(OnboardingLegibility.global_pref("first_feed_done", false)):
		return
	OnboardingLegibility.set_global_pref("first_feed_done", true)
	if _sim != null and _sim.has_method("log_story_event"):
		_sim.log_story_event("First feeding — they came right up.")
	_show_caption("First feeding — watch them converge.")


func on_walkthrough_finish() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.walkthrough_completed = true
		cfg.walkthrough_step = 0
		cfg.save_to_disk()
	_hide_resume_button()
	_offer_watch_demo()
	call_deferred("_show_end_tour_summary")
	call_deferred("_show_chip_legend")
	if cfg != null and String(cfg.cycle_start_mode) == "fresh":
		call_deferred("_show_fresh_cycle_card")


func on_walkthrough_skip() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	var preset: String = String(cfg.walkthrough_scenario_preset)
	if preset != "" and cfg.tank_preset == "empty":
		cfg.tank_preset = preset
		cfg.walkthrough_completed = true
		cfg.walkthrough_step = 0
		cfg.save_to_disk()
		if _main != null:
			get_tree().change_scene_to_file("res://main.tscn")


func on_walkthrough_step_changed(step: int) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.walkthrough_step = step
		cfg.save_to_disk()


func ensure_ui(parent: Node) -> void:
	if _resume_btn != null:
		return
	_resume_btn = PanelTheme.make_secondary_button("Resume setup tour")
	_resume_btn.visible = false
	_resume_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_resume_btn.offset_left = -160
	_resume_btn.offset_top = 8
	_resume_btn.offset_right = -8
	_resume_btn.offset_bottom = 36
	_resume_btn.pressed.connect(_on_resume_walkthrough)
	parent.add_child(_resume_btn)
	_sync_resume_button()


func install_help_rail_button(rail: Control) -> void:
	if rail == null:
		return
	var btn := Button.new()
	btn.name = "HelpToggle"
	btn.tooltip_text = "Help, controls & glossary"
	btn.custom_minimum_size = Vector2(44, 44)
	btn.pressed.connect(toggle_help)
	UiIcons.apply_rail_button(btn, "help", false)
	rail.add_child(btn)


func toggle_help() -> void:
	if _help_overlay != null and is_instance_valid(_help_overlay):
		_help_overlay.queue_free()
		_help_overlay = null
		return
	if _main == null:
		return
	_help_overlay = Control.new()
	_help_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_help_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_help_overlay.z_index = PanelTheme.Z_HELP
	_main.add_child(_help_overlay)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			toggle_help())
	_help_overlay.add_child(bg)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 420)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -260
	panel.offset_right = 260
	panel.offset_top = -210
	panel.offset_bottom = 210
	PanelTheme.apply_panel_chrome(panel)
	_help_overlay.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	vb.add_child(PanelTheme.make_title("Help"))
	var search := LineEdit.new()
	search.placeholder_text = "Search — e.g. gulping, NH₃, feed…"
	vb.add_child(search)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 300)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.custom_minimum_size = Vector2(460, 0)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var mobile: bool = _main.has_method("_is_mobile") and bool(_main.call("_is_mobile"))
	body.text = _help_body(mobile, "")
	search.text_changed.connect(func(t: String): body.text = _help_body(mobile, t))
	var close := PanelTheme.make_primary_button("Close")
	close.pressed.connect(toggle_help)
	vb.add_child(close)


func _help_body(mobile: bool, query: String) -> String:
	if query.strip_edges() != "":
		var hits: PackedStringArray = OnboardingLegibility.search_help(query)
		if hits.is_empty():
			return "[i]No matches — try O₂, algae, or feed.[/i]"
		return "\n".join(hits)
	var parts: Array[String] = []
	parts.append("[b]Controls[/b]")
	for line in OnboardingLegibility.cheat_sheet_lines(mobile):
		parts.append(line)
	parts.append("\n[b]Tank tells[/b]")
	for row in OnboardingLegibility.TANK_TELLS:
		parts.append("• %s → %s" % [row.cue, row.meaning])
	parts.append("\n[b]Glossary[/b]")
	for term in OnboardingLegibility.GLOSSARY.keys():
		parts.append("• %s — %s" % [term, OnboardingLegibility.GLOSSARY[term]])
	parts.append("\n[b]Walstad[/b]")
	parts.append(OnboardingLegibility.walstad_one_pager())
	return "\n".join(parts)


func show_mode_coachmark(mode_id: String, title: String, body: String) -> void:
	var pref_key: String = "mode_coach_%s" % mode_id
	if bool(OnboardingLegibility.global_pref(pref_key, false)):
		return
	OnboardingLegibility.set_global_pref(pref_key, true)
	_show_card(title, body)


func show_builder_tour() -> void:
	if bool(OnboardingLegibility.global_pref("builder_tour_done", false)):
		return
	OnboardingLegibility.set_global_pref("builder_tour_done", true)
	_show_card(
		"Build mode — quick tour",
		"1) block tool (9) — click to place voxels; scroll adjusts height.\n"
		+ "2) Swatches + finishes — pick color and matte/glass/glow/metal.\n"
		+ "3) Object browser — drop a castle or arch; edit voxels after.\n"
		+ "4) save BP / import — share codes; line/box/mirror for big builds."
	)


func _process(dt: float) -> void:
	_nudge_cooldown = maxf(0.0, _nudge_cooldown - dt)
	if _sim == null and _main != null:
		_sim = _main.get("_sim")
	_sync_resume_button()


func _sync_resume_button() -> void:
	if _resume_btn == null:
		return
	var cfg := get_node_or_null("/root/TankConfig")
	var show: bool = cfg != null and cfg.walkthrough_pending == false \
		and not bool(cfg.walkthrough_completed) \
		and int(cfg.walkthrough_step) > 0
	_resume_btn.visible = show


func _on_resume_walkthrough() -> void:
	if _main == null:
		return
	var wt: Node = _main.get("walkthrough_overlay")
	if wt != null and wt.has_method("resume_from_step"):
		wt.resume_from_step(int(get_node("/root/TankConfig").walkthrough_step))


func layout_status_strip(_left: float, _right: float, _compact: bool) -> void:
	pass


func _update_status_glance(_stats: Dictionary) -> void:
	pass


func _mood_score(stats: Dictionary) -> float:
	var o2: float = float(stats.get("dissolved_o2", 1.0))
	var biomass: int = int(stats.get("plant_total_biomass", 0))
	var algae: int = int(stats.get("algae_clusters", 0))
	var waste: int = int(stats.get("waste_particles", 0))
	var ammonia: float = float(stats.get("ammonia", 0.0))
	return clampf(
		0.30 * o2
		+ 0.30 * clampf(float(biomass) / 600.0, 0.0, 1.0)
		+ 0.20 * clampf(1.0 - float(algae) / 60.0, 0.0, 1.0)
		+ 0.20 * clampf(1.0 - float(waste) / 100.0, 0.0, 1.0)
		- clampf(ammonia * 0.25, 0.0, 0.35),
		0.0, 1.0)


func _update_chip_visibility(stats: Dictionary) -> void:
	if _main == null or not _main.has_method("_get_chip"):
		return
	var tour_done: bool = bool(OnboardingLegibility.global_pref("tour_complete", false))
	if not tour_done:
		for key in _chip_keys_all:
			var chip: Control = _main.call("_get_chip", key) as Control
			if chip != null:
				chip.visible = key in _chip_keys_primary
		return
	for key in ["flora", "shrimp", "snails", "morphs"]:
		var c: Control = _main.call("_get_chip", key) as Control
		if c == null:
			continue
		match key:
			"flora":
				c.visible = int(stats.get("plants_alive", 0)) > 0
			"shrimp":
				c.visible = int(stats.get("shrimp_total", 0)) > 0
			"snails":
				c.visible = int(stats.get("snails_total", 0)) > 0
			"morphs":
				c.visible = int(stats.get("morph_distinct", 0)) > 0


func _tick_nudges(stats: Dictionary) -> void:
	if _nudge_cooldown > 0.0:
		return
	var mood: float = _mood_score(stats)
	if mood >= 0.72:
		_thriving_days += 1.0 / 3600.0
		if _thriving_days > 5.0 and not bool(OnboardingLegibility.global_pref("thriving_ack", false)):
			OnboardingLegibility.set_global_pref("thriving_ack", true)
			if _sim != null and _sim.has_method("log_story_event"):
				_sim.log_story_event("Your tank has been thriving — steady days add up.")
		return
	_thriving_days = 0.0
	var suggestion: Dictionary = _pick_nudge(stats)
	if suggestion.is_empty():
		_dismiss_nudge()
		return
	_show_nudge(String(suggestion.id), String(suggestion.text), suggestion.get("action", Callable()))


func _pick_nudge(stats: Dictionary) -> Dictionary:
	if float(stats.get("filter_clog", 0.0)) > 0.45:
		return {"id": "filter", "text": "The filter's getting sluggish — a quick rinse would help.", "action": _act_rinse_filter}
	if float(stats.get("nitrate", 0.0)) > 35.0:
		return {"id": "water_change", "text": "Water's getting heavy with nitrate — a small water change would freshen it.", "action": _act_water_change}
	if float(stats.get("dissolved_o2", 1.0)) < 0.55:
		var snooze_until: float = float(OnboardingLegibility.global_pref("nudge_o2_snooze_until", 0.0))
		if Time.get_unix_time_from_system() < snooze_until:
			return {}
		# Reef bleaching toast already names O₂/warmth — skip duplicate nudge.
		if float(stats.get("reef_bleach_level", 0.0)) > 0.2:
			return {}
		return {"id": "o2", "text": "Oxygen's dipping — aeration or fewer floaters might help.", "action": Callable()}
	if int(stats.get("algae_clusters", 0)) > 15 and not bool(OnboardingLegibility.global_pref("tip_algae_young", false)):
		OnboardingLegibility.set_global_pref("tip_algae_young", true)
		return {"id": "algae_tip", "text": "Algae is normal in a young tank — your plants will outcompete it.", "action": Callable()}
	return {}


func _show_nudge(id: String, text: String, action: Callable) -> void:
	if _main == null:
		return
	if _active_nudge_id == id and _nudge_panel != null:
		return
	_dismiss_nudge()
	_active_nudge_id = id
	_nudge_panel = PanelContainer.new()
	_nudge_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_nudge_panel.offset_bottom = -72.0
	_nudge_panel.offset_top = -120.0
	_nudge_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	PanelTheme.apply_panel_chrome(_nudge_panel)
	_main.add_child(_nudge_panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	_nudge_panel.add_child(hb)
	var lab := Label.new()
	lab.text = text
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(lab)
	if action.is_valid():
		var go := PanelTheme.make_primary_button("Do it")
		go.pressed.connect(func():
			action.call()
			_dismiss_nudge()
			_nudge_cooldown = 120.0)
		hb.add_child(go)
	var dismiss := PanelTheme.make_secondary_button("Not now")
	dismiss.pressed.connect(func():
		_ignored_nudges += 1
		if _active_nudge_id == "o2":
			OnboardingLegibility.set_global_pref(
				"nudge_o2_snooze_until", float(Time.get_unix_time_from_system()) + 600.0)
		_dismiss_nudge()
		_nudge_cooldown = 90.0 + float(_ignored_nudges) * 60.0)
	hb.add_child(dismiss)


func _dismiss_nudge() -> void:
	_active_nudge_id = ""
	if _nudge_panel != null and is_instance_valid(_nudge_panel):
		_nudge_panel.queue_free()
	_nudge_panel = null


func _act_rinse_filter() -> void:
	if _sim != null and _sim.has_method("rinse_filter"):
		_sim.rinse_filter()


func _act_water_change() -> void:
	if _sim != null and _sim.has_method("do_water_change"):
		_sim.do_water_change(0.25)


func _tick_cue_watch(stats: Dictionary) -> void:
	if _sim == null:
		return
	var o2: float = float(stats.get("dissolved_o2", 1.0))
	if o2 < 0.5 and not bool(OnboardingLegibility.global_pref("cue_gulp", false)):
		_show_caption("Gulping at the surface — oxygen is low.")
		OnboardingLegibility.set_global_pref("cue_gulp", true)
	var nh3: float = float(stats.get("ammonia", 0.0))
	if nh3 >= 0.28 and not bool(OnboardingLegibility.global_pref("cue_gill", false)):
		_show_caption("Gill flush — ammonia irritation. Cycle or plants will help.")
		OnboardingLegibility.set_global_pref("cue_gill", true)


func _tick_check_ins(stats: Dictionary) -> void:
	if String(stats.get("hud_mode", "")) != "cycle":
		return
	var day: int = int(stats.get("sim_day", 0))
	for d in [1, 3, 7]:
		var key: String = "checkin_day_%d" % d
		if day >= d and not bool(OnboardingLegibility.global_pref(key, false)):
			OnboardingLegibility.set_global_pref(key, true)
			var msg: String = ""
			match d:
				1: msg = "Day 1: bacteria waking up — light feeding only."
				3: msg = "Day 3: ammonia often peaks — watch for surface gulping."
				7: msg = "Day 7: nitrite phase — clamped fins mean stress; it passes."
			_show_card("Day %d check-in" % d, msg)


func _tick_recovery(stats: Dictionary) -> void:
	var mood: float = _mood_score(stats)
	if _last_mood < 0.45 and mood >= 0.6:
		if _sim != null and _sim.has_method("log_story_event"):
			_sim.log_story_event("The tank recovered — mood lifted and the school relaxed.")
	var kind: String = _alert_kind(stats)
	if _last_alert_kind != "" and kind == "":
		_show_caption("Crisis cleared — steady again.")
	_last_mood = mood
	_last_alert_kind = kind


func _alert_kind(stats: Dictionary) -> String:
	var o2_pct: int = int(round(float(stats.get("dissolved_o2", 0.0)) * 100.0))
	if o2_pct < 30:
		return "low_o2"
	if float(stats.get("ammonia", 0.0)) >= 0.25:
		return "ammonia"
	if float(stats.get("nitrite", 0.0)) >= 0.22:
		return "nitrite"
	return ""


func _pulse_changed_chips(stats: Dictionary) -> void:
	if _main == null or not _main.has_method("_pulse_chip"):
		return
	var mood: float = _mood_score(stats)
	if absf(mood - _last_mood) > 0.12:
		_main.call("_pulse_chip", "mood")
	var kind: String = _alert_kind(stats)
	if kind != _last_alert_kind and kind != "":
		_main.call("_pulse_chip", "alert")


func _refresh_controls_hint(stats: Dictionary = {}) -> void:
	if _main == null:
		return
	var hint: Label = _main.get("controls_hint")
	if hint == null:
		return
	var ctx: String = "default"
	if bool(_main.get("_immersive_mode")):
		ctx = "immersive"
	elif _main.get("_aquascape") != null and bool(_main.get("_aquascape").is_active):
		ctx = "aquascape"
	elif _main.has_method("_is_mobile") and bool(_main.call("_is_mobile")):
		ctx = "mobile"
	var world: Node = _main.get("world") as Node
	if world != null:
		var md: Variant = world.get("motion_debug")
		if md != null and bool(md.get("enabled")):
			hint.text = "Motion debug ON (Shift+M)"
			hint.visible = true
			return
	if not stats.is_empty() and ctx == "default":
		var mood: float = _mood_score(stats)
		var guidance: String = OnboardingLegibility.tank_status_footer(stats, mood)
		if guidance != "":
			hint.text = guidance
			hint.visible = true
			var warn: bool = bool(OnboardingLegibility.tank_status_glance(stats, mood).get("warn", false))
			hint.add_theme_color_override("font_color",
				Color(0.95, 0.78, 0.70, 0.92) if warn else PanelTheme.DIM_FG)
			return
	hint.text = OnboardingLegibility.control_hint_for_context(ctx)
	hint.add_theme_color_override("font_color", PanelTheme.DIM_FG)
	hint.visible = not bool(_main.get("_immersive_mode")) or ctx == "immersive"


func _show_caption(text: String) -> void:
	if _main == null:
		return
	if _caption_label != null and is_instance_valid(_caption_label):
		_caption_label.queue_free()
	_caption_label = Label.new()
	_caption_label.text = text
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_caption_label.offset_top = -100.0
	_caption_label.offset_bottom = -60.0
	_caption_label.add_theme_font_size_override("font_size", 13)
	_caption_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	_caption_label.z_index = 260
	_main.add_child(_caption_label)
	var tw := _main.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(_caption_label, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func():
		if is_instance_valid(_caption_label):
			_caption_label.queue_free())


func _show_card(title: String, body: String) -> void:
	if _main == null:
		return
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = PanelTheme.Z_ONBOARDING
	_main.add_child(overlay)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -220
	panel.offset_right = 220
	panel.offset_top = -80
	panel.offset_bottom = 80
	PanelTheme.apply_panel_chrome(panel)
	overlay.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var t := PanelTheme.make_title(title)
	vb.add_child(t)
	var b := Label.new()
	b.text = body
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(b)
	var ok := PanelTheme.make_primary_button("Got it")
	ok.pressed.connect(overlay.queue_free)
	vb.add_child(ok)


func _show_end_tour_summary() -> void:
	if bool(OnboardingLegibility.global_pref("tour_complete", false)):
		return
	OnboardingLegibility.set_global_pref("tour_complete", true)
	OnboardingLegibility.set_global_pref("coachmarks_seen", true)
	_show_card(
		"Here's your tank",
		"Mood · Water · Alert chips tell you how things are. Tap water for chemistry. "
		+ "Tap water in the tank to feed. We'll nudge gently if something drifts."
	)


func _show_chip_legend() -> void:
	if bool(OnboardingLegibility.global_pref("chip_legend_seen", false)):
		return
	OnboardingLegibility.set_global_pref("chip_legend_seen", true)
	_show_card(
		"What to watch",
		"Top chips: mood (how the tank feels), water (O₂ & cycle), alert (only when needed). "
		+ "Tap any chip for details."
	)


func _show_fresh_cycle_card() -> void:
	_show_card("Your tank is cycling", OnboardingLegibility.fresh_cycle_intro())


func _offer_watch_demo() -> void:
	if bool(OnboardingLegibility.global_pref("watch_demo_seen", false)):
		return
	if _main == null:
		return
	var overlay := Control.new()
	overlay.z_index = 295
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main.add_child(overlay)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -200
	panel.offset_right = 200
	PanelTheme.apply_panel_chrome(panel)
	overlay.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	vb.add_child(PanelTheme.make_title("Watch it breathe?"))
	var body := Label.new()
	body.text = "Run ~60 seconds at high speed to see day/night, pearling, and sleep."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(body)
	var row := HBoxContainer.new()
	vb.add_child(row)
	var skip := PanelTheme.make_secondary_button("Skip")
	skip.pressed.connect(overlay.queue_free)
	row.add_child(skip)
	var go := PanelTheme.make_primary_button("Watch")
	go.pressed.connect(func():
		OnboardingLegibility.set_global_pref("watch_demo_seen", true)
		overlay.queue_free()
		_run_watch_demo())
	row.add_child(go)


func _run_watch_demo() -> void:
	if _sim == null or _main == null:
		return
	var saved: float = float(_sim.time_scale)
	_sim.time_scale = 12.0
	var captions: Array[String] = [
		"Day passes…",
		"Plants pearl in the light…",
		"Fish settle toward sleep…",
		"Morning again — the loop keeps turning.",
	]
	var tw := _main.create_tween()
	for cap in captions:
		tw.tween_callback(func(): _show_caption(cap))
		tw.tween_interval(15.0)
	tw.tween_callback(func():
		if _sim != null:
			_sim.time_scale = saved)


func _hide_resume_button() -> void:
	if _resume_btn != null:
		_resume_btn.visible = false


func show_away_recap_card(gap_human: String, summary: String) -> void:
	_show_card("While you were away (%s)" % gap_human, summary)


func show_voiced_wake(fish_name: String) -> void:
	if bool(OnboardingLegibility.global_pref("voiced_wake_seen", false)):
		return
	OnboardingLegibility.set_global_pref("voiced_wake_seen", true)
	_show_card(
		"A mind wakes up",
		("%s has grown familiar enough to think aloud sometimes. "
		+ "Follow or tap them to overhear — all on your device, private.") % fish_name
	)


func show_guardian_intro() -> void:
	if bool(OnboardingLegibility.global_pref("guardian_intro_seen", false)):
		return
	OnboardingLegibility.set_global_pref("guardian_intro_seen", true)
	_show_card(
		"A Guardian emerges",
		"One of your fish has taken to you. Tap the Guardian in Residents for its diary."
	)


func show_did_you_know() -> void:
	if _nudge_cooldown > 0.0:
		return
	var tips: Array[String] = [
		"Tap a fish to read its story.",
		"Stability climbs as your tank matures — watch the water panel.",
		"Pearling bubbles mean plants are photosynthesizing hard.",
		"The tank self-sustains — absence doesn't punish, presence helps.",
	]
	_show_caption(tips[randi() % tips.size()])
