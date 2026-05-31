# Editable 3D terrain grid for the tank floor and aquascape sculpting.
#
# Each cell stores a Material + nutrient value. EMPTY cells are skipped during
# mesh generation (voids / caves). Soil types use distinct color ramps from
# TankConfig.SUBSTRATE_PROFILES so sand, gravel, aquasoil, and peat read
# clearly different in the viewport.

class_name TerrainVoxelGrid
extends RefCounted

enum CellMaterial {
	EMPTY = 0,
	GRAVEL = 1,
	AQUASOIL = 2,
	SAND = 3,
	ECO_SOIL = 4,
	PEAT = 5,
}

const CELL_SIZE: float = 0.4
const EXTRA_SCULPT_ROWS: int = 14

const PROFILE_BY_MATERIAL: Dictionary = {
	CellMaterial.GRAVEL: "inert_gravel",
	CellMaterial.AQUASOIL: "aquasoil",
	CellMaterial.SAND: "sand",
	CellMaterial.ECO_SOIL: "eco_complete",
	CellMaterial.PEAT: "eco_complete",
}

const BASELINE_BY_MATERIAL: Dictionary = {
	CellMaterial.GRAVEL: 0.05,
	CellMaterial.AQUASOIL: 0.30,
	CellMaterial.SAND: 0.10,
	CellMaterial.ECO_SOIL: 0.50,
	CellMaterial.PEAT: 0.58,
}

const LEAK_BY_MATERIAL: Dictionary = {
	CellMaterial.GRAVEL: 0.0,
	CellMaterial.AQUASOIL: 0.00015,
	CellMaterial.SAND: 0.00003,
	CellMaterial.ECO_SOIL: 0.00030,
	CellMaterial.PEAT: 0.00022,
}

# High-contrast display tints chosen to survive palette quantization.
# Each entry: [surface, mid, deep] — surface is what you see when sculpting.
const DISPLAY_RAMP: Dictionary = {
	CellMaterial.GRAVEL: [
		Color8(165, 170, 185), Color8(130, 135, 150), Color8(95, 98, 112),
	],
	CellMaterial.AQUASOIL: [
		Color8(165, 115, 65), Color8(120, 78, 42), Color8(75, 50, 28),
	],
	CellMaterial.SAND: [
		Color8(252, 242, 215), Color8(235, 220, 185), Color8(210, 195, 160),
	],
	CellMaterial.ECO_SOIL: [
		Color8(90, 72, 58), Color8(55, 42, 35), Color8(28, 22, 18),
	],
	CellMaterial.PEAT: [
		Color8(62, 48, 36), Color8(38, 28, 20), Color8(22, 16, 12),
	],
}

var half_w: float = 8.0
var half_d: float = 4.0
var y_max: float = 1.6
var cols: int = 0
var depths: int = 0
var rows: int = 0
var base_rows: int = 0
var materials: PackedByteArray = PackedByteArray()
var nutrients: PackedFloat32Array = PackedFloat32Array()


static func material_from_substrate_type(substrate_key: String) -> int:
	match substrate_key:
		"sand", "ocean_sand":
			return CellMaterial.SAND
		"inert_gravel":
			return CellMaterial.GRAVEL
		"eco_complete":
			return CellMaterial.ECO_SOIL
		_:
			return CellMaterial.AQUASOIL


static func material_from_tool(tool: String) -> int:
	match tool:
		"dirt", "aquasoil":
			return CellMaterial.AQUASOIL
		"sand":
			return CellMaterial.SAND
		"gravel":
			return CellMaterial.GRAVEL
		"peat", "carbon":
			return CellMaterial.PEAT
		_:
			return CellMaterial.AQUASOIL


static func tool_is_terrain(tool: String) -> bool:
	return tool in ["dirt", "aquasoil", "sand", "gravel", "peat", "carbon"]


static func is_fallable(mat: int) -> bool:
	return mat == CellMaterial.SAND or mat == CellMaterial.GRAVEL


func _idx(cx: int, cy: int, cz: int) -> int:
	return cx + cz * cols + cy * cols * depths


func _in_bounds(cx: int, cy: int, cz: int) -> bool:
	return cx >= 0 and cz >= 0 and cy >= 0 and cx < cols and cz < depths and cy < rows


