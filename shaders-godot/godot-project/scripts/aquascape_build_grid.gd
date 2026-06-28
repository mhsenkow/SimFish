# Player-placed voxels in the water column — MultiMesh-batched build grid.
# AQUASCAPING_CRAFT #11–14, #81, #85, #86, #88.
class_name AquascapeBuildGrid
extends RefCounted

const CELL: float = TerrainVoxelGrid.CELL_SIZE
const MAX_VOXELS: int = 20000
const SAVE_VERSION: int = 2

var _parent: Node3D
var _world: Node3D
var _half_w: float = 4.0
var _half_d: float = 2.0
var _y_origin: float = 0.0
var _batch: VoxelBatch
var _cells: Dictionary = {}  # "ix,iy,iz" -> {color, finish, handle}
var _handles: Dictionary = {}  # key -> VoxelBatch.Handle
var _gravity_mode: bool = false
var build_scale: float = 1.0
var _sync_pending: bool = false
var _substrate_dirty: bool = false
var _opaque_batch_mat: ShaderMaterial = null


func setup(parent: Node3D, world: Node3D) -> void:
	_parent = parent
	_world = world
	if world != null:
		var tg: Variant = world.get("terrain_grid")
		if tg != null:
			_half_w = float(tg.half_w)
			_half_d = float(tg.half_d)
			_y_origin = float(tg.y_origin)
		else:
			if world.get("TANK_HALF_W") != null:
				_half_w = float(world.get("TANK_HALF_W"))
			if world.get("TANK_HALF_D") != null:
				_half_d = float(world.get("TANK_HALF_D"))
	if _batch == null and _parent != null:
		_batch = VoxelBatch.new(_parent, VoxelMat.make_voxel_mm(), 256)
		_batch.mmi.name = "PlayerBuildVoxels"
		apply_lod()


func clear() -> void:
	_cells.clear()
	_handles.clear()
	if _batch != null:
		_batch.clear()
	sync_world_features(true)


func voxel_count() -> int:
	return _cells.size()


func budget_ratio() -> float:
	return float(_cells.size()) / float(MAX_VOXELS)


func can_place() -> bool:
	return _cells.size() < MAX_VOXELS


func set_gravity_mode(on: bool) -> void:
	_gravity_mode = on


func gravity_mode() -> bool:
	return _gravity_mode


func grid_key(ix: int, iy: int, iz: int) -> String:
	return "%d,%d,%d" % [ix, iy, iz]


func world_to_grid(p: Vector3) -> Vector3i:
	return Vector3i(
		int(floor((p.x + _half_w) / CELL)),
		int(floor((p.y - _y_origin) / CELL)),
		int(floor((p.z + _half_d) / CELL)),
	)


func grid_to_world(g: Vector3i) -> Vector3:
	return Vector3(
		-_half_w + (float(g.x) + 0.5) * CELL,
		_y_origin + (float(g.y) + 0.5) * CELL,
		-_half_d + (float(g.z) + 0.5) * CELL,
	)


func is_in_bounds(g: Vector3i) -> bool:
	var p: Vector3 = grid_to_world(g)
	if _world == null:
		return true
	if _world.has_method("is_inside_tank_volume"):
		return _world.is_inside_tank_volume(p.x, p.y, p.z, 0.25)
	return true


func has_cell(g: Vector3i) -> bool:
	return _cells.has(grid_key(g.x, g.y, g.z))


# Build-column height for surface snapping (includes player voxels).
func column_top_y_at(x: float, z: float) -> float:
	var top: float = _y_origin
	if _world != null and _world.has_method("column_surface_y"):
		top = _world.column_surface_y(x, z)
	var half: float = CELL * 0.5 * clampf(build_scale, 0.5, 2.0)
	for key in _cells.keys():
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 3:
			continue
		var wp: Vector3 = grid_to_world(Vector3i(int(parts[0]), int(parts[1]), int(parts[2])))
		if absf(wp.x - x) < CELL * 0.55 and absf(wp.z - z) < CELL * 0.55:
			top = maxf(top, wp.y + half)
	return top


