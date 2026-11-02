extends SceneTree

# CREATURE_MOTION_700 Phase 0, snail section (#25 #26 #27 #28 #39) plus the
# bristle-worm kick (#34).
#
# Drives the real snail.gd, on a body built by the real world.gd builder,
# inside a stub box tank. Each block pins a bug that read as plausible:
#   #25 the body is built head-first on +X but was aimed -Z, so every snail
#       slid along sideways;
#   #26 every surface change snapped the pose in one frame;
#   #27 letting go of the surface film flipped the normal without moving the
#       anchor plane, and the next reclamp put the snail under the floor;
#   #28 the whole node squashed, shell included, and a clamp went 0.35 tall in
#       one frame;
#   #39 eye stalks went in, and came back out, in one frame.
# Also pins that world.gd binds the body after building it: every spawn path
# adds the snail to the tree first, so _ready() never found the eye stalks.

const SnailScript := preload("res://scripts/snail.gd")
const DT: float = 1.0 / 60.0


class TankSim extends Node:
	var time_scale: float = 1.0
	var fish: Array = []
	var waste: Array = []
	var algae: Array = []
	var plants: Array = []
	var snail_predator_count: int = 0
	var water_chemistry: Variant = null
	var substrate: Variant = null


# Box tank: x in [-4, 4], z in [-3, 3], substrate at 1.6, water at 6.5.
class BoxTank extends Node3D:
	var SUBSTRATE_DEPTH: float = 1.6
	var WATER_HEIGHT: float = 6.5
	var TANK_SHAPE: String = "box"
	var half_x: float = 4.0
	var half_z: float = 3.0


	func clamp_xyz_in_tank(p: Vector3, margin: float = 0.25,
			body_radius: float = 0.0) -> Vector3:
		var m: float = margin + maxf(0.0, body_radius)
		return Vector3(clampf(p.x, -half_x + m, half_x - m),
			clampf(p.y, SUBSTRATE_DEPTH, WATER_HEIGHT - m),
			clampf(p.z, -half_z + m, half_z - m))


	func is_inside_tank_volume(x: float, y: float, z: float, margin: float = 0.0) -> bool:
		return absf(x) <= half_x - margin and absf(z) <= half_z - margin \
			and y >= SUBSTRATE_DEPTH - 0.001 and y <= WATER_HEIGHT


	func tank_lateral_boundary_info(p: Vector3, margin: float = 0.25) -> Dictionary:
		var walls: Array = [
			[Vector3.RIGHT, p.x + half_x], [Vector3.LEFT, half_x - p.x],
			[Vector3.BACK, p.z + half_z], [Vector3.FORWARD, half_z - p.z]]
		var best: Array = walls[0]
		for w in walls:
			if float(w[1]) < float(best[1]):
				best = w
		return {"inward": best[0], "clearance": float(best[1]) - margin}


var _tank: BoxTank = null
var _snails: Node3D = null
var _builder: Node = null


func _initialize() -> void:
	await process_frame
	seed(20261029)
	var t := TestSupport.Suite.new("snail_motion")
	_tank = BoxTank.new()
	root.add_child(_tank)
	var sim := TankSim.new()
	sim.name = "SimDriver"
	_tank.add_child(sim)
	_snails = Node3D.new()
	_snails.name = "Snails"
	_tank.add_child(_snails)
	# The real builder; never added to the tree, so it builds no tank. Loaded
	# at runtime: world.gd names autoloads that a preload would compile ahead of.
	var world_script: GDScript = load("res://scripts/world.gd")
	_builder = world_script.new()

	_test_binding(t)
	_test_head_leads(t)
	_test_surface_blend(t)
	_test_film_sink(t)
	_test_clamp_tuck(t)
	_test_eye_stalks(t)
	_test_bristle_kick(t)

	_builder.free()
	quit(t.finish())


