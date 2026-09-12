extends SceneTree

# Guarded JSON input (BROAD_DIRECTIONS #6).
#
# Save files, config, the blueprint library and HTTP bodies are all outside
# our trust boundary. These assertions pin the guard's behaviour: bounded
# before parsed, typed or nothing, loud but never fatal.

const TMP_DIR := "user://safejson_smoke"


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))

	# --- Happy path ---
	var good: String = TMP_DIR + "/good.json"
	_write(good, '{"a": 1, "nested": {"b": [1,2,3]}}')
	var d: Dictionary = SafeJson.read_dict(good)
	TestSupport.check(failed, int(d.get("a", 0)) == 1, "a valid object must read back")
	TestSupport.check(failed, d.get("nested") is Dictionary, "nesting must survive")

	var arr_path: String = TMP_DIR + "/good_array.json"
	_write(arr_path, '[{"name": "x"}, {"name": "y"}]')
	var a: Array = SafeJson.read_array(arr_path)
	TestSupport.check(failed, a.size() == 2, "a valid array must read back")

	# --- Missing / empty files are "absent", not errors ---
	TestSupport.check(failed, SafeJson.read_dict(TMP_DIR + "/nope.json").is_empty(),
		"a missing file must read as empty")
	TestSupport.check(failed, SafeJson.read_array(TMP_DIR + "/nope.json").is_empty(),
		"a missing file must read as an empty array")
	TestSupport.check(failed, SafeJson.read_dict("").is_empty(),
		"an empty path must read as empty")
	var empty_path: String = TMP_DIR + "/empty.json"
	_write(empty_path, "")
	TestSupport.check(failed, SafeJson.read_dict(empty_path).is_empty(),
		"a zero-byte file must read as empty")

	# --- Malformed JSON must not throw ---
	var bad: String = TMP_DIR + "/bad.json"
	for junk in ['{"a": ', 'not json at all', '{,,}', '\\x00\\x01']:
		_write(bad, junk)
		TestSupport.check(failed, SafeJson.read_dict(bad).is_empty(),
			"malformed JSON (%s) must read as empty" % junk.substr(0, 12))

	# Godot's JSON parser is LENIENT about trailing commas — '{"a": 1,}' is
	# accepted, not rejected. Pinned deliberately: it is harmless (the result
	# is a well-formed object) but surprising, and a future engine bump that
	# tightened it would change what loads off players' disks.
	_write(bad, '{"a": 1,}')
	TestSupport.check(failed, int(SafeJson.read_dict(bad).get("a", -1)) == 1,
		"Godot accepts trailing commas; a save written with one must still load")

	# --- Type discipline: a scalar or wrong container is NOT data ---
	# This is the bug class the guard exists for: `parsed is Dictionary` was
	# missing in several readers, so a bare `5` could flow in as state.
	for scalar in ['5', '"a string"', 'true', 'null', '[1,2,3]']:
		_write(bad, scalar)
		TestSupport.check(failed, SafeJson.read_dict(bad).is_empty(),
			"JSON scalar/array (%s) must not read as an object" % scalar)
	_write(bad, '{"a": 1}')
	TestSupport.check(failed, SafeJson.read_array(bad).is_empty(),
		"a JSON object must not read as an array")

	# --- Size cap is enforced BEFORE the parse ---
	var big: String = TMP_DIR + "/big.json"
	# ~40 KiB of valid JSON, read with a 1 KiB cap.
	var filler: PackedStringArray = PackedStringArray()
	for i in 2000:
		filler.append('"k%d": %d' % [i, i])
	_write(big, "{" + ",".join(filler) + "}")
	var big_size: int = _size(big)
	TestSupport.check(failed, big_size > 1024,
		"fixture must exceed the cap under test (got %d)" % big_size)
	TestSupport.check(failed, SafeJson.read_dict(big, 1024, "smoke").is_empty(),
		"a file over the cap must be refused")
	# ...and the same file parses fine when the cap allows it, proving the
	# refusal was the cap and not a parse failure.
	TestSupport.check(failed, not SafeJson.read_dict(big, 1_048_576, "smoke").is_empty(),
		"the same file must parse when within the cap")

	# --- Bodies ---
	var body: PackedByteArray = '{"access_token": "abc"}'.to_utf8_buffer()
	TestSupport.check(failed, String(SafeJson.parse_body(body, 4096, "smoke")
			.get("access_token", "")) == "abc",
		"a valid body must parse")
	TestSupport.check(failed, SafeJson.parse_body(body, 4, "smoke").is_empty(),
		"an oversized body must be refused, not truncated")
	TestSupport.check(failed, SafeJson.parse_body(PackedByteArray(), 4096, "smoke").is_empty(),
		"an empty body must read as empty")
	TestSupport.check(failed, SafeJson.parse_body('garbage'.to_utf8_buffer(), 4096, "smoke").is_empty(),
		"a malformed body must read as empty")
	# Invalid UTF-8 must not throw.
	var invalid_utf8: PackedByteArray = PackedByteArray([0xFF, 0xFE, 0x00, 0x7B])
	TestSupport.check(failed, SafeJson.parse_body(invalid_utf8, 4096, "smoke").is_empty(),
		"invalid UTF-8 must read as empty")

	# --- Text ---
	TestSupport.check(failed, int(SafeJson.parse_text('{"n": 7}', 4096, "smoke").get("n", 0)) == 7,
		"parse_text must handle a valid object")
	TestSupport.check(failed, SafeJson.parse_text('{"n": 7}', 2, "smoke").is_empty(),
		"parse_text must honour its cap")
	TestSupport.check(failed, SafeJson.parse_text("", 4096, "smoke").is_empty(),
		"parse_text on empty input must read as empty")

	# --- NaN/Inf tokens (Godot's own stringify can emit these) ---
	# sanitize_json_text is meant to rescue them; the point here is only that
	# they never throw and never return junk.
	_write(bad, '{"x": nan, "y": inf}')
	var nan_d: Dictionary = SafeJson.read_dict(bad, SafeJson.DEFAULT_MAX_BYTES, "smoke")
	TestSupport.check(failed, nan_d is Dictionary, "NaN/Inf tokens must not throw")

	# --- Callers that were hardened still behave ---
	# The achievement mirror tolerates an "unlocked" field of the wrong type.
	var f := FileAccess.open(SteamStats.LOCAL_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string('{"version": 1, "unlocked": "not-an-array"}')
		f.close()
		var st: Dictionary = SteamStats.load_local()
		TestSupport.check(failed, st.get("unlocked") is Array,
			"load_local must return an Array even when the file lies")
		TestSupport.check(failed, (st.get("unlocked") as Array).is_empty(),
			"a non-array 'unlocked' must yield no unlocks")
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(SteamStats.LOCAL_PATH))

	# The blueprint library returns an Array for any garbage on disk.
	TestSupport.check(failed, AquascapeBlueprint.load_library() is Array,
		"load_library must always return an Array")

	_cleanup()

	quit(TestSupport.report("smoke_safe_json", failed))


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func _size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n: int = f.get_length()
	f.close()
	return n


func _cleanup() -> void:
	var abs_dir: String = ProjectSettings.globalize_path(TMP_DIR)
	var d := DirAccess.open(abs_dir)
	if d == null:
		return
	d.list_dir_begin()
	while true:
		var e: String = d.get_next()
		if e == "":
			break
		if not d.current_is_dir():
			DirAccess.remove_absolute(abs_dir + "/" + e)
	d.list_dir_end()
	DirAccess.remove_absolute(abs_dir)
