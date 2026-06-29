class_name FishLocomotion
extends RefCounted

# ENGINEERING_EXCELLENCE #1 / OPUS_HANDOFF 0C — locomotion carve out of fish.gd
# (first slice: boundary + collision-avoidance steering). Static funcs take the
# Fish as `f`; fish.gd keeps thin one-line delegates so call sites are unchanged
# and behavior is identical (bodies moved verbatim). See docs/ARCHITECTURE.md
# §fish.gd carve. Later slices: _motion_substep (integration), _boids (schooling),
# velocity constraints.
#
# These return a steering push (Vector3) added to `desired` in Fish.tick()'s
# Tier-0 / Tier-0.1; they read Fish + neighbour/world state but (apart from a
# seeded RNG read for coincident hardscape) do not mutate fish state.


# Lateral + vertical tank-wall repulsion. Skips the inward shove when the fish is
# already cruising along the glass tangent (only pushes when heading into a wall).
static func wall_avoid(f: Fish, _b: AABB) -> Vector3:
	var push := Vector3.ZERO
	var hint: Vector3 = f.heading if f.heading.length_squared() > 1e-6 else f.target_velocity
	var lat: Dictionary = f._lateral_boundary_context(f.global_position, -1.0, hint)
	var clearance: float = float(lat.get("clearance", 99.0))
	var inward: Vector3 = lat.get("inward", Vector3.ZERO)
	var body_m: float = float(lat.get("body_m", f._body_tank_margin()))
	if inward.length_squared() > 1e-6:
		var repel_dist: float = body_m * 2.5 + 0.45
		if clearance < repel_dist:
			var t: float = 1.0 - clampf(clearance / repel_dist, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			var steer_dir: Vector3 = f.heading
			if steer_dir.length_squared() < 1e-6 and f.target_velocity.length_squared() > 1e-6:
				steer_dir = f.target_velocity.normalized()
			var outward: Vector3 = -inward
			var into_wall: float = maxf(0.0, steer_dir.dot(outward))
			# Fish already cruising along the glass tangent — skip inward shove.
			if into_wall >= 0.12:
				var strength: float = t * (0.55 + into_wall * 0.65)
				push += inward * strength * maxf(f.max_speed, 0.45)
	var vert: Dictionary = f._vertical_boundary_context(f.global_position)
	if bool(vert.get("active", false)):
		var v_clear: float = float(vert.get("clearance", 99.0))
		var v_in: Vector3 = vert.get("inward", Vector3.ZERO)
		if v_in.length_squared() > 1e-6 and v_clear < 0.42:
			var vt: float = 1.0 - clampf(v_clear / 0.42, 0.0, 1.0)
			push += v_in * vt * vt * maxf(f.max_speed * 0.55, 0.35)
	return push


# Soft anti-intersection from nearby fish (personal space) and plants, with a
# vertical de-stacking weave so same-layer fish slide past instead of clipping.
static func local_clearance_push(f: Fish, neighbors: Array, plants: Array) -> Vector3:
	var push := Vector3.ZERO
	const FISH_PERSONAL_SPACE: float = 0.26
	const PLANT_CLEARANCE: float = 0.20
	var fish_r2: float = FISH_PERSONAL_SPACE * FISH_PERSONAL_SPACE
	var plant_r2: float = PLANT_CLEARANCE * PLANT_CLEARANCE
	for n in neighbors:
		if not (n is Fish):
			continue
		var nf: Fish = n
		var d: Vector3 = f.position - nf.position
		d.y *= 0.42 if f.mouth_orientation == 0 else 0.55
		var d2: float = d.length_squared()
		if d2 < 1e-6 or d2 >= fish_r2:
			continue
		var rel_sp: float = clampf((nf.speed + f.speed) * 0.5 / maxf(f.max_speed, 0.2), 0.0, 1.0)
		var weave_y: float = TopdownMotion.collision_weave_y(f.position.y - nf.position.y, rel_sp)
		if absf(weave_y) > 0.01:
			push.y += weave_y
		push += d.normalized() * (FISH_PERSONAL_SPACE - sqrt(d2)) * 1.9
	for p in plants:
		if not is_instance_valid(p):
			continue
		var to_p: Vector3 = f.position - p._world_pos
		to_p.y *= 0.55
		var d2p: float = to_p.length_squared()
		if d2p < 1e-6 or d2p >= plant_r2:
			continue
		push += to_p.normalized() * (PLANT_CLEARANCE - sqrt(d2p)) * 1.3
	return push


# Push away from driftwood / stones (hardscape_root children) within radius.
static func hardscape_clearance_push(f: Fish) -> Vector3:
	if f.sim == null:
		return Vector3.ZERO
	var root: Variant = f.sim.get("hardscape_root")
	if root == null or not (root is Node3D):
		return Vector3.ZERO
	const CLEAR_R: float = 0.26
	var clear_r2: float = CLEAR_R * CLEAR_R
	var push := Vector3.ZERO
	var count: int = 0
	for h in (root as Node3D).get_children():
		if not is_instance_valid(h):
			continue
		var d: Vector3 = f.position - h.global_position
		d.y *= 0.45
		var d2: float = d.length_squared()
		if d2 >= clear_r2:
			continue
		if d2 < 1e-6:
			d = Vector3(f._behavior_rng().randf_range(-1, 1), 0.0, f._behavior_rng().randf_range(-1, 1))
			if d.length_squared() < 1e-6:
				d = Vector3(1.0, 0.0, 0.0)
			d2 = maxf(d.length_squared(), 1e-6)
		push += d.normalized() * (CLEAR_R - sqrt(d2)) * 1.4
		count += 1
		if count >= 10:
			break
	return push
