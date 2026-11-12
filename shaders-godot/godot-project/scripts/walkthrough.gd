# Guided setup walkthrough.
#
# A step-by-step coach that leads the player through stocking an EMPTY tank:
# hardscape -> plants -> snails -> shrimp -> fish -> watch & feed.
# ONBOARDING_LEGIBILITY #1, #4, #5, #6, #10.

extends Control

var _main: Node = null
var _step: int = 0
var _steps: Array = []
var _awaiting_tool: bool = false
var _active_tool: String = ""
var _effect_lbl: Label = null

# UI refs.
var _card: PanelContainer = null
var _step_lbl: Label = null
var _title_lbl: Label = null
var _body_lbl: Label = null
var _count_lbl: Label = null
var _back_btn: Button = null
var _action_btn: Button = null
var _next_btn: Button = null
var _resume_btn: Button = null


func setup(main_ref: Node) -> void:
	_main = main_ref


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = PanelTheme.Z_WALKTHROUGH
	set_process(false)
	_build_steps()
	_build_ui()


func _build_steps() -> void:
	_steps = [
		{
			"id": "intro", "tool": "",
			"title": "Stock this empty tank",
			"body": "You'll add cover, plants, then animals. The water stays paused so nothing drifts away while you build. Skip leaves the guide and drops you into a living garden that is already running.",
		},
		{
			"id": "hardscape", "tool": "aquascape", "count": "hardscape",
			"title": "1 · Cover (optional)",
			"body": "Rocks and wood are hiding places. Open Build, place a few pieces, drag to move them. Come back here when you want the next step. Empty glass is fine too.",
		},
		{
			"id": "plant", "tool": "plant", "count": "plant",
			"title": "2 · Plants",
			"body": "Plants make oxygen and shade. Open the plant designer, pick a shape, then Add 1. Two or three kinds look more like a garden.",
		},
		{
			"id": "snail", "tool": "snail", "count": "snail",
			"title": "3 · Snails",
			"body": "Snails graze algae and leftover food on the glass and the floor. Design one and add a few. They are the cleanup crew.",
		},
		{
			"id": "shrimp", "tool": "shrimp", "count": "shrimp",
			"title": "4 · Shrimp",
			"body": "Shrimp pick through biofilm in the middle of the tank. Add a small group. They are not the same job as snails — they stay up in the plants.",
		},
		{
			"id": "fish", "tool": "fish", "count": "fish",
			"title": "5 · Fish",
			"body": "Fish are who you watch. Design one and add a school, or a single showy fish. You can mix species.",
		},
		{
			"id": "watch", "tool": "", "live": true,
			"title": "6 · Watch it run",
			"body": "The tank is running now. Drag to look around. Schools pull together — that huddle is shoaling. Give them a moment to settle into the cover.",
		},
		{
			"id": "feed", "tool": "", "live": true,
			"title": "7 · Feed them",
			"body": "Click the water (not this card) to drop food. They should turn toward it. That click is how you feed from now on. Care, in the footer, changes water and rinses the filter.",
		},
		{
			"id": "done", "tool": "",
			"title": "You're keeping a tank",
			"body": "Finish leaves it running. Drag orbits, click feeds, and the footer is Care. You can reopen this tank from the shelf anytime.",
		},
	]


