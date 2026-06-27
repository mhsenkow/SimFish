extends SceneTree

const SHAPES: Array[String] = ["box", "cube", "hex", "triangle", "cylinder", "sphere"]


func _init() -> void:
	for shape in SHAPES:
		var fp := TankFootprint.from_values(shape, 8.0, 4.0)
		fp.substrate_y = 0.0
		fp.water_y = 6.5
		fp.tank_height = 8.0
		var bad := Vector3(NAN, INF, -INF)
		var c: Vector3 = fp.clamp_inside_3d(bad, 0.25)
		if not c.is_finite():
			push_error("[smoke] clamp_inside_3d(%s) returned non-finite: %s" % [shape, c])
			quit(1)
			return
		var probe := Vector3(12.0, 3.0, 5.0)
		c = fp.clamp_inside_3d(probe, 0.25)
		if not c.is_finite():
			push_error("[smoke] clamp_inside_3d(%s) returned non-finite exterior: %s" % [shape, c])
			quit(1)
			return
		if not fp.is_inside_3d(c.x, c.y, c.z, 0.25):
			push_error("[smoke] clamp_inside_3d(%s) exterior not inside: %s" % [shape, c])
			quit(1)
			return
	print("[smoke] footprint clamp OK: ", ", ".join(SHAPES))
	quit()
