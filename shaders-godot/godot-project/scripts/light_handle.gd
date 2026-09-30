extends RefCounted
class_name LightHandle

# Direct manipulation of the tank light: hover it, press to grab it, drag
# to move it, and the beam follows. Esc / right-click cancels.
#
# The maths lives here rather than in main.gd because all of it is pure -
# a ray, a plane, and a clamp - and because the alternative is another
# hundred lines of geometry buried in an 11k-line input handler.
#
# TWO THINGS ARE DRAGGABLE, and they are different:
#
#   the HEAD  - where the lamp is clamped, moved across the rim plane.
#               Writes spot_offset_x / spot_offset_z.
#   the AIM   - where the cone lands, moved across the substrate plane.
#               Writes spot_aim_x / spot_aim_z.
#
# Moving the head alone is not enough to be useful: a lamp that always
# points at the same spot no matter where you clamp it is a lamp on a
# gimbal, not a clip light. Moving the aim alone cannot express "the lamp
# is in the corner". Both, and the beam follows from the pair.

# Which handle is under the cursor.
enum { NONE = 0, LAMP = 1, AIM = 2 }

# Screen-space grab radius. Generous: the lamp head is a small object and
# this is a deliberate, low-frequency interaction, not a precision one.
const GRAB_RADIUS_PX: float = 46.0
const GRAB_RADIUS_PX_TOUCH: float = 72.0

# Progressive disclosure. The handles are invisible until the cursor comes
# near the lamp, then fade up - so the tank is not permanently cluttered
# with gizmos, but you find them by moving toward the thing you want.
#
# NEAR must stay >= the largest grab radius. Otherwise there is a band
# where a handle is already grabbable while still fading in, which reads as
# the gizmo fighting you: you click something half-drawn and it moves.
const REVEAL_NEAR_PX: float = 76.0
const REVEAL_FAR_PX: float = 150.0

# Drawn radii.
const LAMP_RING_PX: float = 15.0
const AIM_RING_PX: float = 19.0

# How far outside the glass the head may be dragged. A clip-on lamp really
# does hang off the rim, so a little overhang is correct - but not so much
# that the lamp ends up across the room.
const HEAD_OVERHANG: float = 1.15


static func grab_radius(touch: bool) -> float:
	return GRAB_RADIUS_PX_TOUCH if touch else GRAB_RADIUS_PX


# Is this screen point close enough to the handle to grab it?
static func hit_test(screen_pos: Vector2, handle_screen: Vector2,
		radius_px: float) -> bool:
	return screen_pos.distance_to(handle_screen) <= maxf(1.0, radius_px)


# Where a camera ray crosses a horizontal plane. Returns Vector3.INF when
# the ray runs parallel to it or would only meet it behind the camera -
# dragging must not teleport the lamp to a point behind the viewer.
static func ray_plane_xz(origin: Vector3, dir: Vector3, plane_y: float) -> Vector3:
	if absf(dir.y) < 1e-5:
		return Vector3.INF
	var t: float = (plane_y - origin.y) / dir.y
	if t <= 0.0:
		return Vector3.INF
	return origin + dir * t


# World xz -> the normalised offsets the rig stores (-1..1 of half-extent).
static func offsets_from_world(world_pos: Vector3, half_w: float,
		half_d: float, overhang: float = HEAD_OVERHANG) -> Vector2:
	var hw: float = maxf(0.001, half_w)
	var hd: float = maxf(0.001, half_d)
	return Vector2(
		clampf(world_pos.x / hw, -overhang, overhang),
		clampf(world_pos.z / hd, -overhang, overhang))


# The aim target stays strictly inside the glass - a cone aimed outside the
# tank is the bug this whole rig was built to stop.
static func aim_from_world(world_pos: Vector3, half_w: float,
		half_d: float) -> Vector2:
	return offsets_from_world(world_pos, half_w, half_d, 0.92)


# World position of the lamp head for given offsets, matching
# LightingRig.head_position so the handle and the light cannot drift apart.
static func head_world(half_w: float, half_d: float, tank_height: float,
		height_above: float, offset_x: float, offset_z: float) -> Vector3:
	return Vector3(
		clampf(offset_x, -HEAD_OVERHANG, HEAD_OVERHANG) * half_w,
		tank_height + height_above,
		clampf(offset_z, -HEAD_OVERHANG, HEAD_OVERHANG) * half_d)


# --- The drag model ------------------------------------------------------
#
# The build and the drag MUST agree on where a given pair of offsets puts
# the lamp, or the lamp jumps the first time it is touched and again on the
# next reload. Both go through fixture_home + mount_above + head_world +
# clamp_to_footprint; nothing else computes a head position.

# Where each fixture sits with zero offsets, as a fraction of the tank's
# half-extent. The gooseneck clamps near the back-right rim by default.
const GOOSENECK_HOME := Vector2(0.15, -0.80)
# The gooseneck head hangs just over its rim clamp, whatever light_height
# (the pendant/bar mount height) says.
const GOOSENECK_MOUNT_ABOVE: float = 0.62
# The aim stays this far inside the glass.
const AIM_INSET: float = 0.92


static func fixture_home(fixture: String) -> Vector2:
	return GOOSENECK_HOME if fixture == "gooseneck" else Vector2.ZERO


static func mount_above(fixture: String, light_height: float) -> float:
	return GOOSENECK_MOUNT_ABOVE if fixture == "gooseneck" else light_height


# World xz -> the offsets the rig stores, which are RELATIVE to the fixture
# home. The inverse of head_world(home + offset).
static func offsets_relative(p: Vector2, half_w: float, half_d: float,
		home: Vector2) -> Vector2:
	return Vector2(p.x / maxf(0.001, half_w), p.y / maxf(0.001, half_d)) - home


