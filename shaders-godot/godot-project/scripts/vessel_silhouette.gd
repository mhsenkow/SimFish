class_name VesselSilhouette
extends Control

# A to-scale drawing of one vessel (tank realism pass).
#
# THE POINT IS THE SHARED SCALE. Every silhouette in a picker is drawn
# against the SAME reference size, so a 5 gallon nano is visibly a fraction
# of a 120 gallon rather than each card filling its own box. Aspect ratio
# alone tells you the shape; a shared scale tells you the size, and size is
# the thing a dropdown of names could never convey.
#
# A fish-length bar sits on the substrate line as a constant reference —
# the same trick the stand uses, and for the same reason.

# Widest vessel in the catalogue, in inches. Everything is drawn relative to
# this so the largest fills the box and the rest fall where they fall.
const REFERENCE_W_IN: float = 48.0
# A small fish, in inches — the reference mark on the substrate.
const FISH_IN: float = 1.8

var w_in: float = 24.0
var d_in: float = 12.0
var h_in: float = 12.0
var shape: String = "box"
var fill_frac: float = 0.93

var glass: Color = Color(0.62, 0.80, 0.90, 0.55)
var water: Color = Color(0.36, 0.62, 0.72, 0.55)
var substrate: Color = Color(0.42, 0.34, 0.26, 0.95)
var fish_mark: Color = Color(0.95, 0.62, 0.28, 0.95)


func configure(spec: Dictionary) -> void:
	w_in = float(spec.get("w_in", w_in))
	d_in = float(spec.get("d_in", d_in))
	h_in = float(spec.get("h_in", h_in))
	shape = String(spec.get("shape", shape))
	queue_redraw()


func _draw() -> void:
	var box: Vector2 = size
	if box.x <= 2.0 or box.y <= 2.0:
		return
	# Scale so REFERENCE_W_IN spans the full width, leaving a small margin.
	var usable_w: float = box.x - 8.0
	var px_per_in: float = usable_w / REFERENCE_W_IN
	# Clamp so the TALLEST vessel in the catalogue still fits, or a column
	# gets cropped. NB: this clamp dominated at first — an 86px-tall box gave
	# 2.5 px/in and every silhouette rendered as a thumbnail in a sea of
	# empty card. The drawing box has to be tall enough that WIDTH is the
	# binding constraint, which is what makes the comparison legible.
	var max_h_in: float = 30.0
	var max_px_h: float = box.y - 8.0
	px_per_in = minf(px_per_in, max_px_h / max_h_in)

	var tw: float = w_in * px_per_in
	var th: float = h_in * px_per_in
	# Sit every vessel on a common baseline, like tanks on a shelf.
	var base_y: float = box.y - 5.0
	var left: float = (box.x - tw) * 0.5
	var top: float = base_y - th

	match shape:
		"cylinder":
			_draw_cylinder(left, top, tw, th)
		"sphere":
			_draw_bowl(left, top, tw, th)
		"hex":
			_draw_hex(left, top, tw, th)
		_:
			_draw_box(left, top, tw, th)

	# Fish-length reference on the substrate line — a constant across every
	# card, so "how big is this really" has an answer.
	var fish_w: float = FISH_IN * px_per_in
	if fish_w >= 2.0:
		draw_rect(Rect2(left + 3.0, base_y - 3.0, fish_w, 2.0), fish_mark)


func _water_top(top: float, th: float) -> float:
	return top + th * (1.0 - fill_frac)


func _draw_box(left: float, top: float, tw: float, th: float) -> void:
	var water_top: float = _water_top(top, th)
	draw_rect(Rect2(left, water_top, tw, top + th - water_top), water)
	# Substrate wedge along the floor.
	var sub_h: float = maxf(2.0, th * 0.14)
	draw_rect(Rect2(left, top + th - sub_h, tw, sub_h), substrate)
	# Glass outline last so it reads on top.
	draw_rect(Rect2(left, top, tw, th), glass, false, 1.5)


func _draw_cylinder(left: float, top: float, tw: float, th: float) -> void:
	# Straight sides with an elliptical top — enough to read as a column.
	var water_top: float = _water_top(top, th)
	draw_rect(Rect2(left, water_top, tw, top + th - water_top), water)
	var sub_h: float = maxf(2.0, th * 0.12)
	draw_rect(Rect2(left, top + th - sub_h, tw, sub_h), substrate)
	draw_rect(Rect2(left, top, tw, th), glass, false, 1.5)
	# Rim ellipse.
	var pts := PackedVector2Array()
	for i in 25:
		var a: float = TAU * float(i) / 24.0
		pts.append(Vector2(left + tw * 0.5 + cos(a) * tw * 0.5,
			top + sin(a) * th * 0.06))
	draw_polyline(pts, glass, 1.5)


func _draw_bowl(left: float, top: float, tw: float, th: float) -> void:
	# A truncated sphere: round bottom, open top. The shape itself is the
	# argument against bowls — almost no surface area at the waterline.
	var cx: float = left + tw * 0.5
	var r: float = minf(tw, th * 1.35) * 0.5
	var cy: float = top + th - r * 0.82
	var pts := PackedVector2Array()
	var water_pts := PackedVector2Array()
	for i in 33:
		var a: float = PI * 0.18 + (PI * 1.64) * float(i) / 32.0
		var p := Vector2(cx + cos(a) * r, cy + sin(a) * r)
		pts.append(p)
		if p.y >= _water_top(top, th):
			water_pts.append(p)
	if water_pts.size() >= 3:
		draw_colored_polygon(water_pts, water)
	draw_polyline(pts, glass, 1.5)


func _draw_hex(left: float, top: float, tw: float, th: float) -> void:
	# Hexagon in plan means a chamfered front elevation.
	var chamfer: float = tw * 0.16
	var water_top: float = _water_top(top, th)
	var body := PackedVector2Array([
		Vector2(left + chamfer, water_top),
		Vector2(left + tw - chamfer, water_top),
		Vector2(left + tw, water_top + (top + th - water_top) * 0.35),
		Vector2(left + tw - chamfer, top + th),
		Vector2(left + chamfer, top + th),
		Vector2(left, water_top + (top + th - water_top) * 0.35),
	])
	draw_colored_polygon(body, water)
	var outline := PackedVector2Array([
		Vector2(left + chamfer, top),
		Vector2(left + tw - chamfer, top),
		Vector2(left + tw, top + th * 0.28),
		Vector2(left + tw - chamfer, top + th),
		Vector2(left + chamfer, top + th),
		Vector2(left, top + th * 0.28),
		Vector2(left + chamfer, top),
	])
	draw_polyline(outline, glass, 1.5)
