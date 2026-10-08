extends SceneTree


func _initialize() -> void:
	var expected: String = OS.get_environment("GODOT_DEV_SCRATCH_NAME")
	var actual: String = OS.get_user_data_dir().simplify_path()
	if expected.is_empty() or actual.get_file() != expected:
		push_error("Isolation refused: expected %s, actual %s" % [expected, actual])
		quit(1)
		return
	print("[dev_run] verified user data: ", actual)
	quit(0)
