class_name SubstrateAoBake
extends RefCounted

# PERFORMANCE_UNTHROTTLED #85 — bake contact AO into substrate voxel albedo at build.


static func apply_to_container(substrate_root: Node3D, contact_points: Array,
		substrate_depth: float) -> int:
	if substrate_root == null or contact_points.is_empty():
		return 0
	var baked: int = 0
	var stack: Array[Node] = [substrate_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n as MeshInstance3D
			if _bake_mesh(mi, contact_points, substrate_depth):
				baked += 1
		for c in n.get_children():
			stack.append(c)
	return baked


static func _bake_mesh(mi: MeshInstance3D, points: Array, substrate_depth: float) -> bool:
	var mat: Material = mi.material_override
	if mat == null:
		return false
	var base: Color = Color.WHITE
	if mat is ShaderMaterial:
		var alb: Variant = (mat as ShaderMaterial).get_shader_parameter("albedo")
		if alb is Color:
			base = alb as Color
	elif mat is StandardMaterial3D:
		base = (mat as StandardMaterial3D).albedo_color
	var wp: Vector3 = mi.global_position
	var darkened: Color = base
	for pt in points:
		if not (pt is Vector4):
			continue
		var p: Vector4 = pt as Vector4
		if p.w < 0.001:
			continue
		var d2: float = (wp.x - p.x) * (wp.x - p.x) + (wp.z - p.z) * (wp.z - p.z)
		var r2: float = p.w * p.w
		if d2 > r2:
			continue
		var t: float = clampf(sqrt(d2) / maxf(p.w, 0.001), 0.0, 1.0)
		var ao: float = lerpf(0.62, 1.0, t)
		if wp.y <= substrate_depth + 0.12:
			ao = minf(ao, 0.78)
		darkened *= Color(ao, ao, ao, 1.0)
	if darkened.is_equal_approx(base):
		return false
	if mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter("albedo", darkened)
	elif mat is StandardMaterial3D:
		(mat as StandardMaterial3D).albedo_color = darkened
	return true
