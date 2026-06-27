# Shared motor/physics helpers for hydrodynamic life (#1–18, #35–36, #49).
class_name Hydrodynamics
extends RefCounted

const PROFILES: Dictionary = {
	"subcarangiform": {
		"stroke_eff": 0.34, "drag": 0.16, "added_mass": 0.55,
		"turn_high": 0.72, "turn_low": 1.05, "thrust_mult": 1.0,
		"pec_row": 0.25, "buoyancy": 0.22, "cruise_bias": 1.0,
	},
	"anguilliform": {
		"stroke_eff": 0.42, "drag": 0.13, "added_mass": 0.48,
		"turn_high": 0.95, "turn_low": 1.35, "thrust_mult": 0.92,
		"pec_row": 0.12, "buoyancy": 0.18, "cruise_bias": 0.82,
	},
	"ostraciiform": {
		"stroke_eff": 0.22, "drag": 0.22, "added_mass": 0.72,
		"turn_high": 0.88, "turn_low": 1.15, "thrust_mult": 0.65,
		"pec_row": 0.95, "buoyancy": 0.38, "cruise_bias": 0.55,
	},
	"labriform": {
		"stroke_eff": 0.12, "drag": 0.19, "added_mass": 0.62,
		"turn_high": 1.05, "turn_low": 1.22, "thrust_mult": 0.55,
		"pec_row": 1.35, "buoyancy": 0.32, "cruise_bias": 0.48,
	},
	"thunniform": {
		"stroke_eff": 0.38, "drag": 0.11, "added_mass": 0.82,
		"turn_high": 0.48, "turn_low": 0.78, "thrust_mult": 1.18,
		"pec_row": 0.18, "buoyancy": 0.20, "cruise_bias": 1.35,
	},
	"shrimp": {
		"stroke_eff": 0.55, "drag": 0.28, "added_mass": 0.25,
		"turn_high": 1.1, "turn_low": 1.25, "thrust_mult": 1.0,
		"pec_row": 0.4, "buoyancy": 0.12, "cruise_bias": 0.9,
	},
	"snail": {"stroke_eff": 0.18, "drag": 0.45, "buoyancy": 0.05},
	"microfauna": {"stroke_eff": 0.0, "drag": 2.8, "buoyancy": 0.02},
	"fry": {"stroke_eff": 0.28, "drag": 1.6, "added_mass": 0.08, "buoyancy": 0.15},
}


static func profile_for_locomotion(locomotion_type: String, body_size: float) -> Dictionary:
	var base: Dictionary = PROFILES.get(locomotion_type, PROFILES["subcarangiform"]).duplicate()
	base["body_size"] = body_size
	base["reynolds"] = reynolds_scale(body_size)
	return base


static func profile_for_species(species_key: String, body_size: float) -> Dictionary:
	var sk: String = species_key.to_lower()
	if "shrimp" in sk or "amano" in sk or "cherry" in sk:
		return profile_for_locomotion("shrimp", body_size)
	if "eel" in sk or "loach" in sk or "kuhli" in sk:
		return profile_for_locomotion("anguilliform", body_size)
	if "puffer" in sk or "box" in sk:
		return profile_for_locomotion("ostraciiform", body_size)
	if "tang" in sk or "angel" in sk:
		return profile_for_locomotion("labriform", body_size)
	if "tuna" in sk:
		return profile_for_locomotion("thunniform", body_size)
	return profile_for_locomotion("subcarangiform", body_size)


static func reynolds_scale(body_size: float) -> float:
	return clampf(body_size / 0.35, 0.12, 1.45)


static func drag_coeff(body_size: float, profile: Dictionary) -> float:
	return float(profile.get("drag", 0.16)) * reynolds_scale(body_size)


static func turn_rate_scale(speed: float, max_speed: float, profile: Dictionary) -> float:
	var t: float = clampf(speed / maxf(max_speed, 0.12), 0.0, 1.0)
	return lerpf(float(profile.get("turn_low", 1.0)), float(profile.get("turn_high", 0.7)), t)


static func added_mass_turn_scale(speed: float, max_speed: float, profile: Dictionary) -> float:
	var mass: float = float(profile.get("added_mass", 0.55))
	var t: float = clampf(speed / maxf(max_speed, 0.12), 0.0, 1.0)
	return lerpf(1.0, 1.0 / (1.0 + mass * 0.85), t)


