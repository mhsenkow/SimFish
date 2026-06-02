# Shared tank-boundary steering for small fauna (microfauna, worms) and as a
# single entry point for lateral / vertical repulsion math used across agents.
extends RefCounted
class_name FaunaBoundary


static func world_from_sim(sim: Node) -> Node:
	if sim == null:
		return null
	return sim.get_parent()


static func lateral_push(world: Node, gp: Vector3, margin: float,
		strength: float = 1.0, vel_hint: Vector3 = Vector3.ZERO) -> Vector3:
	if world == null or not world.has_method("tank_lateral_boundary_info"):
		return Vector3.ZERO
	var info: Dictionary = world.tank_lateral_boundary_info(gp, margin)
	if vel_hint.length_squared() > 0.01:
		var hz: Vector3 = Vector3(vel_hint.x, 0.0, vel_hint.z)
		if hz.length_squared() > 1e-6:
			hz = hz.normalized()
			var ahead: Vector3 = gp + hz * (margin * 1.8 + 0.28)
			var ahead_info: Dictionary = world.tank_lateral_boundary_info(ahead, margin)
			if float(ahead_info.get("clearance", 99.0)) < float(info.get("clearance", 99.0)):
				info = ahead_info
	var clearance: float = float(info.get("clearance", 99.0))
	var inward: Vector3 = info.get("inward", Vector3.ZERO)
	if inward.length_squared() < 1e-6:
		return Vector3.ZERO
	var repel_dist: float = margin * 2.1 + 0.28
	if clearance >= repel_dist:
		return Vector3.ZERO
	var t: float = 1.0 - clampf(clearance / repel_dist, 0.0, 1.0)
	return inward * t * t * strength


static func vertical_push(world: Node, gp: Vector3, margin: float,
		floor_band: float = 0.42, ceil_band: float = 0.38,
		strength: float = 1.0) -> Vector3:
	if world == null or not world.has_method("tank_vertical_boundary_info"):
		return Vector3.ZERO
	var vert: Dictionary = world.tank_vertical_boundary_info(
		gp, margin, floor_band, ceil_band)
	if not bool(vert.get("active", false)):
		return Vector3.ZERO
	var v_clear: float = float(vert.get("clearance", 99.0))
	var v_in: Vector3 = vert.get("inward", Vector3.ZERO)
	if v_in.length_squared() < 1e-6 or v_clear >= ceil_band:
		return Vector3.ZERO
	var vt: float = 1.0 - clampf(v_clear / maxf(ceil_band, floor_band), 0.0, 1.0)
	return v_in * vt * vt * strength


static func constrain_velocity(world: Node, gp: Vector3, vel: Vector3, margin: float,
		floor_band: float = 0.42, ceil_band: float = 0.38) -> Vector3:
	if vel.length_squared() < 1e-8:
		return vel
	var push: Vector3 = lateral_push(world, gp, margin, 0.85, vel)
	if push.length_squared() > 1e-6:
		var h_vel: Vector3 = Vector3(vel.x, 0.0, vel.z)
		var h_push: Vector3 = Vector3(push.x, 0.0, push.z)
		if h_vel.length_squared() > 1e-8 and h_push.length_squared() > 1e-8:
			var out: Vector3 = -h_push.normalized()
			var out_spd: float = h_vel.dot(out)
			if out_spd > 0.0:
				h_vel -= out * out_spd
		vel = Vector3(h_vel.x, vel.y, h_vel.z)
	var v_push: Vector3 = vertical_push(world, gp, margin, floor_band, ceil_band, 0.75)
	if v_push.length_squared() > 1e-6:
		var outward_v: Vector3 = -v_push.normalized()
		var out_v: float = vel.dot(outward_v)
		if out_v > 0.0:
			vel -= outward_v * out_v
	return vel


static func clamp_position(world: Node, gp: Vector3, margin: float,
		body_radius: float = 0.0) -> Vector3:
	if world == null or not world.has_method("clamp_xyz_in_tank"):
		return gp
	return world.clamp_xyz_in_tank(gp, margin, body_radius)
