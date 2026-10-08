extends SceneTree

# Headless compile+run check for tank shelf UI and scenario picker modal.


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_menu_ui")
	var menu_scene: PackedScene = load("res://tank_menu.tscn")
	if menu_scene == null:
		push_error("[smoke_menu_ui] failed to load tank_menu.tscn")
		quit(1)
		return
	var menu: Control = menu_scene.instantiate() as Control
	if menu == null:
		push_error("[smoke_menu_ui] failed to instantiate tank menu")
		quit(1)
		return
	root.add_child(menu)
	await process_frame
	await process_frame
	# A long saved name must not force the shelf wider than a phone.
	var grid: GridContainer = menu.get_node("Scroll/Grid")
	grid.add_child(menu.call("_make_card", {"slot": 999,
		"name": "A very long aquarium name with a thriving shrimp colony"}))

	if menu.get_node_or_null("TopBarShell") == null:
		push_error("[smoke_menu_ui] TopBarShell missing")
		quit(1)
		return

	var picker := ScenarioPicker.new()
	menu.add_child(picker)
	await process_frame
	await process_frame
	for dimensions in [Vector2i(1152, 648), Vector2i(390, 844), Vector2i(900, 600)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		for i in 6:
			await process_frame
		var viewport_rect := Rect2(Vector2.ZERO, Vector2(dimensions))
		var primary: Button = menu.get("_new_btn")
		t.check(viewport_rect.encloses(primary.get_global_rect()),
			"New tank stays on screen at %s" % dimensions)
		var close: Button = PanelTheme.find_header_close(picker)
		t.check(close != null and viewport_rect.encloses(close.get_global_rect()),
			"template close stays on screen at %s" % dimensions)
		var panel: PanelContainer = picker.get("_panel")
		t.check(viewport_rect.encloses(panel.get_global_rect()),
			"template panel fits at %s" % dimensions)
		var template_grid: GridContainer = picker.get("_template_grid")
		t.equals(template_grid.columns, 1 if dimensions.x < 640 else (3 if dimensions.x >= 1000 else 2),
			"template columns adapt after resizing")
		var metrics: Dictionary = menu.call("_grid_metrics")
		t.check(float(metrics.card_w) <= dimensions.x - 32,
			"shelf card floor fits the viewport")
	var browse: Button = null
	for child in picker.find_children("*", "Button", true, false):
		if String(child.text).begins_with("Browse"):
			browse = child
			break
	if t.check(browse != null, "all templates remain discoverable"):
		browse.pressed.emit()
		t.equals((picker.get("_template_grid") as GridContainer).get_child_count(),
			ScenarioPicker.SCENARIOS.size(), "browse shows every template exactly once")
		browse.pressed.emit()
		t.equals((picker.get("_template_grid") as GridContainer).get_child_count(),
			3, "recommended view restores without duplicate cards")
		var rows: Array = picker.get("_size_rows")
		var caption: String = rows[0][0].text
		picker.call("_set_size_scale", 1.2)
		t.check(rows[0][0].text != caption,
			"size selection updates captions after switching template views")
		picker.call("_set_size_scale", 1.0)
	picker.queue_free()
	await process_frame

	# Couch focus helper must exist for modal focus jump.
	var pt_src: String = (load("res://scripts/panel_theme.gd") as Script).source_code
	if not pt_src.contains("grab_couch_focus") or not pt_src.contains("schedule_couch_focus"):
		push_error("[smoke_menu_ui] PanelTheme missing grab/schedule_couch_focus")
		quit(1)
		return
	var sp_src: String = (load("res://scripts/scenario_picker.gd") as Script).source_code
	if not sp_src.contains("schedule_couch_focus"):
		push_error("[smoke_menu_ui] ScenarioPicker must schedule couch focus")
		quit(1)
		return

	menu.queue_free()
	await process_frame
	quit(t.finish())
