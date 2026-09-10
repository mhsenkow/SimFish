extends RefCounted

const MAX_ATTACHMENT_DISTANCE: float = 6.0


static func nearest_valid(near_pos: Vector3, surfaces: Array) -> Dictionary:
	var best_pos := Vector3.ZERO
	var best_kind := ""
	var best_d2: float = MAX_ATTACHMENT_DISTANCE * MAX_ATTACHMENT_DISTANCE
	for surface_v in surfaces:
		if not (surface_v is Dictionary):
			continue
		var surface: Dictionary = surface_v
		var pos_v: Variant = surface.get("position", null)
		var kind: String = String(surface.get("kind", ""))
		if not (pos_v is Vector3) or (kind != "rock" and kind != "wood"):
			continue
		var pos: Vector3 = pos_v
		var d2: float = pos.distance_squared_to(near_pos)
		if d2 <= best_d2:
			best_d2 = d2
			best_pos = pos
			best_kind = kind
	return {} if best_kind == "" else {
		"position": best_pos,
		"kind": best_kind,
		"distance_squared": best_d2,
	}
