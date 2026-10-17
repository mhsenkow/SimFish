extends SceneTree

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_photo_framing")
	var clock: Node = load("res://scripts/day_timeline.gd").new()
	root.add_child(clock)
	(clock as Control).size = Vector2(300, 36)
	clock.call("set_clock", 0.5, "Day 3 · dusk")
	t.check(is_equal_approx(float(clock.get("phase")), 0.5), "clock tracks dusk")
	t.check(String(clock.get("caption")) == "Day 3 · dusk", "clock names the day")
	clock.call("set_clock", 1.1, "Day 4 · dawn")
	t.check(is_equal_approx(float(clock.get("phase")), 0.1), "phase wraps")

	var host := Node.new()
	root.add_child(host)
	host.set_script(load("res://scripts/main.gd"))
	host.set_process(false)
	var hud := Control.new()
	hud.visible = true
	var rail := Control.new()
	rail.visible = true
	var footer := PanelContainer.new()
	footer.visible = true
	host.add_child(hud)
	host.add_child(rail)
	host.add_child(footer)
	host.set("top_hud", hud)
	host.set("right_rail", rail)
	host.set("footer_bar", footer)
	host.call("_toggle_photo_mode")
	t.check(bool(host.get("_photo_framing")), "photo button opens framing")
	t.check(not hud.visible and not rail.visible and not footer.visible, "framing hides the menus")
	var strip: Node = host.get("_photo_strip")
	t.check(strip != null and (strip as CanvasItem).visible, "photo settings are on screen")
	host.call("_set_photo_chrome", false)
	t.check(not (strip as CanvasItem).visible, "photo settings can hide")
	var reveal: Node = host.get("_photo_reveal")
	t.check(reveal != null and (reveal as CanvasItem).visible, "a control remains to bring settings back")
	host.call("_toggle_photo_mode")
	t.check(not bool(host.get("_photo_framing")), "photo button leaves framing")
	t.check(hud.visible and rail.visible and footer.visible, "menus return")
	var cfg: Node = host.call("_cfg")
	t.check(cfg != null and not bool(cfg.get("photo_handheld")), "framing does not leave the blur on")

	var mhud: Control = load("res://scripts/mobile_hud.gd").new()
	root.add_child(mhud)
	mhud.call("_build_action_row")
	mhud.call("set_immersive_mode", false)
	var build_row: Control = mhud.get("_build_row") as Control
	t.check(build_row != null and not build_row.visible, "build row stays hidden outside aquascape mode")
	mhud.call("set_aquascape_mode", true)
	t.check(build_row.visible, "build row shows in aquascape mode")
	var first_tool: Button = build_row.get_child(0) as Button
	t.check(first_tool != null and first_tool.text.contains("Sculpt"), "build tools carry readable labels")
	mhud.call("set_aquascape_mode", false)
	mhud.call("set_immersive_mode", false)
	t.check(not build_row.visible, "leaving immersive mode keeps build row hidden when not sculpting")
	mhud.free()

	host.free()
	clock.free()
	quit(t.finish())
