class_name CameraController
extends RefCounted

# ENGINEERING_EXCELLENCE #2 / OPUS_HANDOFF 0B — orbit/pan/dolly/zoom/deadzone
# camera math extracted from main.gd as pure static functions (the TopdownMotion
# pattern). main.gd keeps the camera STATE (target/radius/yaw/pitch), the
# Camera3D node ref, and the node-dependent steps (MusicContext hero-bias,
# pixel-snap, projection switches); it delegates the pure math here. Behavior is
# identical — values and formulas moved verbatim from main.gd. See
# docs/ARCHITECTURE.md §main.gd carve.
#
# Canonical camera tuning constants live here now; main.gd re-exports them
# (const X := CameraController.X) so its other references — persistence clamps,
# camera-state restore — stay pointed at a single source of truth with no value
# drift.

const SENSITIVITY: float = 0.006            # radians per pixel, orbit drag
const DOLLY_MOUSE_SENSITIVITY: float = 0.012  # log-ish dolly per pixel
const PAN_MOUSE_SENSITIVITY: float = 0.012  # world units per pixel at radius=1
const ZOOM_FACTOR: float = 1.12
const MIN_RADIUS: float = 8.0
const MAX_RADIUS: float = 40.0
const MIN_PITCH: float = -1.45
const MAX_PITCH: float = 1.45
const DRAG_DEADZONE_PX: float = 8.0
const ORTHO_MIN_SIZE: float = 2.0
const ORTHO_MAX_SIZE: float = 80.0

# Target clamp box — the single convergence box (see eye/clamp_target).
const TARGET_MIN := Vector3(-20.0, -2.0, -20.0)
const TARGET_MAX := Vector3(20.0, 12.0, 20.0)


# Deadzone gate: orbit/pan/dolly navigation only commits once the cursor has
# travelled DRAG_DEADZONE_PX since mousedown. A release before that is a tap
# (feed / pick), not a drag — this is the rule the smoke pins.
static func drag_committed(drag_total_px: float) -> bool:
	return drag_total_px >= DRAG_DEADZONE_PX


# Inverse of drag_committed: a release under the deadzone is a tap, not an orbit.
static func is_tap(drag_total_px: float) -> bool:
	return drag_total_px < DRAG_DEADZONE_PX


# Orbit: yaw/pitch follow mouse delta; pitch clamped, yaw free.
# Returns Vector2(yaw, pitch).
static func orbit(yaw: float, pitch: float, delta: Vector2) -> Vector2:
	var ny: float = yaw - delta.x * SENSITIVITY
	var np: float = clampf(pitch - delta.y * SENSITIVITY, MIN_PITCH, MAX_PITCH)
	return Vector2(ny, np)


# Dolly: radius scales with vertical drag, clamped to the orbit shell.
static func dolly(radius: float, delta_y: float) -> float:
	return clampf(radius * (1.0 + delta_y * DOLLY_MOUSE_SENSITIVITY),
			MIN_RADIUS, MAX_RADIUS)


# Wheel/pinch zoom — perspective (radius) variant.
static func zoom_radius(radius: float, factor: float) -> float:
	return clampf(radius * factor, MIN_RADIUS, MAX_RADIUS)


# Wheel/pinch zoom — orthographic (camera.size) variant.
static func zoom_ortho(size: float, factor: float) -> float:
	return clampf(size * factor, ORTHO_MIN_SIZE, ORTHO_MAX_SIZE)


# Pan: slide target perpendicular to the view using the camera basis right/up.
# Drag right pushes the scene right (target moves left), matching Figma/PS.
static func pan_target(target: Vector3, delta: Vector2, cam_right: Vector3,
		cam_up: Vector3, radius: float) -> Vector3:
	var pan_sc: float = PAN_MOUSE_SENSITIVITY * radius
	var t: Vector3 = target
	t -= cam_right * (delta.x * pan_sc)
	t += cam_up * (delta.y * pan_sc)
	return t


# Auto-orbit: gentle yaw drift per second (speed is a runtime var in main).
static func auto_orbit_yaw(yaw: float, speed: float, dt: float) -> float:
	return yaw + speed * dt


# Target clamp: the single convergence box so no pan/WASD/follow delta can push
# the target through the camera (breaking look_at) or to ±∞.
static func clamp_target(target: Vector3) -> Vector3:
	return Vector3(
		clampf(target.x, TARGET_MIN.x, TARGET_MAX.x),
		clampf(target.y, TARGET_MIN.y, TARGET_MAX.y),
		clampf(target.z, TARGET_MIN.z, TARGET_MAX.z))


# Eye position from spherical orbit coords. +pitch puts the eye above the
# target (y = sin(pitch)); yaw rotates around Y.
static func eye_position(target: Vector3, yaw: float, pitch: float,
		radius: float) -> Vector3:
	var x: float = cos(pitch) * sin(yaw)
	var y: float = sin(pitch)
	var z: float = cos(pitch) * cos(yaw)
	return target + Vector3(x, y, z) * radius
