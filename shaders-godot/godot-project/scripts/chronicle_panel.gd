# Chronicle panel — the tank's history read like a book.
#
# A thin view over TankChronicle (tank_chronicle.gd): one chapter per page,
# title ("Day 12 — The Long Dark"), prose paragraphs in the tank's serif
# narrative voice, cast names highlighted. Prose is built lazily by the
# chronicle and cached there, so paging is cheap.
#
# Docks left like the Mind / Residents panels; main.gd owns open/close and
# layout (_toggle_chronicle_panel, hotkey L, rail button 📖).

extends PanelContainer

const TankChronicleScript = preload("res://scripts/tank_chronicle.gd")
const _SPAN_FMT: String = "[color=#9aa8c8]%s[/color]\n\n%s"

var main_ref: Node = null

var _title_lbl: Label = null
var _page_lbl: Label = null
var _body: RichTextLabel = null
var _prev_btn: Button = null
var _next_btn: Button = null
var _pos: int = -1
# main.gd sets this before refresh() when the panel opens: jump to the newest
# page (the in-progress chapter, or the away recap just written).
var _jump_latest: bool = true


func _ready() -> void:
	PanelTheme.apply_panel_chrome(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(PanelTheme.PANEL_MIN_W, 0)
	z_index = 130
	_build_ui()
	visible = false


func _build_ui() -> void:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)
	outer.add_child(PanelTheme.make_panel_header("Chronicle", close_panel))
	outer.add_child(PanelTheme.make_rule())

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	outer.add_child(nav)
	_prev_btn = PanelTheme.make_icon_button("◀")
	_prev_btn.tooltip_text = tr("Previous chapter")
	_prev_btn.pressed.connect(func() -> void: _turn(-1))
	nav.add_child(_prev_btn)
	_page_lbl = Label.new()
	PanelTheme.as_mono(_page_lbl, PanelTheme.SIZE_CAPTION)
	_page_lbl.add_theme_color_override("font_color", PanelTheme.DIM_FG)
	_page_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(_page_lbl)
	_next_btn = PanelTheme.make_icon_button("▶")
	_next_btn.tooltip_text = tr("Next chapter")
	_next_btn.pressed.connect(func() -> void: _turn(1))
	nav.add_child(_next_btn)
	var copy_btn := PanelTheme.make_icon_button("⧉")
	copy_btn.tooltip_text = tr("Copy this chapter")
	copy_btn.pressed.connect(_copy_chapter)
	nav.add_child(copy_btn)

	_title_lbl = Label.new()
	PanelTheme.as_serif(_title_lbl, PanelTheme.SIZE_SECTION, true)
	_title_lbl.add_theme_color_override("font_color", PanelTheme.TITLE_FG)
	_title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_title_lbl)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = false
	_body.scroll_active = true
	_body.selection_enabled = true
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.custom_minimum_size = Vector2(0, 240)
	_body.add_theme_color_override("default_color", Color(0.88, 0.91, 0.96, 0.96))
	PanelTheme.apply_font(_body, PanelTheme.FONT_SERIF, PanelTheme.SIZE_ITEM)
	outer.add_child(_body)
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _chronicle() -> Node:
	if main_ref == null:
		return null
	var sim: Variant = main_ref.get("_sim")
	if sim == null or not is_instance_valid(sim) or not (sim is Node):
		return null
	return TankChronicleScript.attach(sim as Node)


func _turn(delta: int) -> void:
	var c: Node = _chronicle()
	if c == null:
		return
	var n: int = int(c.call("view_count"))
	_pos = clampi(_pos + delta, 0, maxi(0, n - 1))
	refresh()


func refresh() -> void:
	var c: Node = _chronicle()
	var n: int = int(c.call("view_count")) if c != null else 0
	if c == null or n == 0:
		_title_lbl.text = tr("Nothing written yet")
		_page_lbl.text = "—"
		_body.text = "[color=#9aa8c8]%s[/color]" % tr("The tank has not lived long enough to have a story. Give it a few days.")
		_prev_btn.disabled = true
		_next_btn.disabled = true
		return
	if _jump_latest or _pos < 0:
		_jump_latest = false
		_pos = n - 1
	_pos = clampi(_pos, 0, n - 1)
	var prose: Dictionary = c.call("view_at", _pos)
	var title: String = String(prose.get("title", ""))
	if bool(prose.get("open", false)):
		title += "  (still being written)"
	_title_lbl.text = title
	var first_num: int = int(c.call("dropped_count")) + 1
	_page_lbl.text = tr("Chapter %d of %d") % [first_num + _pos, first_num + n - 1]
	var d0: int = int(prose.get("d0", 1))
	var d1: int = int(prose.get("d1", d0))
	var span: String = "Day %d" % d0 if d1 <= d0 else "Days %d–%d" % [d0, d1]
	_body.text = _SPAN_FMT % [span, TankChronicleScript.prose_bbcode(prose)]
	_body.scroll_to_line(0)
	_prev_btn.disabled = _pos <= 0
	_next_btn.disabled = _pos >= n - 1


func _copy_chapter() -> void:
	var c: Node = _chronicle()
	if c == null or int(c.call("view_count")) == 0:
		return
	DisplayServer.clipboard_set(TankChronicleScript.plain_text(c.call("view_at", _pos)))


func close_panel() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: Key = (event as InputEventKey).keycode
		if k == KEY_ESCAPE:
			close_panel()
			get_viewport().set_input_as_handled()
		elif k == KEY_BRACKETLEFT or k == KEY_PAGEUP:
			_turn(-1)
			get_viewport().set_input_as_handled()
		elif k == KEY_BRACKETRIGHT or k == KEY_PAGEDOWN:
			_turn(1)
			get_viewport().set_input_as_handled()
