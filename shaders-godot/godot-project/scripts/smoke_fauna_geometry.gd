extends SceneTree

const Shell = preload("res://scripts/snail_shell.gd")

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_fauna_geometry")
	for shape in 6:
		var fish := Fish.new()
		root.add_child(fish)
		fish.init_genome({"tail_shape": shape, "fin_length_factor": 2.4, "finnage": 1.8, "head_proportion": 1.0})
		fish.set_process(false)
		var tail_boxes: Array[AABB] = []
		var eyes: int = 0
		for h in fish.get("_cached_meshes"):
			var parent: Node = h.batch.mmi.get_parent()
			var box: AABB = _handle_box(h)
			if parent.name in ["PecLeft", "PecRight", "DorsalPivot", "AnalPivot"]:
				t.approx(fposmod(h.custom_data.r, 1.0), 0.72,
					"%s receives the fin-flutter shader weight" % parent.name)
			if parent == fish.get("_tail_pivot"):
				tail_boxes.append(box)
			if parent == fish.get("_head_pivot") and is_equal_approx(h.local_pos.z, -2.38 * fish.adult_voxel_scale):
				eyes += 1
				t.check(absf(h.local_pos.x) + box.size.x * 0.5 > fish.adult_voxel_scale * 0.475,
					"pupil protrudes from the head surface")
		t.equals(eyes, 2, "both pupils exist")
		t.check(_connected(tail_boxes), "tail shape %d has a connected peduncle and fin membrane" % shape)
		fish.free()

	for plan in ["caridean", "crab", "lobster", "mantis"]:
		for length in [0.65, 2.0]:
			var shrimp := Shrimp.new()
			root.add_child(shrimp)
			shrimp.maturity = Shrimp.MATURITY_ADULT
			shrimp.init_genome({"body_shape": plan, "body_length_factor": length})
			shrimp.set_process(false)
			var antenna: Node3D = shrimp.get("_antenna_pivot")
			var head_z: float = shrimp.call("_head_eye_z", shrimp.adult_voxel_scale, shrimp.body_length_factor)
			t.approx(antenna.position.z, head_z - shrimp.adult_voxel_scale * 0.1,
				"%s antennae follow head length %.2f" % [plan, length])
			shrimp.free()

	var library_script: GDScript = load("res://scripts/library_panel.gd")
	var library: PanelContainer = library_script.new()
	for shape in ["trochus", "tower", "ramshorn", "turbo"]:
		var g: Dictionary = {"shell_shape": shape, "spire_height": 2.0, "whorl_count": 5}
		var boxes: Array[AABB] = []
		var host := Node3D.new()
		Shell.build(host, g, func(_parent: Node3D, pos: Vector3, size_v: Vector3, _color: Color):
			var mesh_size: Vector3 = VoxelMat.get_box(size_v).size
			boxes.append(AABB(pos - mesh_size * 0.5, mesh_size)))
		# The last voxel is the foot; continuity here concerns the shell itself.
		boxes.pop_back()
		t.check(_connected(boxes), "%s whorls stay connected at maximum spire height" % shape)
		var preview := Node3D.new()
		library.call("_build_preview_snail_shell", preview, g)
		t.equals(preview.get_child_count(), boxes.size() + 3,
			"%s preview uses the live shell plus foot and two eye stalks" % shape)
		for i in boxes.size():
			var mesh := preview.get_child(i) as MeshInstance3D
			var size_v: Vector3 = (mesh.mesh as BoxMesh).size
			t.check(mesh.position.distance_to(boxes[i].get_center()) < 0.000001 and size_v.is_equal_approx(boxes[i].size),
				"%s preview whorl %d matches live geometry" % [shape, i])
		preview.free()
		host.free()
	library.free()
	quit(t.finish())

func _handle_box(h: Variant) -> AABB:
	var xform: Transform3D = h.transform
	var size_v := Vector3(xform.basis.x.length(), xform.basis.y.length(), xform.basis.z.length())
	return AABB(xform.origin - size_v * 0.5, size_v)

func _connected(boxes: Array[AABB]) -> bool:
	if boxes.is_empty():
		return false
	var reached: Array[int] = [0]
	var cursor: int = 0
	while cursor < reached.size():
		var current: AABB = boxes[reached[cursor]].grow(0.0001)
		for i in boxes.size():
			if i not in reached and current.intersects(boxes[i]):
				reached.append(i)
		cursor += 1
	return reached.size() == boxes.size()
