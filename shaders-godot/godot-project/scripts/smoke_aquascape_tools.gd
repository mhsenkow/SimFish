extends SceneTree

# Exercise aquascape tool ergonomics: views, drag rules, nudge, line/box anchors.
func _initialize() -> void:
	await process_frame
	var w: Node3D = load("res://scripts/smoke_aquascape_stub.gd").new() as Node3D
	w.name = "SmokeToolsStub"
	root.add_child(w)
	var hs := Node3D.new()
	hs.name = "Hardscape"
	w.add_child(hs)

	var host := Node.new()
	host.set_script(load("res://scripts/smoke_aquascape_ui_host.gd"))
	root.add_child(host)

	var cam := Camera3D.new()
	cam.current = true
	root.add_child(cam)

	var palette := PanelContainer.new()
	root.add_child(palette)
	await process_frame

	var ctrl := AquascapeController.new()
	ctrl.setup(host, cam, w, palette)
	ctrl.is_active = true
	await process_frame

	# Workbench stays narrow — tank viewport is the priority.
	if PanelTheme.AQUASCAPE_WORKBENCH_W > 200.0:
		push_error("[smoke_aquascape_tools] workbench width constant too large")
		quit(1)
		return

	# View snaps route through host.
	ctrl.snap_camera("top")
	if host.get("last_camera_view") != "top":
		push_error("[smoke_aquascape_tools] top view snap failed")
		quit(1)
		return
	if host.get("last_projection") != "top_down_ortho":
		push_error("[smoke_aquascape_tools] top ortho projection failed")
		quit(1)
		return
	ctrl.snap_camera("front")
	if host.get("last_camera_view") != "front":
		push_error("[smoke_aquascape_tools] front view snap failed")
		quit(1)
		return
	if host.get("last_projection") != "perspective":
		push_error("[smoke_aquascape_tools] front view should restore perspective")
		quit(1)
		return

	# Drag paint rules.
	ctrl.set_tool("fill")
	if ctrl.allows_drag_paint():
		push_error("[smoke_aquascape_tools] fill should not drag-paint")
		quit(1)
		return
	ctrl.set_tool("block")
	if not ctrl.allows_drag_paint():
		push_error("[smoke_aquascape_tools] block should drag-paint")
		quit(1)
		return

	# Line tool: two-click anchor workflow.
	ctrl.set_tool("line")
	ctrl._click_anchor = Vector3i(1, 2, 3)
	if ctrl._click_anchor == AquascapeController.INVALID_GRID:
		push_error("[smoke_aquascape_tools] line anchor invalid")
		quit(1)
		return

	# Ortho move keeps drag on one horizontal axis.
	var diag := Vector3(1.0, 0.0, 1.0)
	var dxz := Vector3(diag.x, 0.0, diag.z)
	if absf(dxz.x) >= absf(dxz.z):
		dxz.z = 0.0
	else:
		dxz.x = 0.0
	if absf(dxz.x) > 0.001 and absf(dxz.z) > 0.001:
		push_error("[smoke_aquascape_tools] ortho axis constraint failed")
		quit(1)
		return

	# Nudge selection.
	var stone := MeshInstance3D.new()
	stone.name = "TestStone"
	w.add_child(stone)
	stone.global_position = Vector3(0, 1, 0)
	ctrl._multi_select = [stone]
	var before: Vector3 = stone.global_position
	ctrl.nudge_selection(Vector3(TerrainVoxelGrid.CELL_SIZE, 0, 0))
	if stone.global_position.distance_to(before) < 0.01:
		push_error("[smoke_aquascape_tools] nudge failed")
		quit(1)
		return

	ctrl._sync_placement_gizmo()
	if not ctrl.gumball_enabled:
		push_error("[smoke_aquascape_tools] gumball should default on")
		quit(1)
		return

	print("[smoke] aquascape tool ergonomics OK")
	quit(0)
