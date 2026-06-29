# Shared visual language for the side-bar panels (Settings / Render / Sound
# Store). All three are PanelContainer subclasses built procedurally; this
# helper centralises the styling so a tweak here cascades across the app
# without each panel rolling its own colors and margins.
#
# Naming aligns with the TopHUD cluster look (see main.tscn SBF_cluster)
# so the panels feel like part of the same family.

class_name PanelTheme
extends RefCounted


# ---- Color tokens ------------------------------------------------------------

const BG: Color = Color(0.06, 0.07, 0.12, 0.92)
const BORDER: Color = Color(0.35, 0.45, 0.6, 0.55)
const TITLE_FG: Color = Color(0.95, 0.96, 0.98)
const SECTION_FG: Color = Color(0.65, 0.80, 1.0, 0.85)
const LABEL_FG: Color = Color(0.85, 0.88, 0.93)
const VALUE_FG: Color = Color(0.98, 0.99, 1.0)
const DIM_FG: Color = Color(0.78, 0.83, 0.90, 0.75)
const RULE_FG: Color = Color(0.35, 0.45, 0.6, 0.45)
const PRIMARY_BG: Color = Color(0.22, 0.58, 0.88, 0.9)
const PRIMARY_BG_HOVER: Color = Color(0.32, 0.68, 0.96, 0.95)
const PRIMARY_FG: Color = Color(0.98, 0.99, 1.0)
const HUD_BG: Color = Color(0.06, 0.07, 0.12, 0.78)
const HUD_BORDER: Color = Color(0.35, 0.45, 0.6, 0.5)
const RAIL_ACTIVE_BG: Color = Color(0.28, 0.42, 0.58, 0.85)
const SHELF_BG: Color = Color(0.05, 0.04, 0.07, 1.0)
const SHELF_CARD_BG: Color = Color(0.07, 0.08, 0.13, 0.95)
const MODAL_SCRIM: Color = Color(0.0, 0.0, 0.0, 0.55)

# Biotope-synced overrides (#91) — fall back to const tokens when unset.
static var _cohesion_bg: Color = BG
static var _cohesion_border: Color = BORDER
static var _cohesion_section: Color = SECTION_FG
static var _cohesion_primary: Color = PRIMARY_BG
static var _cohesion_glass_tint: Color = Color(0.07, 0.08, 0.11, 0.55)
static var _cohesion_active: bool = false


static func sync_biotope_cohesion(hexes: Array) -> void:
	var tok: Dictionary = AestheticsRuntime.ui_palette_tokens(hexes)
	if tok.is_empty():
		_cohesion_active = false
		return
	_cohesion_bg = tok.bg
	_cohesion_border = tok.border
	_cohesion_section = tok.section
	_cohesion_primary = tok.primary_bg
	_cohesion_glass_tint = tok.glass_tint
	_cohesion_active = true


static func glass_panel_tint() -> Color:
	return _cohesion_glass_tint if _cohesion_active else Color(0.07, 0.08, 0.11, 0.55)


# ---- Overlay z-index (document stacking order) -------------------------------

const Z_WALKTHROUGH: int = 280
const Z_HELP: int = 290
const Z_ONBOARDING: int = 300
const Z_MENU_MODAL: int = 400
const Z_GUARDIAN: int = 450
const Z_COACHMARK: int = 490
const Z_TUTORIAL: int = 500


# ---- HUD layout constants ----------------------------------------------------

const HUD_TOP: float = 52.0
const HUD_BOTTOM: float = 34.0
const FOOTER_HEIGHT: float = 48.0
const EDGE_MARGIN: float = 12.0
const RAIL_WIDTH: float = 56.0
const RAIL_BOTTOM_HEIGHT: float = 60.0
const RAIL_BUTTON: float = 48.0
const PANEL_MIN_W: float = 360.0
const PANEL_MAX_W: float = 520.0
const TOAST_STACK_W: float = 280.0
const TOAST_STACK_H: float = 240.0


