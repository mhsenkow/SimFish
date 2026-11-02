extends SceneTree

# CREATURE_MOTION_700 §G — pose library smoke (#193–#217, #220).


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_motion_poses")
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true
	var host: Node3D = load("res://scripts/motion_world_test_stub.gd").new()
	root.add_child(host)
	var sim: Node = load("res://scripts/motion_visibility_test_stub.gd").new()
	sim.creature_visible = true
	host.add_child(sim)

	MotionPoseLibrary.reload_data()
	var required: PackedStringArray = FishPoseRuntime.required_poses()
	t.check(required.size() >= 20, "required pose set covers §G catalogue")

	# #220: every species has every required pose (via _default inheritance).
	var species_keys: Array = cfg.SPECIES_LIBRARY.keys()
	t.check(species_keys.size() >= 5, "species library is populated")
	for sp in species_keys:
		var sid: String = str(sp)
		for pose_name in required:
			t.check(MotionPoseLibrary.has_pose(sid, pose_name) \
					or MotionPoseLibrary.has_pose("_default", pose_name),
				"%s has pose %s" % [sid, pose_name])

	# #213: every required pose is reachable from cruise in the transition graph.
	var graph: Variant = MotionPoseLibrary._data.get("_transitions", {})
	t.check(graph is Dictionary and (graph as Dictionary).has("cruise"),
		"transition graph has a cruise row")
	var cruise_row: Dictionary = (graph as Dictionary).get("cruise", {})
	for pose_name in required:
		if pose_name == "cruise":
			continue
		t.check(cruise_row.has(pose_name),
			"cruise → %s is an allowed transition" % pose_name)

	# #217: per-species overrides deepen signature poses.
	var betta_disp: Dictionary = MotionPoseLibrary.get_pose("betta", "display")
	var guppy_disp: Dictionary = MotionPoseLibrary.get_pose("guppy", "display")
	t.check(float(betta_disp.get("caudal_spread", 1.0)) > float(guppy_disp.get("caudal_spread", 1.0)),
		"betta display flares further than default")
	t.check(float(MotionPoseLibrary.get_pose("corydoras", "sifting").get("head_pitch", 0.0)) > 0.5,
		"cory sifting is nose-down")
	t.check(float(MotionPoseLibrary.get_pose("pleco", "attached").get("head_pitch", 0.0)) > 0.7,
		"pleco attached is mouth-on-surface")

	# Runtime select / blend / apply on a living fish.
	var f := Fish.new()
	host.add_child(f)
	f.set_process(false)
	var g: Dictionary = cfg.SPECIES_LIBRARY["guppy"]["genome"].duplicate(true)
	f.id = "pose_smoke"
	f.init_genome(g)
	f.sim = sim
	f.heading = Vector3.FORWARD
	f.global_position = Vector3(0, 3, 0)
	f.speed = 0.35
	f._spawn_settle_remaining = 0.0
	f._fin_tail_activity = 0.8

	FishPoseRuntime.ensure(f)
	t.equals(FishPoseRuntime.select_pose(f), "cruise", "calm cruise selects cruise")
	f.speed = 0.02
	t.equals(FishPoseRuntime.select_pose(f), "hover", "near-still selects hover")
	f.stress = 0.8
	f.spooked = 0.7
	t.equals(FishPoseRuntime.select_pose(f), "clamped", "high stress selects clamped")
	f.stress = 0.2
	f.spooked = 0.0
	f.speed = 0.4
	f._courtship_flare = true
	f.current_mode = Fish.Mode.COURT
	t.equals(FishPoseRuntime.select_pose(f), "display", "court flare selects display")
	f._courtship_flare = false
	f.current_mode = Fish.Mode.CRUISE
	FishPoseRuntime.note_action_end(f, "glide", 0.4)
	t.equals(FishPoseRuntime.select_pose(f), "glide", "#216 dart end holds glide")

	# #214 / #215: tick leaves breath/flicker alive and channels finite.
	f.speed = 0.3
	f.set_meta("_pose_end", "")
	f.set_meta("_pose_end_t", 0.0)
	var ch: Dictionary = FishPoseRuntime.tick(f, 1.0 / 60.0)
	t.check(not ch.is_empty(), "tick yields channels")
	t.check(is_finite(float(ch.get("breath", 1.0))), "breath channel finite")
	t.check(is_finite(float(ch.get("fin_carriage", 0.0))), "fin carriage finite")

	for i in 30:
		f._motion_substep(1.0 / 60.0, 1.0 / 60.0)
	t.check(f._bank_pivot != null and f._bank_pivot.transform.is_finite(),
		"pose apply keeps bank pivot finite")
	t.check(str(f.get_meta("_pose_name", "")) != "", "pose name sticks after substeps")

	# Blend times for alarm vs display (#213 data).
	var sleep_alert: float = FishPoseRuntime.transition_seconds("guppy", "sleep", "alert")
	var alert_cruise: float = FishPoseRuntime.transition_seconds("guppy", "alert", "cruise")
	var clamped_cruise: float = FishPoseRuntime.transition_seconds("guppy", "clamped", "cruise")
	t.check(sleep_alert < 0.25, "sleep → alert snaps (%.3f)" % sleep_alert)
	t.check(alert_cruise > 0.5, "alert → cruise eases (%.3f)" % alert_cruise)
	t.check(clamped_cruise >= 2.0, "clamped → cruise is slow (%.3f)" % clamped_cruise)

	f.queue_free()
	host.queue_free()
	await process_frame
	quit(t.finish())
