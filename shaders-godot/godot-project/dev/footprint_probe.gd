extends Node

# Lists every MeshInstance3D whose world-space AABB pokes outside the tank's
# own footprint polygon. A rectangular mesh inside a hex tank reads as a
# straight line cutting across the glass.

func _ready() -> void:
	for _i in 240:
		await get_tree().process_frame
	var world: Node = get_node_or_null("SubViewport/World")
	if world == null:
		for c in get_children():
			if c.name == "World":
				world = c
	if world == null:
		print("[probe] no World"); get_tree().quit(1); return
	var shape: String = String(world.get("TANK_SHAPE"))
	var hw: float = float(world.get("TANK_HALF_W"))
	var hd: float = float(world.get("TANK_HALF_D"))
	var th: float = float(world.get("TANK_HEIGHT"))
	print("[probe] shape=%s half=(%.2f, %.2f) height=%.2f" % [shape, hw, hd, th])
	var corners: Array = []
	if world.has_method("_tank_footprint_corners"):
		corners = world._tank_footprint_corners()
	print("[probe] footprint corners=%d" % corners.size())
	for c in corners:
		print("[probe]   (%.2f, %.2f)" % [c.x, c.z])
	var offenders: Array = []
	_walk(world, corners, offenders, "")
	offenders.sort_custom(func(a, b): return a["over"] > b["over"])
	print("[probe] --- meshes outside the footprint (top 25) ---")
	for i in mini(25, offenders.size()):
		var o: Dictionary = offenders[i]
		print("[probe] %6.3f  %-14s v=%-5d %s   xz=(%.2f..%.2f, %.2f..%.2f)" % [
			o["over"], o["kind"], o["verts"], o["path"],
			o["x0"], o["x1"], o["z0"], o["z1"]])
	print("[probe] total offenders=%d" % offenders.size())
	# Anything longer than the tank itself: that is what crosses the frame
	# as a stray line.
	print("[probe] --- long thin meshes (>6u, one axis <0.6u) ---")
	var longs: Array = []
	_walk_long(world, longs, "")
	longs.sort_custom(func(a, b): return a["len"] > b["len"])
	for i in mini(12, longs.size()):
		var o: Dictionary = longs[i]
		print("[probe] len=%6.2f %-12s size=(%.2f,%.2f,%.2f) at (%.1f,%.1f,%.1f) %s" % [
			o["len"], o["kind"], o["sx"], o["sy"], o["sz"],
			o["cx"], o["cy"], o["cz"], o["path"]])

	print("[probe] --- direct MeshInstance3D children of World ---")
	for c in world.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var mi := c as MeshInstance3D
			var ab: AABB = mi.get_aabb()
			var t: Transform3D = mi.global_transform
			var lo := Vector3(INF, INF, INF)
			var hi := Vector3(-INF, -INF, -INF)
			for i in 8:
				var p: Vector3 = t * (ab.position + Vector3(
					ab.size.x * float(i & 1), ab.size.y * float((i >> 1) & 1),
					ab.size.z * float((i >> 2) & 1)))
				lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
				hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
			var sz: Vector3 = hi - lo
			print("[probe] %-10s vis=%s size=(%.2f,%.2f,%.2f) pos=(%.1f,%.1f,%.1f) %s" % [
				mi.mesh.get_class(), str(mi.visible), sz.x, sz.y, sz.z,
				(lo.x+hi.x)*0.5, (lo.y+hi.y)*0.5, (lo.z+hi.z)*0.5, mi.name])

	print("[probe] --- particle emitters ---")
	_walk_particles(world, "")

	# Does the shipped beam material actually carry the footprint clip?
	var shaft: Node = _find_named(world, "BeamShaft")
	if shaft == null:
		print("[probe] no BeamShaft")
	else:
		var m: Material = (shaft as MeshInstance3D).material_override
		if m is ShaderMaterial:
			var sm := m as ShaderMaterial
			print("[probe] shaft tank_plane_count=",
				sm.get_shader_parameter("tank_plane_count"))
			var pl: Variant = sm.get_shader_parameter("tank_planes")
			print("[probe] shaft tank_planes=",
				(str(pl[0]) + " .. " + str(pl[5])) if (pl is Array and pl.size() >= 6) else str(pl))
			print("[probe] shaft beam_color=", sm.get_shader_parameter("beam_color"))
		else:
			print("[probe] shaft material is not a ShaderMaterial: ", m)
	get_tree().quit(0)