# True when keyboard focus is in a text field — suppress game shortcuts/panel toggles.
static func typing_focus_in_ui(viewport: Viewport) -> bool:
	var focus: Control = viewport.gui_get_focus_owner()
	if focus == null:
		return false
	if focus is LineEdit or focus is TextEdit:
		return true
	if focus.get_parent() is SpinBox:
		return true
	return false
const SHELF_TOP_BAR_H: float = 64.0
const SHELF_CARD_MIN_W: float = 260.0
const SHELF_CARD_MAX_W: float = 320.0
const MODAL_MIN_W: float = 320.0
const MODAL_MIN_H: float = 360.0
const MOBILE_NARROW_W: float = 480.0
const AQUASCAPE_WORKBENCH_W: float = 188.0
const AQUASCAPE_VIEW_BAR_H: float = 36.0


# ---- Type system -------------------------------------------------------------
#
# One bundled superfamily (IBM Plex) across the whole UI. The project default
# theme (assets/theme/walstad_theme.tres) already sets Plex Sans as the
# inherited font, so most controls need no font override at all. These helpers
# layer the two *other* voices on top where a role calls for it:
#   Serif → identity & narrative (titles, species names + lore, the story log)
#   Mono  → data & instruments  (stat values, parameters, slider readouts, ids)

const FONT_SANS: FontFile = preload("res://assets/fonts/IBMPlexSans-Regular.woff2")
const FONT_SANS_MED: FontFile = preload("res://assets/fonts/IBMPlexSans-Medium.woff2")
const FONT_SERIF: FontFile = preload("res://assets/fonts/IBMPlexSerif-Regular.woff2")
const FONT_SERIF_MED: FontFile = preload("res://assets/fonts/IBMPlexSerif-Medium.woff2")
const FONT_SERIF_ITALIC: FontFile = preload("res://assets/fonts/IBMPlexSerif-Italic.woff2")
const FONT_MONO: FontFile = preload("res://assets/fonts/IBMPlexMono-Regular.woff2")
const FONT_MONO_MED: FontFile = preload("res://assets/fonts/IBMPlexMono-Medium.woff2")

# Modular scale — replaces the old ad-hoc 9..28 spread. Floored at 11 so no UI
# text drops below comfortable legibility.
const SIZE_CAPTION: int = 11
const SIZE_SMALL: int = 12
const SIZE_BODY: int = 14
const SIZE_ITEM: int = 16
const SIZE_SECTION: int = 20
const SIZE_TITLE: int = 26
const SIZE_DISPLAY: int = 34


static func font_scale() -> float:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return 1.0
	var st: SceneTree = ml as SceneTree
	if st == null or st.root == null:
		return 1.0
	var cfg := st.root.get_node_or_null("/root/TankConfig")
	if cfg == null:
		return 1.0
	return clampf(float(cfg.ui_font_scale), 0.8, 1.5)


static func scaled_size(base: int) -> int:
	return maxi(8, int(round(float(base) * font_scale())))


# Apply a font family (+ optional size) to any text control. Hides the
# per-class override-key differences between Label/Button and RichTextLabel.
static func apply_font(node: Control, font: Font, size: int = -1) -> void:
	if size > 0:
		size = scaled_size(size)
	if node is RichTextLabel:
		node.add_theme_font_override("normal_font", font)
		if size > 0:
			node.add_theme_font_size_override("normal_font_size", size)
	else:
		node.add_theme_font_override("font", font)
		if size > 0:
			node.add_theme_font_size_override("font_size", size)


# Voice helpers. Each returns the node, so a fresh Label can be wrapped inline:
#   var l := PanelTheme.as_serif(Label.new(), PanelTheme.SIZE_SECTION, true)
static func as_sans(node: Control, size: int = SIZE_BODY, medium: bool = false) -> Control:
	apply_font(node, FONT_SANS_MED if medium else FONT_SANS, size)
	return node


