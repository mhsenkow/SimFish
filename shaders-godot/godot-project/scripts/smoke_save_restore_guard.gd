extends SceneTree

class SnapshotStub extends Node:
	var calls: int = 0
	func save_state() -> Dictionary:
		calls += 1
		return {}

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_save_restore_guard")
	var manager: Script = load("res://scripts/save_manager.gd")
	var host := Node.new()
	root.add_child(host)
	host.set_script(load("res://scripts/main.gd"))
	host.set_process(false)
	var sim := SnapshotStub.new()
	host.add_child(sim)
	host.call("_show_incompatible_save_prompt", "", {"refused": "future", "reason": "Newer save"})
	t.check(bool(host.call("is_save_restore_blocked")), "unresolved restore blocks autosave")
	t.equals(manager.save_active(host, sim, null, null, 2.0), 2.0, "refused save retains pending speed")
	t.equals(sim.calls, 0, "refused save never snapshots replacement world")
	host.call("_save_thumbnail", "user://guard_should_not_write.png")
	t.equals(host.get("_thumbnail_pending_path"), "", "refused save never queues replacement photo")
	for child in host.get_children():
		if child is AcceptDialog:
			child.free()
	host.set("_save_restore_blocked", false)
	host.call("_show_corrupt_save_prompt", "user://no_such_guard_state.json")
	t.check(bool(host.call("is_save_restore_blocked")), "corrupt save blocks replacement world")
	host.set("_save_restore_blocked", false)
	host.call("_save_thumbnail", "user://guard_queued.png")
	t.equals(host.get("_thumbnail_pending_path"), "user://guard_queued.png", "resolved restore permits a new photo")
	host.free()
	quit(t.finish())
