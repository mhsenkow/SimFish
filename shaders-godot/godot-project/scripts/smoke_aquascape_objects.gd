extends SceneTree

const ObjectMeshes := preload("res://scripts/aquascape_object_meshes.gd")

# Object tool: mesh spawn + click must not be stolen by hardscape drag.
func _initialize() -> void:
	await process_frame
	var w: Node3D = load("res://scripts/smoke_aquascape_stub.gd").new() as Node3D
	w.name = "SmokeObjectStub"
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

	ctrl.set_tool("object")
	ctrl.selected_object_id = "boulder"
	if ctrl.begin_drag(Vector2(400, 300)):
		push_error("[smoke_aquascape_objects] object tool must not begin hardscape drag")
		quit(1)
		return

	ctrl.set_tool("stone")
	if not ctrl.begin_drag(Vector2(400, 300)):
		pass  # ok — no hardscape to pick yet

	var fp: Vector3 = ObjectMeshes.footprint("castle", {"towers": 6, "height": 9})
	if fp.y < 1.0:
		push_error("[smoke_aquascape_objects] castle footprint height too small")
		quit(1)
		return

	var castle: Node3D = ObjectMeshes.spawn("castle", {"towers": 6, "height": 9})
	if castle.get_child_count() < 3:
		push_error("[smoke_aquascape_objects] castle mesh too sparse")
		quit(1)
		return

	print("[smoke] aquascape object meshes OK")
	quit(0)