# A snail spawned the way world.gd does it: configured, added, THEN built.
func _spawn(pos: Vector3, wall_n: Vector3, facing: Vector2, shape: String = "turbo",
		with_operculum: bool = false) -> SnailScript:
	var sn: SnailScript = SnailScript.new()
	sn.position = pos
	sn.wall_normal = wall_n
	sn.shell_shape = shape
	sn.operculum = with_operculum
	_snails.add_child(sn)
	_builder.call("_build_snail_body", sn)
	sn.set_process(false)
	sn._direction = facing.normalized()
	sn._facing = facing.normalized()
	sn._t_until_turn = 999.0
	sn._paused = false
	sn._eye_retract_timer = 999.0
	sn._crawl_speed_smoothed = SnailScript.SPEED
	sn._sync_initial_orientation(false)
	return sn


func _run(sn: SnailScript, frames: int) -> void:
	for _i in frames:
		sn._process(DT)


func _in_plane(v: Vector3, n: Vector3) -> Vector3:
	return v - n * v.dot(n)


func _test_binding(t: TestSupport.Suite) -> void:
	var sn: SnailScript = _spawn(Vector3(0.0, 1.7, 0.0), Vector3.UP, Vector2.RIGHT, "turbo", true)
	t.check(sn._eye_stalks != null, "built-after-ready snail binds its eye stalks")
	t.check(sn._foot_pivot != null and sn._shell_pivot != null and sn._body != null,
		"built-after-ready snail binds body, shell and foot pivots")
	var op: Node3D = sn._operculum_pivot
	t.check(op != null and not op.visible, "operculum is bound and hidden while out")
	# #565: pedal-wave bands exist under the foot (glass pad or sole).
	t.check(sn._pedal_bands.size() >= 3, "pedal-wave bands are bound (#565)")
	sn.queue_free()


func _test_head_leads(t: TestSupport.Suite) -> void:
	var cases: Array = [
		["back glass", Vector3(0.0, 4.0, -3.0 + 0.24), Vector3.BACK],
		["side glass", Vector3(-4.0 + 0.24, 4.0, 0.0), Vector3.RIGHT],
		["floor", Vector3(0.0, 1.7, 0.0), Vector3.UP],
		["surface film", Vector3(0.0, 6.45, 0.0), Vector3.DOWN],
	]
	for c in cases:
		var label: String = c[0]
		var n: Vector3 = c[2]
		var sn: SnailScript = _spawn(c[1], n, Vector2(1.0, 0.25))
		if n == Vector3.DOWN:
			sn._film_dwell = 100.0
		var p0: Vector3 = sn.global_position
		# Short windows: the crawl wanders on an S-curve, so only the
		# heading over the last few frames says where the snail is going.
		var cos_sum: float = 0.0
		var windows: int = 0
		var prev: Vector3 = p0
		for _w in 25:
			_run(sn, 6)
			var step: Vector3 = _in_plane(sn.global_position - prev, n)
			prev = sn.global_position
			if step.length() < 0.001:
				continue
			var head: Vector3 = _in_plane(sn._eye_stalks.global_position - sn.global_position, n)
			cos_sum += head.normalized().dot(step.normalized())
			windows += 1
		var d: Vector3 = _in_plane(sn.global_position - p0, n)
		t.check(d.length() > 0.05, "%s snail crawls (moved %.3f)" % [label, d.length()])
		var c_head: float = cos_sum / maxf(1.0, float(windows))
		t.check(windows > 15 and c_head > 0.95,
			"%s snail leads with its head (mean cos %.2f over %d windows)" % [label, c_head, windows])
		var up_ok: float = sn.global_transform.basis.y.normalized().dot(SnailSurface.shell_up_for(n))
		t.check(up_ok > 0.95, "%s snail keeps its shell on the right side (%.2f)" % [label, up_ok])
		sn.queue_free()


# Lowest point of every visible voxel along -n: how far the drawn body
# reaches toward (or through) a surface with inward normal n at offset.
func _penetration(sn: SnailScript, n: Vector3, plane_offset: float) -> float:
	var worst: float = -INF
	var stack: Array = [sn._body]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for ch in node.get_children():
			stack.append(ch)
		if node is MeshInstance3D and (node as MeshInstance3D).is_visible_in_tree():
			var mi: MeshInstance3D = node
			var box: AABB = mi.global_transform * mi.get_aabb()
			for i in 8:
				var depth: float = plane_offset - n.dot(box.get_endpoint(i))
				worst = maxf(worst, depth)
	return worst


