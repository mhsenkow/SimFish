extends SceneTree

# Pins the side-panel transition contract.
#
# Panels used to pop with a bare `visible = not visible`. They now fade and
# settle, which introduces a window where a panel is still `visible` but is on
# its way out. Everything that asks "is this open?" has to go through
# is_panel_open(), or a second Escape / a click-outside lands on a panel that
# is already closing and re-opens it.


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	var cfg: Node = root.get_node_or_null("TankConfig")
	var restore_reduced: bool = cfg != null and bool(cfg.get("reduced_motion"))
	if cfg != null:
		cfg.set("reduced_motion", false)
	AccessibilityRuntime.reset_cache_for_test()

	var panel := PanelContainer.new()
	panel.size = Vector2(320, 480)
	panel.visible = false
	root.add_child(panel)

	# ---- Open ---------------------------------------------------------------
	_assert(failed, not PanelTheme.is_panel_open(panel), "hidden panel is not open")
	PanelTheme.transition_panel(panel, true)
	_assert(failed, panel.visible, "open shows the panel immediately")
	_assert(failed, PanelTheme.is_panel_open(panel), "open panel reports open")
	_assert(failed, panel.mouse_filter == Control.MOUSE_FILTER_STOP,
		"open panel takes input")
	await _settle(PanelTheme.PANEL_FADE_IN_S)
	_assert(failed, is_equal_approx(panel.modulate.a, 1.0), "fade-in reaches full alpha")
	_assert(failed, panel.scale.is_equal_approx(Vector2.ONE), "settle returns to 1:1 scale")

	# ---- Close --------------------------------------------------------------
	PanelTheme.transition_panel(panel, false)
	_assert(failed, panel.visible, "closing panel is still drawn during the fade")
	_assert(failed, not PanelTheme.is_panel_open(panel),
		"closing panel does NOT report open")
	_assert(failed, panel.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"closing panel stops eating input straight away")
	# A second close mid-fade must be inert.
	PanelTheme.transition_panel(panel, false)
	await _settle(PanelTheme.PANEL_FADE_OUT_S)
	_assert(failed, not panel.visible, "fade-out ends hidden")
	_assert(failed, is_equal_approx(panel.modulate.a, 1.0),
		"alpha is restored so the next open is not invisible")
	_assert(failed, panel.scale.is_equal_approx(Vector2.ONE), "scale restored after close")

	# ---- Re-open mid-close reverses cleanly ---------------------------------
	PanelTheme.transition_panel(panel, true)
	await _settle(PanelTheme.PANEL_FADE_IN_S)
	PanelTheme.transition_panel(panel, false)
	PanelTheme.transition_panel(panel, true)
	await _settle(PanelTheme.PANEL_FADE_OUT_S + PanelTheme.PANEL_FADE_IN_S)
	_assert(failed, panel.visible and PanelTheme.is_panel_open(panel),
		"re-open during a close wins")
	_assert(failed, is_equal_approx(panel.modulate.a, 1.0),
		"re-open during a close ends fully opaque")

	# ---- The transform must be render-only ----------------------------------
	# Control.position writes back into anchor offsets, so a position tween
	# would fight layout_side_panel(). Only modulate/scale/pivot are touched.
	var src: String = FileAccess.get_file_as_string("res://scripts/panel_theme.gd")
	var body: String = src.substr(src.find("static func transition_panel"))
	body = body.substr(0, body.find("static func layout_side_panel"))
	_assert(failed, not body.contains("position"),
		"transition never tweens Control.position (it rewrites layout offsets)")

	# ---- Reduced motion is instant ------------------------------------------
	if cfg != null:
		cfg.set("reduced_motion", true)
		AccessibilityRuntime.reset_cache_for_test()
		_assert(failed, AccessibilityRuntime.reduced_motion_enabled(),
			"reduced motion reads back from config")
		PanelTheme.transition_panel(panel, false)
		_assert(failed, not panel.visible, "reduced motion closes instantly")
		PanelTheme.transition_panel(panel, true)
		_assert(failed, panel.visible and is_equal_approx(panel.modulate.a, 1.0),
			"reduced motion opens instantly at full alpha")
		_assert(failed, not AccessibilityRuntime.allow_auto_orbit(true),
			"reduced motion refuses auto-orbit at the toggle")
		cfg.set("reduced_motion", restore_reduced)
		AccessibilityRuntime.reset_cache_for_test()

	# ---- Callers use is_panel_open(), not .visible ---------------------------
	var main_src: String = FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(failed, main_src.contains("if PanelTheme.is_panel_open(settings_panel):"),
		"Escape handler checks is_panel_open for settings")
	_assert(failed, main_src.contains("if PanelTheme.is_panel_open(render_panel):"),
		"Escape handler checks is_panel_open for render")
	_assert(failed, main_src.contains("if PanelTheme.is_panel_open(sound_panel):"),
		"Escape handler checks is_panel_open for sound")
	var uip: String = FileAccess.get_file_as_string("res://scripts/ui_panel_manager.gd")
	_assert(failed, uip.contains("PanelTheme.is_panel_open(panel)"),
		"panel manager checks is_panel_open before toggling a sibling closed")
	# A panel closed through transition_panel must also be OPENED through it —
	# a bare `visible = true` inside the out-tween gets undone by the tween's
	# completion callback a frame later.
	var uip_code: String = ""
	for line in uip.split("\n"):
		if not line.strip_edges().begins_with("#"):
			uip_code += line + "\n"
	_assert(failed, not uip_code.contains("visible = true"),
		"panel manager opens panels through transition_panel, not raw visibility")

	panel.queue_free()

	if failed.is_empty():
		print("[smoke] panel_motion OK")
		quit(0)
	else:
		for f in failed:
			push_error("[smoke] FAIL: %s" % f)
		print("[smoke] panel_motion FAILED (%d)" % failed.size())
		quit(1)


# Tweens advance on process frames; step past the animation with margin.
func _settle(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int((seconds + 0.15) * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _assert(failed: Array[String], cond: bool, label: String) -> void:
	if not cond:
		failed.append(label)
