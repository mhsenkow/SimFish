class_name MotionField
extends RefCounted

# LIVING_MOTION §J #91 — one motion authority for waves, schools, and flow hooks.

const _MotionSchoolScript = preload("res://scripts/motion_school.gd")
const _MotionWaveScript = preload("res://scripts/motion_wave.gd")

static var _threat_origin: Vector3 = Vector3.ZERO
static var _threat_until: float = 0.0


static func sync_tuning(cfg: Node) -> void:
	MindBoidsBuffer.sync_tuning(cfg)
	_MotionWaveScript.sync_tuning(cfg)


static func reset_for_test() -> void:
	_MotionWaveScript.reset_for_test()
	_MotionSchoolScript.reset_for_test()
	_threat_origin = Vector3.ZERO
	_threat_until = 0.0


static func tick(fish_arr: Array, dt: float, world: Node = null) -> void:
	_MotionWaveScript.tick(fish_arr, dt)
	_MotionSchoolScript.tick(fish_arr, dt)
	_threat_until = maxf(0.0, _threat_until - dt)
	if world != null and world.has_method("tick_flow_convection"):
		world.tick_flow_convection(dt)


static func sample_flow(world: Node, pos: Vector3) -> Vector3:
	if world == null or not world.has_method("sample_flow"):
		return Vector3.ZERO
	return world.sample_flow(pos)


static func inject_startle(fish_arr: Array, origin: Vector3, salience: float = 1.0,
		turn_away: Vector3 = Vector3.ZERO, freeze_first: bool = false) -> void:
	var amt: float = clampf(0.25 + salience * 0.75, 0.0, 1.0)
	if freeze_first and salience > 0.45:
		for f_v in fish_arr:
			if not is_instance_valid(f_v) or not _MotionWaveScript.uses_wave(f_v):
				continue
			var p: Vector3 = f_v.position as Vector3
			if Vector2(p.x - origin.x, p.z - origin.z).length() < 6.0 + salience * 4.0:
				f_v.motion_freeze_t = lerpf(0.12, 0.38, salience)
	_MotionWaveScript.inject_at(fish_arr, origin, amt, turn_away, salience)
	_threat_origin = origin
	_threat_until = lerpf(2.5, 6.0, salience)


static func inject_feeding(fish_arr: Array, origin: Vector3, strength: float = 0.7) -> void:
	var target: Node = _MotionWaveScript.inject_at(fish_arr, origin, strength * 0.35)
	if target == null:
		return
	var pull: Vector3 = origin - (target.position as Vector3)
	pull.y *= 0.15
	if pull.length_squared() > 1e-4:
		target.motion_turn_intent = pull.normalized() * strength


static func inject_calm(fish_arr: Array, origin: Vector3, amount: float = 0.35) -> void:
	_MotionWaveScript.inject_calm(fish_arr, origin, amount)


static func inject_shadow(fish_arr: Array, origin: Vector3, extent: float = 1.0) -> void:
	var away: Vector3 = Vector3(0.0, -0.85, 0.0)
	inject_startle(fish_arr, origin, clampf(extent, 0.5, 1.0), away, true)


static func threat_avoid_steer(f: Node, effective_max: float) -> Vector3:
	if f == null or _threat_until <= 0.0:
		return Vector3.ZERO
	if not _MotionWaveScript.uses_wave(f):
		return Vector3.ZERO
	var away: Vector3 = (f.position as Vector3) - _threat_origin
	away.y = 0.0
	if away.length_squared() < 0.12:
		return Vector3.ZERO
	var w: float = clampf(_threat_until / 4.0, 0.0, 1.0)
	return away.normalized() * effective_max * w * 0.35


static func tick_music_sweep(fish_arr: Array, sweep: float, beat_phase: float) -> void:
	_MotionWaveScript.tick_music_sweep(fish_arr, sweep, beat_phase)


static func deposit_feeding_burst(world: Node, origin: Vector3, strength: float = 0.18) -> void:
	if world == null or not world.has_method("deposit_flow_burst"):
		return
	world.deposit_flow_burst(origin, Vector3(0.0, 0.0, 0.35), strength)
