extends SceneTree
# Round-trip MultiMesh buffer layout vs set_instance_transform.


func _init() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = 1
	mm.visible_instance_count = 1
	var xform := Transform3D(
		Basis(Vector3(2, 0.5, 0.1), Vector3(0.2, 3, 0.4), Vector3(0.1, 0.3, 4)),
		Vector3(1.5, 2.5, 3.5))
	var color := Color(0.1, 0.2, 0.3, 0.4)
	var custom := Color(0.5, 0.6, 0.7, 0.8)
	mm.set_instance_transform(0, xform)
	mm.set_instance_color(0, color)
	mm.set_instance_custom_data(0, custom)

	# Godot stores basis.rows — (x.x,y.x,z.x), (x.y,y.y,z.y), (x.z,y.z,z.z).
	var b := xform.basis
	var o := xform.origin
	var rows := PackedFloat32Array([
		b.x.x, b.y.x, b.z.x, o.x,
		b.x.y, b.y.y, b.z.y, o.y,
		b.x.z, b.y.z, b.z.z, o.z,
		color.r, color.g, color.b, color.a,
		custom.r, custom.g, custom.b, custom.a,
	])
	mm.set_buffer(rows)
	var via_rows := mm.get_instance_transform(0)
	var rows_ok := via_rows.origin.distance_to(xform.origin) < 0.001 \
			and via_rows.basis.get_scale().distance_to(xform.basis.get_scale()) < 0.05

	# Contiguous axes layout must NOT round-trip a non-symmetric basis.
	var axes := PackedFloat32Array([
		b.x.x, b.x.y, b.x.z, o.x,
		b.y.x, b.y.y, b.y.z, o.y,
		b.z.x, b.z.y, b.z.z, o.z,
		color.r, color.g, color.b, color.a,
		custom.r, custom.g, custom.b, custom.a,
	])
	mm.set_buffer(axes)
	var via_axes := mm.get_instance_transform(0)
	var axes_wrong := via_axes.basis.get_scale().distance_to(xform.basis.get_scale()) > 0.05 \
			or via_axes.origin.distance_to(xform.origin) > 0.001

	var _Blit = load("res://scripts/multimesh_buffer_blit.gd")
	_Blit.upload(mm, [xform], PackedColorArray([color]), PackedColorArray([custom]), 1, true)
	var via_blit := mm.get_instance_transform(0)
	var blit_ok := via_blit.origin.distance_to(xform.origin) < 0.001 \
			and via_blit.basis.get_scale().distance_to(xform.basis.get_scale()) < 0.05

	print("[smoke_multimesh_layout] rows_ok=", rows_ok, " axes_diverges=", axes_wrong, " blit_ok=", blit_ok)
	if not rows_ok or not blit_ok:
		push_error("[smoke_multimesh_layout] FAIL — buffer layout mismatch")
		quit(1)
		return
	print("[smoke_multimesh_layout] OK")
	quit(0)
