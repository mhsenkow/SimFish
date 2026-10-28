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


# Preserve yaw while reducing the pitch component of a combined steering axis.
static func steering_axis_gain(axis: Vector3) -> float:
	return sqrt(0.25 + 0.75 * axis.y * axis.y)


static func steering_axis(axis: Vector3) -> Vector3:
	var result := Vector3(axis.x * 0.5, axis.y, axis.z * 0.5)
	return result.normalized() if result.length_squared() > 1e-8 else Vector3.UP


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
		push += d * ((FISH_PERSONAL_SPACE - sqrt(d2)) / maxf(sqrt(d2), 0.001)) * 1.9
	for p in plants:
		if not is_instance_valid(p):
			continue
		var to_p: Vector3 = f.position - p._world_pos
		to_p.y *= 0.55
		var d2p: float = to_p.length_squared()
		if d2p < 1e-6 or d2p >= plant_r2:
			continue
		push += to_p * ((PLANT_CLEARANCE - sqrt(d2p)) / maxf(sqrt(d2p), 0.001)) * 1.3
	return push


# Push away from driftwood / stones (hardscape_root children) within radius.
# Hardscape positions, rebuilt once per frame. Every fish used to walk the
# hardscape children (get_children() allocation + global_position per node)
# on every behaviour tick - ~2 ms of a full tank's tick.
static var _hardscape_frame: int = -1
static var _hardscape_root_id: int = 0
static var _hardscape_pos: PackedVector3Array = PackedVector3Array()


static func _hardscape_positions(root: Node3D) -> PackedVector3Array:
	var frame: int = Engine.get_process_frames()
	if frame == _hardscape_frame and root.get_instance_id() == _hardscape_root_id:
		return _hardscape_pos
	_hardscape_frame = frame
	_hardscape_root_id = root.get_instance_id()
	_hardscape_pos.clear()
	for h in root.get_children():
		if is_instance_valid(h) and h is Node3D:
			_hardscape_pos.append((h as Node3D).global_position)
	return _hardscape_pos


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
	for hp in _hardscape_positions(root as Node3D):
		var d: Vector3 = f.position - hp
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


# Holistic #083 — yaw authority from body size and current speed.
# Large cruisers turn in broader arcs; crawl speed further softens the rate
# (FishLifeBouts.inertial_turn still kills the spin-in-place floor).
static func body_speed_turn_scale(body_m: float, speed: float, max_speed: float) -> float:
	var body: float = clampf(0.55 / maxf(body_m, 0.28), 0.38, 1.35)
	var spd: float = clampf(speed / maxf(max_speed, 0.12), 0.0, 1.0)
	var crawl: float = lerpf(0.55, 1.0, clampf(spd / 0.12, 0.0, 1.0))
	return body * crawl
