extends SceneTree

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_settings_save_lifetime")
	var cfg: Node = load("res://scripts/settings_worker_test_stub.gd").new()
	root.add_child(cfg)
	cfg.marker = 1
	cfg.save_to_disk()
	cfg.marker = 2
	cfg.save_to_disk()
	var deadline: int = Time.get_ticks_msec() + 5000
	while bool(cfg.get("_save_in_flight")) and Time.get_ticks_msec() < deadline:
		await process_frame
	t.check(not bool(cfg.get("_save_in_flight")), "queued config saves finish")
	t.equals(cfg.get("_save_task_id"), -1, "completed worker task is reclaimed")
	var saved := ConfigFile.new()
	t.equals(saved.load("user://settings_worker_test_0.cfg"), OK, "settings file remains readable")
	t.equals(saved.get_value("test", "marker", -1), 2, "coalesced edit persists latest snapshot")
	cfg.marker = 3
	cfg.save_to_disk()
	cfg.marker = 4
	cfg.save_to_disk()
	cfg.flush_pending_settings()
	cfg.test_slot = 1
	cfg.marker = 5
	cfg.save_to_disk()
	cfg.marker = 6
	cfg.save_to_disk()
	cfg.free()
	saved.load("user://settings_worker_test_0.cfg")
	t.equals(saved.get_value("test", "marker", -1), 4, "immediate teardown flushes queued final edit")
	saved.load("user://settings_worker_test_1.cfg")
	t.equals(saved.get_value("test", "marker", -1), 6, "next slot retains its own final edit")
	t.check(not FileAccess.file_exists("user://settings_worker_test_0.cfg.pending"), "atomic save leaves no partial file")
	DirAccess.remove_absolute("user://settings_worker_test_0.cfg")
	DirAccess.remove_absolute("user://settings_worker_test_1.cfg")
	quit(t.finish())
