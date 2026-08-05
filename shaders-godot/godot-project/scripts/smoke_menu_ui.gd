extends SceneTree

# Headless compile+run check for tank shelf UI and scenario picker modal.


func _initialize() -> void:
	await process_frame
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

	if menu.get_node_or_null("TopBarShell") == null:
		push_error("[smoke_menu_ui] TopBarShell missing")
		quit(1)
		return

	var picker := ScenarioPicker.new()
	menu.add_child(picker)
	await process_frame
	await process_frame
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

	print("[smoke_menu_ui] tank menu + scenario picker OK")
	quit(0)