func snap_cell_on_surface(x: float, z: float, surface_y: float) -> Vector3i:
	# surface_y is the top face of the column — occupy that cell, don't float a
	# hollow row above it (center = top face minus half a voxel).
	var gx: float = floorf(x / CELL) * CELL + CELL * 0.5
	var gz: float = floorf(z / CELL) * CELL + CELL * 0.5
	return world_to_grid(Vector3(gx, surface_y - CELL * 0.5, gz))


# Hide substrate mesh only where a build voxel occupies the same grid cell.
func covers_substrate_center(center: Vector3) -> bool:
	return has_cell(world_to_grid(center))


func place_cell(g: Vector3i, color: Color, finish: String = "matte") -> Dictionary:
	if not can_place() or not is_in_bounds(g):
		return {}
	var key: String = grid_key(g.x, g.y, g.z)
	if _cells.has(key):
		return {}
	color = _vary_color(g, color)
	var wp: Vector3 = grid_to_world(g)
	var sc: float = clampf(build_scale, 0.5, 2.0)
	var xform := Transform3D(Basis().scaled(Vector3(CELL * sc, CELL * sc, CELL * sc)), wp)
	_ensure_batch_material_opaque()
	var display_color: Color = _display_color_for_finish(color, finish)
	var h: VoxelBatch.Handle = _batch.add(xform, display_color)
	_cells[key] = {"color": color, "finish": finish}
	_handles[key] = h
	_batch.flush()
	if _world != null and _world.has_method("clear_terrain_at_build_overlap"):
		if _world.clear_terrain_at_build_overlap(g):
			_substrate_dirty = true
	sync_world_features(true)
	return {"grid": g, "key": key, "world": wp, "color": color, "finish": finish}


func remove_cell(g: Vector3i) -> Dictionary:
	var key: String = grid_key(g.x, g.y, g.z)
	if not _cells.has(key):
		return {}
	var prev: Dictionary = _cells[key].duplicate(true)
	prev["grid"] = g
	prev["world"] = grid_to_world(g)
	var h: Variant = _handles.get(key)
	if h != null and h is VoxelBatch.Handle:
		(h as VoxelBatch.Handle).hide()
	_handles.erase(key)
	_cells.erase(key)
	sync_world_features(true)
	return prev


func raycast_face(origin: Vector3, dir: Vector3, max_dist: float = 40.0) -> Dictionary:
	# DDA through grid cells along the ray; return hit cell + outward normal.
	var step: float = CELL * 0.45
	var t: float = 0.0
	var last_empty: Vector3i = Vector3i(99999, 99999, 99999)
	while t < max_dist:
		var p: Vector3 = origin + dir * t
		var g: Vector3i = world_to_grid(p)
		if g != last_empty:
			if has_cell(g):
				var normal: Vector3 = _estimate_face_normal(g, p)
				return {"hit": true, "cell": g, "normal": normal, "world": grid_to_world(g)}
			last_empty = g
		t += step
	return {"hit": false}


func adjacent_cell(from: Vector3i, normal: Vector3) -> Vector3i:
	var n: Vector3i = Vector3i(
		int(signf(normal.x)), int(signf(normal.y)), int(signf(normal.z)))
	if n == Vector3i.ZERO:
		n = Vector3i(0, 1, 0)
	return from + n


func plane_cell_at_y(origin: Vector3, dir: Vector3, plane_y: float) -> Vector3i:
	if absf(dir.y) < 0.001:
		return world_to_grid(Vector3(origin.x, plane_y, origin.z))
	var t: float = (plane_y - origin.y) / dir.y
	if t < 0.0:
		return world_to_grid(origin)
	var hit: Vector3 = origin + dir * t
	hit.y = plane_y
	return world_to_grid(hit)


