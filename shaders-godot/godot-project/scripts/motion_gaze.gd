class_name MotionGaze
extends RefCounted

# Where a creature is looking, and how its eyes and head get there
# (CREATURE_MOTION_700 #53, #298–#301). Gaze is the cheapest anticipation:
# the eyes move first, the head follows, then the body. A target carries a
# kind and a priority (threat > food > mate > rival > keeper > curiosity >
# idle); the highest live one wins. Each eye saccades on its own schedule
# (#298, #300). Feeding converges both eyes inward (#299).
#
# step() writes per-eye yaw/pitch and a head-lead yaw, in radians relative
# to the body's forward axis.

const PRIORITY: Dictionary = {
	&"threat": 6, &"food": 5, &"mate": 4, &"rival": 3, &"keeper": 2, &"curiosity": 1, &"idle": 0,
}
const EYE_YAW_MAX: float = 0.45
const EYE_PITCH_MAX: float = 0.25
const HEAD_LEAD_MAX: float = 0.15   # fish have no neck; more lead is body bend
const SACCADE_S: float = 0.04
const CONVERGE_MAX: float = 0.18    # inward yaw at full converge (#299)

var kind: StringName = &"idle"
var target: Vector3 = Vector3.ZERO
var has_target: bool = false
var converge: float = 0.0           # 0..1, binocular fixation
var _hold: float = 0.0
var _eye_l: Vector2 = Vector2.ZERO
var _eye_r: Vector2 = Vector2.ZERO
var _saccade_t_l: float = 0.0
var _saccade_t_r: float = 0.0
var _saccade_from_l: Vector2 = Vector2.ZERO
var _saccade_from_r: Vector2 = Vector2.ZERO
var _saccade_to_l: Vector2 = Vector2.ZERO
var _saccade_to_r: Vector2 = Vector2.ZERO
var _next_saccade_l: float = 0.0
var _next_saccade_r: float = 0.0
var _head: MotionSpring = MotionSpring.new(2.5, 0.9, 0.0)
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value
	_next_saccade_l = _rng.randf_range(0.4, 2.0)
	_next_saccade_r = _rng.randf_range(0.8, 2.8)


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


# Mean yaw — kept for callers that don't need per-eye independence.
func eye_yaw() -> float:
	return (_eye_l.x + _eye_r.x) * 0.5


func eye_pitch() -> float:
	return (_eye_l.y + _eye_r.y) * 0.5


func left_eye_yaw() -> float:
	return _eye_l.x


func left_eye_pitch() -> float:
	return _eye_l.y


func right_eye_yaw() -> float:
	return _eye_r.x


func right_eye_pitch() -> float:
	return _eye_r.y


func head_yaw() -> float:
	return _head.y


# body: the creature's global transform (forward is -Z). rest_factor fades
# idle saccades while it swims (eyes stabilise during locomotion, #301).
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
	# Converge: left looks right (negative yaw), right looks left (#299).
	var cin: float = clampf(converge, 0.0, 1.0) * CONVERGE_MAX
	var desired_l := Vector2(desired.x - cin, desired.y)
	var desired_r := Vector2(desired.x + cin, desired.y)
	_step_eye(dt, rest_factor, true, desired_l, has_target)
	_step_eye(dt, rest_factor, false, desired_r, has_target)
	_head.step(dt, clampf(eye_yaw() * 0.4, -HEAD_LEAD_MAX, HEAD_LEAD_MAX))


func _step_eye(dt: float, rest_factor: float, is_left: bool, desired: Vector2, tracking: bool) -> void:
	# 2–4 saccades per 10 s at rest (#300); swimming slows the schedule.
	var pace: float = maxf(rest_factor, 0.2)
	if is_left:
		_next_saccade_l -= dt * pace
	else:
		_next_saccade_r -= dt * pace
	var next_t: float = _next_saccade_l if is_left else _next_saccade_r
	var to: Vector2 = _saccade_to_l if is_left else _saccade_to_r
	var jump: bool = next_t <= 0.0 or (tracking and desired.distance_to(to) > 0.12)
	if jump:
		var gap: float = _rng.randf_range(2.5, 5.0) if rest_factor > 0.45 else _rng.randf_range(4.0, 8.0)
		if is_left:
			_next_saccade_l = gap
		else:
			_next_saccade_r = gap
		var idle_offset := Vector2(_rng.randf_range(-0.28, 0.28), _rng.randf_range(-0.09, 0.09)) \
			* rest_factor
		if is_left:
			_saccade_from_l = _eye_l
			_saccade_to_l = desired + (idle_offset * 0.25 if tracking else idle_offset)
			_saccade_t_l = SACCADE_S
		else:
			_saccade_from_r = _eye_r
			_saccade_to_r = desired + (idle_offset * 0.25 if tracking else idle_offset)
			_saccade_t_r = SACCADE_S
	# #269: fast attack, brief settle, then hold — not a plain lerp.
	if is_left:
		if _saccade_t_l > 0.0:
			_saccade_t_l = maxf(0.0, _saccade_t_l - dt)
			var u_l: float = 1.0 - _saccade_t_l / SACCADE_S
			_eye_l = _saccade_from_l.lerp(_saccade_to_l, MotionEase.burst(u_l, 0.35, 5.0))
		else:
			_eye_l = _saccade_to_l
	else:
		if _saccade_t_r > 0.0:
			_saccade_t_r = maxf(0.0, _saccade_t_r - dt)
			var u_r: float = 1.0 - _saccade_t_r / SACCADE_S
			_eye_r = _saccade_from_r.lerp(_saccade_to_r, MotionEase.burst(u_r, 0.35, 5.0))
		else:
			_eye_r = _saccade_to_r
