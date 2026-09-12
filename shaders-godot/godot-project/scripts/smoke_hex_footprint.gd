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

	# --- anything spanning the FRONT PANE must use the pane, not the box ---
	# TANK_HALF_W is the bounding box. On a box they are the same; on a hex
	# the front pane is far narrower, so a full-width bar at z = half_d
	# hangs out past the glass on both sides. The waterline tick did exactly
	# that and rendered as a stray line straight through the tank.
	var hexc: Array = [
		Vector3(5.0, 0.0, 0.0), Vector3(2.5, 0.0, 5.0), Vector3(-2.5, 0.0, 5.0),
		Vector3(-5.0, 0.0, 0.0), Vector3(-2.5, 0.0, -5.0), Vector3(2.5, 0.0, -5.0)]
	var fe: Dictionary = TankFootprint.front_edge_of(hexc)
	if not bool(fe.get("ok", false)):
		failed.append("a hex must have a front pane")
	else:
		var fe_len: float = float(fe["length"])
		if absf(fe_len - 5.0) > 0.01:
			failed.append("hex front pane should be 5 wide, got %.2f" % fe_len)
		if fe_len >= 10.0:
			failed.append("the pane must be narrower than the bounding box")
		var fe_mid: Vector3 = fe["mid"]
		if absf(fe_mid.z - 5.0) > 0.01:
			failed.append("front pane should sit at z=5, got %.2f" % fe_mid.z)
		# A bar of that length centred on the pane stays inside the glass.
		var half_span: float = (fe_len - 0.8) * 0.5
		for s_x in [-half_span, 0.0, half_span]:
			if not LightingRig.inside_footprint(
					fe_mid.x + s_x, fe_mid.z - 0.03, hexc, 0.05):
				failed.append("tick end at x=%.2f pokes outside the glass" % s_x)
	# A square tank must be unaffected.
	var boxc: Array = [
		Vector3(6.0, 0.0, 4.0), Vector3(-6.0, 0.0, 4.0),
		Vector3(-6.0, 0.0, -4.0), Vector3(6.0, 0.0, -4.0)]
	var fb: Dictionary = TankFootprint.front_edge_of(boxc)
	if absf(float(fb["length"]) - 12.0) > 0.01:
		failed.append("a box front pane should be its full width")
	if bool(TankFootprint.front_edge_of([]).get("ok", true)):
		failed.append("no corners must mean no pane")
	# Wiring: the tick must actually use it.
	var av: String = _read_src("res://scripts/aquarium_visuals.gd")
	if not av.contains("TankFootprint.front_edge_of("):
		failed.append("the waterline tick must be sized from the front pane")
	if av.contains("_world.TANK_HALF_W) - 0.4"):
		failed.append("the waterline tick must not use the bounding box")

	quit(TestSupport.report("smoke_hex_footprint", failed))


func _read_src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt: String = f.get_as_text()
	f.close()
	return txt
