extends SceneTree

# Exercise the actual container floors, not just requested panel sizes: an
# oversized child can move the header close outside a small viewport.
func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_panel_responsive")
	root.content_scale_size = Vector2i(900, 600)
	await process_frame
	var library_script: GDScript = load("res://scripts/library_panel.gd")
	var library: PanelContainer = library_script.new()
	root.add_child(library)
	library.show()
	library.position = Vector2(140, 60)
	await _settle()
	library.size = Vector2(558, 476)
	await _settle()
	t.check(library.size.x <= 558.0, "library content fits the narrow modal width")
	t.check(library.size.y <= 476.0, "library content fits the work area height: %s" % library.size)
	var close: Button = PanelTheme.find_header_close(library)
	t.check(close != null and Rect2(Vector2.ZERO, Vector2(900, 600)).encloses(close.get_global_rect()),
		"library close stays entirely on screen")
	for node in library.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text in ["Pin to Global", "Spawn in Tank", "Share strain (copy code)", "Import strain (paste code)"]:
			t.check(library.get_global_rect().encloses(button.get_global_rect()),
				"library action stays visible: %s" % button.text)
	var preview: Control = library.get("_preview_column")
	var details: VBoxContainer = library.get("_detail_body")
	t.check(preview.get_parent() == details, "narrow library puts preview inside scrolling details")
	root.content_scale_size = Vector2i(1536, 864)
	await _settle()
	t.check(preview.get_parent() == library.get("_body"), "wide library restores its gallery columns")
	root.content_scale_size = Vector2i(900, 600)
	await _settle()
	t.check(preview.get_parent() == details, "resizing back restores compact details")
	library.queue_free()
	await process_frame

	var adopt_script: GDScript = load("res://scripts/adopt_panel.gd")
	var adopt: PanelContainer = adopt_script.new()
	root.add_child(adopt)
	adopt.show()
	adopt.call("_regenerate")
	adopt.position = Vector2(231, 118)
	await _settle()
	adopt.size = Vector2(378, 360)
	await _settle()
	t.check(adopt.size.y <= 360.0, "arrival cards cannot force the modal over the footer: %s" % adopt.size)
	var arrivals := adopt.find_child("Arrivals", true, false) as ScrollContainer
	t.check(arrivals != null and arrivals.get_v_scroll_bar().max_value > arrivals.size.y,
		"overflowing arrival cards scroll")
	for node in adopt.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == "Reroll":
			t.check(adopt.get_global_rect().encloses(button.get_global_rect()), "Reroll stays inside the modal")
	adopt.call("_regenerate")
	t.equals((adopt.get("_cards_container") as VBoxContainer).get_child_count(), 3,
		"reroll replaces cards immediately without a temporary doubled layout")
	adopt.queue_free()
	await process_frame
	quit(t.finish())

func _settle() -> void:
	for i in 4:
		await process_frame
