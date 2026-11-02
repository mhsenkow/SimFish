extends SceneTree

# CREATURE_MOTION_700 #303–#305: opercula flap with breath; the jaw opens for gape.


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_motion_face")
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true
	cfg.music_enabled = false
	cfg.music_sync_fish = false
	var host: Node3D = load("res://scripts/motion_world_test_stub.gd").new()
	root.add_child(host)
	_pivots(t, host)
	_breath_flaps_opercula(t, host)
	_gape_opens_jaw(t, host)
	_head_stays_unscaled(t, host)
	_pelvics(t, host)
	_yawn_and_cough(t, host)
	_soft_chains(t, host)
	host.queue_free()
	await process_frame
	quit(t.finish())


func _swimmer(host: Node3D, species: String = "guppy") -> Fish:
	var sim: Node = load("res://scripts/motion_visibility_test_stub.gd").new()
	sim.creature_visible = true
	host.add_child(sim)
	var f := Fish.new()
	host.add_child(f)
	f.set_process(false)
	var g: Dictionary = root.get_node("TankConfig").SPECIES_LIBRARY[species]["genome"].duplicate(true)
	g["sex"] = 0
	f.init_genome(g)
	f.sim = sim
	f.heading = Vector3.FORWARD
	f.target_velocity = Vector3.FORWARD * 0.1
	f.global_position = Vector3(0, 3, 0)
	f.home_y = 3.0
	f._hover_depth = 3.0
	f.speed = 0.02
	f.hunger = 0.8
	f._spawn_settle_remaining = 0.0
	f._wag_freq_jitter = 1.0
	f._motor_phase = 0.3
	f._swim_phase = 0.3
	return f


func _pivots(t: TestSupport.Suite, host: Node3D) -> void:
	var f := _swimmer(host)
	t.check(f._operculum_left != null and f._operculum_right != null, "both opercula exist")
	t.check(f._jaw_pivot != null, "jaw pivot exists")
	t.check(f._operculum_left.get_parent() == f._head_pivot, "left operculum parents to the head")
	t.check(f._jaw_pivot.get_parent() == f._head_pivot, "jaw parents to the head")


func _breath_flaps_opercula(t: TestSupport.Suite, host: Node3D) -> void:
	var f := _swimmer(host)
	f._breath_load = 1.8
	var max_open: float = 0.0
	for i in 90:
		f._motion_substep(1.0 / 60.0, 1.0 / 60.0)
		max_open = maxf(max_open, absf(f._operculum_right.rotation.y))
	t.check(max_open > 0.04, "opercula open on the breath clock")
	t.check(absf(f._operculum_left.rotation.y + f._operculum_right.rotation.y) < 0.02,
		"opercula open symmetrically outward")


func _gape_opens_jaw(t: TestSupport.Suite, host: Node3D) -> void:
	var f := _swimmer(host)
	f._mouth_gape = 1.0
	f._motion_substep(1.0 / 60.0, 1.0 / 60.0)
	t.check(f._jaw_pivot.rotation.x > 0.2, "a full gape pitches the jaw open")


func _head_stays_unscaled(t: TestSupport.Suite, host: Node3D) -> void:
	var f := _swimmer(host)
	f._mouth_gape = 1.0
	f._breath_load = 2.0
	f._gill_flush_t = 0.4
	var rest: Vector3 = f._head_rest_pos
	for i in 30:
		# Force a mid-body bend so a buggy spine offset would shear the skull.
		f._body_mid_pivot.rotation.y = 0.55
		f._motion_substep(1.0 / 60.0, 1.0 / 60.0)
	t.approx(f._head_pivot.scale.x, 1.0, "breath no longer scales the skull", 0.02)
	t.approx(f._head_pivot.scale.y, 1.0, "gulp no longer stretches the skull", 0.02)
	t.approx(f._head_pivot.scale.z, 1.0, "gape no longer stretches the skull", 0.02)
	t.approx(f._head_pivot.position.x, rest.x, "head stays on rest X (no shear)", 0.02)
	t.approx(f._head_pivot.position.z, rest.z, "head stays on rest Z", 0.02)
	# Pitch writers must settle back — stuck nose-up was the pug face.
	f._aerial_timer = 0.0
	f._brake_pose = 0.0
	f.speed = 0.5
	f._motion_target_spd = 0.5
	for i in 12:
		f.set_meta("_ant_takeoff", 1.0)
		f._motion_substep(1.0 / 60.0, 1.0 / 60.0)
	t.check(f._head_pivot.rotation.x < -0.08, "pitch targets tip the head")
	f.set_meta("_ant_takeoff", 0.0)
	f.set_meta("_head_pitch_bite", 0.0)
	for i in 90:
		f.set_meta("_ant_takeoff", 0.0)
		f._motion_substep(1.0 / 60.0, 1.0 / 60.0)
	t.approx(f._head_pivot.rotation.x, 0.0, "head pitch returns to rest", 0.04)


