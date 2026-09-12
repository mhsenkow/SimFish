extends SceneTree

# Pins the mobile chrome contract:
#   * SafeArea converts a device cutout into viewport-space insets, clamps
#     bogus values, and is the single source of truth (mobile_hud delegates).
#   * Every HUD edge in main.gd feeds through _safe_pad(), so a notch pushes
#     the stats bar, footer, rail and side panels inward instead of under it.
#   * Touch targets are sized from physical inches, not from the render
#     resolution, so a 1536 px viewport stretched onto a phone still yields a
#     ~7 mm button.

func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	# ---- SafeArea ------------------------------------------------------------
	SafeArea.clear_test_override()
	TestSupport.check(failed, SafeArea.insets(null) == SafeArea.ZERO, "null viewport -> zero insets")

	SafeArea.set_test_override(Vector4(0.0, 47.0, 0.0, 34.0))
	var pad: Vector4 = SafeArea.insets(root)
	TestSupport.check(failed, is_equal_approx(pad.y, 47.0), "override reports top inset")
	TestSupport.check(failed, is_equal_approx(pad.w, 34.0), "override reports bottom inset")

	# Negative insets are nonsense — a device that reports them must not be
	# able to pull chrome off-screen.
	SafeArea.set_test_override(Vector4(-20.0, -5.0, -1.0, -9.0))
	var neg: Vector4 = SafeArea.insets(root)
	TestSupport.check(failed, neg.x >= 0.0 and neg.y >= 0.0 and neg.z >= 0.0 and neg.w >= 0.0,
		"negative insets clamped to zero")

	SafeArea.set_test_override(Vector4(10.0, 20.0, 30.0, 40.0))
	var r: Rect2 = SafeArea.rect(root)
	var view: Vector2 = root.get_visible_rect().size
	TestSupport.check(failed, is_equal_approx(r.position.x, 10.0) and is_equal_approx(r.position.y, 20.0),
		"safe rect origin follows insets")
	TestSupport.check(failed, is_equal_approx(r.size.x, view.x - 40.0), "safe rect width excludes L+R")
	TestSupport.check(failed, is_equal_approx(r.size.y, view.y - 60.0), "safe rect height excludes T+B")

	# The cap keeps one cutout from eating the whole screen even if the
	# platform hands back garbage.
	TestSupport.check(failed, SafeArea.MAX_INSET_FRACTION > 0.0 and SafeArea.MAX_INSET_FRACTION <= 0.25,
		"inset cap is a sane fraction")

	# ---- main.gd routes every edge through the pad ---------------------------
	var src: String = FileAccess.get_file_as_string("res://scripts/main.gd")
	TestSupport.check(failed, src.contains("func _safe_pad()"), "main exposes _safe_pad()")
	TestSupport.check(failed, src.contains("func _apply_footer_layout()"),
		"footer geometry is re-appliable on resize")
	TestSupport.check(failed, src.contains("_apply_footer_layout()\n\t_apply_panel_layout()"),
		"resize handler re-lays the footer")
	for marker in ["stats_bar.offset_top = 4.0 + pad.y",
			"footer_bar.offset_bottom = -pad.w",
			"left_cluster.offset_top = 6.0 + pad.y"]:
		TestSupport.check(failed, src.contains(marker), "safe-area applied: %s" % marker)

	# The tank shelf is the first screen on a phone; it must inset too.
	var menu: String = FileAccess.get_file_as_string("res://scripts/tank_menu.gd")
	TestSupport.check(failed, menu.contains("SafeArea.insets(get_viewport())"),
		"tank menu reads the safe area")
	TestSupport.check(failed, menu.contains("- pad.x - pad.z"),
		"card grid divides usable width, not raw viewport width")

	# mobile_hud must not keep its own copy of the notch maths.
	var mh: String = FileAccess.get_file_as_string("res://scripts/mobile_hud.gd")
	TestSupport.check(failed, not mh.contains("DisplayServer.get_display_safe_area()"),
		"mobile_hud delegates safe area to SafeArea")
	TestSupport.check(failed, mh.contains("SafeArea.rect("), "mobile_hud reads shared safe rect")

	# ---- Physical touch targets ---------------------------------------------
	TestSupport.check(failed, PanelTheme.MIN_TOUCH_INCHES >= 0.25,
		"touch floor is at least ~6.4 mm")
	# On desktop there is no floor, so touch_size() is the identity.
	if not PanelTheme.is_touch_device():
		TestSupport.check(failed, is_equal_approx(PanelTheme.min_touch_px(root), 0.0),
			"desktop has no touch floor")
		TestSupport.check(failed, is_equal_approx(PanelTheme.touch_size(root, 48.0), 48.0),
			"desktop button size unchanged")
	TestSupport.check(failed, PanelTheme.touch_size(root, 48.0) >= 48.0,
		"touch sizing never shrinks a control")
	# The cap has to bound growth, otherwise a mis-reported DPI blows up the HUD.
	TestSupport.check(failed, PanelTheme.touch_size(root, 48.0) <= 48.0 * 2.4 + 0.001,
		"touch growth is capped")
	# Rail gutter must clear the (possibly grown) rail button.
	var inset: float = PanelTheme.rail_chrome_inset(root)
	TestSupport.check(failed, inset >= PanelTheme.rail_button_size(root),
		"rail chrome inset clears the rail button")
	TestSupport.check(failed, is_equal_approx(PanelTheme.rail_chrome_inset(),
			PanelTheme.RAIL_WIDTH + PanelTheme.EDGE_MARGIN + PanelTheme.RAIL_CLEARANCE),
		"no-arg rail inset keeps the desktop constant")

	SafeArea.clear_test_override()
	TestSupport.check(failed, SafeArea.insets(root) == SafeArea.ZERO or PanelTheme.is_touch_device(),
		"override cleanly cleared")

	if failed.is_empty():
		print("[smoke] mobile_chrome OK")
		quit(0)
	else:
		for f in failed:
			push_error("[smoke] FAIL: %s" % f)
		print("[smoke] mobile_chrome FAILED (%d)" % failed.size())
		quit(1)