func _test_surface_blend(t: TestSupport.Suite) -> void:
	# Floor -> back glass climb.
	var sn: SnailScript = _spawn(Vector3(0.0, 1.7, -3.0 + 0.26), Vector3.UP, Vector2(0.0, -1.0))
	sn._paused = true
	_run(sn, 4)
	var floor_pen0: float = _penetration(sn, Vector3.UP, 1.6)
	var climbed: bool = false
	for _i in 40:
		if sn._try_climb_onto_glass():
			climbed = true
			break
	t.check(climbed, "floor snail at the glass climbs")
	sn._wall_transition_cooldown = 99.0
	t.check(sn.global_transform.basis.y.normalized().dot(Vector3.BACK) > 0.95,
		"the logical pose is on the glass at once")
	t.check(sn._body.global_transform.basis.y.normalized().dot(Vector3.UP) > 0.95,
		"the drawn body has not snapped: it starts from the floor pose")
	t.check(sn.is_surface_blending(), "a surface blend is running")
	var worst_floor: float = floor_pen0
	var worst_glass: float = -INF
	var mid_up: float = 1.0
	for i in 45:
		sn._process(DT)
		worst_floor = maxf(worst_floor, _penetration(sn, Vector3.UP, 1.6))
		worst_glass = maxf(worst_glass, _penetration(sn, Vector3.BACK, -3.0))
		if i == 17:
			mid_up = sn._body.global_transform.basis.y.normalized().dot(Vector3.UP)
	t.in_range(mid_up, 0.1, 0.95, "at 0.3 s the body is part-way round (up·UP %.2f)" % mid_up)
	t.check(not sn.is_surface_blending(), "the climb blend finishes inside 0.75 s")
	t.check(sn._body.transform.is_equal_approx(Transform3D.IDENTITY),
		"after the blend the body sits exactly on the logical pose")
	var glass_pen_end: float = _penetration(sn, Vector3.BACK, -3.0)
	var floor_pen_end: float = _penetration(sn, Vector3.UP, 1.6)
	t.check(worst_floor <= maxf(floor_pen0, floor_pen_end) + 0.02,
		"the climb never sinks the body further into the floor (%.3f vs %.3f/%.3f)"
			% [worst_floor, floor_pen0, floor_pen_end])
	t.check(floor_pen_end <= 0.06,
		"on the glass at the corner the tail stays out of the gravel (%.3f)" % floor_pen_end)
	t.check(worst_glass <= maxf(glass_pen_end, 0.0) + 0.02,
		"the climb never pushes the body through the glass (%.3f vs %.3f)"
			% [worst_glass, glass_pen_end])
	sn.queue_free()

	# Back glass -> floor descent.
	var dn: SnailScript = _spawn(Vector3(0.5, 1.6 + 0.30, -3.0 + 0.24), Vector3.BACK, Vector2(0.0, -1.0))
	dn._paused = true
	_run(dn, 4)
	var floor_before: float = _penetration(dn, Vector3.UP, 1.6)
	var descended: bool = false
	for _i in 40:
		if dn._try_descend_to_substrate():
			descended = true
			break
	t.check(descended, "glass snail at the floor descends")
	dn._wall_transition_cooldown = 99.0
	var worst_desc: float = floor_before
	for _i in 45:
		dn._process(DT)
		worst_desc = maxf(worst_desc, _penetration(dn, Vector3.UP, 1.6))
	var floor_after: float = _penetration(dn, Vector3.UP, 1.6)
	t.check(worst_desc <= maxf(floor_before, floor_after) + 0.02,
		"the descent never sinks the body further into the floor (%.3f vs %.3f/%.3f)"
			% [worst_desc, floor_before, floor_after])
	dn.queue_free()