func _pelvics(t: TestSupport.Suite, host: Node3D) -> void:
	var f := _swimmer(host)
	t.check(f._pelvic_left_pivot != null and f._pelvic_right_pivot != null, "both pelvic pivots exist")
	t.check(f._pelvic_left_pivot.get_parent() == f._body_mid_pivot, "pelvics parent to the body")
	f.speed = 0.02
	var moved: bool = false
	var x0: float = f._pelvic_right_pivot.rotation.x
	for i in 60:
		f._motion_substep(1.0 / 60.0, 1.0 / 60.0)
		if absf(f._pelvic_right_pivot.rotation.x - x0) > 0.02:
			moved = true
			break
	t.check(moved or absf(f._pelvic_right_pivot.rotation.x) > 0.05, "pelvics animate")


func _yawn_and_cough(t: TestSupport.Suite, host: Node3D) -> void:
	var f := _swimmer(host)
	f._fidget_kind = 2
	f._fidget_remaining = 0.35
	f._mouth_gape = 1.0
	f._motion_substep(1.0 / 60.0, 1.0 / 60.0)
	t.check(absf(f._operculum_right.rotation.y) > 0.08, "a yawn flares the opercula")
	t.check(f._jaw_pivot.rotation.x > 0.25, "a yawn opens the jaw wide")
	var c := _swimmer(host)
	c._gill_flush_t = 0.45  # early cough: covers clamp shut
	c._breath_load = 1.0
	c._motion_substep(1.0 / 60.0, 1.0 / 60.0)
	t.check(c._operculum_right.rotation.y < 0.0, "a cough first clamps the opercula")
	c._gill_flush_t = 0.15  # late cough: reverse flare
	c._motion_substep(1.0 / 60.0, 1.0 / 60.0)
	t.check(c._operculum_right.rotation.y > 0.05, "then the cough flares them open")


func _soft_chains(t: TestSupport.Suite, host: Node3D) -> void:
	var library: Dictionary = root.get_node("TankConfig").SPECIES_LIBRARY
	var barbel_species := "guppy"
	for key in library.keys():
		var g: Dictionary = library[key].get("genome", {})
		if not not g.get("has_barbels", false):
			barbel_species = String(key)
			break
	var f := _swimmer(host, barbel_species)
	t.check(not f._soft_chains.is_empty(), "barbelled fish build soft chains")
	f.speed = 1.2
	f._last_yaw_rate = 2.0
	var tip0: float = 0.0
	if f._soft_chains.size() > 0:
		var pivots: Array = f._soft_chains[0]["pivots"]
		if pivots.size() > 0:
			tip0 = pivots[pivots.size() - 1].rotation.x
	for i in 45:
		f._motion_substep(1.0 / 60.0, 1.0 / 60.0)
	var tip1: float = tip0
	if f._soft_chains.size() > 0:
		var pivots2: Array = f._soft_chains[0]["pivots"]
		if pivots2.size() > 0:
			tip1 = pivots2[pivots2.size() - 1].rotation.x
	t.check(absf(tip1 - tip0) > 0.01 or absf(tip1) > 0.01, "soft chains trail the body")
