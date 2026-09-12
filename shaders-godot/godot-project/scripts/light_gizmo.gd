extends Control
class_name LightGizmo

# The visible handles for the tank lamp.
#
# Drawn as a 2D overlay rather than 3D meshes on purpose. The world renders
# through a 48-colour palette quantizer at low internal resolution; a gizmo
# built from voxels would be quantized along with it and read as scenery
# rather than as UI. Everything here sits above Display, crisp, like the
# rest of the HUD - so it is unmistakably a control, not part of the tank.
#
# The design this replaces was double-click-to-enter-a-mode, then drag,
# then Escape. Four steps to nudge a lamp, with nothing on screen to say
# any of it was possible. This version has no modes: the handles appear as
# you approach, you drag them, and that is the whole interaction.

const H := preload("res://scripts/light_handle.gd")

var lamp_screen: Vector2 = Vector2.INF
var aim_screen: Vector2 = Vector2.INF
var reveal: float = 0.0
var hover_kind: int = H.NONE
var drag_kind: int = H.NONE

const COL_LAMP := Color(1.0, 0.86, 0.52)
const COL_AIM := Color(0.62, 0.86, 1.0)


func _ready() -> void:
	# Purely a painter. It must never eat a click, or it would block the
	# camera, the feeding tools and every other click in the tank.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func refresh(p_lamp: Vector2, p_aim: Vector2, p_reveal: float,
		p_hover: int, p_drag: int) -> void:
	# Only repaint when something actually changed - this runs on mouse
	# motion, which is every frame while the cursor moves.
	if p_lamp == lamp_screen and p_aim == aim_screen \
			and is_equal_approx(p_reveal, reveal) \
			and p_hover == hover_kind and p_drag == drag_kind:
		return
	lamp_screen = p_lamp
	aim_screen = p_aim
	reveal = p_reveal
	hover_kind = p_hover
	drag_kind = p_drag
	visible = reveal > 0.01
	queue_redraw()


# A handle whose world anchor is off to the side still unprojects to a
# large FINITE screen position, so an INF check alone is not enough: the
# lamp-to-aim link used to be drawn to those, producing a long stray line
# straight across the tank. Nothing is drawn for a handle that is not
# actually on screen.
func _on_screen(p: Vector2) -> bool:
	if p == Vector2.INF or not (is_finite(p.x) and is_finite(p.y)):
		return false
	var r: Rect2 = get_viewport_rect().grow(64.0)
	return r.has_point(p)


func _draw() -> void:
	if reveal <= 0.01 or not _on_screen(lamp_screen):
		return
	var a: float = clampf(reveal, 0.0, 1.0)
	var dragging: bool = drag_kind != H.NONE
	# The aim ring only matters once you are engaged with the lamp, so it
	# comes in later than the lamp ring rather than both arriving at once.
	var aim_a: float = a if (dragging or hover_kind != H.NONE) else a * 0.35

	if _on_screen(aim_screen):
		_draw_aim(aim_a)
	if _on_screen(lamp_screen):
		_draw_lamp(a)


func _draw_lamp(a: float) -> void:
	var hot: bool = hover_kind == H.LAMP or drag_kind == H.LAMP
	var r: float = H.LAMP_RING_PX * (1.18 if hot else 1.0)
	var col := Color(COL_LAMP.r, COL_LAMP.g, COL_LAMP.b, a * (0.95 if hot else 0.5))
	# A soft halo under the ring so the lamp reads as lit, not just circled.
	if hot:
		draw_circle(lamp_screen, r * 1.9,
			Color(COL_LAMP.r, COL_LAMP.g, COL_LAMP.b, a * 0.14))
	draw_arc(lamp_screen, r, 0.0, TAU, 40, col, 2.5 if hot else 1.5, true)
	# Four ticks reading as a move handle rather than a target.
	if hot:
		for i in 4:
			var ang: float = TAU * float(i) / 4.0 + PI * 0.25
			var d := Vector2(cos(ang), sin(ang))
			draw_line(lamp_screen + d * (r + 3.0),
				lamp_screen + d * (r + 8.0), col, 2.0, true)


func _draw_aim(a: float) -> void:
	var hot: bool = hover_kind == H.AIM or drag_kind == H.AIM
	var r: float = H.AIM_RING_PX * (1.15 if hot else 1.0)
	var col := Color(COL_AIM.r, COL_AIM.g, COL_AIM.b, a * (0.95 if hot else 0.45))
	# Flattened: it lies on the substrate, so a circle would read as
	# floating in the water rather than painted on the gravel.
	_draw_ellipse(aim_screen, r, r * 0.42, col, 2.2 if hot else 1.4)
	var cross: float = r * 0.5
	draw_line(aim_screen - Vector2(cross, 0.0),
		aim_screen + Vector2(cross, 0.0), col, 2.0 if hot else 1.2, true)
	draw_line(aim_screen - Vector2(0.0, cross * 0.42),
		aim_screen + Vector2(0.0, cross * 0.42), col, 2.0 if hot else 1.2, true)


func _draw_ellipse(c: Vector2, rx: float, ry: float, col: Color,
		width: float) -> void:
	var pts := PackedVector2Array()
	for i in 41:
		var t: float = TAU * float(i) / 40.0
		pts.append(c + Vector2(cos(t) * rx, sin(t) * ry))
	draw_polyline(pts, col, width, true)
