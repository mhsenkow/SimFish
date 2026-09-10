extends SceneTree

# Loads every script in scripts/ so the parser reports errors for all of them.
func _initialize() -> void:
	var dir := DirAccess.open("res://scripts")
	var bad: int = 0
	var n: int = 0
	dir.list_dir_begin()
	var f: String = dir.get_next()
	while f != "":
		if f.ends_with(".gd"):
			n += 1
			var r: Resource = ResourceLoader.load("res://scripts/" + f, "Script",
				ResourceLoader.CACHE_MODE_IGNORE)
			if r == null:
				push_error("LOAD FAILED: " + f)
				bad += 1
		f = dir.get_next()
	dir.list_dir_end()
	print("[compile_check] %d scripts, %d failed" % [n, bad])
	quit(1 if bad > 0 else 0)
