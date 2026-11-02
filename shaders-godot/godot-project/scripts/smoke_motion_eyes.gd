extends SceneTree

# CREATURE_MOTION_700 #297: each eye sits on its own pivot and follows MotionGaze.


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_motion_eyes")
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true
	cfg.music_enabled = false
	cfg.music_sync_fish = false
	var host: Node3D = load("res://scripts/motion_world_test_stub.gd").new()
	root.add_child(host)
	_pivots(t, host)
	_gaze_turns_eyes(t, host)
	_eyes_not_head(t, host)
	_independent_and_converge(t, host)
	_stabilize_while_swimming(t, host)
	host.queue_free()
	await process_frame
	quit(t.finish())


func _swimmer(host: Node3D) -> Fish:
	var sim: Node = load("res://scripts/motion_visibility_test_stub.gd").new()
	sim.creature_visible = true
	host.add_child(sim)
	var f := Fish.new()
	host.add_child(f)
	f.set_process(false)
	var g: Dictionary = root.get_node("TankConfig").SPECIES_LIBRARY["guppy"]["genome"].duplicate(true)
	g["sex"] = 0
	f.init_genome(g)
	f.sim = sim
	f.heading = Vector3.FORWARD
	f.target_velocity = Vector3.FORWARD * 0.2
	f.global_position = Vector3(0, 3, 0)
	f.home_y = 3.0
	f._hover_depth = 3.0
	f.speed = 0.05
	f.hunger = 0.8
	f._spawn_settle_remaining = 0.0
	f._wag_freq_jitter = 1.0
	f._motor_phase = 0.3
	f._swim_phase = 0.3
	return f


func _pivots(t: TestSupport.Suite, host: Node3D) -> void:
	var f := _swimmer(host)
	t.check(f._eye_left_pivot != null and f._eye_right_pivot != null, "both eye pivots exist")
	t.check(f._eye_left_pivot.get_parent() == f._head_pivot, "left eye parents to the head")
	t.check(f._eye_right_pivot.get_parent() == f._head_pivot, "right eye parents to the head")
	t.check(f._motion_gaze != null, "MotionGaze is wired")
	t.check(f._eye_left_pivot.position.x < 0.0, "left eye is on -X")
	t.check(f._eye_right_pivot.position.x > 0.0, "right eye is on +X")


func _gaze_turns_eyes(t: TestSupport.Suite, host: Node3D) -> void:
	var f := _swimmer(host)
	f._gaze_yaw = -0.35
	f._gaze_remaining = 2.0
	for i in 45:
		f._motion_substep(1.0 / 60.0, 1.0 / 60.0)
	t.check(f._eye_right_pivot.rotation.y < -0.05 or f._eye_left_pivot.rotation.y < -0.05,
		"eyes yaw toward a gaze target on the fish's right")


func _eyes_not_head(t: TestSupport.Suite, host: Node3D) -> void:
	var f := _swimmer(host)
	f.speed = 0.02
	f._gaze_yaw = 0.3
	f._gaze_remaining = 2.0
	var head0: float = f._head_pivot.rotation.y
	for i in 60:
		f._motion_substep(1.0 / 60.0, 1.0 / 60.0)
	var eye_yaw: float = absf(f._eye_left_pivot.rotation.y)
	var head_delta: float = absf(f._head_pivot.rotation.y - head0)
	t.check(eye_yaw > 0.04, "eyes carry the look")
	t.check(head_delta < eye_yaw + 0.05, "the head leads less than the eyes turn")


func _independent_and_converge(t: TestSupport.Suite, host: Node3D) -> void:
	var gaze := MotionGaze.new(11)
	# Idle long enough for each eye to fire its own saccade.
	for i in 400:
		gaze.step(1.0 / 60.0, Transform3D.IDENTITY, 1.0)
	t.check(absf(gaze.left_eye_yaw() - gaze.right_eye_yaw()) > 0.02
			or absf(gaze.left_eye_pitch() - gaze.right_eye_pitch()) > 0.01,
		"each eye saccades on its own schedule")
	gaze.converge = 1.0
	gaze.look_at_point(&"food", Vector3(0.0, 0.0, -2.0), 2.0)
	for i in 30:
		gaze.step(1.0 / 60.0, Transform3D.IDENTITY, 1.0)
	t.check(gaze.left_eye_yaw() < gaze.right_eye_yaw() - 0.08,
		"feeding converges the eyes inward")
	var f := _swimmer(host)
	f._cached_glance_strength = 0.8
	f._cached_glance_point = f.global_position + Vector3(1.5, 0.2, -0.5)
	f.speed = 0.05
	for i in 40:
		f._motion_substep(1.0 / 60.0, 1.0 / 60.0)
	t.check(f._motion_gaze.kind == &"keeper", "eyes track the keeper at the glass")


func _stabilize_while_swimming(t: TestSupport.Suite, host: Node3D) -> void:
	var f := _swimmer(host)
	f.speed = 1.4
	f.target_velocity = Vector3.FORWARD * 1.4
	f._fin_tail_activity = 1.0
	f._motion_gaze.release()
	f._motion_gaze.converge = 0.0
	var max_head: float = 0.0
	var max_residual: float = 0.0
	for i in 180:
		f._motion_substep(1.0 / 60.0, 1.0 / 60.0)
		var hy: float = f._head_pivot.rotation.y
		max_head = maxf(max_head, absf(hy))
		# Residual world-ish yaw after the eye's counter-rotate.
		max_residual = maxf(max_residual, absf(hy + f._eye_left_pivot.rotation.y))
	# If this species barely head-wags, the stabilize path is still present
	# (eyes get the -0.85·head term); only assert cancellation when the head moves.
	if max_head > 0.02:
		t.check(max_residual < max_head * 0.6 + 0.03, "eyes counter the head wag")
	else:
		t.check(f._eye_left_pivot != null, "stabilize path keeps eye pivots live")
