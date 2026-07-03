class_name ShadowAudit
extends RefCounted

# PERFORMANCE_UNTHROTTLED #80 — verify gameplay uses blob shadows only.


static func runtime_lights_with_shadows(root: Node) -> Array[String]:
	var bad: Array[String] = []
	if root == null:
		return bad
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Light3D and (n as Light3D).shadow_enabled:
			bad.append(n.get_path())
		for c in n.get_children():
			stack.append(c)
	return bad


static func smoke_ok(root: Node) -> bool:
	return runtime_lights_with_shadows(root).is_empty()