func _test_film_sink(t: TestSupport.Suite) -> void:
	var sn: SnailScript = _spawn(Vector3(0.3, 6.45, 0.2), Vector3.DOWN, Vector2.RIGHT)
	sn._film_dwell = 5.0
	sn._wall_anchor_offset = Vector3.DOWN.dot(sn.global_position)
	_run(sn, 3)
	var xz0 := Vector2(sn.global_position.x, sn.global_position.z)
	sn._release_surface_film()
	t.check(sn.wall_normal.is_equal_approx(Vector3.UP), "away from the glass the snail lets go")
	t.approx(sn._wall_anchor_offset, 1.6 + SnailScript.WALL_TRANSITION_NUDGE,
		"the anchor moves to the substrate it falls to", 0.001)
	# The sim's bounds pass calls this every ~0.2 s; it must not teleport.
	sn._reclamp_to_footprint()
	t.check(sn.global_position.y > 6.0, "a reclamp mid-fall does not teleport the snail")
	var lowest: float = INF
	var prev_y: float = sn.global_position.y
	var monotonic: bool = true
	var landed_after: int = -1
	for i in 600:
		sn._process(DT)
		var y: float = sn.global_position.y
		lowest = minf(lowest, y)
		if y > prev_y + 1e-5:
			monotonic = false
		prev_y = y
		if i == 30:
			t.check(sn._tuck > 0.9 and sn._eye_ext < 0.1, "a falling snail is withdrawn")
		if not sn._sinking:
			landed_after = i
			break
	t.check(landed_after > 0, "the snail lands (after %d frames)" % landed_after)
	t.check(monotonic, "the fall only goes down")
	t.check(lowest >= 1.6 + SnailScript.WALL_TRANSITION_NUDGE - 0.001,
		"the fall never goes under the substrate (lowest %.3f)" % lowest)
	var xz1 := Vector2(sn.global_position.x, sn.global_position.z)
	t.check(xz0.distance_to(xz1) < 0.05, "the fall is straight down, no sideways yank")
	sn._reclamp_to_footprint()
	t.approx(sn.global_position.y, 1.6 + SnailScript.WALL_TRANSITION_NUDGE,
		"a reclamp after landing keeps it on the substrate", 0.001)
	t.check(sn.global_transform.basis.y.dot(Vector3.UP) < -0.5,
		"it lands shell-first, upside down")
	var yaw0: Vector3 = sn.global_transform.basis.x
	sn._process(DT)
	t.check(sn._righting_remaining > 0.0, "landing on its back starts the righting response")
	for _i in 300:
		if sn._righting_remaining <= 0.0:
			break
		sn._process(DT)
	var up_after: float = sn.global_transform.basis.y.normalized().dot(Vector3.UP)
	t.check(up_after > 0.9, "and rights itself within ~2 s (up·UP %.2f)" % up_after)
	var yaw_kept: float = _in_plane(yaw0, Vector3.UP).normalized().dot(
		_in_plane(sn.global_transform.basis.x, Vector3.UP).normalized())
	t.check(yaw_kept > 0.9,
		"righting rolls it over instead of spinning it round (heading kept %.2f)" % yaw_kept)
	sn.queue_free()