static func as_serif(node: Control, size: int = SIZE_BODY, medium: bool = false) -> Control:
	apply_font(node, FONT_SERIF_MED if medium else FONT_SERIF, size)
	return node


static func as_serif_italic(node: Control, size: int = SIZE_BODY) -> Control:
	apply_font(node, FONT_SERIF_ITALIC, size)
	return node


static func as_mono(node: Control, size: int = SIZE_SMALL, medium: bool = false) -> Control:
	apply_font(node, FONT_MONO_MED if medium else FONT_MONO, size)
	return node


# ---- Panel chrome ------------------------------------------------------------

# Applies the dark rounded backdrop + generous padding to a PanelContainer.
# Call once from each panel's _build_ui() before adding any children.
static func apply_panel_chrome(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = _cohesion_bg if _cohesion_active else BG
	style.border_color = _cohesion_border if _cohesion_active else BORDER
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	# Generous inner padding — the old panels were CRAMPED right against the
	# rounded edge; bumping to 18/14 gives the form room to breathe.
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 14
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	panel.add_theme_stylebox_override("panel", style)


# Lighter card chrome for the tank shelf grid — same family as side panels but
# subtler border and tighter padding.
static func apply_shelf_card_chrome(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = SHELF_CARD_BG
	style.border_color = Color(BORDER.r, BORDER.g, BORDER.b, 0.42)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.shadow_color = Color(0, 0, 0, 0.28)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	panel.add_theme_stylebox_override("panel", style)


static func make_shelf_card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = SHELF_CARD_BG
	style.border_color = Color(BORDER.r, BORDER.g, BORDER.b, 0.42)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


# Full-screen shelf backdrop.
static func make_page_background(parent: Control) -> ColorRect:
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = SHELF_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	parent.move_child(bg, 0)
	return bg


# Modal overlay: dim scrim + centered host. Returns { overlay, center, panel_slot }.
static func make_modal_root(parent: Control, z_index: int = Z_MENU_MODAL,
		on_dismiss: Callable = Callable()) -> Dictionary:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = z_index
	parent.add_child(overlay)

	var scrim := ColorRect.new()
	scrim.color = MODAL_SCRIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	if on_dismiss.is_valid():
		scrim.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				on_dismiss.call())
	overlay.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	return {"overlay": overlay, "center": center, "scrim": scrim}


# Viewport-relative modal panel sizing (replaces fixed 720×580 offsets).
static func layout_modal_panel(panel: PanelContainer, vp: Vector2,
		min_w: float = MODAL_MIN_W, min_h: float = MODAL_MIN_H,
		max_w_frac: float = 0.92, max_h_frac: float = 0.88) -> void:
	var w: float = clampf(vp.x * max_w_frac, min_w, vp.x - EDGE_MARGIN * 2.0)
	var h: float = clampf(vp.y * max_h_frac, min_h, vp.y - EDGE_MARGIN * 2.0)
	panel.custom_minimum_size = Vector2(w, h)


# Standard top-bar row for menu pages.
static func make_top_bar_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	return row


# Visually groups related toolbar buttons (Create / Manage / Help).
static func make_action_cluster(buttons: Array[Button], separation: int = 8) -> HBoxContainer:
	var cluster := HBoxContainer.new()
	cluster.add_theme_constant_override("separation", separation)
	for btn in buttons:
		if btn != null:
			cluster.add_child(btn)
	return cluster


# ---- Typography --------------------------------------------------------------

# Full-height side dock — all rail-triggered panels share the same slot
# (right edge, below TopHUD, above FooterBar, inset for the rail).
static func apply_side_dock(panel: Control, edge: String = "right") -> void:
	if edge == "left":
		panel.anchor_left = 0.0
		panel.anchor_top = 0.0
		panel.anchor_right = 0.0
		panel.anchor_bottom = 1.0
	else:
		panel.anchor_left = 1.0
		panel.anchor_top = 0.0
		panel.anchor_right = 1.0
		panel.anchor_bottom = 1.0


static func layout_side_panel(panel: Control, rail_inset: float, top: float,
		bottom: float, width: float, edge: String = "right") -> void:
	apply_side_dock(panel, edge)
	panel.offset_top = top
	panel.offset_bottom = -bottom
	if edge == "left":
		panel.offset_left = EDGE_MARGIN
		panel.offset_right = EDGE_MARGIN + width
	else:
		panel.offset_left = -(rail_inset + width)
		panel.offset_right = -rail_inset


# Transient notification cards — bottom-left stack, clear of side panels + rail.
static func layout_toast_stack(layer: Control, bottom_inset: float) -> void:
	layer.anchor_left = 0.0
	layer.anchor_top = 1.0
	layer.anchor_right = 0.0
	layer.anchor_bottom = 1.0
	layer.offset_left = EDGE_MARGIN
	layer.offset_right = EDGE_MARGIN + TOAST_STACK_W
	layer.offset_top = -(bottom_inset + TOAST_STACK_H)
	layer.offset_bottom = -bottom_inset


# Title row with an optional trailing Close — used by full-screen modals whose
# header also carries tabs or filters (Life Library, Notifications, etc.).
static func make_panel_header(title_text: String, on_close: Callable = Callable()) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var title := make_title(title_text)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	if on_close.is_valid():
		row.add_child(make_close_button(on_close))
	return row


# Compact title row for HUD chip popovers — small × instead of a full Close pill.
static func make_chip_popup_header(title_text: String, on_close: Callable = Callable()) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var title := make_title(title_text)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	if on_close.is_valid():
		var xbtn := make_secondary_button("×")
		xbtn.custom_minimum_size = Vector2(22, 22)
		xbtn.tooltip_text = "Close"
		xbtn.pressed.connect(on_close)
		row.add_child(xbtn)
	return row


# Standard dismiss control — always the same label + styling app-wide.
static func make_close_button(on_close: Callable = Callable()) -> Button:
	var b := make_secondary_button("Close")
	if on_close.is_valid():
		b.pressed.connect(on_close)
	return b


# Pinned footer row for side panels: optional leading actions, Close on the right.
static func make_panel_footer(on_close: Callable, primary: Button = null,
		middle: Array[Button] = []) -> VBoxContainer:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 8)
	block.add_child(make_rule())
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 8)
	block.add_child(hb)
	for btn in middle:
		if btn != null:
			hb.add_child(btn)
	if primary != null:
		hb.add_child(primary)
	hb.add_child(make_close_button(on_close))
	return block