# Keep a point inside the tank footprint scaled about its centre: > 1 lets
# the lamp overhang the rim, < 1 keeps the aim off the glass. A bounding-box
# clamp let both past the corners of a hex or a cylinder, which put the cone
# outside the tank.
static func clamp_to_footprint(p: Vector2, corners: Array, scale: float) -> Vector2:
	var poly := PackedVector2Array()
	for c in corners:
		var v: Vector3 = c
		poly.append(Vector2(v.x, v.z) * scale)
	if poly.size() < 3 or Geometry2D.is_point_in_polygon(p, poly):
		return p
	var best: Vector2 = p
	var best_d: float = INF
	for i in poly.size():
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(
			p, poly[i], poly[(i + 1) % poly.size()])
		var d: float = p.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best = q
	return best


# Which surface a drag slides along, chosen ONCE at grab. At hero camera
# angles the lamp's own plane is nearly edge-on: |ray.y| -> 0 makes a
# ray-plane hit explode, so a one-pixel mouse move slammed the lamp from
# one clamp corner to the other. Past GRAZE_DIR_Y the drag uses an upright,
# camera-facing plane instead (sideways = sideways, up = away).
enum { SURFACE_FLAT = 0, SURFACE_UPRIGHT = 1 }
const GRAZE_DIR_Y: float = 0.28


static func choose_surface(dir: Vector3) -> int:
	return SURFACE_UPRIGHT if absf(dir.y) < GRAZE_DIR_Y else SURFACE_FLAT


# The camera's horizontal forward - the normal of the upright surface.
static func view_flat(dir: Vector3) -> Vector3:
	var f := Vector3(dir.x, 0.0, dir.z)
	if f.length_squared() < 1e-8:
		return Vector3.FORWARD
	return f.normalized()


# Where the cursor ray meets the drag surface, on the plane y = plane_y.
# `anchor` is a point on the upright surface (the handle at grab).
static func surface_hit(surface: int, origin: Vector3, dir: Vector3,
		plane_y: float, anchor: Vector3, view: Vector3) -> Vector3:
	if surface == SURFACE_FLAT:
		return ray_plane_xz(origin, dir, plane_y)
	var denom: float = dir.dot(view)
	if denom < 1e-4:
		return Vector3.INF
	var t: float = (anchor - origin).dot(view) / denom
	if t <= 0.0:
		return Vector3.INF
	var p: Vector3 = origin + dir * t
	return Vector3(p.x, plane_y, p.z) + view * (p.y - plane_y)


# The grab-offset model: the dragged thing keeps the offset it had from the
# cursor at grab, so pressing does not snap its centre to the pointer and a
# click without a move changes nothing at all.
static func dragged(start: Vector3, grab_hit: Vector3, hit: Vector3) -> Vector3:
	if start == Vector3.INF or grab_hit == Vector3.INF or hit == Vector3.INF:
		return Vector3.INF
	return Vector3(start.x + hit.x - grab_hit.x, start.y,
		start.z + hit.z - grab_hit.z)


# Round for display so a dragged value reads as a settled number rather
# than eighteen decimal places of jitter.
static func quantise(v: float) -> float:
	return snappedf(v, 0.01)


static func describe(offset_x: float, offset_z: float,
		aim_x: float, aim_z: float) -> String:
	return "lamp %.2f, %.2f  ->  aim %.2f, %.2f" % [
		quantise(offset_x), quantise(offset_z),
		quantise(aim_x), quantise(aim_z)]


# 0 at REVEAL_FAR and beyond, 1 at REVEAL_NEAR and closer. Drives how
# strongly the gizmo is drawn, so it appears as the cursor approaches
# rather than either always cluttering the tank or never being found.
static func reveal(cursor: Vector2, lamp_screen: Vector2) -> float:
	if lamp_screen == Vector2.INF:
		return 0.0
	var d: float = cursor.distance_to(lamp_screen)
	if d <= REVEAL_NEAR_PX:
		return 1.0
	if d >= REVEAL_FAR_PX:
		return 0.0
	return 1.0 - (d - REVEAL_NEAR_PX) / (REVEAL_FAR_PX - REVEAL_NEAR_PX)


# Which handle the cursor is over. The LAMP wins ties: it is the thing
# people reach for, and the two rings can overlap on a top-down camera.
static func pick(cursor: Vector2, lamp_screen: Vector2, aim_screen: Vector2,
		radius_px: float) -> int:
	if hit_test(cursor, lamp_screen, radius_px):
		return LAMP
	if hit_test(cursor, aim_screen, radius_px):
		return AIM
	return NONE


static func handle_label(kind: int) -> String:
	match kind:
		LAMP:
			return "Lamp"
		AIM:
			return "Aim"
		_:
			return ""


# Snapshot for cancel. A drag that cannot be undone is a drag people are
# afraid to try, which is most of why the first version felt bad.
static func snapshot(offset_x: float, offset_z: float,
		aim_x: float, aim_z: float) -> Dictionary:
	return {
		"offset_x": offset_x, "offset_z": offset_z,
		"aim_x": aim_x, "aim_z": aim_z,
	}


static func snapshot_changed(before: Dictionary, offset_x: float,
		offset_z: float, aim_x: float, aim_z: float) -> bool:
	if before.is_empty():
		return false
	return absf(float(before.get("offset_x", 0.0)) - offset_x) > 0.001 \
		or absf(float(before.get("offset_z", 0.0)) - offset_z) > 0.001 \
		or absf(float(before.get("aim_x", 0.0)) - aim_x) > 0.001 \
		or absf(float(before.get("aim_z", 0.0)) - aim_z) > 0.001
