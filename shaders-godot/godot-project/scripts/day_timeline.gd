extends Control

# Compact day & time-of-day timeline bar. Four phase icons sit along a 24h
# track (dawn, day, dusk, night) and a glowing puck slides with day_phase.
var phase: float = 0.25
var caption: String = ""
var _pill_style: StyleBoxFlat = null

const _MARKS: Array[Dictionary] = [
	{"p": 0.0, "kind": "dawn"},
	{"p": 0.25, "kind": "day"},
	{"p": 0.5, "kind": "dusk"},
	{"p": 0.75, "kind": "night"},
]


func _ready() -> void:
	custom_minimum_size = Vector2(310, 36)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_style()


func _ensure_style() -> void:
	if _pill_style != null:
		return
	_pill_style = StyleBoxFlat.new()
	_pill_style.bg_color = Color(0.06, 0.08, 0.13, 0.90)
	_pill_style.border_color = Color(0.36, 0.48, 0.66, 0.55)
	_pill_style.set_border_width_all(1)
	_pill_style.set_corner_radius_all(8)


func set_clock(next_phase: float, text: String) -> void:
	var wrapped: float = fposmod(next_phase, 1.0)
	if is_equal_approx(wrapped, phase) and text == caption:
		return
	phase = wrapped
	caption = text
	queue_redraw()


func _kind_at(p: float) -> String:
	if p < 0.125 or p >= 0.875:
		return "dawn"
	if p < 0.375:
		return "day"
	if p < 0.5:
		return "dusk"
	return "night"


func _draw() -> void:
	_ensure_style()
	var font: Font = PanelTheme.FONT_SANS if PanelTheme.FONT_SANS != null else ThemeDB.fallback_font
	if font == null:
		return
	var w: float = size.x
	var h: float = size.y
	if w > 4.0 and h > 4.0:
		draw_style_box(_pill_style, Rect2(Vector2.ZERO, size))
	var pad_x: float = 10.0
	var label_w: float = minf(132.0, maxf(84.0, (w - pad_x * 2.0) * 0.44))
	var display_text: String = caption if caption != "" else ("Day 1 · " + _kind_at(phase))
	draw_string(font, Vector2(pad_x, h * 0.66), display_text,
			HORIZONTAL_ALIGNMENT_LEFT, label_w, 13, Color(0.95, 0.97, 1.0))
	var x0: float = pad_x + label_w + 10.0
	var track_w: float = maxf(16.0, w - x0 - 14.0)
	var y: float = h * 0.52
	draw_line(Vector2(x0, y), Vector2(x0 + track_w, y), Color(0.55, 0.66, 0.82, 0.35), 3.0)
	var prog_x: float = x0 + clampf(phase, 0.0, 1.0) * track_w
	if prog_x > x0 + 1.0:
		draw_line(Vector2(x0, y), Vector2(prog_x, y), Color(0.96, 0.82, 0.44, 0.72), 3.0)
	var ink := Color(0.82, 0.88, 0.95, 0.90)
	for mark in _MARKS:
		var x: float = x0 + float(mark["p"]) * track_w
		draw_line(Vector2(x, y - 5.0), Vector2(x, y + 5.0), Color(0.75, 0.82, 0.92, 0.45), 1.2)
		_draw_mark(String(mark["kind"]), Vector2(x, y - 9.0), 3.4, ink)
	var now := Vector2(prog_x, y)
	draw_circle(now, 8.5, Color(1.0, 0.88, 0.46, 0.28))
	draw_circle(now, 6.2, Color(0.08, 0.11, 0.16, 0.96))
	draw_arc(now, 6.2, 0.0, TAU, 16, Color(1.0, 0.90, 0.54, 0.95), 1.5)
	_draw_mark(_kind_at(phase), now, 4.0, Color(1.0, 0.94, 0.66))


func _draw_mark(kind: String, at: Vector2, r: float, color: Color) -> void:
	match kind:
		"day":
			draw_circle(at, r * 0.55, color)
			for i in 4:
				var a: float = float(i) * TAU / 4.0 + 0.4
				var dir := Vector2(cos(a), sin(a))
				draw_line(at + dir * r * 0.85, at + dir * r * 1.35, color, 1.2)
		"night":
			draw_arc(at, r * 0.7, -1.15, 1.15, 10, color, 1.4)
		"dusk":
			draw_circle(at + Vector2(0, r * 0.15), r * 0.5, color)
			draw_line(at + Vector2(-r, r * 0.55), at + Vector2(r, r * 0.55), color, 1.2)
		_:
			draw_arc(at + Vector2(0, r * 0.25), r * 0.7, PI, TAU, 8, color, 1.4)
			draw_line(at + Vector2(-r, r * 0.35), at + Vector2(r, r * 0.35), color, 1.2)
