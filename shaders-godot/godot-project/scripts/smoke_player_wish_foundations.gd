extends SceneTree

# PLAYER_WISH foundations: Care dock helpers, UiIcons care labels,
# filter clog getter, status toast path assumptions.


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	_assert(failed, UiIcons.care_button_label("water", true) != "", "care water label")
	_assert(failed, UiIcons.care_tooltip("filter").contains("filter") \
			or UiIcons.care_tooltip("filter").contains("Filter") \
			or UiIcons.care_tooltip("filter").contains("Rinse"),
		"care filter tooltip")
	_assert(failed, UiIcons.CARE.has("water") and UiIcons.CARE.has("filter"),
		"CARE dict keys")

	var lines: PackedStringArray = OnboardingLegibility.cheat_sheet_lines(false)
	var joined: String = " ".join(lines)
	_assert(failed, joined.contains("Care") or joined.contains("Water change"),
		"desktop cheat sheet mentions Care")
	var mlines: PackedStringArray = OnboardingLegibility.cheat_sheet_lines(true)
	var mjoined: String = " ".join(mlines)
	_assert(failed, mjoined.contains("Care") or mjoined.contains("water change"),
		"mobile cheat sheet mentions Care")

	# SimDriver filter clog API (no full tank needed).
	var sim_script: Script = load("res://scripts/sim_driver.gd") as Script
	_assert(failed, sim_script != null, "sim_driver loads")
	# Parse-level: method exists on class via source check is fragile; instantiate
	# a bare Node with the script only if it doesn't require scene tree heavy init.
	# Instead assert the script source contains the getter we added.
	var src: String = FileAccess.get_file_as_string("res://scripts/sim_driver.gd")
	_assert(failed, src.contains("func get_filter_clog"), "get_filter_clog present")
	_assert(failed, src.contains("func do_water_change"), "do_water_change present")
	_assert(failed, src.contains("func rinse_filter"), "rinse_filter present")

	var main_src: String = FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(failed, main_src.contains("func _setup_care_dock"), "care dock setup")
	_assert(failed, main_src.contains("func _show_status_toast"), "status toast")
	_assert(failed, main_src.contains("_show_status_toast(\"Saved\")"), "autosave ceremony")
	_assert(failed, main_src.contains("OS.shell_show_in_file_manager"), "photo reveal")
	_assert(failed, main_src.contains("Reveal"), "photo toast Reveal button")

	if failed.is_empty():
		print("SMOKE_PLAYER_WISH_FOUNDATIONS_OK")
		quit(0)
	else:
		for f in failed:
			push_error(f)
		print("SMOKE_PLAYER_WISH_FOUNDATIONS_FAIL count=%d" % failed.size())
		quit(1)


func _assert(failed: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		failed.append(msg)