func cell_center(cx: int, cy: int, cz: int) -> Vector3:
	return Vector3(
		-half_w + (float(cx) + 0.5) * CELL_SIZE,
		(float(cy) + 0.5) * CELL_SIZE,
		-half_d + (float(cz) + 0.5) * CELL_SIZE,
	)


func world_to_cell(pos: Vector3) -> Vector3i:
	var cx: int = int(floor((pos.x + half_w) / CELL_SIZE))
	var cy: int = int(floor(pos.y / CELL_SIZE))
	var cz: int = int(floor((pos.z + half_d) / CELL_SIZE))
	return Vector3i(cx, cy, cz)


func get_material(cx: int, cy: int, cz: int) -> int:
	if not _in_bounds(cx, cy, cz):
		return CellMaterial.EMPTY
	return int(materials[_idx(cx, cy, cz)])


func get_nutrient(cx: int, cy: int, cz: int) -> float:
	if not _in_bounds(cx, cy, cz):
		return 0.0
	return nutrients[_idx(cx, cy, cz)]


func _set_cell(cx: int, cy: int, cz: int, mat: int, nut: float) -> void:
	if not _in_bounds(cx, cy, cz):
		return
	var i: int = _idx(cx, cy, cz)
	materials[i] = mat
	nutrients[i] = nut


func clear_cell(cx: int, cy: int, cz: int) -> Dictionary:
	var old: Dictionary = {
		"cx": cx, "cy": cy, "cz": cz,
		"mat": get_material(cx, cy, cz),
		"nut": get_nutrient(cx, cy, cz),
	}
	_set_cell(cx, cy, cz, CellMaterial.EMPTY, 0.0)
	return old


func restore_cell(rec: Dictionary) -> void:
	var cx: int = int(rec.get("cx", -1))
	var cy: int = int(rec.get("cy", -1))
	var cz: int = int(rec.get("cz", -1))
	if not _in_bounds(cx, cy, cz):
		return
	_set_cell(cx, cy, cz, int(rec.get("mat", CellMaterial.EMPTY)), float(rec.get("nut", 0.0)))


func configure(half_width: float, half_depth: float, substrate_depth: float,
		build_half_w: float, build_half_d: float) -> void:
	half_w = half_width
	half_d = half_depth
	y_max = substrate_depth
	cols = maxi(1, int((build_half_w * 2.0) / CELL_SIZE))
	depths = maxi(1, int((build_half_d * 2.0) / CELL_SIZE))
	base_rows = maxi(1, int(ceil(substrate_depth / CELL_SIZE)))
	rows = base_rows + EXTRA_SCULPT_ROWS
	var count: int = cols * depths * rows
	materials = PackedByteArray()
	materials.resize(count)
	materials.fill(CellMaterial.EMPTY)
	nutrients = PackedFloat32Array()
	nutrients.resize(count)
	nutrients.fill(0.0)


func populate_initial(voxel_ok: Callable, default_cap_mat: int, rng: RandomNumberGenerator,
		tank_shape: String, _bowl: Dictionary) -> void:
	# Only the bottom 2 rows are inert drainage gravel; the rest uses the
	# tank's selected substrate so settings changes are immediately visible.
	var gravel_rows: int = mini(2, base_rows)
	for cy in base_rows:
		for cx in cols:
			for cz in depths:
				var center: Vector3 = cell_center(cx, cy, cz)
				if center.y > y_max:
					continue
				if not voxel_ok.call(center.x, center.y, center.z, CELL_SIZE * 0.12):
					continue
				if tank_shape != "sphere" and cy == base_rows - 1 and rng.randf() < 0.12:
					continue
				var mat: int
				var nut: float
				if cy < gravel_rows:
					mat = CellMaterial.GRAVEL
					nut = float(BASELINE_BY_MATERIAL[CellMaterial.GRAVEL])
				else:
					mat = default_cap_mat
					nut = float(BASELINE_BY_MATERIAL.get(default_cap_mat, 0.30))
					var rel: float = float(cy - gravel_rows) / maxf(1.0, float(base_rows - gravel_rows))
					nut += rel * 0.08
				_set_cell(cx, cy, cz, mat, nut)