func _test_clamp_tuck(t: TestSupport.Suite) -> void:
	var sn: SnailScript = _spawn(Vector3(1.0, 1.7, 1.0), Vector3.UP, Vector2.RIGHT)
	var shell: Node3D = sn._shell_pivot
	var foot: Node3D = sn._foot_pivot
	var foot_x_seen: Array[float] = []
	for _i in 90:
		sn._process(DT)
		foot_x_seen.append(foot.scale.x)
		t.check(shell.scale.is_equal_approx(Vector3.ONE), "the shell never deforms while crawling")
		if not shell.scale.is_equal_approx(Vector3.ONE):
			break
	t.check(sn.scale.is_equal_approx(Vector3.ONE), "an adult root carries no squash")
	t.check(float(foot_x_seen.max()) - float(foot_x_seen.min()) > 0.05,
		"the foot creeps while crawling")
	# #567: shell rocks with the foot pulse while crawling.
	t.check(absf(shell.rotation.x) > 0.005 or absf(sn._shell_rock) > 0.005,
		"the shell rocks on the foot (#567)")
	# #565: pedal bands travel along the sole.
	if sn._pedal_bands.size() >= 2:
		var b0: Node3D = sn._pedal_bands[0] as Node3D
		var x0: float = b0.position.x
		_run(sn, 40)
		t.check(absf(b0.position.x - x0) > 0.01, "pedal bands scroll (#565)")
	sn._clamped = true
	sn._clamp_grace_remaining = 99.0
	sn._process(DT)
	t.in_range(sn._tuck, 0.05, 0.6, "a clamp is not instant (one frame: %.2f)" % sn._tuck)
	_run(sn, 12)  # ~0.2 s
	t.check(sn._tuck > 0.95, "but it is fast: tucked within 0.2 s (%.2f)" % sn._tuck)
	t.approx(shell.position.y, -SnailScript.SHELL_TUCK_DROP * sn.shell_size,
		"the shell lowers onto the foot", 0.004)
	t.check(shell.scale.is_equal_approx(Vector3.ONE), "the clamped shell keeps its shape")
	t.check(foot.scale.y < 0.45, "the clamped foot flattens (%.2f)" % foot.scale.y)
	t.check(sn.scale.is_equal_approx(Vector3.ONE), "the clamp does not scale the snail")
	sn._clamped = false
	sn._clamp_grace_remaining = 0.0
	_run(sn, 12)
	t.check(sn._tuck > 0.5, "re-emergence is slow (%.2f after 0.2 s)" % sn._tuck)
	_run(sn, 150)
	t.check(sn._tuck < 0.05, "and complete within ~3 s (%.3f)" % sn._tuck)
	sn.queue_free()


func _test_eye_stalks(t: TestSupport.Suite) -> void:
	var sn: SnailScript = _spawn(Vector3(-1.0, 1.7, -1.0), Vector3.UP, Vector2.RIGHT)
	var stalks: Node3D = sn._eye_stalks
	sn._clamped = true
	sn._clamp_grace_remaining = 99.0
	sn._process(DT)
	t.in_range(sn._eye_ext, 0.5, 0.95, "stalks do not vanish in one frame (%.2f)" % sn._eye_ext)
	_run(sn, 9)  # ~0.17 s
	t.check(sn._eye_ext < 0.06, "but they are in within ~0.15 s (%.3f)" % sn._eye_ext)
	t.check(stalks.scale.y < 0.16, "the stalk pivot pulls in (%.2f)" % stalks.scale.y)
	sn._clamped = false
	sn._clamp_grace_remaining = 0.0
	_run(sn, 18)  # 0.3 s
	t.check(sn._eye_ext < 0.6, "they do not shoot back out (%.2f after 0.3 s)" % sn._eye_ext)
	_run(sn, 90)  # 1.8 s total
	t.check(sn._eye_ext > 0.9, "they are back out in ~1.5 s (%.2f)" % sn._eye_ext)
	# Crawling lean is a forward pitch in the model frame (about Z, toward +X).
	t.check(stalks.rotation.z < 0.0, "crawling stalks lean forward (%.2f)" % stalks.rotation.z)
	sn.queue_free()


func _test_bristle_kick(t: TestSupport.Suite) -> void:
	var wr := Node3D.new()
	wr.name = "WriggleWorms"
	root.add_child(wr)
	_builder.set("wriggle_root", wr)
	var near := BristleWorm.new()
	var far := BristleWorm.new()
	for bw in [near, far]:
		wr.add_child(bw)
		bw.set_process(false)
	near.global_position = Vector3(0.5, 1.6, 0.0)
	far.global_position = Vector3(3.5, 1.6, 2.5)
	near._emerged_t = 0.0
	far._emerged_t = 0.0
	_builder.call("_kick_bristle_worms_near", Vector3(0.0, 1.6, 0.0))
	t.check(near._emerged_t >= 0.65, "a digging fish kicks a nearby bristle worm out")
	t.approx(far._emerged_t, 0.0, "a far bristle worm is left alone")
	_builder.set("wriggle_root", null)
	wr.queue_free()
