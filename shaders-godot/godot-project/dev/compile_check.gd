extends SceneTree

# Fast parse/compile gate over every script in scripts/ (BROAD_DIRECTIONS #11).
#
# THE BUG THIS FIXES: the previous version treated a non-null
# ResourceLoader.load() as success. But Godot returns a non-null GDScript
# even when that script FAILED to compile — the resource loads, the
# compilation does not. So a hard parse error ("Function ... not found in
# base self") printed a SCRIPT ERROR to the console and this reported
# "N scripts, 0 failed" with exit code 0.
#
# That made the project's primary fast gate — the one AGENTS.md tells every
# contributor and agent to run after a broad edit — silently unreliable for
# exactly the error class it exists to catch.
#
# GDScript.can_instantiate() returns false for a script that failed to
# compile, so that is the check now. (reload() also reports compile status
# but returns err 22 for any script already instantiated — every autoload —
# so it is unusable here.) Verified in both directions: 1 of 407 flagged
# with a deliberately broken script present, 0 of 406 on the clean tree.


func _initialize() -> void:
	var dir := DirAccess.open("res://scripts")
	if dir == null:
		push_error("[compile_check] cannot open res://scripts")
		quit(1)
		return
	var bad: Array[String] = []
	var n: int = 0
	dir.list_dir_begin()
	var f: String = dir.get_next()
	while f != "":
		if f.ends_with(".gd"):
			n += 1
			var why: String = _check_one("res://scripts/" + f)
			if why != "":
				bad.append("%s: %s" % [f, why])
		f = dir.get_next()
	dir.list_dir_end()

	if bad.is_empty():
		print("[compile_check] %d scripts, 0 failed" % n)
		quit(0)
		return
	for b in bad:
		push_error("[compile_check] FAILED %s" % b)
	print("[compile_check] %d scripts, %d failed" % [n, bad.size()])
	quit(1)


# Empty string = fine; otherwise the reason.
func _check_one(path: String) -> String:
	var r: Resource = ResourceLoader.load(path, "Script", ResourceLoader.CACHE_MODE_IGNORE)
	if r == null:
		return "load returned null"
	var gd := r as GDScript
	if gd == null:
		# A .gd that is not a GDScript should not happen; flag rather than skip.
		return "not a GDScript resource"
	# The actual compile status. A script that parsed but failed to compile
	# still loads as a resource — this is what catches it.
	if not gd.can_instantiate():
		return "failed to compile"
	return ""
