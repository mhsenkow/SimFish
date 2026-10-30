extends SceneTree

const SnailScript = preload("res://scripts/snail.gd")

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_living_locomotion")
	var host := Node3D.new()
	root.add_child(host)
	var sh := Shrimp.new()
	host.add_child(sh)
	sh.init_genome({"substrate_top_y": 0.0})
	t.check(not sh._leg_pivots.is_empty(), "real walking model supplies animated legs")
	sh.set_process(false)
	sh.substrate_top_y = 0.0
	sh.position = Vector3(0, 0.08, 0)
	sh.heading = Vector3.RIGHT
	sh._target_velocity = Vector3(0.8, 0, 0)
	for _i in 120:
		sh._motion_substep(1.0 / 60.0)
	t.check(sh.position.x > 0.5, "ordinary acceleration goes toward the target")
	t.approx(sh._escape_remaining, 0.0, "ordinary acceleration is not a tail escape")
	t.equals(sh._target_velocity, Vector3(0.8, 0, 0), "physics preserves the brain command")
	t.approx(sh.position.y, 0.08, "walking maintains substrate contact", 0.002)
	sh._target_velocity = Vector3.ZERO
	for _i in 120:
		sh._motion_substep(1.0 / 60.0)
	var rest: Vector3 = sh.position
	for _i in 120:
		sh._motion_substep(1.0 / 60.0)
	t.approx(sh.position.distance_to(rest), 0.0, "resting shrimp does not skate", 0.002)
	var gait_before: float = sh._gait_phase
	sh.speed = 1.0
	sh._tick_gait(0.1, true, 0.0)
	t.approx(sh._gait_phase, gait_before, "blocked feet do not advance walking phase")
	sh._escape_remaining = 0.2
	sh._target_velocity = Vector3.RIGHT
	sh._motion_substep(0.02)
	# Motion, not facing: a tail flip travels backwards along the body (#23),
	# so heading alone no longer says where an escape goes. Safety straight
	# ahead is a forward bolt.
	t.check(sh.velocity.normalized().dot(Vector3.RIGHT) > 0.9, "tail escape moves in the selected safe direction")
	for _i in 120:
		sh._escape_remaining = 0.2
		sh._motion_substep(1.0 / 60.0)
	t.check(sh.speed <= maxf(sh.max_speed * 1.8, 0.65) + 0.001,
		"sustained predator pressure cannot accelerate escape without bound")

	# Tail flip (#23). The display used to flip to -heading, and the 5.5 rad/s
	# visual turn cap made that a 0.57 s spin inside a 0.28 s escape. A
	# caridean shoots backwards with its head still toward the threat.
	var flipper := Shrimp.new()
	host.add_child(flipper)
	flipper.init_genome({"substrate_top_y": 0.0})
	flipper.set_process(false)
	flipper.position = Vector3(0, 0.08, 0)
	flipper.heading = Vector3.LEFT
	flipper._visual_heading = Vector3.LEFT
	flipper._target_velocity = Vector3.RIGHT
	for _i in 18:
		flipper._escape_remaining = 0.2
		flipper._motion_substep(1.0 / 60.0)
	t.check(flipper.velocity.normalized().dot(Vector3.RIGHT) > 0.95,
		"tail flip shoots backwards toward safety behind it")
	t.check(flipper.heading.dot(Vector3.LEFT) > 0.95, "tail flip keeps the head toward the threat")
	t.check(flipper._visual_heading.dot(Vector3.LEFT) > 0.95,
		"tail flip does not spin the displayed body round")
	t.check(flipper.speed <= maxf(flipper.max_speed * 1.8, 0.65) + 0.001, "tail flip speed is bounded")
	# Safety off to one side of straight back: the thrust bends toward it,
	# but only within the flip cone, and the body yaws slowly.
	var side_safe := Vector3(cos(1.2), 0.0, sin(1.2))
	flipper.heading = Vector3.LEFT
	flipper._target_velocity = side_safe
	flipper._escape_remaining = 0.2
	flipper._motion_substep(1.0 / 60.0)
	t.check(flipper.velocity.normalized().dot(side_safe) >= cos(Shrimp.ESCAPE_FLIP_REACH) - 0.01,
		"an off-axis tail flip still leads away toward safety")
	t.check(flipper.heading.angle_to(Vector3.LEFT) <= Shrimp.ESCAPE_FLIP_YAW_RATE / 60.0 + 0.001,
		"the body yaws slowly during a flip instead of turning to face its travel")

	# Landing (#37). Within 0.22 of the substrate Y used to snap to +0.08 in
	# one frame; a descending shrimp now eases down, then grips the floor.
	var lander := Shrimp.new()
	host.add_child(lander)
	lander.init_genome({"substrate_top_y": 0.0})
	lander.set_process(false)
	lander.position = Vector3(0, 0.21, 0)
	lander._target_velocity = Vector3.ZERO
	lander._motion_substep(1.0 / 60.0)
	t.check(lander.position.y > 0.17, "touchdown eases in rather than snapping to the floor")
	for _i in 120:
		lander._motion_substep(1.0 / 60.0)
		if lander._floor_gripped:
			break
	t.check(lander._floor_gripped, "an eased descent ends with the feet gripping the floor")
	t.approx(lander.position.y, 0.08, "a landed shrimp rests on the floor", 0.002)
	var rest_y: float = lander._body_pivot_rest_y
	for _i in 9:
		lander._motion_substep(1.0 / 60.0)
	t.check(lander._bank_pivot.position.y < rest_y - 0.004, "the body settles onto its legs at touchdown")
	for _i in 60:
		lander._motion_substep(1.0 / 60.0)
	t.approx(lander._bank_pivot.position.y, rest_y, "the touchdown settle recovers", 0.001)
	var land_heights: Array[float] = []
	for hz in [30, 120]:
		var drop := Shrimp.new()
		host.add_child(drop)
		drop.set_process(false)
		drop.substrate_top_y = 0.0
		drop.position = Vector3(0, 0.21, 0)
		for _i in roundi(float(hz) * 0.5):
			drop._motion_substep(1.0 / float(hz))
		land_heights.append(drop.position.y)
	t.approx(land_heights[0], land_heights[1], "the touchdown ease is frame-rate independent", 0.002)
	sh.body_shape = "crab"
	sh._escape_remaining = 0.0
	sh._target_velocity = Vector3(0.5, 1.5, 0)
	sh.position.y = 0.08
	for _i in 60:
		sh._motion_substep(1.0 / 60.0)
	t.approx(sh.position.y, 0.08, "crab cannot fly toward vertical steering", 0.002)
	var phase: float = sh._swim_phase
	sh._motion_substep(0.02)
	t.check(sh._swim_phase != phase, "motion oscillator advances independently of rendering")

	var frame_positions: Array[Vector3] = []
	for hz in [30, 60, 120]:
		var walker := Shrimp.new()
		host.add_child(walker)
		walker.set_process(false)
		walker.substrate_top_y = 0.0
		walker.position = Vector3(0, 0.08, 0)
		walker.heading = Vector3.RIGHT
		walker._target_velocity = Vector3(0.4, 0, 0)
		for _i in hz * 2:
			walker._motion_substep(1.0 / float(hz))
		frame_positions.append(walker.position)
	t.check(frame_positions[0].distance_to(frame_positions[2]) < 0.02,
		"walking pace stays consistent from 30 to 120 Hz")

	var snail := SnailScript.new()
	host.add_child(snail)
	snail.set_process(false)
	snail._direction = Vector2.RIGHT
	snail._steer_direction(Vector2.LEFT, 0.1)
	t.approx(snail._direction.length(), 1.0, "opposite turn retains a unit heading")
	t.check(absf(snail._direction.angle()) > 0.01 and absf(snail._direction.angle()) < PI,
		"opposite turn starts gradually rather than snapping or stalling")
	var before_turn: float = snail._direction.angle()
	snail._steer_direction(Vector2.LEFT, 0.01)
	t.check(absf(wrapf(snail._direction.angle() - before_turn, -PI, PI)) < 0.1,
		"small steering steps have bounded turn rate")
	snail.wall_normal = Vector3.UP
	snail._t_until_turn = 999.0
	snail._paused = false
	snail._eating_pulse_remaining = 1.0
	snail._crawl_speed_smoothed = 0.0
	var feeding_position: Vector3 = snail.position
	snail._process(0.1)
	t.approx(snail.position.distance_to(feeding_position), 0.0,
		"snail with a handled meal rasps in place", 0.002)

	var plant := Plant.new()
	host.add_child(plant)
	plant.set_process(false)
	plant.brush(Vector3.RIGHT, 0.01)
	t.approx(plant._brush_bend.length(), 0.01, "gentle animal touch gives gentle plant bend")
	plant._brush_bend = Vector2.ZERO
	plant.brush(Vector3.RIGHT, 0.0)
	t.equals(plant._brush_bend, Vector2.ZERO, "zero contact cannot bend a plant")
	plant.brush(Vector3.RIGHT, 1.0)
	t.check(plant._brush_bend.length() <= 0.55001, "strong brush remains bounded")
	host.queue_free()
	await process_frame
	quit(t.finish())