static func stroke_thrust(phase: float, profile: Dictionary, speed: float,
		target_spd: float, max_speed: float) -> float:
	var stroke: float = maxf(0.0, sin(phase))
	var demand: float = clampf((target_spd - speed) / maxf(max_speed * 0.35, 0.08), 0.12, 1.5)
	var cruise: float = clampf(speed / maxf(max_speed, 0.1), 0.0, 1.0)
	var trim: float = lerpf(demand, 0.35 + cruise * 0.25, float(profile.get("cruise_bias", 1.0)) * 0.15)
	return stroke * float(profile.get("stroke_eff", 0.3)) * trim \
		* float(profile.get("thrust_mult", 1.0))


static func pec_thrust(phase: float, profile: Dictionary, speed: float, target_spd: float) -> float:
	var row: float = float(profile.get("pec_row", 0.2))
	if row < 0.05:
		return 0.0
	var pec_stroke: float = absf(sin(phase * 2.2))
	var demand: float = clampf(target_spd - speed * 0.6, 0.0, 1.0)
	return pec_stroke * row * demand * 0.55


static func integrate_speed(speed: float, target_spd: float, stroke_thrust_val: float,
		drag_k: float, motor_accel: float, dt: float, coasting: bool) -> float:
	var motor: float = 0.0
	if target_spd > speed + 0.015:
		motor = motor_accel
	elif not coasting and target_spd + 0.04 < speed:
		motor = -motor_accel * 0.65
	var thrust: float = motor + stroke_thrust_val
	var drag: float = drag_k * speed * speed
	var next: float = speed + (thrust - drag) * dt
	return maxf(0.0, next)


static func flow_coupling(body_size: float) -> float:
	return clampf(0.22 + reynolds_scale(body_size) * 0.35, 0.15, 0.62)


static func upstream_effort(flow: Vector3, heading: Vector3) -> float:
	if flow.length_squared() < 1e-6:
		return 1.0
	var against: float = -flow.normalized().dot(heading)
	return 1.0 + clampf(against * flow.length() * 4.5, 0.0, 0.35)


static func buoyancy_step(y: float, hover_y: float, speed: float, target_spd: float,
		dt: float, bob_t: float, profile: Dictionary) -> Dictionary:
	var spring: float = float(profile.get("buoyancy", 0.2))
	var bob_t_next: float = bob_t + dt * 0.55
	var bob: float = sin(bob_t_next) * 0.012 * (1.0 - clampf(speed * 1.2, 0.0, 0.85))
	var sink: float = 0.0
	if target_spd < 0.08 and speed < 0.12:
		sink = -0.018 * dt
	var lift: float = (hover_y - y) * spring * dt + bob + sink
	return {"y_delta": lift, "bob_t": bob_t_next}


static func brake_pose_amount(speed: float, target_spd: float) -> float:
	if speed < 0.35 or target_spd > speed * 0.55:
		return 0.0
	return clampf((speed - target_spd) / maxf(speed, 0.1), 0.0, 1.0)


static func effort_wag_boost(speed: float, target_spd: float, max_speed: float) -> float:
	return clampf((target_spd - speed) / maxf(max_speed, 0.1), 0.0, 1.0) * 0.28


static func tail_recoil_yaw(phase: float, effort: float) -> float:
	return -sin(phase) * 0.07 * effort


static func station_keep_pec(phase: float, flow_strength: float, target_spd: float) -> float:
	if target_spd > 0.18 or flow_strength < 0.008:
		return 0.0
	return sin(phase * 3.1) * 0.35 * clampf(flow_strength * 18.0, 0.0, 1.0)


static func overshoot_bias(speed: float, target_spd: float, dist_to_goal: float) -> float:
	if dist_to_goal > 1.2 or target_spd < 0.05:
		return 0.0
	var overshoot: float = clampf(speed - target_spd, 0.0, 1.0)
	return overshoot * clampf(1.0 - dist_to_goal / 1.2, 0.0, 1.0) * 0.08


static func centripetal_bank(speed: float, yaw_rate: float) -> float:
	return clampf(speed * yaw_rate * 0.08, -0.35, 0.35)


static func use_full_physics(sim: Node, creature: Node3D) -> bool:
	if sim == null or not sim.has_method("is_creature_visible_to_camera"):
		return true
	return sim.is_creature_visible_to_camera(creature)
