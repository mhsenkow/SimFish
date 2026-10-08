extends SceneTree

# Run through scripts/dev_run.sh; fixture slots live only in its scratch data.
func _initialize() -> void:
	await process_frame
	root.get_node("TankConfig").set("capture_mode", true)
	var prefs := ConfigFile.new()
	prefs.set_value("app", "first_launch_done", true)
	prefs.save("user://global_prefs.cfg")
	var saves: Node = root.get_node("TankSaves")
	for title in ["Quiet Garden", "Iwagumi stone garden", "A very long aquarium name with a thriving shrimp colony"]:
		var slot: int = saves.new_tank(title)
		var photo: String = OS.get_environment("MENU_CAPTURE_THUMB")
		if title == "Quiet Garden" and not photo.is_empty():
			var img: Image = preload("res://scripts/tank_thumbnail.gd").load_image(photo)
			preload("res://scripts/tank_thumbnail.gd").save_image(img, saves.thumbnail_path(slot))
		elif title == "Iwagumi stone garden" and not photo.is_empty():
			# Shelf-only fixture: visited legacy slot lacking a thumbnail.
			saves.write_text_atomic(saves.state_path(slot), '{"sim":{}}')
	var out: String = OS.get_environment("MENU_CAPTURE_OUT")
	if out.is_empty():
		out = OS.get_environment("GODOT_DEV_OUT_ROOT") + "/menu"
	DirAccess.make_dir_recursive_absolute(out)
	var menu: Control = load("res://tank_menu.tscn").instantiate()
	root.add_child(menu)
	var sizes: Array[Vector2i] = [Vector2i(1152, 648), Vector2i(900, 600), Vector2i(390, 844)]
	if OS.get_environment("MENU_CAPTURE_PHONE_ONLY") == "1":
		sizes = [Vector2i(390, 844)]
	for dimensions in sizes:
		root.content_scale_size = dimensions
		DisplayServer.window_set_size(dimensions)
		await _settle()
		await _capture(out, "shelf_%dx%d" % [dimensions.x, dimensions.y])
		var picker: Control = load("res://scripts/scenario_picker.gd").new()
		menu.add_child(picker)
		await _settle()
		await _capture(out, "templates_%dx%d" % [dimensions.x, dimensions.y])
		for button in picker.find_children("*", "Button", true, false):
			if button.text == "Details":
				button.toggled.emit(true)
				await _settle()
				await _capture(out, "template_details_%dx%d" % [dimensions.x, dimensions.y])
				button.toggled.emit(false)
				break
		for b in picker.find_children("*", "Button", true, false):
			if String(b.text).begins_with("More") or String(b.text).begins_with("Browse"):
				b.pressed.emit()
				break
		await _settle()
		await _capture(out, "all_templates_%dx%d" % [dimensions.x, dimensions.y])
		picker.free()
		menu.get_node("Scroll").hide()
		menu.get_node("EmptyHero").show()
		menu.call("_build_empty_hero")
		menu.call("_apply_responsive_layout")
		await _settle()
		await _capture(out, "empty_%dx%d" % [dimensions.x, dimensions.y])
		menu.call("_refresh")
	menu.free()
	quit()

func _settle() -> void:
	for i in 8:
		await process_frame
	await create_timer(0.3).timeout

func _capture(out: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + label + ".png")
	print("[menu_capture] ", label)
