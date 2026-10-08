extends SceneTree

class FixtureSaves extends "res://scripts/tank_saves.gd":
	func _slot_dir(_slot: int) -> String:
		return "user://smoke_save_invalidation_archive"


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_save_invalidation_archive")
	var saves := FixtureSaves.new()
	var path: String = saves.state_path(1)
	var backup: String = saves.state_backup_path(1)
	t.equals(saves.write_text_atomic(path, "previous exact state"), OK, "fixture previous state written")
	t.equals(saves.write_text_atomic(path, "current exact state"), OK, "fixture current state written")
	saves.clear_active_state()
	t.check(not FileAccess.file_exists(path), "incompatible current state cannot be loaded")
	t.check(not FileAccess.file_exists(backup), "incompatible backup cannot be loaded")
	var archives: PackedStringArray = DirAccess.get_directories_at(saves.slot_dir(1).path_join("invalidated"))
	t.check(not archives.is_empty(), "recovery archive exists")
	var found: bool = false
	for archive in archives:
		var directory: String = saves.slot_dir(1).path_join("invalidated").path_join(archive)
		if FileAccess.get_file_as_string(directory.path_join("state.json")) == "current exact state":
			t.equals(FileAccess.get_file_as_string(directory.path_join("state.json.bak")),
				"previous exact state", "both states are preserved byte for byte")
			found = true
	t.check(found, "current state is recoverable")
	saves.clear_active_state()
	t.equals(DirAccess.get_directories_at(saves.slot_dir(1).path_join("invalidated")).size(),
		archives.size(), "empty invalidation does not create another archive")
	saves.free()
	quit(t.finish())
