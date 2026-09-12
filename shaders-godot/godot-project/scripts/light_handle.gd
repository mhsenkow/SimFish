extends RefCounted
class_name LightHandle

# Direct manipulation of the tank light: hover it, double-click to grab it,
# drag to move it, and the beam follows.
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
