extends SceneTree

# Headless check that themed scenario presets spawn plants with sensible
# spatial spread — polyp lab keeps a tight center island but hydra on the rim;
# iwagumi carpet should not collapse to a single pile.
const CASES: Array[Dictionary] = [
	{
		"preset": "polyp_lab",
		"shape": "sphere",
		"half_w": 5.0,
		"half_d": 5.0,
		"height": 6.0,
		"substrate": "eco_complete",
		"min_hydra_outside": 1.4,
		"max_carpet_radius": 1.6,
	},
	{
		"preset": "iwagumi_school",
		"shape": "box",
		"half_w": 11.0,
		"half_d": 3.0,
		"height": 5.0,
		"substrate": "sand",
		"min_carpet_spread": 2.5,
		"max_carpet_radius": 99.0,
	},
	{
		"preset": "apex_tank",
		"shape": "box",
		"half_w": 6.0,
		"half_d": 4.0,
		"height": 6.0,
		"substrate": "eco_complete",
		"min_corner_plants": 2,
	},
]


func _initialize() -> void:
	await process_frame
	var cfg := get_root().get_node_or_null("TankConfig")
	if cfg == null:
		push_error("[smoke_scenario_layouts] TankConfig autoload missing")
		quit(1)
		return
	var saves := get_root().get_node_or_null("TankSaves")
	if saves != null and saves.has_method("clear_active_state"):
		saves.clear_active_state()
	var world_script: Script = load("res://scripts/world.gd")
	var failed: Array[String] = []
	for case in CASES:
		cfg.tank_preset = String(case["preset"])
		cfg.tank_shape = String(case["shape"])
		cfg.tank_half_w = float(case["half_w"])
		cfg.tank_half_d = float(case["half_d"])
		cfg.tank_height = float(case["height"])
		cfg.substrate_type = String(case["substrate"])
		var w: Node3D = world_script.new() as Node3D
		w.name = "SmokeLayout_" + String(case["preset"])
		root.add_child(w)
		var min_children: int = 12 if case["preset"] == "polyp_lab" else 8
		var deadline: int = 250
		var stable: int = 0
		var last_count: int = -1
		while deadline > 0:
			await process_frame
			deadline -= 1
			var plants_root: Node = w.get("plants_root")
			var count: int = plants_root.get_child_count() if plants_root != null else 0
			if count == last_count:
				stable += 1
			else:
				stable = 0
			last_count = count
			if count >= min_children and stable >= 8:
				break
		var err: String = _check_case(w, case)
		if not err.is_empty():
			failed.append("%s: %s" % [case["preset"], err])
		w.queue_free()
		await process_frame
	if failed.is_empty():
		print("[smoke] scenario plant layouts OK: ",
			", ".join(CASES.map(func(c): return String(c["preset"]))))
		quit(0)
	else:
		for f in failed:
			push_error("[smoke_scenario_layouts] " + f)
		quit(1)


func _check_case(world: Node3D, case: Dictionary) -> String:
	var plants_root: Node = world.get("plants_root")
	if plants_root == null:
		return "plants_root missing"
	var carpet_positions: PackedVector2Array = PackedVector2Array()
	var hydra_positions: PackedVector2Array = PackedVector2Array()
	var all_positions: PackedVector2Array = PackedVector2Array()
	for child in plants_root.get_children():
		if not is_instance_valid(child):
			continue
		var p: Vector3 = child.global_position
		all_positions.append(Vector2(p.x, p.z))
		if child is Coral:
			var form: String = String(child.coral_form)
			if form == "hydra_fresh" or form == "sponge_fresh":
				hydra_positions.append(Vector2(p.x, p.z))
		elif child is Plant:
			carpet_positions.append(Vector2(p.x, p.z))
	if all_positions.is_empty():
		return "no plants spawned"
	if case.has("min_hydra_outside"):
		var min_out: float = float(case["min_hydra_outside"])
		var outside: int = 0
		for hp in hydra_positions:
			if hp.length() >= min_out:
				outside += 1
		if outside < 2:
			return "hydra not spread on rim (outside=%d of %d, need >=2)" % [
				outside, hydra_positions.size()]
	if case.has("max_carpet_radius") and not carpet_positions.is_empty():
		var max_r: float = 0.0
		for cp in carpet_positions:
			max_r = maxf(max_r, cp.length())
		if max_r > float(case["max_carpet_radius"]):
			return "carpet spread too wide (max_r=%.2f > %.2f)" % [
				max_r, float(case["max_carpet_radius"])]
	if case.has("min_carpet_spread") and carpet_positions.size() >= 3:
		var mean := Vector2.ZERO
		for cp in carpet_positions:
			mean += cp
		mean /= float(carpet_positions.size())
		var spread: float = 0.0
		for cp in carpet_positions:
			spread = maxf(spread, mean.distance_to(cp))
		if spread < float(case["min_carpet_spread"]):
			return "carpet too clustered (spread=%.2f < %.2f)" % [
				spread, float(case["min_carpet_spread"])]
	if case.has("min_corner_plants"):
		var corner_n: int = 0
		var hw: float = float(case["half_w"])
		var hd: float = float(case["half_d"])
		for ap in all_positions:
			var nx: float = ap.x / maxf(hw, 0.1)
			var nz: float = ap.y / maxf(hd, 0.1)
			if absf(nx) > 0.45 and absf(nz) > 0.35:
				corner_n += 1
		if corner_n < int(case["min_corner_plants"]):
			return "corner refuge thin (corner plants=%d, total=%d)" % [
				corner_n, all_positions.size()]
	return ""
