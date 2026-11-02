extends SceneTree

# CREATURE_MOTION_700 Staging (#171–#192) helper smokes.


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_motion_staging")
	MotionStaging.reset()
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true
	var host: Node3D = load("res://scripts/motion_world_test_stub.gd").new()
	root.add_child(host)
	var sim: Node = load("res://scripts/motion_visibility_test_stub.gd").new()
	sim.creature_visible = true
	host.add_child(sim)
	var f := Fish.new()
	host.add_child(f)
	f.set_process(false)
	f.init_genome(cfg.SPECIES_LIBRARY["guppy"]["genome"].duplicate(true))
	f.sim = sim
	f.global_position = Vector3(0, 3, 0)
	f.heading = Vector3(0, 0, -1)
	f.speed = 0.4

	# #171
	t.check(MotionStaging.legibility_scale(f, 0.01) >= 1.0, "tiny amp gets legibility gain")
	# #172: caudal heave is a bounded rest offset — never integrate y + heave.
	var cam_heave := Camera3D.new()
	host.add_child(cam_heave)
	cam_heave.global_position = Vector3(4, 3, 0)  # broadside to heading -Z
	var boost: Dictionary = MotionStaging.camera_relative_tail_boost(f, cam_heave)
	t.check(float(boost.get("heave", 0.0)) > 0.0, "broadside lift asks for heave")
	var y: float = 0.0
	for _i in 180:
		y = lerpf(y, float(boost["heave"]), 0.35)
	t.check(absf(y - float(boost["heave"])) < 0.01, "heave converges to offset, not runaway")
	t.check(absf(y) <= 0.09, "heave stays within tip lift range")
	cam_heave.queue_free()
	# #175
	t.check(MotionStaging.begin_big_event(f.global_position, &"a", 1.0), "event 1 ok")
	t.check(MotionStaging.begin_big_event(f.global_position, &"b", 1.0), "event 2 ok")
	t.check(MotionStaging.begin_big_event(f.global_position, &"c", 1.0), "event 3 ok")
	t.check(not MotionStaging.begin_big_event(f.global_position, &"d", 1.0),
		"event 4 rejected at cap")
	t.check(MotionStaging.region_busy(f.global_position), "region marked busy")
	# #178 / #179
	var lead: Vector3 = MotionStaging.follow_lead_aim(Vector3.ZERO, Vector3(0, 0, -1), 0.2)
	t.check(lead.z < 0.0, "lead aim ahead of -Z heading")
	t.check(MotionStaging.follow_deadzone_for_speed(0.9, 0.8, 0.0) > 0.9,
		"deadzone widens on burst")
	# #182
	t.check(MotionStaging.stagger_delay(f) >= 0.0, "stagger delay non-negative")
	# #183
	t.check(MotionStaging.curve_intent(f, f.global_position + Vector3(2, 0, 0)).length() > 0.0,
		"curve intent pulls toward goal")
	# #186
	var slot := Vector3(1, 0, 0)
	var drifted: Vector3 = MotionStaging.formation_drift(f, slot, 12.0)
	t.check(drifted != slot, "formation slot drifts")
	# #187
	for i in 8:
		MotionStaging.note_activity(false)
	t.check(MotionStaging.should_force_rest(), "force rest when none resting")
	MotionStaging.note_activity(true)
	# #190
	f.maturity = Fish.MATURITY_FRY
	f._startle_remaining = 0.3
	t.check(MotionStaging.fry_trail_allowed(f), "fry trail on startle")
	f._startle_remaining = 0.0
	t.check(not MotionStaging.fry_trail_allowed(f), "fry trail quiet without escape/play")
	# #176
	MotionStaging.silhouette_mode = true
	t.check(MotionStaging.silhouette_mode, "silhouette mode toggles")
	MotionStaging.silhouette_mode = false

	# Yield field points away.
	var yv: Vector3 = MotionStaging.yield_field(f, f.global_position + Vector3(1, 0, 0), 0.5)
	t.check(yv.x < 0.0, "yield pushes away from event")

	# #177: LOS slab test + prefer_visible_site.
	var box := AABB(Vector3(-0.5, -0.5, 2.0), Vector3(1, 1, 1))
	var cam := Camera3D.new()
	host.add_child(cam)
	cam.global_position = Vector3(0, 0, 0)
	t.check(MotionStaging.ray_hits_aabb(Vector3(0, 0, 0), Vector3(0, 0, 1), box, 5.0),
		"ray hits plant AABB ahead")
	t.check(not MotionStaging.ray_hits_aabb(Vector3(0, 0, 0), Vector3(1, 0, 0), box, 5.0),
		"ray misses off-axis AABB")
	# Fake plant with canopy sphere.
	var fake := Node3D.new()
	host.add_child(fake)
	fake.set_script(load("res://scripts/motion_plant_aabb_test_stub.gd"))
	fake.global_position = Vector3(0, 1, 3)
	var blocked: Vector3 = Vector3(0, 1, 5)
	var cleared: Vector3 = MotionStaging.prefer_visible_site(blocked, cam, [fake], 0.9)
	t.check(cleared.distance_to(cam.global_position) < blocked.distance_to(cam.global_position) + 0.01 \
			or MotionStaging.clear_to_camera(cleared, cam, [fake]),
		"#177 prefer_visible_site moves toward a clearer offset")

	# #181: contact shadow packs tight on the bed.
	var bed: float = 0.0
	f.global_position = Vector3(1, 0.2, 0)
	var cpt: Vector4 = MotionStaging.contact_shadow_point(f, bed, 0.25)
	t.check(cpt.w > 0.1 and absf(cpt.y - bed - 0.06) < 0.02,
		"#181 contact shadow pinned just above bed")
	f.global_position = Vector3(1, 3.0, 0)
	t.check(MotionStaging.contact_shadow_point(f, bed, 0.25).w < 0.001,
		"#181 mid-water fish get no contact shadow")

	fake.queue_free()
	cam.queue_free()
	f.queue_free()
	host.queue_free()
	MotionStaging.reset()
	await process_frame
	quit(t.finish())
