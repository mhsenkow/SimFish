extends SceneTree

# Pins VISUAL_POLISH spine defaults so a future tweak can't silently undo
# the hero framing / room-dither / outline / chrome-off contract.


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	var main_script: Resource = load("res://scripts/main.gd")
	TestSupport.check(failed, main_script != null, "main.gd parses")

	var cfg_script: Resource = load("res://scripts/tank_config.gd")
	TestSupport.check(failed, cfg_script != null, "tank_config.gd parses")

	# Instantiate TankConfig defaults without the full autoload tree.
	var cfg: Node = (cfg_script as GDScript).new()
	TestSupport.check(failed, is_equal_approx(float(cfg.get("camera_fov")), 45.0),
			"hero FOV default is 45°")
	TestSupport.check(failed, is_equal_approx(float(cfg.get("camera_radius")), 15.5),
			"hero radius default is 15.5")
	TestSupport.check(failed, is_equal_approx(float(cfg.get("camera_pitch")), 0.18),
			"hero pitch ~10°")
	TestSupport.check(failed, is_equal_approx(float(cfg.get("dither_strength")), 0.72),
			"dither_strength lowered from 0.85")
	TestSupport.check(failed, bool(cfg.get("dither_world_lock")) == true,
			"dither_world_lock on by default")
	TestSupport.check(failed, is_equal_approx(float(cfg.get("room_dither_scale")), 0.35),
			"room dither ~35% of tank")
	TestSupport.check(failed, float(cfg.get("creature_outline_strength")) >= 0.30,
			"creature outlines on by default")
	TestSupport.check(failed, is_equal_approx(float(cfg.get("film_grain_strength")), 0.0),
			"film grain off by default")
	TestSupport.check(failed, is_equal_approx(float(cfg.get("crt_strength")), 0.0),
			"CRT off by default")
	cfg.free()

	var layout_script: GDScript = load("res://scripts/palette_layout.gd") as GDScript
	TestSupport.check(failed, layout_script != null, "palette_layout.gd loads")
	if layout_script != null:
		TestSupport.check(failed, int(layout_script.call("bank_for_index", 0)) == 0, "cool bank")
		TestSupport.check(failed, int(layout_script.call("bank_for_index", 20)) == 1, "neutral bank")
		TestSupport.check(failed, int(layout_script.call("bank_for_index", 40)) == 2, "warm bank")

	var icons_script: GDScript = load("res://scripts/ui_icons.gd") as GDScript
	TestSupport.check(failed, icons_script != null, "ui_icons.gd loads")
	if icons_script != null:
		TestSupport.check(failed, bool(icons_script.call("use_color_emoji")) == false,
				"monochrome icon language (#179)")

	if failed.is_empty():
		print("[smoke] visual_polish OK")
		quit(0)
	else:
		for f in failed:
			push_error("[smoke] FAIL: %s" % f)
		print("[smoke] visual_polish FAILED (%d)" % failed.size())
		quit(1)