func place_object_voxels(voxels: Array, origin: Vector3, default_color: Color) -> Array:
	var placed: Array = []
	for v in voxels:
		if not (v is Dictionary):
			continue
		var off: Vector3 = v.get("offset", Vector3.ZERO)
		if v.get("offset_i") is Vector3i:
			off = Vector3(v.offset_i) * CELL
		var g: Vector3i = world_to_grid(origin + off)
		var c: Color = v.get("color", default_color)
		var fin: String = String(v.get("finish", "matte"))
		var rec: Dictionary = place_cell(g, c, fin)
		if not rec.is_empty():
			placed.append(rec)
	return placed


func to_save_arr() -> Array:
	var out: Array = []
	for key in _cells.keys():
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 3:
			continue
		var entry: Dictionary = _cells[key]
		out.append({
			"kind": "build_voxel",
			"v": SAVE_VERSION,
			"ix": int(parts[0]), "iy": int(parts[1]), "iz": int(parts[2]),
			"color": SaveHelpers.color_to_array(entry.get("color", Color.WHITE)),
			"finish": String(entry.get("finish", "matte")),
		})
	return out


func restore_from_save(arr: Array) -> void:
	clear()
	for entry in arr:
		if not (entry is Dictionary):
			continue
		if String(entry.get("kind", "")) != "build_voxel":
			continue
		var g := Vector3i(int(entry.get("ix", 0)), int(entry.get("iy", 0)), int(entry.get("iz", 0)))
		var c: Color = SaveHelpers.array_to_color(entry.get("color", []), Color.WHITE)
		place_cell(g, c, String(entry.get("finish", "matte")))
	if _batch != null:
		_batch.flush()
	refresh_voxel_appearance()
	sync_world_features(true)


func refresh_voxel_appearance() -> void:
	_ensure_batch_material_opaque()
	for key in _cells.keys():
		var e: Dictionary = _cells[key]
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 3:
			continue
		var base: Color = e.get("color", Color.WHITE)
		var fin: String = String(e.get("finish", "matte"))
		var tinted: Color = _display_color_for_finish(base, fin)
		e["color"] = base
		var h: Variant = _handles.get(key)
		if h != null and h is VoxelBatch.Handle:
			(h as VoxelBatch.Handle).set_color(_apply_patina(tinted))
	if _batch != null:
		_batch.flush()


func get_cell_data(g: Vector3i) -> Dictionary:
	var key: String = grid_key(g.x, g.y, g.z)
	if _cells.has(key):
		return _cells[key].duplicate(true)
	return {}


func export_voxel_list() -> Array:
	var out: Array = []
	for key in _cells.keys():
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 3:
			continue
		var e: Dictionary = _cells[key]
		out.append({
			"ix": int(parts[0]), "iy": int(parts[1]), "iz": int(parts[2]),
			"color": SaveHelpers.color_to_array(e.get("color", Color.WHITE)),
			"finish": String(e.get("finish", "matte")),
		})
	return out


func import_voxel_list(voxels: Array, origin: Vector3i = Vector3i.ZERO) -> int:
	var n: int = 0
	for v in voxels:
		if not (v is Dictionary):
			continue
		var g := Vector3i(
			int(v.get("ix", 0)) + origin.x,
			int(v.get("iy", 0)) + origin.y,
			int(v.get("iz", 0)) + origin.z,
		)
		var c: Color = SaveHelpers.array_to_color(v.get("color", []), Color.WHITE)
		if not place_cell(g, c, String(v.get("finish", "matte"))).is_empty():
			n += 1
	return n


func apply_lod() -> void:
	if _batch != null and _batch.mmi != null:
		_batch.mmi.visibility_range_begin = 22.0
		_batch.mmi.visibility_range_end = 50.0


