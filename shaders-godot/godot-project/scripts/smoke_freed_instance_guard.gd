extends SceneTree

# Lint: `is` must never run before its own is_instance_valid guard.
#
# THE BUG. GDScript raises
#   "Left operand of 'is' is a previously freed instance"
# when `x is SomeType` is evaluated on a freed Object. Thirty call sites
# wrote the guard in the wrong order:
#
#   if partner != null and ... and partner is Node3D \
#           and is_instance_valid(partner as Node3D):
#
# `and` short-circuits left to right, so `is` ran on the dead reference and
# threw before the validity test it was sitting next to could save it. A
# bonded mate dying is routine - fish live about four minutes and bonds
# outlive them - so this fired constantly.
#
# Worse were three guards written specifically to DETECT a freed node:
#
#   if state is Node and not is_instance_valid(state):
#       return null
#
# which throws on precisely the input they exist to catch, so they could
# never once do their job.
#
# This is a lint rather than a unit test because the failure is a source
# ORDERING, invisible to any assertion about behaviour: the crash only
# happens when a real object is freed at the wrong moment.

const SKIP_FILES: Array[String] = ["smoke_freed_instance_guard.gd"]


func _init() -> void:
	var t := TestSupport.Suite.new("freed_instance_guard")
	var dir := DirAccess.open("res://scripts")
	if dir == null:
		t.fail("cannot open res://scripts")
		quit(t.finish())
		return
	var offenders: Array[String] = []
	var scanned: int = 0
	dir.list_dir_begin()
	while true:
		var fn: String = dir.get_next()
		if fn == "":
			break
		if not fn.ends_with(".gd") or fn in SKIP_FILES:
			continue
		scanned += 1
		offenders.append_array(_scan("res://scripts/" + fn, fn))
	dir.list_dir_end()
	t.check(scanned > 100, "scanned the script directory (%d files)" % scanned)
	for o in offenders:
		t.fail(o)
	t.check(offenders.is_empty(),
		"no `is` runs before its own is_instance_valid guard")
	quit(t.finish())


func _scan(path: String, short_name: String) -> Array[String]:
	var out: Array[String] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var lines: PackedStringArray = f.get_as_text().split("\n")
	f.close()
	var i: int = 0
	while i < lines.size():
		var start: int = i
		var stmt: String = lines[i]
		# Join line continuations - the original bug spanned two lines.
		while stmt.strip_edges().ends_with("\\") and i + 1 < lines.size():
			i += 1
			stmt = stmt.strip_edges().trim_suffix("\\") + " " + lines[i].strip_edges()
		var code: String = stmt.strip_edges()
		if not code.begins_with("#") and code.contains(" is ") \
				and code.contains("is_instance_valid("):
			var vi: int = code.find("is_instance_valid(")
			# Any ` is ` appearing BEFORE the guard on the same statement.
			var seg: String = code.substr(0, vi)
			if _has_type_test(seg):
				out.append("%s:%d  `is` before is_instance_valid: %s"
					% [short_name, start + 1, code.left(96)])
		i += 1
	return out


# A ` is Type` test, ignoring `is_instance_valid` itself and `is_empty` etc.
func _has_type_test(seg: String) -> bool:
	var idx: int = 0
	while true:
		idx = seg.find(" is ", idx)
		if idx < 0:
			return false
		var rest: String = seg.substr(idx + 4).strip_edges()
		if rest.length() > 0 and rest[0] == rest[0].to_upper() \
				and rest[0] != "_" and not rest.begins_with("not "):
			return true
		idx += 4
	return false
