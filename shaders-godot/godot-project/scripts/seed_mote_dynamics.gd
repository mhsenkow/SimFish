extends RefCounted

const MAX_LIFETIME_S: float = 8.0
const SETTLE_SPEED: float = 0.42
const MAX_HORIZONTAL_SPEED: float = 0.9


static func make_state(start: Vector3, genome: Dictionary, dormancy: Dictionary,
		lifetime_s: float = 5.0, surface_only: bool = false) -> Dictionary:
	return {
		"position": start,
		"velocity": Vector3.ZERO,
		"genome": genome.duplicate(true),
		"dormancy": dormancy.duplicate(true),
		"life": clampf(lifetime_s, 0.5, MAX_LIFETIME_S),
		"surface_only": surface_only,
	}


static func integrate(state: Dictionary, dt: float, flow: Vector3,
		floor_y: float, water_y: float, clamp_xz: Callable) -> bool:
	var step: float = clampf(dt, 0.0, 0.25)
	state.life = maxf(0.0, float(state.get("life", 0.0)) - step)
	var pos: Vector3 = state.get("position", Vector3.ZERO)
	var vel: Vector3 = state.get("velocity", Vector3.ZERO)
	var surface_only: bool = bool(state.get("surface_only", false))
	var target_y: float = water_y - 0.04 if surface_only else floor_y
	var horizontal := Vector3(flow.x, 0.0, flow.z).limit_length(MAX_HORIZONTAL_SPEED)
	vel.x = move_toward(vel.x, horizontal.x, step * 1.8)
	vel.z = move_toward(vel.z, horizontal.z, step * 1.8)
	vel.y = move_toward(vel.y, -SETTLE_SPEED if not surface_only else 0.0, step * 0.5)
	pos += vel * step
	if surface_only:
		pos.y = target_y
	else:
		pos.y = maxf(target_y, pos.y)
	var fitted: Vector2 = clamp_xz.call(pos.x, pos.z)
	pos.x = fitted.x
	pos.z = fitted.y
	state.position = pos
	state.velocity = vel
	return float(state.life) <= 0.0 or (not surface_only and pos.y <= floor_y + 0.01)
