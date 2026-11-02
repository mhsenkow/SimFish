extends SceneTree

# CREATURE_MOTION_700 #218 / #219 — pose editor save path + contact sheet tiling.


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_motion_pose_lab")
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true

	MotionPoseLibrary.reload_data()
	t.check(MotionPoseLibrary.CHANNELS.size() >= 10, "pose editor exposes channels")
	t.check(MotionPoseLibrary.list_poses("guppy").has("display"), "list_poses includes display")

	# #218: upsert a species override and round-trip through save/reload.
	var before: float = float(MotionPoseLibrary.get_pose("guppy", "display").get("caudal_spread", 1.0))
	var edited: Dictionary = MotionPoseLibrary.get_pose("guppy", "display")
	edited["caudal_spread"] = before + 0.11
	MotionPoseLibrary.upsert_pose("guppy", "display", edited)
	t.approx(float(MotionPoseLibrary.get_pose("guppy", "display").get("caudal_spread", 0.0)),
		before + 0.11, "upsert updates in-memory pose", 0.001)
	var tmp: String = "user://smoke_pose_lab_poses.json"
	var wrote: String = MotionPoseLibrary.save_data(PackedStringArray([tmp]))
	t.equals(wrote, tmp, "save_data writes the requested path")
	t.check(FileAccess.file_exists(tmp), "saved pose JSON exists")
	# Reload shipped library — smoke must never mutate res://poses.json.
	MotionPoseLibrary.reload_data()
	t.approx(float(MotionPoseLibrary.get_pose("guppy", "display").get("caudal_spread", 0.0)),
		before, "reload restores shipped poses", 0.02)

	# Force-pose lock for the lab preview.
	var host: Node3D = load("res://scripts/motion_world_test_stub.gd").new()
	root.add_child(host)
	var sim: Node = load("res://scripts/motion_visibility_test_stub.gd").new()
	sim.creature_visible = true
	host.add_child(sim)
	var f := Fish.new()
	host.add_child(f)
	f.set_process(false)
	var g: Dictionary = cfg.SPECIES_LIBRARY["guppy"]["genome"].duplicate(true)
	f.init_genome(g)
	f.sim = sim
	f.global_position = Vector3(0, 3, 0)
	f._spawn_settle_remaining = 0.0
	FishPoseRuntime.force_pose(f, "clamped")
	t.equals(FishPoseRuntime.select_pose(f), "clamped", "force_pose locks selection")
	var ch: Dictionary = {"fin_carriage": -0.9, "caudal_spread": 0.7, "head_pitch": 0.2}
	FishPoseRuntime.set_edit_channels(f, ch)
	var applied: Dictionary = FishPoseRuntime.tick(f, 0.05)
	t.approx(float(applied.get("fin_carriage", 0.0)), -0.9, "edit channels win while locked", 0.001)
	FishPoseRuntime.clear_force_pose(f)
	t.check(not f.has_meta("_pose_force"), "clear_force_pose removes lock")

	# #219: contact sheet compositor tiles cells.
	var cells: Array = []
	for i in 6:
		var im := Image.create(32, 24, false, Image.FORMAT_RGBA8)
		im.fill(Color(0.1 * float(i + 1), 0.2, 0.3))
		cells.append(im)
	var sheet: Image = MotionPoseLibrary.compose_contact_sheet(cells, 3, 2)
	t.equals(sheet.get_width(), 32 * 3 + 2 * 2, "sheet width = 3 cells + pads")
	t.equals(sheet.get_height(), 24 * 2 + 2, "sheet height = 2 rows + pad")
	var out: String = "user://smoke_pose_contact_sheet.png"
	sheet.save_png(out)
	t.check(FileAccess.file_exists(out), "contact sheet PNG written")

	f.queue_free()
	host.queue_free()
	await process_frame
	quit(t.finish())
