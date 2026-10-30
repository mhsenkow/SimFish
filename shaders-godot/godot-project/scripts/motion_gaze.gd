class_name MotionGaze
extends RefCounted

# Where a creature is looking, and how its eyes and head get there
# (CREATURE_MOTION_700 #53). Gaze is the cheapest anticipation there is: the
# eyes move first, the head follows, then the body. A target carries a kind
# and a priority (threat > food > mate > rival > keeper > curiosity > idle);
# the highest live one wins. Between targets the eyes saccade: a fast jump
# (about 40 ms), a hold, and small drifts, on a seeded schedule so two fish
# never look around in step.
#
# step() returns local yaw/pitch offsets for the eyes and a head-lead yaw, in
# radians relative to the body's forward axis.

const PRIORITY: Dictionary = {
	&"threat": 6, &"food": 5, &"mate": 4, &"rival": 3, &"keeper": 2, &"curiosity": 1, &"idle": 0,
}
const EYE_YAW_MAX: float = 0.45
const EYE_PITCH_MAX: float = 0.25
const HEAD_LEAD_MAX: float = 0.15   # fish have no neck; more lead is body bend
const SACCADE_S: float = 0.04

var kind: StringName = &"idle"
var target: Vector3 = Vector3.ZERO
var has_target: bool = false
var _hold: float = 0.0
var _saccade_t: float = 0.0
var _saccade_from: Vector2 = Vector2.ZERO
var _saccade_to: Vector2 = Vector2.ZERO
var _eye: Vector2 = Vector2.ZERO
var _next_saccade: float = 0.0
var _head: MotionSpring = MotionSpring.new(2.5, 0.9, 0.0)
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value
	_next_saccade = _rng.randf_range(0.5, 2.5)


# Offer a target; it replaces the current one only if it is at least as
# important or the current one has expired.
func look_at_point(what: StringName, world_pos: Vector3, hold_s: float = 1.5) -> bool:
	var p_new: int = int(PRIORITY.get(what, 0))
	var p_cur: int = int(PRIORITY.get(kind, 0)) if has_target and _hold > 0.0 else -1
	if p_new < p_cur:
		return false
	kind = what
	target = world_pos
	has_target = true
	_hold = hold_s
	return true


func release() -> void:
	has_target = false
	kind = &"idle"


func eye_yaw() -> float:
	return _eye.x


func eye_pitch() -> float:
	return _eye.y


func head_yaw() -> float:
	return _head.y


# body: the creature's global transform (forward is -Z). rest_factor fades
# idle saccades while it swims (eyes stabilise during locomotion).
func step(dt: float, body: Transform3D, rest_factor: float = 1.0) -> void:
	if not (dt > 0.0):
		return
	_hold -= dt
	if has_target and _hold <= 0.0:
		release()
	var desired := Vector2.ZERO
	if has_target:
		var local: Vector3 = body.affine_inverse() * target
		var fwd: float = -local.z
		desired = Vector2(
			clampf(atan2(-local.x, maxf(fwd, 0.05)), -EYE_YAW_MAX, EYE_YAW_MAX),
			clampf(atan2(local.y, maxf(Vector2(local.x, local.z).length(), 0.05)),
				-EYE_PITCH_MAX, EYE_PITCH_MAX))
	_next_saccade -= dt * maxf(rest_factor, 0.25)
	var jump: bool = _next_saccade <= 0.0 or (has_target and desired.distance_to(_saccade_to) > 0.12)
	if jump:
		_next_saccade = _rng.randf_range(1.2, 3.6)
		var idle_offset := Vector2(_rng.randf_range(-0.25, 0.25), _rng.randf_range(-0.08, 0.08)) \
			* rest_factor
		_saccade_from = _eye
		_saccade_to = desired + (idle_offset * 0.3 if has_target else idle_offset)
		_saccade_t = SACCADE_S
	if _saccade_t > 0.0:
		_saccade_t = maxf(0.0, _saccade_t - dt)
		_eye = _saccade_from.lerp(_saccade_to, MotionEase.smooth(1.0 - _saccade_t / SACCADE_S))
	else:
		# Fixation with a slow drift back toward the target.
		_eye = _eye.lerp(_saccade_to, 1.0 - exp(-1.5 * dt))
	_head.step(dt, clampf(_eye.x * 0.4, -HEAD_LEAD_MAX, HEAD_LEAD_MAX))
