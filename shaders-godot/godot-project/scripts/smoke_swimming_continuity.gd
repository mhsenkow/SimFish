extends SceneTree
const LifeBouts = preload("res://scripts/fish_life_bouts.gd")

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_swimming_continuity")
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true
	cfg.music_enabled = false
	cfg.music_sync_fish = false
	var fish := Fish.new()
	root.add_child(fish)
	fish.set_process(false)
	fish._turn_rate_state = 3.0
	fish._turn_axis_state = Vector3.UP
	var reverse: float = LifeBouts.inertial_turn(fish, 1.0, 0.1, 0.02, 0.0, 0.8, 0.45, Vector3.DOWN)
	t.check(reverse < 0.0, "turn reversal brakes existing angular momentum first")
	for i in 30:
		reverse = LifeBouts.inertial_turn(fish, 1.0, 0.1, 0.02, 0.0, 0.8, 0.45, Vector3.DOWN)
	t.check(reverse > 0.0, "reversed turn eventually follows its target")
	fish._turn_rate_state = 3.0
	fish._turn_axis_state = Vector3.UP
	t.check(LifeBouts.inertial_turn(fish, 1.0, 0.1, 0.02, 0.9, 0.8, 0.45, Vector3.DOWN) > 0.0,
		"near glass, clearance takes priority over holding the old turn")
	t.approx(LifeBouts.inertial_turn(fish, 1.0, 0.1, 0.0, 0.0), 0.0, "zero time cannot turn")
	t.check(FishLocomotion.steering_axis(Vector3(1, 1, 0).normalized()).y > 0.7,
		"diagonal steering favours yaw rather than pitch")
	t.approx(FishLocomotion.steering_axis(Vector3.UP).y, 1.0, "level yaw is unchanged")
	t.approx(FishLocomotion.steering_axis_gain(Vector3.RIGHT), 0.5, "pure pitch turns at half the yaw rate")
	t.approx(FishLocomotion.steering_axis_gain(Vector3.UP), 1.0, "yaw retains the full turn rate")
	for phase in [0.0, 0.7, 2.4, 4.7]:
		t.approx(TopdownMotion.burst_glide_speed_mult(phase, "cruise"),
			TopdownMotion.burst_glide_speed_mult(phase + TAU, "cruise"), "glide follows a full tailbeat cycle")
	var phase_wrap: float = Hydrodynamics.advance_phase(TAU * 100.0 - 0.01, 1.0, 0.02, TAU * 100.0)
	t.approx(sin(phase_wrap * 0.19), sin((TAU * 100.0 + 0.01) * 0.19), "bounded motor clock preserves slow steering harmonics")
	var slow: float = 0.0
	var fine: float = 0.0
	for i in 25:
		slow = Hydrodynamics.integrate_speed(slow, 0.8, 0.05, 0.16, 1.0, 0.04, false)
	for i in 100:
		fine = Hydrodynamics.integrate_speed(fine, 0.8, 0.05, 0.16, 1.0, 0.01, false)
	t.check(absf(slow - fine) < 0.025, "speed integration is stable across time partitions")
	var settled: float = 0.8
	for i in 1000:
		settled = Hydrodynamics.integrate_speed(settled, 0.8, 0.05, 0.16, 1.0, 0.01, false)
	t.in_range(settled, 0.75, 0.85, "cruise settles near requested pace")
	var coast: float = 0.8
	for i in 300:
		coast = Hydrodynamics.integrate_speed(coast, 0.12, 0.05, 0.16, 1.0, 0.01, true)
	t.in_range(coast, 0.12, 0.5, "coasting sheds momentum rather than sustaining cruise")
	var host: Node3D = load("res://scripts/motion_world_test_stub.gd").new()
	root.add_child(host)
	var seen := _make_swimmer(host, true)
	var unseen := _make_swimmer(host, false)
	for i in 60:
		seen._motion_substep(1.0 / 60.0)
		unseen._motion_substep(1.0 / 60.0)
	t.check(seen.speed > 0.3, "visibility comparison performs actual swimming")
	t.check(seen.global_position.distance_to(Vector3(0, 3, 0)) > 0.25, "visibility comparison covers a forward path")
	t.approx(seen.speed, unseen.speed, "camera culling does not change swimming speed")
	t.approx(seen._motor_phase, unseen._motor_phase, "camera culling does not stop the stroke clock")
	t.check(seen.global_position.distance_to(unseen.global_position) < 0.0001,
		"visible and culled fish follow the same physical path")
	var regular := _make_swimmer(host, true)
	var batched := _make_swimmer(host, true)
	var old_pose_phase: float = batched._swim_phase
	for step in 5:
		regular._motion_substep(0.01)
		batched._motion_substep(0.01, 0.05 if step == 4 else 0.0)
		if step < 4:
			t.approx(batched._swim_phase, old_pose_phase, "intermediate integration does not write a hidden fin pose")
	t.approx(regular.speed, batched.speed, "pose batching preserves physical momentum")
	t.approx(regular._motor_phase, batched._motor_phase, "pose batching preserves the propulsion clock")
	t.check(regular.position.distance_to(batched.position) < 0.0001,
		"pose batching preserves movement through all substeps")
	t.check(batched._swim_phase > old_pose_phase, "final visible pose advances the fin clock")
	t.check(batched.transform.is_finite(), "batched swimmer remains finite")
	var paused_speed: float = seen.speed
	var paused_position: Vector3 = seen.global_position
	seen._motion_substep(0.0)
	seen._motion_substep(-0.5)
	t.approx(seen.speed, paused_speed, "pause and negative time preserve momentum")
	t.check(seen.global_position == paused_position, "pause and negative time preserve position")
	fish.queue_free()
	host.queue_free()
	await process_frame
	quit(t.finish())

func _make_swimmer(host: Node3D, visible: bool) -> Fish:
	var sim: Node = load("res://scripts/motion_visibility_test_stub.gd").new()
	sim.creature_visible = visible
	host.add_child(sim)
	var f := Fish.new()
	host.add_child(f)
	f.set_process(false)
	f.sim = sim
	f.heading = Vector3.FORWARD
	f.target_velocity = Vector3.FORWARD * 0.8
	f.global_position = Vector3(0, 3, 0)
	f.home_y = 3.0
	f._hover_depth = 3.0
	f.speed = 0.4
	f.hunger = 0.8
	f.current_mode = Fish.Mode.FLEE
	f._spawn_settle_remaining = 0.0
	f._wag_freq_jitter = 1.0
	f._motor_phase = 0.3
	f._swim_phase = 0.3
	f._breath_phase = 0.0
	return f
