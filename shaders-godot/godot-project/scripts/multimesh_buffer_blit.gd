class_name MultiMeshBufferBlit
extends RefCounted

# PERFORMANCE_UNTHROTTLED #78 — upload MultiMesh instance data in one RS call.


static func _stride_for(mm: MultiMesh, use_custom: bool) -> int:
	var stride: int = 12 if mm.transform_format == MultiMesh.TRANSFORM_3D else 8
	if mm.use_colors:
		stride += 4
	if use_custom and mm.use_custom_data:
		stride += 4
	return stride


static func _write_xform(buf: PackedFloat32Array, base: int, xform: Transform3D) -> void:
	# Godot stores Transform3D as basis.rows[0..2] then origin components:
	#   rows[0] = (x.x, y.x, z.x), rows[1] = (x.y, y.y, z.y), …
	# Matches RendererMeshStorage::multimesh_instance_set_transform.
	var b: Basis = xform.basis
	var o: Vector3 = xform.origin
	buf[base + 0] = b.x.x
	buf[base + 1] = b.y.x
	buf[base + 2] = b.z.x
	buf[base + 3] = o.x
	buf[base + 4] = b.x.y
	buf[base + 5] = b.y.y
	buf[base + 6] = b.z.y
	buf[base + 7] = o.y
	buf[base + 8] = b.x.z
	buf[base + 9] = b.y.z
	buf[base + 10] = b.z.z
	buf[base + 11] = o.z


static func upload(mm: MultiMesh, xforms: Array, colors: PackedColorArray,
		customs: PackedColorArray, count: int, use_custom: bool) -> void:
	if mm == null or count <= 0:
		return
	var instances: int = mm.instance_count
	if instances <= 0:
		return
	var stride: int = _stride_for(mm, use_custom)
	var buf := PackedFloat32Array()
	buf.resize(instances * stride)
	buf.fill(0.0)
	var hidden: Transform3D = Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for i in instances:
		var base: int = i * stride
		var xform: Transform3D = hidden
		if i < count and i < xforms.size():
			xform = xforms[i]
		if not xform.is_finite():
			xform = hidden
		_write_xform(buf, base, xform)
		var off: int = 12
		if mm.use_colors:
			var c: Color = colors[i] if i < count and i < colors.size() else Color.WHITE
			buf[base + off] = c.r
			buf[base + off + 1] = c.g
			buf[base + off + 2] = c.b
			buf[base + off + 3] = c.a
			off += 4
		if use_custom and mm.use_custom_data:
			var cu: Color = customs[i] if i < count and i < customs.size() else Color(0, 0, 0, 1)
			buf[base + off] = cu.r
			buf[base + off + 1] = cu.g
			buf[base + off + 2] = cu.b
			buf[base + off + 3] = cu.a
	RenderingServer.multimesh_set_buffer(mm.get_rid(), buf)
