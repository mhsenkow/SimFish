# Fibonacci spiral plant.
#
# Voxels are placed in a phyllotaxis pattern - each new leaf is rotated by
# the golden angle (137.5°) around the central axis. When growth would cross
# the glass, it reflects off the wall and keeps spiraling inward.
#
# Leaves are strictly vertical (no look_at / pitch). Placement is validated at
# grow time via the tank footprint; foliage renders through one MultiMesh batch.

extends Plant
class_name SpiralPlant

const GOLDEN_ANGLE: float = 2.39996322972865332
const MAX_WALL_BOUNCES: int = 8
# Half-width of a paddle voxel + safety pad for inside tests.
const VOXEL_FOOTPRINT: float = VOXEL_SIZE * 0.55

@export var radius_step: float = 0.003
@export var height_step: float = 0.18
@export var radius_cap: float = 0.05
@export var max_horizontal_extent: float = 0.14
@export var tank_wall_margin: float = 0.50


func init(initial_height: int = 1, params: Dictionary = {}) -> void:
	monocarpic = true
	emergent_growth = true
	sway_amplitude = 0.0
	params["sway_amplitude"] = 0.0
	_world_pos = global_position
	super.init(initial_height, params)
	rotation = Vector3.ZERO
	_refresh_horizontal_budget()


func tick(dt: float, substrate: SubstrateGrid) -> void:
	# Plant.tick applies rotation.z sway (~0.08 rad) and leaf flutter — both
	# push voxels outside the tank. Run full lifecycle, then lock upright.
	super.tick(dt, substrate)
	rotation = Vector3.ZERO
	_refresh_horizontal_budget()


func _refresh_horizontal_budget() -> void:
	var w := _aquarium_world()
	if w == null or not w.has_method("lateral_room_at"):
		return
	var room: float = w.lateral_room_at(
		global_position.x, global_position.z, tank_wall_margin, global_position.y)
	max_horizontal_extent = clampf(room * 0.72, 0.03, 0.12)


func _flutter_leaves(_dt: float) -> void:
	pass


func _grow_one() -> bool:
	if current_height >= max_height:
		return false
	if emergent_growth and _at_surface_cap():
		return false
	var idx: int = current_height
	var theta: float = float(idx) * GOLDEN_ANGLE
	var rel: float = float(idx) / float(maxi(1, max_height - 1))
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	var taper: float = 1.0 - (rel * 0.85)
	var outward := Vector3(cos(theta), 0.0, sin(theta)).normalized()

	var leaf_len: int = 2
	var leaf_reach: float = _leaf_horizontal_reach(leaf_len)
	var r_ideal: float = minf(radius_step * sqrt(float(idx) + 1.0), radius_cap) * taper
	var r_cap: float = maxf(0.0, max_horizontal_extent - leaf_reach)
	var r_start: float = minf(r_ideal, r_cap)

	var local_y: float = float(idx) * height_step
	var placement: Dictionary = _fit_placement(
		outward, local_y, r_start, leaf_reach)

	# Bake into the per-plant foliage MultiMesh — one draw call per plant, not
	# one MeshInstance3D per leaf voxel (unique meshes wedge the Metal driver).
	var leaf_node := Node3D.new()
	leaf_node.position = placement["position"]
	if placement.get("reflected", false):
		leaf_node.set_meta("wall_reflected", true)
	var leaf_voxels: Array = LeafShapes.build_paddle(leaf_len, ramp, 1.0 - rel, 1, 0.45)
	_leaf_groups.append(_bake_leaf(leaf_node, leaf_voxels))
	_leaf_ages.append(_t)
	leaf_node.free()

	current_height += 1
	return true


func _save_kind() -> String:
	return "spiral_plant"


func to_save_dict() -> Dictionary:
	var d: Dictionary = super.to_save_dict()
	d["max_horizontal_extent"] = max_horizontal_extent
	d["tank_wall_margin"] = tank_wall_margin
	d["radius_step"] = radius_step
	d["height_step"] = height_step
	d["radius_cap"] = radius_cap
	return d


func apply_save_dict(d: Dictionary) -> void:
	# Set subclass-specific fields BEFORE super so init() sees them.
	max_horizontal_extent = float(d.get("max_horizontal_extent", max_horizontal_extent))
	tank_wall_margin = float(d.get("tank_wall_margin", tank_wall_margin))
	radius_step = float(d.get("radius_step", radius_step))
	height_step = float(d.get("height_step", height_step))
	radius_cap = float(d.get("radius_cap", radius_cap))
	super.apply_save_dict(d)


func top_world_y() -> float:
	var crown_y: float = float(current_height) * height_step
	var leaf_extension: float = float(2) * VOXEL_SIZE * 0.85
	return global_position.y + crown_y + leaf_extension


func get_seed_config() -> Dictionary:
	var cfg: Dictionary = super.get_seed_config()
	cfg["radius_step"] = radius_step
	cfg["height_step"] = height_step
	cfg["radius_cap"] = radius_cap
	cfg["max_horizontal_extent"] = max_horizontal_extent
	cfg["tank_wall_margin"] = tank_wall_margin
	cfg["sway_amplitude"] = 0.0
	return cfg


