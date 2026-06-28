extends SceneTree

# Palette wiring + tool coverage after the tabbed aquascape UI refactor.
func _initialize() -> void:
	await process_frame
	var w: Node3D = load("res://scripts/smoke_aquascape_stub.gd").new() as Node3D
	w.name = "SmokeAquascapeUIStub"
	root.add_child(w)
	var hs := Node3D.new()
	hs.name = "Hardscape"
	w.add_child(hs)

	var host := Node.new()
	host.name = "SmokeHost"
	host.set_script(load("res://scripts/smoke_aquascape_ui_host.gd"))
	root.add_child(host)

	var cam := Camera3D.new()
	cam.name = "SmokeCam"
	root.add_child(cam)

	var palette := PanelContainer.new()
	palette.name = "AquascapeToolPalette"
	root.add_child(palette)
	await process_frame

	var ctrl := AquascapeController.new()
	ctrl.setup(host, cam, w, palette)
	await process_frame

	if palette.get_child_count() == 0:
		push_error("[smoke_aquascape_ui] palette empty after build")
		quit(1)
		return

	var missing: Array[String] = []
	for key in AquascapeController.AQUASCAPE_TOOLS:
		if key == "object":
			continue
		if not ctrl._tool_buttons.has(key):
			missing.append(key)
	if not missing.is_empty():
		push_error("[smoke_aquascape_ui] palette missing tools: %s" % ", ".join(missing))
		quit(1)
		return

	ctrl.is_active = true
	for key in AquascapeController.AQUASCAPE_TOOLS:
		if key == "object":
			continue
		ctrl.set_tool(key)
		if ctrl.tool != key:
			push_error("[smoke_aquascape_ui] set_tool(%s) failed" % key)
			quit(1)
			return

	ctrl.set_tool("object")
	ctrl.selected_object_id = "castle"
	ctrl._refresh_tool_buttons()

	var palette_children_before: int = palette.get_child_count()
	ctrl._object_category = "Natural"
	ctrl._refresh_object_buttons()
	ctrl._refresh_category_buttons(ctrl._cat_row, ctrl._object_category)
	if palette.get_child_count() != palette_children_before:
		push_error("[smoke_aquascape_ui] category switch rebuilt palette")
		quit(1)
		return

	ctrl.snap_grid = false
	ctrl._refresh_tool_buttons()
	if not ctrl._toggle_buttons.has("snap"):
		push_error("[smoke_aquascape_ui] snap toggle missing")
		quit(1)
		return

	ctrl.build_finish = "glass"
	ctrl._refresh_tool_buttons()
	var finish_btn: Button = ctrl._finish_buttons.get("glass", null) as Button
	if finish_btn == null:
		push_error("[smoke_aquascape_ui] finish button missing")
		quit(1)
		return

	ctrl.build_scale = 2.0
	ctrl._build_grid.build_scale = 2.0
	ctrl._refresh_tool_buttons()
	if not ctrl._toggle_buttons["scale_2"].has_theme_stylebox_override("normal"):
		push_error("[smoke_aquascape_ui] scale choice buttons not styled")
		quit(1)
		return

	ctrl.toggle()
	if ctrl.is_active:
		push_error("[smoke_aquascape_ui] toggle off failed")
		quit(1)
		return

	ctrl.is_active = true
	ctrl.set_tool("object")
	if ctrl.allows_drag_paint():
		push_error("[smoke_aquascape_ui] object drag paint without stamp")
		quit(1)
		return
	ctrl.stamp_mode = true
	if not ctrl.allows_drag_paint():
		push_error("[smoke_aquascape_ui] object drag paint with stamp")
		quit(1)
		return
	ctrl.set_tool("line")
	if ctrl.allows_drag_paint():
		push_error("[smoke_aquascape_ui] line should not drag paint")
		quit(1)
		return
	ctrl.set_tool("block")
	if not ctrl.allows_drag_paint():
		push_error("[smoke_aquascape_ui] block should drag paint")
		quit(1)
		return

	if not ctrl._coord_label or not ctrl._status_label or not ctrl._selection_label:
		push_error("[smoke_aquascape_ui] workbench status labels missing")
		quit(1)
		return
	ctrl.update_workbench(Vector2(128, 128))
	if ctrl._coord_label.text.is_empty():
		push_error("[smoke_aquascape_ui] coord label empty")
		quit(1)
		return

	ctrl.ortho_move = true
	ctrl.gumball_enabled = true
	ctrl._refresh_tool_buttons()
	if not ctrl._toggle_buttons.has("ortho") or not ctrl._toggle_buttons.has("gumball"):
		push_error("[smoke_aquascape_ui] workbench snap toggles missing")
		quit(1)
		return

	ctrl.is_active = false

	print("[smoke] aquascape UI palette + tool wiring OK")
	quit(0)
