extends SceneTree

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_save_write_queue")
	var manager: Script = load("res://scripts/save_manager.gd")
	manager.reset_for_test()
	var a: String = "user://save_queue_test/a.json"
	var b: String = "user://save_queue_test/b.json"
	manager._enqueue_async_write(a, {"marker": 1})
	manager._enqueue_async_write(b, {"marker": 2})
	manager._enqueue_async_write(a, {"marker": 3})
	manager._enqueue_async_write(b, {"marker": 4})
	manager.flush_pending_writes()
	t.equals(JSON.parse_string(FileAccess.get_file_as_string(a)), {"marker": 3.0}, "first tank retains its latest snapshot")
	t.equals(JSON.parse_string(FileAccess.get_file_as_string(b)), {"marker": 4.0}, "second tank retains its latest snapshot")
	t.equals(manager.writes_in_flight(), 0, "exit drain finishes every write")
	t.equals(manager.get("_write_task_id"), -1, "write task resources are reclaimed")
	manager._enqueue_async_write(a, {"marker": 5})
	var deadline: int = Time.get_ticks_msec() + 5000
	while manager.writes_in_flight() > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	t.equals(manager.writes_in_flight(), 0, "autoload reclaims completed saves during normal play")
	t.equals(JSON.parse_string(FileAccess.get_file_as_string(a)), {"marker": 5.0}, "normal polling persists snapshot")
	for path in [a, b, a + ".bak", b + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	quit(t.finish())
