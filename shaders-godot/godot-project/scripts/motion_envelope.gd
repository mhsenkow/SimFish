class_name MotionEnvelope
extends RefCounted

# Wind-up → action → follow-through → settle, for every discrete action
# (CREATURE_MOTION_700 #52). A dart, strike, gulp, flip, peck or lunge used to
# be a bare timer and a speed multiplier that started at full speed. This
# gives each action the anticipation and follow-through the principles ask for,
# with per-species durations from the exposure sheets (#106).
#
# value() is the canonical drive curve: a small negative pull in the wind-up
# (the coil), a fast rise to 1 in the action, a drag-shaped fall through
# follow-through, and a gentle return to 0 in settle.

enum Stage { IDLE, WINDUP, ACTION, FOLLOW, SETTLE }

var windup_s: float = 0.08
var action_s: float = 0.10
var follow_s: float = 0.35
var settle_s: float = 0.25
var windup_depth: float = 0.25   # how far value() dips below 0 while coiling

var stage: int = Stage.IDLE
var _t: float = 0.0


func _init(windup: float = 0.08, action: float = 0.10, follow: float = 0.35,
		settle: float = 0.25, depth: float = 0.25) -> void:
	windup_s = maxf(windup, 0.0)
	action_s = maxf(action, 0.001)
	follow_s = maxf(follow, 0.0)
	settle_s = maxf(settle, 0.0)
	windup_depth = depth


# Durations in frames at a frame rate, as written on an exposure sheet.
static func from_frames(windup_f: int, action_f: int, follow_f: int, settle_f: int,
		fps: float = 60.0, depth: float = 0.25) -> MotionEnvelope:
	var s: float = 1.0 / maxf(fps, 1.0)
	return MotionEnvelope.new(windup_f * s, action_f * s, follow_f * s, settle_f * s, depth)


func trigger(skip_windup: bool = false) -> void:
	_t = 0.0
	stage = Stage.ACTION if skip_windup or windup_s <= 0.0 else Stage.WINDUP


func active() -> bool:
	return stage != Stage.IDLE


func stage_duration(s: int) -> float:
	match s:
		Stage.WINDUP: return windup_s
		Stage.ACTION: return action_s
		Stage.FOLLOW: return follow_s
		Stage.SETTLE: return settle_s
	return 0.0


# 0..1 progress through the current stage.
func progress() -> float:
	var d: float = stage_duration(stage)
	return clampf(_t / d, 0.0, 1.0) if d > 0.0 else 1.0


func step(dt: float) -> int:
	if stage == Stage.IDLE or not (dt > 0.0):
		return stage
	_t += dt
	while stage != Stage.IDLE and _t >= stage_duration(stage):
		_t -= stage_duration(stage)
		# Zero-length stages fall straight through on the same step.
		stage = stage + 1 if stage < Stage.SETTLE else Stage.IDLE
	if stage == Stage.IDLE:
		_t = 0.0
	return stage


func value() -> float:
	var p: float = progress()
	match stage:
		Stage.WINDUP:
			return -windup_depth * MotionEase.sine_in_out(p)
		Stage.ACTION:
			return lerpf(-windup_depth, 1.0, MotionEase.smooth(p)) if windup_s > 0.0 \
				else MotionEase.smooth(p)
		Stage.FOLLOW:
			return lerpf(1.0, 0.25, MotionEase.expo_out(p, 3.0))
		Stage.SETTLE:
			return lerpf(0.25, 0.0, MotionEase.sine_in_out(p))
	return 0.0


# Enter/exit thresholds plus a minimum dwell, so a value hovering near one
# threshold can't flicker a pose on and off (#76).
class Hysteresis:
	extends RefCounted
	var enter_at: float = 0.6
	var exit_at: float = 0.4
	var min_dwell_s: float = 0.5
	var on: bool = false
	var _dwell: float = 0.0

	func _init(enter_threshold: float = 0.6, exit_threshold: float = 0.4, dwell: float = 0.5) -> void:
		enter_at = enter_threshold
		exit_at = exit_threshold
		min_dwell_s = dwell

	func step(dt: float, x: float) -> bool:
		_dwell += maxf(dt, 0.0)
		if _dwell < min_dwell_s:
			return on
		if not on and x >= enter_at:
			on = true
			_dwell = 0.0
		elif on and x <= exit_at:
			on = false
			_dwell = 0.0
		return on
