extends SceneTree

# Dev-only: extract every tr("...") literal into a CSV catalogue
# (BROAD_DIRECTIONS #14).
#
# The project uses English-as-key, so the key column IS the source string.
# Godot's own POT generator only sees scenes and a configured file list; this
# scans the scripts directly, which is where ~all of this game's UI text lives.
#
# Output: assets/i18n/strings.csv  (key,en  — add a column per locale)

const OUT_PATH := "res://assets/i18n/strings.csv"


func _initialize() -> void:
	var keys: Dictionary = {}       # key -> Array[String] of source files
	var dir := DirAccess.open("res://scripts")
	if dir == null:
		push_error("[i18n] cannot open res://scripts")
		quit(1)
		return
	dir.list_dir_begin()
	var f: String = dir.get_next()
	while f != "":
		if f.ends_with(".gd") and not f.begins_with("smoke_"):
			_scan(("res://scripts/" + f), keys)
		f = dir.get_next()
	dir.list_dir_end()

	var sorted: Array = keys.keys()
	sorted.sort()
	var out := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if out == null:
		push_error("[i18n] cannot write %s" % OUT_PATH)
		quit(1)
		return
	out.store_line("key,en")
	for k in sorted:
		out.store_line("%s,%s" % [_csv(String(k)), _csv(String(k))])
	out.close()
	print("[i18n] %d keys -> %s" % [sorted.size(), OUT_PATH])

	# Coverage: unwrapped player-facing literals still out there.
	var unwrapped: int = _count_unwrapped()
	print("[i18n] wrapped=%d  still-unwrapped .text/.tooltip_text literals=%d"
		% [sorted.size(), unwrapped])
	quit(0)


func _scan(path: String, keys: Dictionary) -> void:
	var src: String = FileAccess.get_file_as_string(path)
	if src.is_empty():
		return
	var i: int = 0
	while true:
		var at: int = src.find('tr("', i)
		if at < 0:
			break
		var start: int = at + 4
		var end: int = _closing_quote(src, start)
		if end < 0:
			i = start
			continue
		var key: String = src.substr(start, end - start)
		if not key.is_empty():
			if not keys.has(key):
				keys[key] = []
			(keys[key] as Array).append(path.get_file())
		i = end + 1


# Index of the closing quote, honouring backslash escapes.
func _closing_quote(src: String, from: int) -> int:
	var i: int = from
	while i < src.length():
		var c: String = src[i]
		if c == "\\":
			i += 2
			continue
		if c == '"':
			return i
		i += 1
	return -1


func _csv(v: String) -> String:
	if v.contains(",") or v.contains('"') or v.contains("\n"):
		return '"%s"' % v.replace('"', '""')
	return v


# How much player-facing text is still NOT wrapped. This is the number that
# should trend to zero.
func _count_unwrapped() -> int:
	var n: int = 0
	var dir := DirAccess.open("res://scripts")
	dir.list_dir_begin()
	var f: String = dir.get_next()
	while f != "":
		if f.ends_with(".gd") and not f.begins_with("smoke_"):
			var src: String = FileAccess.get_file_as_string("res://scripts/" + f)
			for line in src.split("\n"):
				if line.contains("tr(") or line.strip_edges().begins_with("#"):
					continue
				if line.contains(".text = \"") or line.contains(".tooltip_text = \""):
					n += 1
		f = dir.get_next()
	dir.list_dir_end()
	return n