func _build_ui() -> void:
	_card = PanelContainer.new()
	_card.set_anchors_preset(Control.PRESET_CENTER)
	_card.custom_minimum_size = Vector2(560, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	PanelTheme.apply_panel_chrome(_card)
	add_child(_card)
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.anchor_top = 1.0
	_card.anchor_bottom = 1.0
	_card.offset_left = -280
	_card.offset_right = 280
	_card.offset_top = -280
	_card.offset_bottom = -72

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_card.add_child(v)

	_step_lbl = Label.new()
	PanelTheme.as_mono(_step_lbl, PanelTheme.SIZE_SMALL)
	_step_lbl.add_theme_color_override("font_color", Color8(120, 200, 255))
	v.add_child(_step_lbl)

	_title_lbl = Label.new()
	PanelTheme.as_serif(_title_lbl, PanelTheme.SIZE_SECTION, true)
	_title_lbl.add_theme_color_override("font_color", Color8(245, 240, 220))
	v.add_child(_title_lbl)

	_body_lbl = Label.new()
	_body_lbl.add_theme_font_size_override("font_size", 14)
	_body_lbl.add_theme_color_override("font_color", Color8(200, 212, 228))
	_body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_lbl.custom_minimum_size = Vector2(280, 0)
	v.add_child(_body_lbl)

	_effect_lbl = Label.new()
	_effect_lbl.add_theme_font_size_override("font_size", 12)
	_effect_lbl.add_theme_color_override("font_color", Color8(255, 220, 140))
	v.add_child(_effect_lbl)

	_count_lbl = Label.new()
	_count_lbl.add_theme_font_size_override("font_size", 13)
	_count_lbl.add_theme_color_override("font_color", Color8(140, 235, 160))
	v.add_child(_count_lbl)

	v.add_child(PanelTheme.make_rule())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	_back_btn = PanelTheme.make_secondary_button("◂ Back")
	_back_btn.pressed.connect(_on_back)
	row.add_child(_back_btn)
	var skip := PanelTheme.make_secondary_button("Skip")
	skip.tooltip_text = tr("Skip the walkthrough — lands you in a living preset tank")
	skip.pressed.connect(_skip)
	row.add_child(skip)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_action_btn = PanelTheme.make_primary_button("Open")
	_action_btn.pressed.connect(_on_action)
	row.add_child(_action_btn)
	_next_btn = PanelTheme.make_primary_button("Next ▸")
	_next_btn.pressed.connect(_on_next)
	row.add_child(_next_btn)

	_resume_btn = PanelTheme.make_primary_button("◂ Back to guide")
	_resume_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_resume_btn.anchor_left = 0.5
	_resume_btn.anchor_right = 0.5
	_resume_btn.anchor_top = 1.0
	_resume_btn.anchor_bottom = 1.0
	_resume_btn.offset_left = -90
	_resume_btn.offset_right = 90
	_resume_btn.offset_top = -56
	_resume_btn.offset_bottom = -16
	_resume_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_resume_btn.visible = false
	_resume_btn.pressed.connect(_on_resume)
	add_child(_resume_btn)


func begin() -> void:
	_step = 0
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null and int(cfg.walkthrough_step) > 0 and not cfg.walkthrough_completed:
		_step = clampi(int(cfg.walkthrough_step), 0, _steps.size() - 1)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	if _main != null and _main.has_method("wt_pause_sim"):
		_main.wt_pause_sim(true)
	_show_step()


func resume_from_step(step_index: int) -> void:
	_step = clampi(step_index, 0, _steps.size() - 1)
	begin()


func _show_step() -> void:
	_awaiting_tool = false
	_active_tool = ""
	_resume_btn.visible = false
	_card.visible = true
	var s: Dictionary = _steps[_step]
	_step_lbl.text = "Step %d of %d" % [_step + 1, _steps.size()]
	_title_lbl.text = String(s.get("title", ""))
	_body_lbl.text = String(s.get("body", ""))
	_back_btn.disabled = _step == 0
	var tool: String = String(s.get("tool", ""))
	_action_btn.visible = tool != ""
	match tool:
		"aquascape": _action_btn.text = tr("Open Build")
		"plant": _action_btn.text = tr("Open plant designer")
		"snail": _action_btn.text = tr("Open snail designer")
		"shrimp": _action_btn.text = tr("Open shrimp designer")
		"fish": _action_btn.text = tr("Open fish designer")
	_next_btn.text = tr("Finish ✓") if _step == _steps.size() - 1 else "Next ▸"
	_update_count()
	_update_effect_readout()
	_apply_live_pause(s)
	_place_card()
	_notify_step_changed()


func _place_card() -> void:
	if _card == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var w: float = minf(520.0, maxf(280.0, vp.x - 32.0))
	_card.offset_left = -w * 0.5
	_card.offset_right = w * 0.5
	_card.offset_bottom = -76.0
	_card.offset_top = _card.offset_bottom - 300.0
	if _body_lbl != null:
		_body_lbl.custom_minimum_size.x = maxf(240.0, w - 40.0)


func _apply_live_pause(s: Dictionary) -> void:
	if _main == null or not _main.has_method("wt_pause_sim"):
		return
	if bool(s.get("live", false)):
		_main.wt_pause_sim(false)
	else:
		_main.wt_pause_sim(true)


func _update_effect_readout() -> void:
	var s: Dictionary = _steps[_step]
	var ckey: String = String(s.get("count", ""))
	if ckey == "":
		_effect_lbl.text = ""
		return
	var Ol := preload("res://scripts/onboarding_legibility.gd")
	_effect_lbl.text = Ol.WALKTHROUGH_EFFECTS.get(ckey, "")


func _update_count() -> void:
	var s: Dictionary = _steps[_step]
	var ckey: String = String(s.get("count", ""))
	if ckey == "" or ckey == "hardscape" or _main == null or not _main.has_method("wt_counts"):
		if ckey != "hardscape":
			_count_lbl.text = ""
		else:
			_count_lbl.text = tr("Optional — structure helps fish feel safe")
		return
	var counts: Dictionary = _main.wt_counts()
	var n: int = int(counts.get(ckey, 0))
	var noun: String = ckey if n == 1 else (ckey + "s" if ckey != "fish" else "fish")
	_count_lbl.text = "In tank: %d %s" % [n, noun]


func _notify_step_changed() -> void:
	if _main != null and _main.has_method("wt_on_step_changed"):
		_main.wt_on_step_changed(_step)


func _on_action() -> void:
	var s: Dictionary = _steps[_step]
	var tool: String = String(s.get("tool", ""))
	if tool == "":
		return
	_active_tool = tool
	_awaiting_tool = true
	_card.visible = false
	_resume_btn.visible = true
	if tool == "aquascape":
		if _main != null and _main.has_method("wt_set_aquascape"):
			_main.wt_set_aquascape(true)
	else:
		if _main != null and _main.has_method("wt_open_creator"):
			_main.wt_open_creator(tool)


func _on_resume() -> void:
	_close_active_tool()
	_show_step()


func _close_active_tool() -> void:
	if _main == null:
		return
	if _active_tool == "aquascape":
		if _main.has_method("wt_set_aquascape"):
			_main.wt_set_aquascape(false)
	elif _active_tool != "":
		if _main.has_method("wt_close_creator"):
			_main.wt_close_creator()
	_active_tool = ""
	_awaiting_tool = false


func _on_next() -> void:
	if _step >= _steps.size() - 1:
		_finish()
		return
	_close_active_tool()
	_step += 1
	_show_step()


func _on_back() -> void:
	if _step == 0:
		return
	_close_active_tool()
	_step -= 1
	_show_step()


func _skip() -> void:
	if _main != null and _main.has_method("wt_on_walkthrough_skip"):
		_main.wt_on_walkthrough_skip()
	_finish()


func _finish() -> void:
	_close_active_tool()
	if _main != null and _main.has_method("wt_pause_sim"):
		_main.wt_pause_sim(false)
	if _main != null and _main.has_method("wt_on_walkthrough_finish"):
		_main.wt_on_walkthrough_finish()
	set_process(false)
	visible = false


func _process(_dt: float) -> void:
	if not _awaiting_tool:
		return
	if _main == null:
		return
	var still_open: bool = false
	if _active_tool == "aquascape":
		var aq: Variant = _main.get("_aquascape")
		still_open = aq != null and bool(aq.is_active)
	else:
		var creator: Node = _main.get("creature_creator_panel")
		still_open = creator != null and is_instance_valid(creator) and (creator as CanvasItem).visible
	if not still_open:
		_awaiting_tool = false
		_show_step()
