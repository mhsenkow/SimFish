extends SceneTree

# Hex glass corners must match is_inside / substrate; snail spawn must land
# inside the tank volume, not pushed through the glass.
func _initialize() -> void:
	await process_frame
	var fp := TankFootprint.from_values("hex", 7.0, 7.0)
	fp.substrate_y = 0.0
	fp.water_y = 6.5
	var failed: Array[String] = []
	for c in fp.footprint_corners():
		if not fp.is_inside(c.x, c.z, 0.0):
			failed.append("corner (%.2f, %.2f) outside footprint" % [c.x, c.z])
	var inward: Vector3 = fp._lateral_inward(5.0, 5.0, 0.1)
	if inward.dot(Vector3(-5.0, 0.0, -5.0)) < 0.0:
		failed.append("hex inward points outward at (+,+) quadrant")

	var cfg := get_root().get_node_or_null("TankConfig")
	if cfg == null:
		failed.append("TankConfig autoload missing")
	else:
		cfg.tank_shape = "hex"
		cfg.tank_half_w = 7.0
		cfg.tank_half_d = 7.0
		cfg.tank_height = 8.0
		var world_script: Script = load("res://scripts/world.gd")
		var w: Node3D = world_script.new() as Node3D
		w.name = "SmokeHexWorld"
		root.add_child(w)
		await process_frame
		await process_frame
		if w.get("terrain_grid") == null:
			failed.append("hex world failed to build terrain")
		else:
			var layout: Array = w.call("_snail_founder_layout_hex", false)
			for i in layout.size():
				var pw: Array = layout[i]
				var pos: Vector3 = pw[0]
				var wn: Vector3 = pw[1]
				if not w.is_inside_tank_volume(pos.x, pos.y, pos.z, 0.12):
					failed.append("snail spawn %d outside tank: %s" % [i, pos])
				if wn.dot(pos) > 0.05:
					failed.append("snail wall_normal %d points away from tank center" % i)
		w.queue_free()

	if failed.is_empty():
		print("[smoke] hex footprint + snail spawn OK")
		quit(0)
	else:
		for f in failed:
			push_error("[smoke_hex_footprint] " + f)
		quit(1)