func cells_on_line(a: Vector3i, b: Vector3i) -> Array:
	var out: Array = []
	var steps: int = maxi(maxi(absi(b.x - a.x), absi(b.y - a.y)), absi(b.z - a.z))
	for i in steps + 1:
		var t: float = float(i) / float(maxi(1, steps))
		out.append(Vector3i(
			int(roundi(lerpf(float(a.x), float(b.x), t))),
			int(roundi(lerpf(float(a.y), float(b.y), t))),
			int(roundi(lerpf(float(a.z), float(b.z), t))),
		))
	return out


func cells_in_box(a: Vector3i, b: Vector3i, hollow: bool) -> Array:
	var lo := Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))
	var hi := Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))
	var out: Array = []
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				if hollow:
					var on_shell: bool = x == lo.x or x == hi.x or y == lo.y or y == hi.y \
						or z == lo.z or z == hi.z
					if not on_shell:
						continue
				out.append(Vector3i(x, y, z))
	return out


func expand_mirror_cells(cells: Array, mirror_x: bool, mirror_z: bool) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for g_v in cells:
		if not (g_v is Vector3i):
			continue
		var g: Vector3i = g_v
		var variants: Array[Vector3i] = [g]
		if mirror_x:
			variants.append(Vector3i(-g.x, g.y, g.z))
		if mirror_z:
			variants.append(Vector3i(g.x, g.y, -g.z))
		if mirror_x and mirror_z:
			variants.append(Vector3i(-g.x, g.y, -g.z))
		for v in variants:
			var k: String = grid_key(v.x, v.y, v.z)
			if seen.has(k):
				continue
			seen[k] = true
			out.append(v)
	return out


func place_many(
		cells: Array,
		color: Color,
		finish: String,
		mirror_x: bool,
		mirror_z: bool,
	) -> Array:
	var placed: Array = []
	for g_v in expand_mirror_cells(cells, mirror_x, mirror_z):
		if not can_place():
			break
		if not (g_v is Vector3i):
			continue
		var g: Vector3i = g_v
		if not is_in_bounds(g) or has_cell(g):
			continue
		var rec: Dictionary = place_cell(g, color, finish)
		if rec.is_empty():
			continue
		rec["kind"] = "build_place"
		rec["grid"] = g
		placed.append(rec)
	return placed


func compute_shelter_points() -> Array:
	var points: Array = []
	var checked: Dictionary = {}
	var dirs: Array[Vector3i] = [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	]
	for key in _cells.keys():
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 3:
			continue
		var solid: Vector3i = Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
		for d in dirs:
			var air: Vector3i = solid + d
			if has_cell(air):
				continue
			var ak: String = grid_key(air.x, air.y, air.z)
			if checked.has(ak):
				continue
			checked[ak] = true
			if not is_in_bounds(air):
				continue
			var neighbors: int = 0
			for d2 in dirs:
				if has_cell(air + d2):
					neighbors += 1
			if neighbors >= 4:
				points.append(grid_to_world(air))
	return points


func compute_bubble_anchors() -> Array:
	var anchors: Array = []
	for key in _cells.keys():
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 3:
			continue
		var e: Dictionary = _cells[key]
		if String(e.get("finish", "")) != "glow":
			continue
		var g := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
		var wp: Vector3 = grid_to_world(g)
		anchors.append(wp + Vector3(CELL * 0.5, CELL * 0.35, CELL * 0.5))
	return anchors


func sync_world_features(force: bool = false) -> void:
	if not force and _sync_pending:
		return
	_sync_pending = true
	_sync_occupancy()
	if _world == null:
		_sync_pending = false
		return
	if _world.has_method("sync_build_shelter_points"):
		_world.sync_build_shelter_points(compute_shelter_points())
	if _world.has_method("sync_build_bubble_emitters"):
		_world.sync_build_bubble_emitters(compute_bubble_anchors())
	if _world.has_method("sync_build_territory_sites"):
		_world.sync_build_territory_sites(compute_shelter_points())
	if _world.has_method("sync_build_glow_lights"):
		_world.sync_build_glow_lights(compute_bubble_anchors())
	if _world.has_method("sync_build_graze_cells"):
		_world.sync_build_graze_cells(_cells.size())
	if _world.has_method("sync_build_epiphyte_anchors"):
		_world.sync_build_epiphyte_anchors(compute_epiphyte_anchors())
	if _substrate_dirty and _world.has_method("rebuild_substrate_mesh"):
		_world.rebuild_substrate_mesh()
		_substrate_dirty = false
	_sync_pending = false


