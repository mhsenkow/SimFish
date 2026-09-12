class_name ChipPopup
extends PanelContainer

# The shell every HUD chip popup shares (messaging consolidation pass).
#
# There were four — population history, tank story, water chemistry, tank
# alert — each rebuilding the identical container by hand: PanelContainer,
# visible false, MOUSE_FILTER_STOP, z_index 220, the chip stylebox with an
# accent, a VBox, and a header with a close button. ~586 lines of chip/popup
# code sat in main.gd across 26 functions.
#
# Only the BODY differs between them (a wrapped label, a sparkline, a tabbed
# list), so this consolidates the shell and hands each caller its `body` to
# fill. Forcing three dissimilar bodies into one component would have been
# the wrong kind of sharing.
#
# It also removes `header.get_child(0) as Label` — two popups reached their
# title that way, which is the same fragile index-walk that was reaching the
# toast body label. `title_label` is exposed properly.

# Above panels, below modals. Was duplicated as a literal in four places.
const Z_INDEX: int = 220

const BG: Color = Color(0.06, 0.07, 0.12, 0.96)

# Line-height used to size a popup from its content.
const LINE_H: float = 17.0
const CHROME_H: float = 44.0
const MIN_H: float = 72.0
const MAX_H: float = 200.0

var body: VBoxContainer = null
var title_label: Label = null

var _detail: Label = null


static func create(title: String, accent: Color = PanelTheme.HUD_BORDER,
		on_close: Callable = Callable()) -> ChipPopup:
	var p := ChipPopup.new()
	p._configure(title, accent, on_close)
	return p


static func stylebox(accent: Color = PanelTheme.HUD_BORDER) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BG
	style.border_color = Color(accent.r, accent.g, accent.b, 0.68)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	style.shadow_color = Color(0, 0, 0, 0.42)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	return style


# Height for a popup showing `line_count` lines of text.
static func size_for_lines(line_count: int, min_w: float = 236.0) -> Vector2:
	var body_h: float = float(maxi(line_count, 1)) * LINE_H
	return Vector2(min_w, clampf(CHROME_H + body_h, MIN_H, MAX_H))


func _configure(title: String, accent: Color, on_close: Callable) -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = Z_INDEX
	add_theme_stylebox_override("panel", stylebox(accent))

	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	add_child(body)

	var header: HBoxContainer = PanelTheme.make_chip_popup_header(title, on_close)
	body.add_child(header)
	for c in header.get_children():
		var l := c as Label
		if l != null:
			title_label = l
			break


func set_title(text: String) -> void:
	if title_label != null and is_instance_valid(title_label):
		title_label.text = text


# The common case: a single wrapped detail label. Water chemistry and tank
# alert are both exactly this.
func add_detail_label() -> Label:
	if _detail != null and is_instance_valid(_detail):
		return _detail
	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	PanelTheme.apply_font(_detail, PanelTheme.FONT_SANS, PanelTheme.SIZE_SMALL)
	body.add_child(_detail)
	return _detail


func detail_label() -> Label:
	return _detail if is_instance_valid(_detail) else null


# Fill the detail label and size the popup to fit, in one call — the shape
# both water and alert repeated by hand.
func show_lines(lines: PackedStringArray, min_w: float = 236.0) -> void:
	var l: Label = add_detail_label()
	l.text = "\n".join(lines)
	custom_minimum_size = size_for_lines(lines.size(), min_w)
	size = custom_minimum_size


# Place under its chip, clamped to the viewport. Was a free function in
# main.gd that every caller had to remember to call.
func place_under(chip: Control, viewport_size: Vector2, hud_top: float) -> void:
	var sz: Vector2 = size
	if sz.x < 1.0:
		sz = custom_minimum_size
	var x: float = (viewport_size.x - sz.x) * 0.5
	var y: float = hud_top + 6.0
	if chip != null and is_instance_valid(chip):
		var r: Rect2 = chip.get_global_rect()
		x = clampf(r.position.x + r.size.x * 0.5 - sz.x * 0.5,
			8.0, maxf(8.0, viewport_size.x - sz.x - 8.0))
		y = clampf(r.end.y + 6.0, hud_top, maxf(hud_top, viewport_size.y - sz.y - 8.0))
	position = Vector2(x, y)