func column_top_cell(x: float, z: float) -> Vector3i:
	var base: Vector3i = world_to_cell(Vector3(x, y_max + CELL_SIZE * float(rows), z))
	var cx: int = clampi(base.x, 0, cols - 1)
	var cz: int = clampi(base.z, 0, depths - 1)
	for cy in range(rows - 1, -1, -1):
		if get_material(cx, cy, cz) != CellMaterial.EMPTY:
			return Vector3i(cx, cy, cz)
	return Vector3i(-1, -1, -1)


func surface_y_at(x: float, z: float) -> float:
	var top: Vector3i = column_top_cell(x, z)
	if top.x < 0:
		return 0.0
	return cell_center(top.x, top.y, top.z).y + CELL_SIZE * 0.5


func place_at_column(x: float, z: float, mat: int, voxel_ok: Callable) -> Dictionary:
	var top: Vector3i = column_top_cell(x, z)
	var cx: int
	var cy: int
	var cz: int
	if top.x < 0:
		cx = clampi(world_to_cell(Vector3(x, y_max * 0.5, z)).x, 0, cols - 1)
		cz = clampi(world_to_cell(Vector3(x, y_max * 0.5, z)).z, 0, depths - 1)
		cy = 0
	else:
		cx = top.x
		cz = top.z
		cy = top.y + 1
		# Stack upward when there's room and the cell passes the sculpt bounds.
		if cy < rows:
			var stack_center: Vector3 = cell_center(cx, cy, cz)
			if not voxel_ok.call(stack_center.x, stack_center.y, stack_center.z, CELL_SIZE * 0.12):
				cy = top.y
		else:
			cy = top.y
	if cy >= rows:
		return {}
	var center: Vector3 = cell_center(cx, cy, cz)
	if not voxel_ok.call(center.x, center.y, center.z, CELL_SIZE * 0.12):
		return {}
	var nut: float = float(BASELINE_BY_MATERIAL.get(mat, 0.30))
	if mat == CellMaterial.PEAT:
		nut += 0.12
	var undo: Dictionary = {
		"cx": cx, "cy": cy, "cz": cz,
		"mat": get_material(cx, cy, cz),
		"nut": get_nutrient(cx, cy, cz),
	}
	_set_cell(cx, cy, cz, mat, nut)
	return undo


func dig_at_column(x: float, z: float) -> Dictionary:
	var top: Vector3i = column_top_cell(x, z)
	if top.x < 0:
		return {}
	return clear_cell(top.x, top.y, top.z)


func place_brush(x: float, z: float, radius_cells: int, mat: int,
		voxel_ok: Callable) -> Array:
	var center: Vector3i = world_to_cell(Vector3(x, y_max * 0.5, z))
	var undos: Array = []
	for dx in range(-radius_cells, radius_cells + 1):
		for dz in range(-radius_cells, radius_cells + 1):
			if dx * dx + dz * dz > radius_cells * radius_cells:
				continue
			var wx: float = cell_center(
				clampi(center.x + dx, 0, cols - 1), 0,
				clampi(center.z + dz, 0, depths - 1)).x
			var wz: float = cell_center(
				clampi(center.x + dx, 0, cols - 1), 0,
				clampi(center.z + dz, 0, depths - 1)).z
			var undo: Dictionary = place_at_column(wx, wz, mat, voxel_ok)
			if not undo.is_empty():
				undos.append(undo)
	return undos


func dig_brush(x: float, z: float, radius_cells: int) -> Array:
	var center: Vector3i = world_to_cell(Vector3(x, y_max * 0.5, z))
	var undos: Array = []
	for dx in range(-radius_cells, radius_cells + 1):
		for dz in range(-radius_cells, radius_cells + 1):
			if dx * dx + dz * dz > radius_cells * radius_cells:
				continue
			var wx: float = cell_center(
				clampi(center.x + dx, 0, cols - 1), 0,
				clampi(center.z + dz, 0, depths - 1)).x
			var wz: float = cell_center(
				clampi(center.x + dx, 0, cols - 1), 0,
				clampi(center.z + dz, 0, depths - 1)).z
			var undo: Dictionary = dig_at_column(wx, wz)
			if not undo.is_empty() and int(undo.get("mat", CellMaterial.EMPTY)) \
					!= CellMaterial.EMPTY:
				undos.append(undo)
	return undos


