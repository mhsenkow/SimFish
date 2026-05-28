# Guided setup walkthrough.
#
# A step-by-step coach that leads the player through stocking an EMPTY tank:
# hardscape -> plants -> snails -> shrimp -> fish. Each "tool" step opens the
# relevant builder (aquascape mode or the Creature Creator on the right tab);
# the player adds what they like, then returns to the guide and advances.
#
# The sim is paused for the whole walkthrough and resumes on Finish, so the
# tank comes alive all at once when the player is done.
#
# The overlay root is a transparent full-rect Control that passes input
# through to the tank/tools. Only the centered instruction card and the small
# "Back to guide" button capture input, and only one of them is visible at a
# time, so the builder tools are fully usable while a step is in progress.

extends Control

var _main: Node = null
var _step: int = 0
var _steps: Array = []
var _awaiting_tool: bool = false
var _active_tool: String = ""

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
	z_index = 280
	set_process(false)
	_build_steps()
	_build_ui()


func _build_steps() -> void:
	_steps = [
		{
			"id": "intro", "tool": "",
			"title": "Build a tank from scratch",
			"body": "Welcome! Let's set up a living aquarium step by step - hardscape first, then plants, then your animals. The simulation is paused while you build, and starts when you finish.",
		},
		{
			"id": "hardscape", "tool": "aquascape",
			"title": "1 · Hardscape",
			"body": "Rocks and driftwood give fish cover and structure. Open the aquascape tools to place dirt, stone, and wood - drag a piece to reposition it, or use Dig to carve. Come back when you're happy (it's optional).",
		},
		{
			"id": "plant", "tool": "plant", "count": "plant",
			"title": "2 · Plants",
			"body": "Live plants oxygenate the water and feed grazers. Design a plant, then press Add 1 / 3 / 5. Try a couple of different forms and colors for variety.",
		},
		{
			"id": "snail", "tool": "snail", "count": "snail",
			"title": "3 · Snails",
			"body": "Snails are your cleanup crew - they graze algae and detritus along the glass and substrate. Design one and add a few.",
		},
		{
			"id": "shrimp", "tool": "shrimp", "count": "shrimp",
			"title": "4 · Shrimp",
			"body": "Shrimp scavenge biofilm and leftover food and add life to the midwater. Add a small colony.",
		},
		{
			"id": "fish", "tool": "fish", "count": "fish",
			"title": "5 · Fish",
			"body": "The stars of the tank. Design your fish and stock a school, or a bold centerpiece. Mix species if you like.",
		},
		{
			"id": "done", "tool": "",
			"title": "Your tank is alive!",
			"body": "Everything's stocked. Press Finish to start the simulation - your plants will grow, your animals will feed, breed, and settle into their new home.",
		},
	]


func _build_ui() -> void:
	# Centered instruction card.
	_card = PanelContainer.new()
	_card.set_anchors_preset(Control.PRESET_CENTER)
	_card.custom_minimum_size = Vector2(560, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	PanelTheme.apply_panel_chrome(_card)
	add_child(_card)
	# Keep it horizontally centered, anchored toward the lower third so it
	# doesn't fight the top HUD.
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.anchor_top = 0.5
	_card.anchor_bottom = 0.5
	_card.offset_left = -280
	_card.offset_right = 280
	_card.offset_top = -150
	_card.offset_bottom = 150

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_card.add_child(v)

	_step_lbl = Label.new()
	_step_lbl.add_theme_font_size_override("font_size", 12)
	_step_lbl.add_theme_color_override("font_color", Color8(120, 200, 255))
	v.add_child(_step_lbl)

	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 22)
	_title_lbl.add_theme_color_override("font_color", Color8(245, 240, 220))
	v.add_child(_title_lbl)

	_body_lbl = Label.new()
	_body_lbl.add_theme_font_size_override("font_size", 14)
	_body_lbl.add_theme_color_override("font_color", Color8(200, 212, 228))
	_body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_lbl.custom_minimum_size = Vector2(520, 0)
	v.add_child(_body_lbl)

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
	skip.tooltip_text = "Skip the walkthrough and start the tank"
	skip.pressed.connect(_finish)
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

	# "Back to guide" button shown while a builder tool is open.
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
	visible = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	if _main != null and _main.has_method("wt_pause_sim"):
		_main.wt_pause_sim(true)
	_show_step()


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
		"aquascape": _action_btn.text = "Open aquascape tools"
		"plant": _action_btn.text = "Open plant designer"
		"snail": _action_btn.text = "Open snail designer"
		"shrimp": _action_btn.text = "Open shrimp designer"
		"fish": _action_btn.text = "Open fish designer"
	_next_btn.text = "Finish ✓" if _step == _steps.size() - 1 else "Next ▸"
	_update_count()


func _update_count() -> void:
	var s: Dictionary = _steps[_step]
	var ckey: String = String(s.get("count", ""))
	if ckey == "" or _main == null or not _main.has_method("wt_counts"):
		_count_lbl.text = ""
		return
	var counts: Dictionary = _main.wt_counts()
	var n: int = int(counts.get(ckey, 0))
	var noun: String = ckey if n == 1 else (ckey + "s" if ckey != "fish" else "fish")
	_count_lbl.text = "In tank: %d %s" % [n, noun]


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


func _finish() -> void:
	_close_active_tool()
	if _main != null and _main.has_method("wt_pause_sim"):
		_main.wt_pause_sim(false)
	set_process(false)
	visible = false


# While a builder tool is open we hide the card and watch for the tool being
# dismissed by other means (Close button, B key); when it closes, bring the
# guide card back automatically.
func _process(_dt: float) -> void:
	if not _awaiting_tool:
		return
	if _main == null:
		return
	var still_open: bool = false
	if _active_tool == "aquascape":
		still_open = bool(_main.get("_aquascape_mode"))
	else:
		var creator: Node = _main.get("creature_creator_panel")
		still_open = creator != null and is_instance_valid(creator) and (creator as CanvasItem).visible
	if not still_open:
		_awaiting_tool = false
		_show_step()
