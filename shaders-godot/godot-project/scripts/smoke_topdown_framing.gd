extends SceneTree

# Headless check for TOPDOWN_MOTION #10 plan-view half-extents per tank_shape.
# Mirrors main.gd::_topdown_plan_half_extents so round bowls frame tighter
# than the legacy height-dominated ortho metric.

const SHAPES: Array[String] = ["box", "cube", "hex", "triangle", "cylinder", "sphere"]
const GLASS_MARGIN: float = 0.35


func _footprint(shape: String, hw: float, hd: float, h: float) -> TankFootprint:
	var fp := TankFootprint.new()
	fp.shape = shape
	fp.half_w = hw
	fp.half_d = hd
	fp.tank_height = h
	fp.substrate_y = h * 0.23
	fp.water_y = h * 0.93
	return fp


func _plan_half_extents(fp: TankFootprint) -> Vector2:
	match fp.shape:
		"cylinder", "sphere":
			var rad: float = fp.radius_at_height(fp.water_y, GLASS_MARGIN)
			if rad <= 0.0:
				rad = fp.effective_radius(GLASS_MARGIN)
			return Vector2(rad, rad)
		_:
			return fp.bounding_half_extents(GLASS_MARGIN)


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	for shape in SHAPES:
		var hw: float = 8.0 if shape != "cube" else 6.5
		var hd: float = 4.0 if shape != "cube" else 6.5
		var h: float = 10.0 if shape in ["cylinder", "sphere"] else 7.0
		if shape == "sphere":
			hw = 4.0
			hd = 4.0
			h = 4.5
		var fp: TankFootprint = _footprint(shape, hw, hd, h)
		var ext: Vector2 = _plan_half_extents(fp)
		if ext.x <= 0.05 or ext.y <= 0.05:
			failed.append("%s: zero plan extent" % shape)
	# Round tanks: square plan footprint, tighter than legacy ortho on tall columns.
	var cyl: TankFootprint = _footprint("cylinder", 4.0, 4.0, 10.0)
	var cyl_ext: Vector2 = _plan_half_extents(cyl)
	if absf(cyl_ext.x - cyl_ext.y) > 0.01:
		failed.append("cylinder: plan extents not square")
	var legacy_ortho: float = maxf(10.0 * 1.4, 4.0 * 2.6) * 1.2
	var cyl_ortho: float = cyl_ext.x * 1.06
	if cyl_ortho >= legacy_ortho * 0.98:
		failed.append("cylinder: new ortho should beat legacy (%.2f vs %.2f)" % [cyl_ortho, legacy_ortho])
	# Hex AABB should exceed inscribed circle of min half-axis.
	var hex: TankFootprint = _footprint("hex", 6.0, 3.0, 7.0)
	var hex_ext: Vector2 = _plan_half_extents(hex)
	if hex_ext.x < 5.0 or hex_ext.y < 2.4:
		failed.append("hex: AABB extents too small (%.2f, %.2f)" % [hex_ext.x, hex_ext.y])
	if failed.is_empty():
		print("[smoke] topdown framing OK: ", ", ".join(SHAPES))
		quit(0)
	else:
		for f in failed:
			push_error("[smoke] " + f)
		quit(1)