# Basic granular physics — sand / gravel fall down (and slightly sideways into
# gaps) until supported. Runs to stability after each sculpt edit.
func settle_gravity(voxel_ok: Callable) -> bool:
	var moved_any: bool = false
	for _iteration in rows * 2:
		var moved_step: bool = false
		for cy in range(rows - 1, 0, -1):
			for cx in cols:
				for cz in depths:
					if _try_fall_cell(cx, cy, cz, voxel_ok):
						moved_step = true
		if not moved_step:
			break
		moved_any = true
	return moved_any


func _try_fall_cell(cx: int, cy: int, cz: int, voxel_ok: Callable) -> bool:
	var mat: int = get_material(cx, cy, cz)
	if not is_fallable(mat):
		return false
	var nut: float = get_nutrient(cx, cy, cz)
	var dests: Array[Vector3i] = [
		Vector3i(cx, cy - 1, cz),
		Vector3i(cx - 1, cy - 1, cz),
		Vector3i(cx + 1, cy - 1, cz),
		Vector3i(cx, cy - 1, cz - 1),
		Vector3i(cx, cy - 1, cz + 1),
	]
	for dest: Vector3i in dests:
		if not _in_bounds(dest.x, dest.y, dest.z):
			continue
		if get_material(dest.x, dest.y, dest.z) != CellMaterial.EMPTY:
			continue
		var center: Vector3 = cell_center(dest.x, dest.y, dest.z)
		if not voxel_ok.call(center.x, center.y, center.z, CELL_SIZE * 0.12):
			continue
		_set_cell(cx, cy, cz, CellMaterial.EMPTY, 0.0)
		_set_cell(dest.x, dest.y, dest.z, mat, nut)
		return true
	return false


func sample_column_nutrients(x: float, z: float) -> Dictionary:
	var top: Vector3i = column_top_cell(x, z)
	if top.x < 0:
		return {"surface": 0.15, "leak": 0.0001, "mat": CellMaterial.GRAVEL}
	var sum: float = 0.0
	var weight: float = 0.0
	var leak: float = 0.0
	var surface_mat: int = CellMaterial.GRAVEL
	var surface_is_gravel_cap: bool = false
	for i in 3:
		var cy: int = top.y - i
		if cy < 0:
			break
		var mat: int = get_material(top.x, cy, top.z)
		if mat == CellMaterial.EMPTY:
			break
		if i == 0:
			surface_mat = mat
			surface_is_gravel_cap = mat == CellMaterial.GRAVEL
		# Walstad cap: gravel surface blocks upward nutrient bleed from soil below.
		if surface_is_gravel_cap and i > 0:
			break
		var w: float = 1.0 / float(i + 1)
		sum += get_nutrient(top.x, cy, top.z) * w
		weight += w
		leak = maxf(leak, float(LEAK_BY_MATERIAL.get(mat, 0.0)))
	var surface: float = sum / maxf(weight, 1.0)
	return {"surface": surface, "leak": leak, "mat": surface_mat}


func count_exposed_peat() -> int:
	var n: int = 0
	for cx in cols:
		for cz in depths:
			var top: Vector3i = column_top_cell(
				cell_center(cx, 0, cz).x, cell_center(cx, 0, cz).z)
			if top.x >= 0 and get_material(top.x, top.y, top.z) == CellMaterial.PEAT:
				n += 1
	return n


func sync_nutrients_to_substrate(grid: SubstrateGrid) -> void:
	if grid == null:
		return
	for x in grid.cells_x:
		for z in grid.cells_z:
			var wx: float = grid.origin.x + (float(x) + 0.5) * grid.cell_size
			var wz: float = grid.origin.z + (float(z) + 0.5) * grid.cell_size
			var sample: Dictionary = sample_column_nutrients(wx, wz)
			grid.nutrients[x][z] = clampf(float(sample["surface"]), 0.0, SubstrateGrid.NUTRIENT_MAX)


