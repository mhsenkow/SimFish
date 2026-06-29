extends SceneTree

# ENGINEERING_EXCELLENCE #42 — single entry runs all smoke_*.gd scripts headless.


const SKIP: Array[String] = [
	"smoke_runner.gd",
	"smoke_llama_macos.gd",
]


func _initialize() -> void:
	await process_frame
	var godot_bin: String = OS.get_executable_path()
	var project_path: String = ProjectSettings.globalize_path("res://")
	var scripts_dir: String = project_path.path_join("scripts")
	var dir := DirAccess.open(scripts_dir)
	if dir == null:
		push_error("[smoke_runner] cannot open scripts dir")
		quit(1)
		return
	var smokes: Array[String] = []
	dir.list_dir_begin()
	var fn: String = dir.get_next()
	while fn != "":
		if fn.begins_with("smoke_") and fn.ends_with(".gd") and fn not in SKIP:
			smokes.append(fn)
		fn = dir.get_next()
	dir.list_dir_end()
	smokes.sort()
	var failed: Array[String] = []
	var passed: int = 0
	for script_name in smokes:
		var rel: String = "res://scripts/%s" % script_name
		print("[smoke_runner] RUN ", script_name)
		var args: PackedStringArray = PackedStringArray([
			"--headless", "--path", project_path, "--script", rel,
		])
		var output: Array = []
		var code: int = OS.execute(godot_bin, args, output, true, false)
		if code != 0:
			failed.append(script_name)
			for line in output:
				push_error(str(line))
		else:
			passed += 1
	print("[smoke_runner] done: %d passed, %d failed, %d skipped" % [
		passed, failed.size(), SKIP.size()])
	if failed.is_empty():
		quit(0)
	else:
		for f in failed:
			push_error("[smoke_runner] FAIL " + f)
		quit(1)