func compute_epiphyte_anchors() -> Array:
	var anchors: Array = []
	for key in _cells.keys():
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 3:
			continue
		var g := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
		if has_cell(g + Vector3i(0, 1, 0)):
			continue
		var wp: Vector3 = grid_to_world(g)
		anchors.append(wp + Vector3(0, CELL * 0.55, 0))
	return anchors


func apply_patina_tint() -> void:
	if _batch == null:
		return
	for key in _cells.keys():
		var e: Dictionary = _cells[key]
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 3:
			continue
		var base: Color = e.get("color", Color.WHITE)
		var tinted: Color = _apply_patina(base)
		var h: Variant = _handles.get(key)
		if h != null and h is VoxelBatch.Handle:
			(h as VoxelBatch.Handle).set_color(tinted)
	_batch.flush()


func _vary_color(g: Vector3i, c: Color) -> Color:
	var h: int = absi(g.x * 92837111 ^ g.y * 689287499 ^ g.z * 283923481)
	var j: float = float(h % 17) / 17.0 * 0.12 - 0.06
	return c.lightened(j)


func _apply_patina(c: Color) -> Color:
	if _world == null or not _world.has_method("build_patina_factor"):
		return c
	var p: float = float(_world.build_patina_factor())
	if p <= 0.001:
		return c
	var algae: Color = Color8(70, 110, 75)
	return c.lerp(algae, p * 0.35).darkened(p * 0.08)


func request_sync_deferred() -> void:
	_sync_pending = false
	sync_world_features(true)


func cells_in_brush(center: Vector3i, radius: int, shape: String) -> Array:
	var out: Array = []
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				var g := Vector3i(center.x + dx, center.y + dy, center.z + dz)
				match shape:
					"sphere":
						if dx * dx + dy * dy + dz * dz > radius * radius:
							continue
					"disc":
						if dx * dx + dz * dz > radius * radius:
							continue
					_:
						pass
				out.append(g)
	return out


func _ensure_batch_material_opaque() -> void:
	if _batch == null or _batch.mmi == null:
		return
	if _opaque_batch_mat == null:
		_opaque_batch_mat = VoxelMat.make_voxel_mm()
	_batch.mmi.material_override = _opaque_batch_mat


func _display_color_for_finish(color: Color, finish: String) -> Color:
	var c: Color = _apply_patina(color)
	match finish:
		"glass":
			return c.lightened(0.42)
		"glow":
			return (c * 1.35).clamp()
		"metal":
			return c.lightened(0.15)
		"caustic":
			return c.lightened(0.08)
		_:
			return c


func _estimate_face_normal(g: Vector3i, hit_world: Vector3) -> Vector3:
	var center: Vector3 = grid_to_world(g)
	var d: Vector3 = hit_world - center
	var ax: float = absf(d.x)
	var ay: float = absf(d.y)
	var az: float = absf(d.z)
	if ax >= ay and ax >= az:
		return Vector3(signf(d.x), 0, 0)
	if ay >= az:
		return Vector3(0, signf(d.y), 0)
	return Vector3(0, 0, signf(d.z))


func _mark_occupancy(wp: Vector3) -> void:
	if _world != null and _world.has_method("_mark_hardscape_occupancy"):
		_world._mark_hardscape_occupancy(wp, Vector3(CELL, CELL, CELL))


func _sync_occupancy() -> void:
	if _world == null or not ("_hardscape_occupancy" in _world):
		return
	_world._hardscape_occupancy.clear()
	for key in _cells.keys():
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 3:
			continue
		_mark_occupancy(grid_to_world(Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))))