# Big panel title. Pair with add_rule() right after for a clean separator
# between the title and the body content.
static func make_title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	apply_font(l, FONT_SERIF_MED, SIZE_TITLE)
	l.add_theme_color_override("font_color", TITLE_FG)
	return l


# Optional subtitle / context line shown right under the title. Smaller
# and dimmer so the eye lands on the title first.
static func make_subtitle(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", scaled_size(SIZE_CAPTION))
	l.add_theme_color_override("font_color", DIM_FG)
	return l


# Section header. Uppercase + tinted to read as a category label rather
# than a value, so groups are scannable without bold/letter-spacing
# tricks Godot 4 doesn't expose on Label.
static func make_section(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", scaled_size(SIZE_CAPTION))
	l.add_theme_color_override("font_color", SECTION_FG)
	return l


# Description line under a dropdown. Wraps automatically; reads as
# secondary information so it doesn't compete with the labels.
static func make_description() -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", scaled_size(SIZE_CAPTION))
	l.add_theme_color_override("font_color", DIM_FG)
	return l


# Thin horizontal separator. Replaces the default HSeparator look (which
# is high-contrast and blocky) with a near-invisible 1-px tint line.
static func make_rule() -> HSeparator:
	var s := HSeparator.new()
	var rule_style := StyleBoxFlat.new()
	rule_style.bg_color = RULE_FG
	s.add_theme_stylebox_override("separator", rule_style)
	s.custom_minimum_size = Vector2(0, 1)
	return s


# Pure vertical spacer — useful between section header and first row,
# or above section headers for breathing room.
static func make_spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


# ---- Form rows ---------------------------------------------------------------

# Standard label + slider + value layout. The value_label is built by
# the caller (so they can hold a reference for live updates) and is
# right-aligned in a fixed-width column for tidy decimal alignment.
static func add_slider_row(parent: Node, label_text: String, min_val: float,
		max_val: float, step: float, value_label: Label) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(160, 0)
	l.add_theme_color_override("font_color", LABEL_FG)
	row.add_child(l)

	var s := HSlider.new()
	s.min_value = min_val
	s.max_value = max_val
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Bumped to 24px so a fingertip can actually grab the thumb on touch
	# without the slider feeling like a hairline on tablets.
	s.custom_minimum_size = Vector2(0, 24)
	row.add_child(s)

	value_label.custom_minimum_size = Vector2(56, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", VALUE_FG)
	# Numeric readout → Mono so decimals line up in the fixed-width column.
	as_mono(value_label, SIZE_BODY)
	row.add_child(value_label)
	return s


# Standard label + dropdown layout. Returns the OptionButton so the
# caller can populate it with their domain-specific options.
static func add_dropdown_row(parent: Node, label_text: String) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(160, 0)
	l.add_theme_color_override("font_color", LABEL_FG)
	row.add_child(l)

	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.custom_minimum_size = Vector2(0, 30)
	row.add_child(ob)
	return ob


# ---- Footer buttons ----------------------------------------------------------

# Primary action (Apply): filled tinted button. Visually stronger than
# the secondary so the user knows which one commits.
# Per-platform button height. Mobile gets 48dp to satisfy Material Design's
# minimum tap target. Desktop keeps the denser 34px so a settings panel
# doesn't feel cavernous on a mouse-driven display.
static func _button_min_height() -> int:
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		return 48
	return 34


static func make_primary_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110, _button_min_height())
	apply_font(b, FONT_SANS_MED, SIZE_BODY)
	b.add_theme_color_override("font_color", PRIMARY_FG)
	b.add_theme_color_override("font_hover_color", PRIMARY_FG)
	b.add_theme_color_override("font_pressed_color", PRIMARY_FG)
	b.add_theme_stylebox_override("normal", _filled_stylebox(PRIMARY_BG))
	b.add_theme_stylebox_override("hover", _filled_stylebox(PRIMARY_BG_HOVER))
	b.add_theme_stylebox_override("pressed",
		_filled_stylebox(PRIMARY_BG.darkened(0.15)))
	b.add_theme_stylebox_override("focus", _filled_stylebox(PRIMARY_BG))
	return b


# Secondary action (Close, Cancel, etc.): flat outlined button.
static func make_secondary_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(88, _button_min_height())
	apply_font(b, FONT_SANS_MED, SIZE_BODY)
	b.add_theme_color_override("font_color", LABEL_FG)
	b.add_theme_stylebox_override("normal", _outlined_stylebox())
	b.add_theme_stylebox_override("hover", _filled_stylebox(Color(0.22, 0.28, 0.36, 0.7)))
	b.add_theme_stylebox_override("pressed", _filled_stylebox(Color(0.32, 0.38, 0.48, 0.8)))
	b.add_theme_stylebox_override("focus", _outlined_stylebox())
	return b


# Tertiary / example actions — dim outlined chips (demo tracks, optional links).
static func make_chip_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(108, _button_min_height() - 2)
	apply_font(b, FONT_SANS, SIZE_SMALL)
	b.add_theme_color_override("font_color", DIM_FG)
	b.add_theme_color_override("font_hover_color", LABEL_FG)
	b.add_theme_color_override("font_pressed_color", SECTION_FG)
	var normal := _outlined_stylebox()
	normal.bg_color = Color(0.09, 0.11, 0.16, 0.72)
	normal.border_color = Color(BORDER.r, BORDER.g, BORDER.b, 0.38)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", _filled_stylebox(Color(0.16, 0.20, 0.28, 0.82)))
	b.add_theme_stylebox_override("pressed", _filled_stylebox(Color(0.20, 0.26, 0.34, 0.9)))
	b.add_theme_stylebox_override("focus", normal)
	return b


# Square glyph button for inline row actions (rename / duplicate / delete on a
# card). Distinct from make_chip_button, which is a *wide* labelled pill — an
# icon button is sized to its glyph so three of them don't crowd out a title.
static func make_icon_button(glyph: String) -> Button:
	var b := Button.new()
	b.text = glyph
	b.focus_mode = Control.FOCUS_NONE
	var side: int = 40 if _button_min_height() >= 48 else 32
	b.custom_minimum_size = Vector2(side, side)
	apply_font(b, FONT_SANS, SIZE_ITEM)
	b.add_theme_color_override("font_color", DIM_FG)
	b.add_theme_color_override("font_hover_color", LABEL_FG)
	b.add_theme_color_override("font_pressed_color", SECTION_FG)
	var normal := _icon_button_stylebox(Color(0.09, 0.11, 0.16, 0.0))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover",
		_icon_button_stylebox(Color(0.16, 0.20, 0.28, 0.82)))
	b.add_theme_stylebox_override("pressed",
		_icon_button_stylebox(Color(0.20, 0.26, 0.34, 0.9)))
	b.add_theme_stylebox_override("focus", normal)
	return b


static func _icon_button_stylebox(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


# Flat text-only control (disclosure toggles, low-priority links).
static func make_ghost_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, _button_min_height() - 6)
	apply_font(b, FONT_SANS, SIZE_SMALL)
	b.add_theme_color_override("font_color", DIM_FG)
	b.add_theme_color_override("font_hover_color", LABEL_FG)
	b.add_theme_color_override("font_pressed_color", SECTION_FG)
	var empty := StyleBoxEmpty.new()
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("hover", _filled_stylebox(Color(0.14, 0.17, 0.24, 0.55)))
	b.add_theme_stylebox_override("pressed", _filled_stylebox(Color(0.18, 0.22, 0.30, 0.65)))
	b.add_theme_stylebox_override("focus", empty)
	return b


static func _filled_stylebox(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func _outlined_stylebox() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = BORDER
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


# ---- HUD / rail chrome -------------------------------------------------------

# Top-bar cluster backdrop — matches main.tscn SBF_cluster but sourced here
# so future tweaks stay in one place.
static func make_hud_cluster_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = HUD_BG
	s.border_color = HUD_BORDER
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.corner_radius_top_left = 10
	s.corner_radius_top_right = 10
	s.corner_radius_bottom_left = 10
	s.corner_radius_bottom_right = 10
	s.content_margin_left = 8.0
	s.content_margin_top = 6.0
	s.content_margin_right = 8.0
	s.content_margin_bottom = 6.0
	s.shadow_color = Color(0, 0, 0, 0.25)
	s.shadow_size = 4
	s.shadow_offset = Vector2(0, 2)
	return s


# Bottom footer dock — rounded top edge only so it reads as attached to the
# viewport bottom; flat bottom sits flush with the screen edge.
static func make_footer_bar_style() -> StyleBoxFlat:
	var s := make_hud_cluster_style()
	s.corner_radius_bottom_left = 0
	s.corner_radius_bottom_right = 0
	s.content_margin_left = 10.0
	s.content_margin_right = 10.0
	s.content_margin_top = 5.0
	s.content_margin_bottom = 5.0
	return s


# Vertical rail dock — taller, softer shadow so it reads as a sidebar.
static func make_rail_cluster_style() -> StyleBoxFlat:
	var s := make_hud_cluster_style()
	s.content_margin_left = 4.0
	s.content_margin_right = 4.0
	s.content_margin_top = 8.0
	s.content_margin_bottom = 8.0
	s.shadow_size = 6
	s.shadow_offset = Vector2(-2, 0)
	return s


static func _rail_button_stylebox(bg: Color, radius: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


# Style a rail icon button. `active` tints the background when its panel/mode
# is open so the dock communicates state at a glance.
static func style_rail_button(btn: Button, active: bool = false) -> void:
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(RAIL_BUTTON, RAIL_BUTTON)
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_stylebox_override("normal",
		_rail_button_stylebox(Color(0, 0, 0, 0)))
	btn.add_theme_stylebox_override("hover",
		_rail_button_stylebox(Color(0.18, 0.24, 0.34, 0.55)))
	btn.add_theme_stylebox_override("pressed",
		_rail_button_stylebox(Color(0.32, 0.46, 0.62, 0.7)))
	btn.add_theme_stylebox_override("focus",
		_rail_button_stylebox(Color(0, 0, 0, 0)))
	if active:
		btn.add_theme_stylebox_override("normal",
			_rail_button_stylebox(RAIL_ACTIVE_BG))
		btn.modulate = Color(1.0, 1.0, 1.0, 1.0)
	else:
		btn.modulate = Color(0.92, 0.94, 0.98, 0.92)


# Compact tool chip for aquascape / inline toolbars.
static func style_compact_tool_button(btn: Button, active: bool = false) -> void:
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 28)
	apply_font(btn, FONT_SANS, SIZE_CAPTION)
	var fg: Color = PRIMARY_FG if active else LABEL_FG
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", PRIMARY_FG)
	btn.add_theme_color_override("font_pressed_color", PRIMARY_FG)
	var normal := _filled_stylebox(Color(0.10, 0.12, 0.18, 0.55) if active else Color(0.08, 0.10, 0.15, 0.45))
	normal.content_margin_left = 8
	normal.content_margin_right = 8
	normal.content_margin_top = 3
	normal.content_margin_bottom = 3
	normal.border_color = Color(SECTION_FG.r, SECTION_FG.g, SECTION_FG.b, 0.55 if active else 0.22)
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", _filled_stylebox(Color(0.16, 0.20, 0.28, 0.78)))
	btn.add_theme_stylebox_override("pressed", _filled_stylebox(Color(0.20, 0.26, 0.34, 0.9)))
	btn.add_theme_stylebox_override("focus", normal)


# Top aquascape toolbar — lighter than a full side panel, same HUD family.
static func apply_aquascape_toolbar_chrome(panel: PanelContainer) -> void:
	var style := make_hud_cluster_style()
	style.bg_color = Color(HUD_BG.r, HUD_BG.g, HUD_BG.b, 0.92)
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	panel.add_theme_stylebox_override("panel", style)


# Thin vertical rule between stat-chip groups in the top bar.
static func make_hud_chip_divider() -> Control:
	var sep := VSeparator.new()
	var rule := StyleBoxFlat.new()
	rule.bg_color = Color(RULE_FG.r, RULE_FG.g, RULE_FG.b, 0.65)
	sep.add_theme_stylebox_override("separator", rule)
	sep.custom_minimum_size = Vector2(2, 22)
	return sep


static func style_hud_toggle_button(btn: Button, active: bool = false) -> void:
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, _button_min_height())
	btn.add_theme_font_size_override("font_size", 14)
	var normal_bg: Color = RAIL_ACTIVE_BG if active else Color(0, 0, 0, 0)
	btn.add_theme_stylebox_override("normal",
		_rail_button_stylebox(normal_bg, 6))
	btn.add_theme_stylebox_override("hover",
		_rail_button_stylebox(Color(0.18, 0.24, 0.34, 0.55), 6))
	btn.add_theme_stylebox_override("pressed",
		_rail_button_stylebox(Color(0.32, 0.46, 0.62, 0.7), 6))
	btn.add_theme_stylebox_override("focus",
		_rail_button_stylebox(Color(0, 0, 0, 0), 6))
	btn.modulate = Color(1, 1, 1, 1) if active else Color(0.92, 0.94, 0.98, 0.95)