func _walk(n: Node, corners: Array, out: Array, path: String) -> void:
	var here: String = path + "/" + n.name
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and n.visible:
		var mi := n as MeshInstance3D
		# REAL vertices, not the AABB. The axis-aligned bounding box of a
		# correct hex prism IS a rectangle, so an AABB test flags every
		# properly-built hex mesh as poking out of its own footprint.
		var faces: PackedVector3Array = mi.mesh.get_faces()
		var t: Transform3D = mi.global_transform
		var worst: float = 0.0
		var x0 := INF
		var x1 := -INF
		var z0 := INF
		var z1 := -INF
		var step: int = maxi(1, faces.size() / 900)
		for i in range(0, faces.size(), step):
			var p: Vector3 = t * faces[i]
			x0 = minf(x0, p.x); x1 = maxf(x1, p.x)
			z0 = minf(z0, p.z); z1 = maxf(z1, p.z)
			worst = maxf(worst, _outside_by(p, corners))
		if worst > 0.06:
			out.append({"over": worst, "path": here,
				"kind": mi.mesh.get_class(),
				"verts": faces.size(),
				"x0": x0, "x1": x1, "z0": z0, "z1": z1})
	for c in n.get_children():
		_walk(c, corners, out, here)


# How far outside the convex footprint polygon this point lies (0 = inside).
func _outside_by(p: Vector3, corners: Array) -> float:
	if corners.size() < 3:
		return 0.0
	var worst: float = 0.0
	for i in corners.size():
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % corners.size()]
		var e := Vector2(b.x - a.x, b.z - a.z)
		if e.length_squared() < 1e-8:
			continue
		var nrm := Vector2(e.y, -e.x).normalized()
		var mid := Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)
		if nrm.dot(mid) < 0.0:
			nrm = -nrm
		var d: float = nrm.dot(Vector2(p.x, p.z)) - nrm.dot(Vector2(a.x, a.z))
		worst = maxf(worst, d)
	return worst


func _find_named(n: Node, want: String) -> Node:
	if String(n.name).begins_with(want):
		return n
	for c in n.get_children():
		var r: Node = _find_named(c, want)
		if r != null:
			return r
	return null


func _walk_long(n: Node, out: Array, path: String) -> void:
	var here: String = path + "/" + n.name
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and n.visible:
		var mi := n as MeshInstance3D
		var ab: AABB = mi.get_aabb()
		var t: Transform3D = mi.global_transform
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for i in 8:
			var p: Vector3 = t * (ab.position + Vector3(
				ab.size.x * float(i & 1),
				ab.size.y * float((i >> 1) & 1),
				ab.size.z * float((i >> 2) & 1)))
			lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
			hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
		var sz: Vector3 = hi - lo
		var longest: float = maxf(sz.x, maxf(sz.y, sz.z))
		if longest > 6.0 and (sz.y < 0.6 or sz.z < 0.6):
			out.append({"len": longest, "path": here,
				"kind": mi.mesh.get_class(),
				"sx": sz.x, "sy": sz.y, "sz": sz.z,
				"cx": (lo.x + hi.x) * 0.5, "cy": (lo.y + hi.y) * 0.5,
				"cz": (lo.z + hi.z) * 0.5})
	for c in n.get_children():
		_walk_long(c, out, here)


func _walk_particles(n: Node, path: String) -> void:
	var here: String = path + "/" + n.name
	if n is GPUParticles3D:
		var p := n as GPUParticles3D
		var dp: Mesh = p.draw_pass_1
		var msz := "-"
		if dp is QuadMesh:
			msz = str((dp as QuadMesh).size)
		elif dp is BoxMesh:
			msz = str((dp as BoxMesh).size)
		elif dp != null:
			msz = dp.get_class()
		print("[probe] GPU amount=%4d vis=%s pos=(%.1f,%.1f,%.1f) scale=%s mesh=%s %s" % [
			p.amount, str(p.visible), p.global_position.x, p.global_position.y,
			p.global_position.z, str(p.scale), msz, here])
	elif n is CPUParticles3D:
		var c := n as CPUParticles3D
		print("[probe] CPU amount=%4d pos=(%.1f,%.1f,%.1f) %s" % [
			c.amount, c.global_position.x, c.global_position.y,
			c.global_position.z, here])
	for ch in n.get_children():
		_walk_particles(ch, here)
