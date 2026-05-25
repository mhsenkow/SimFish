# Shared visual language for the side-bar panels (Settings / Render / Fish
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


# ---- Panel chrome ------------------------------------------------------------

# Applies the dark rounded backdrop + generous padding to a PanelContainer.
# Call once from each panel's _build_ui() before adding any children.
static func apply_panel_chrome(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = BG
	style.border_color = BORDER
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


# ---- Typography --------------------------------------------------------------

# Big panel title. Pair with add_rule() right after for a clean separator
# between the title and the body content.
static func make_title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", TITLE_FG)
	return l


# Optional subtitle / context line shown right under the title. Smaller
# and dimmer so the eye lands on the title first.
static func make_subtitle(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", DIM_FG)
	return l


# Section header. Uppercase + tinted to read as a category label rather
# than a value, so groups are scannable without bold/letter-spacing
# tricks Godot 4 doesn't expose on Label.
static func make_section(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", SECTION_FG)
	return l


# Description line under a dropdown. Wraps automatically; reads as
# secondary information so it doesn't compete with the labels.
static func make_description() -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 11)
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
static func make_primary_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110, 34)
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
	b.custom_minimum_size = Vector2(88, 34)
	b.add_theme_color_override("font_color", LABEL_FG)
	b.add_theme_stylebox_override("normal", _outlined_stylebox())
	b.add_theme_stylebox_override("hover", _filled_stylebox(Color(0.22, 0.28, 0.36, 0.7)))
	b.add_theme_stylebox_override("pressed", _filled_stylebox(Color(0.32, 0.38, 0.48, 0.8)))
	b.add_theme_stylebox_override("focus", _outlined_stylebox())
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