func material_color(mat: int, cy: int, cx: int, cz: int) -> Color:
	if mat == CellMaterial.EMPTY:
		return Color.BLACK
	var ramp: Array = DISPLAY_RAMP.get(mat, DISPLAY_RAMP[CellMaterial.AQUASOIL])
	# Shade by depth within this column (surface = bright, buried = deep tint).
	var top: Vector3i = column_top_cell(
		cell_center(cx, cy, cz).x, cell_center(cx, cy, cz).z)
	var depth_in_col: float = 0.0
	if top.x >= 0 and top.y >= cy:
		depth_in_col = float(top.y - cy) / maxf(1.0, float(top.y + 1))
	var idx: float = clampf(depth_in_col * 2.0, 0.0, 1.0)
	# Sculpted sand/gravel piles stay visibly pale — deep-column shading was
	# making tall sand stacks read as brown soil after palette quantization.
	if is_fallable(mat) and top.x >= 0 and cy >= maxi(0, top.y - 2):
		idx = minf(idx, 0.2)
	var c0: Color = ramp[0]
	var c1: Color = ramp[mini(1, ramp.size() - 1)]
	var c2: Color = ramp[mini(2, ramp.size() - 1)]
	var color: Color = c0.lerp(c1, idx) if idx < 0.5 else c1.lerp(c2, (idx - 0.5) * 2.0)
	var cell_hash: int = absi(cx * 73856093 ^ cz * 19349663 ^ cy * 83492791)
	var jitter: float = float(cell_hash % 13) / 13.0 * 0.06 - 0.03
	return color.lightened(jitter)


func material_shader_id(mat: int) -> int:
	return mat


func build_render_buckets(y_max_limit: float, caustic_rows_from_top: int,
		voxel_ok: Callable) -> Dictionary:
	var buckets: Dictionary = {}
	for cy in rows:
		for cx in cols:
			for cz in depths:
				var mat: int = get_material(cx, cy, cz)
				if mat == CellMaterial.EMPTY:
					continue
				var center: Vector3 = cell_center(cx, cy, cz)
				if not voxel_ok.call(center.x, center.y, center.z, CELL_SIZE * 0.12):
					continue
				# Caustics only on the exposed surface cell — not the row below.
				# Putting caustic on the subsurface cap row left a visible seam (dark
				# gap) on vertical faces where opaque gravel meets caustic soil.
				var top_cell: Vector3i = column_top_cell(center.x, center.z)
				var is_caustic: bool = false
				if mat != CellMaterial.SAND and mat != CellMaterial.GRAVEL:
					if top_cell.x >= 0 and cy == top_cell.y:
						is_caustic = center.y <= y_max_limit + CELL_SIZE * 0.5 \
							and cy < base_rows
				var color: Color = material_color(mat, cy, cx, cz)
				var mat_id: int = material_shader_id(mat)
				var bucket_key: String = "%d_%d_%d" % [mat, 1 if is_caustic else 0, color.to_rgba32()]
				if not buckets.has(bucket_key):
					buckets[bucket_key] = {
						"transforms": [],
						"caustic": is_caustic,
						"color": color,
						"material_id": mat_id,
					}
				buckets[bucket_key]["transforms"].append(center)
	return buckets


func to_save_dict() -> Dictionary:
	return {
		"half_w": half_w,
		"half_d": half_d,
		"y_max": y_max,
		"cols": cols,
		"depths": depths,
		"rows": rows,
		"base_rows": base_rows,
		"materials": Array(materials),
		"nutrients": Array(nutrients),
	}


func apply_save_dict(d: Dictionary) -> bool:
	if d.is_empty():
		return false
	var sc: int = int(d.get("cols", 0))
	var sd: int = int(d.get("depths", 0))
	var sr: int = int(d.get("rows", 0))
	if sc <= 0 or sd <= 0 or sr <= 0:
		return false
	cols = sc
	depths = sd
	rows = sr
	base_rows = int(d.get("base_rows", base_rows))
	half_w = float(d.get("half_w", half_w))
	half_d = float(d.get("half_d", half_d))
	y_max = float(d.get("y_max", y_max))
	var count: int = cols * depths * rows
	var mat_arr: Array = d.get("materials", [])
	var nut_arr: Array = d.get("nutrients", [])
	if mat_arr.size() < count or nut_arr.size() < count:
		return false
	materials = PackedByteArray()
	materials.resize(count)
	nutrients = PackedFloat32Array()
	nutrients.resize(count)
	for i in count:
		materials[i] = int(mat_arr[i])
		nutrients[i] = float(nut_arr[i])
	return true