func _leaf_horizontal_reach(_leaf_len: int) -> float:
	return VOXEL_FOOTPRINT


func _fit_placement(
	outward: Vector3, local_y: float, r_start: float, leaf_reach: float,
) -> Dictionary:
	var r: float = r_start
	var best: Dictionary = {
		"position": Vector3(0.0, local_y, 0.0),
		"reflected": false,
	}
	for _attempt in 16:
		var ideal_local: Vector3 = Vector3(outward.x * r, local_y, outward.z * r)
		var candidate: Dictionary = _reflect_placement(ideal_local, leaf_reach)
		candidate["position"].y = local_y
		if _leaf_base_inside_world(candidate["position"]):
			return candidate
		best = candidate
		r *= 0.82
	# Last resort: grow on the stem column so Fibonacci height continues.
	if not _leaf_base_inside_world(best["position"]):
		best["position"] = Vector3(0.0, local_y, 0.0)
		best["reflected"] = true
	return best


func _reflect_placement(ideal_local: Vector3, leaf_reach: float) -> Dictionary:
	var margin: float = tank_wall_margin + leaf_reach
	var world: Vector3 = global_position + ideal_local
	var reflected: bool = false
	var local_pos: Vector3 = ideal_local
	var w := _aquarium_world()
	if w != null and w.has_method("clamp_xz_in_tank"):
		var clamped: Vector2 = w.clamp_xz_in_tank(world.x, world.z, margin)
		reflected = clamped.distance_squared_to(Vector2(world.x, world.z)) > 1e-5
		local_pos = Vector3(
			clamped.x - global_position.x,
			ideal_local.y,
			clamped.y - global_position.z,
		)
		return {"position": local_pos, "reflected": reflected}
	# Fallback: axis-aligned box bounce (legacy).
	var bounds: Dictionary = _tank_inner_bounds(margin)
	var hw: float = bounds["hw"]
	var hd: float = bounds["hd"]
	world = global_position + ideal_local
	reflected = false
	var local_y: float = ideal_local.y

	for _bounce in MAX_WALL_BOUNCES:
		if _inside_tank_world(world.x, world.z, margin):
			break
		var bounced: bool = false
		if world.x > hw:
			world.x = hw - (world.x - hw)
			bounced = true
		elif world.x < -hw:
			world.x = -hw + (-hw - world.x)
			bounced = true
		if world.z > hd:
			world.z = hd - (world.z - hd)
			bounced = true
		elif world.z < -hd:
			world.z = -hd + (-hd - world.z)
			bounced = true
		if bounced:
			reflected = true
		else:
			world.x = clampf(world.x, -hw, hw)
			world.z = clampf(world.z, -hd, hd)
			reflected = true
			break

	local_pos = world - global_position
	local_pos.y = local_y
	return {"position": local_pos, "reflected": reflected}


func _inside_tank_world(x: float, z: float, margin: float, y: float = NAN) -> bool:
	var w := _aquarium_world()
	if w != null:
		if not is_nan(y) and w.has_method("is_inside_tank_volume"):
			return w.is_inside_tank_volume(x, y, z, margin)
		if w.has_method("is_inside_tank"):
			return w.is_inside_tank(x, z, margin, y)
	return _inside_shape(x, z, _tank_inner_bounds(margin))


func _leaf_base_inside_world(local_pos: Vector3) -> bool:
	var w: Vector3 = global_position + local_pos
	return _inside_tank_world(w.x, w.z, tank_wall_margin + VOXEL_FOOTPRINT, w.y)


func _aquarium_world() -> Node:
	var n: Node = self
	while n != null:
		if n.has_method("is_inside_tank"):
			return n
		n = n.get_parent()
	return null


func _tank_inner_bounds(margin: float) -> Dictionary:
	var cfg := get_node_or_null("/root/TankConfig")
	var hw: float = 8.0 - margin
	var hd: float = 4.0 - margin
	var shape: String = "box"
	if cfg != null:
		hw = float(cfg.tank_half_w) - margin
		hd = float(cfg.tank_half_d) - margin
		shape = String(cfg.tank_shape)
	return {"hw": hw, "hd": hd, "shape": shape}


func _inside_shape(x: float, z: float, bounds: Dictionary) -> bool:
	var hw: float = bounds["hw"]
	var hd: float = bounds["hd"]
	if hw <= 0.0 or hd <= 0.0:
		return false
	match String(bounds["shape"]):
		"hex":
			var q: float = absf(x) / hw
			var r_hex: float = absf(z) / hd
			return q + r_hex * 0.5 < 1.0 and r_hex < 1.0
		"triangle":
			if z > hd or z < -hd:
				return false
			var base_half: float = hw * (hd - z) / (2.0 * hd)
			return absf(x) <= base_half
		"cylinder", "sphere":
			var rad: float = minf(hw, hd)
			return x * x + z * z <= rad * rad
		_:
			return absf(x) <= hw and absf(z) <= hd
