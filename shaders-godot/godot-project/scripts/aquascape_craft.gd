# Composition coaching, flood-fill, scape analysis, guides.
# AQUASCAPING_CRAFT §C #23, §G #62–70, §D #39.
class_name AquascapeCraft
extends RefCounted

const BUILD_PALETTE_INDICES: Array = AquascapeObjectLibrary.BUILD_PALETTE


static func flood_fill(grid: AquascapeBuildGrid, start: Vector3i, color: Color, finish: String, max_cells: int = 512) -> Array:
	if grid == null or grid.has_cell(start):
		return []
	var dirs: Array[Vector3i] = [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	]
	var queue: Array[Vector3i] = [start]
	var visited: Dictionary = {}
	var fill_cells: Array = []
	while not queue.is_empty() and fill_cells.size() < max_cells:
		var g: Vector3i = queue.pop_front()
		var key: String = "%d,%d,%d" % [g.x, g.y, g.z]
		if visited.has(key):
			continue
		if grid.has_cell(g) or not grid.is_in_bounds(g):
			continue
		visited[key] = true
		fill_cells.append(g)
		for d in dirs:
			queue.append(g + d)
	return grid.place_many(fill_cells, color, finish, false, false)


static func gradient_fill(
		grid: AquascapeBuildGrid,
		start: Vector3i,
		color_a: Color,
		color_b: Color,
		finish: String,
		max_cells: int = 256,
	) -> Array:
	if grid == null:
		return []
	var dirs: Array[Vector3i] = [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	]
	var queue: Array = [{"g": start, "d": 0}]
	var visited: Dictionary = {}
	var placements: Array = []
	var max_d: int = 1
	while not queue.is_empty() and placements.size() < max_cells:
		var item: Dictionary = queue.pop_front()
		var g: Vector3i = item["g"]
		var dist: int = int(item["d"])
		max_d = maxi(max_d, dist)
		var key: String = "%d,%d,%d" % [g.x, g.y, g.z]
		if visited.has(key):
			continue
		if grid.has_cell(g) or not grid.is_in_bounds(g):
			continue
		visited[key] = true
		placements.append({"g": g, "d": dist})
		for d in dirs:
			queue.append({"g": g + d, "d": dist + 1})
	var placed: Array = []
	for p in placements:
		var g2: Vector3i = p["g"]
		var t: float = float(p["d"]) / float(maxi(1, max_d))
		var pi: int = int(t * 15.0) % 16
		var use_b: bool = pi >= 8
		var c: Color = color_a if not use_b else color_b
		if not grid.can_place():
			break
		var rec: Dictionary = grid.place_cell(g2, c, finish)
		if rec.is_empty():
			continue
		rec["kind"] = "build_place"
		rec["grid"] = g2
		placed.append(rec)
	return placed


static func recolor_build(grid: AquascapeBuildGrid, theme: String) -> int:
	if grid == null:
		return 0
	var shift: Dictionary = {
		"coral": Color8(180, 100, 90),
		"obsidian": Color8(60, 58, 70),
		"zen": Color8(120, 115, 110),
		"fantasy": Color8(140, 90, 200),
	}
	var target: Color = shift.get(theme, Color8(130, 125, 135))
	var n: int = 0
	for v in grid.export_voxel_list():
		if not (v is Dictionary):
			continue
		var g := Vector3i(int(v.get("ix", 0)), int(v.get("iy", 0)), int(v.get("iz", 0)))
		var old: Color = SaveHelpers.array_to_color(v.get("color", []), Color.WHITE)
		var mapped: Color = old.lerp(target, 0.55)
		grid.remove_cell(g)
		if not grid.place_cell(g, mapped, String(v.get("finish", "matte"))).is_empty():
			n += 1
	return n


static func analyze_scape(world: Node3D, grid: AquascapeBuildGrid, placed: Array) -> Dictionary:
	var tips: Array[String] = []
	var voxel_n: int = grid.voxel_count() if grid != null else 0
	var hw: float = float(world.get("TANK_HALF_W")) if world != null else 4.0
	var hd: float = float(world.get("TANK_HALF_D")) if world != null else 2.0
	var wh: float = float(world.get("WATER_HEIGHT")) if world != null else 6.5
	var tank_vol: float = maxf(1.0, hw * 2.0 * hd * 2.0 * wh)
	var build_vol: float = float(voxel_n) * 0.064
	var open_pct: float = clampf(100.0 - (build_vol / tank_vol) * 100.0, 0.0, 100.0)
	if open_pct < 35.0:
		tips.append("Center feels crowded — leave more open water.")
	elif open_pct > 78.0:
		tips.append("Lots of swimming room; a focal piece could anchor the scape.")
	var cx: float = 0.0
	var cz: float = 0.0
	var mass_n: int = 0
	if grid != null:
		for key in grid.export_voxel_list():
			if not (key is Dictionary):
				continue
			cx += float(key.get("ix", 0))
			cz += float(key.get("iz", 0))
			mass_n += 1
	for node in placed:
		if is_instance_valid(node):
			cx += node.global_position.x / TerrainVoxelGrid.CELL_SIZE
			cz += node.global_position.z / TerrainVoxelGrid.CELL_SIZE
			mass_n += 1
	var focal_off: float = 0.0
	if mass_n > 0:
		cx /= float(mass_n)
		cz /= float(mass_n)
		focal_off = sqrt(cx * cx + cz * cz)
		if focal_off < 1.5:
			tips.append("Mass sits near center — try a thirds power-point.")
		else:
			tips.append("Nice asymmetry — focal mass off-center.")
	var style: String = "Nature"
	if voxel_n > 120:
		style = "Dutch"
	elif voxel_n < 25 and mass_n < 8:
		style = "Iwagumi"
	elif open_pct < 50.0:
		style = "Jungle"
	for node in placed:
		if is_instance_valid(node) and String(node.get_meta("aquascape_tool", "")) == "wood":
			style = "Biotope"
			break
	return {
		"style": style,
		"open_water_pct": open_pct,
		"voxels": voxel_n,
		"tips": tips,
		"focal_offset": focal_off,
	}


static func style_palette_hint(style: String) -> String:
	match style:
		"Iwagumi", "Zen":
			return "Muted stone + single accent."
		"Dutch":
			return "Terraced slopes + colorful stems."
		"Fantasy", "Jungle":
			return "Glow/glass accents + dense clusters."
		"Biotope":
			return "Driftwood + peat tones."
	return "Sand paths through soil read natural."


static func compress_voxels(voxels: Array) -> Array:
	var out: Array = []
	for v in voxels:
		if not (v is Dictionary):
			continue
		var c: Color = SaveHelpers.array_to_color(v.get("color", []), Color.WHITE)
		var pi: int = _palette_index(c)
		out.append({
			"ix": int(v.get("ix", 0)),
			"iy": int(v.get("iy", 0)),
			"iz": int(v.get("iz", 0)),
			"pi": pi,
			"finish": String(v.get("finish", "matte")),
		})
	return out


static func decompress_voxels(compact: Array) -> Array:
	var out: Array = []
	for v in compact:
		if not (v is Dictionary):
			continue
		var pi: int = int(v.get("pi", 0))
		var c: Color = BUILD_PALETTE_INDICES[clampi(pi, 0, BUILD_PALETTE_INDICES.size() - 1)]
		if v.has("color"):
			c = SaveHelpers.array_to_color(v.get("color", []), c)
		out.append({
			"ix": int(v.get("ix", 0)),
			"iy": int(v.get("iy", 0)),
			"iz": int(v.get("iz", 0)),
			"color": SaveHelpers.color_to_array(c),
			"finish": String(v.get("finish", "matte")),
		})
	return out


static func _palette_index(c: Color) -> int:
	var best_i: int = 0
	var best_d: float = INF
	for i in BUILD_PALETTE_INDICES.size():
		var pc: Color = BUILD_PALETTE_INDICES[i]
		var d: float = (c.r - pc.r) * (c.r - pc.r) + (c.g - pc.g) * (c.g - pc.g) + (c.b - pc.b) * (c.b - pc.b)
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


static func ruinify_region(grid: AquascapeBuildGrid, center: Vector3i, radius: int, ratio: float = 0.35) -> Array:
	if grid == null:
		return []
	var removed: Array = []
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if randf() > ratio:
					continue
				var g := Vector3i(center.x + dx, center.y + dy, center.z + dz)
				var prev: Dictionary = grid.remove_cell(g)
				if not prev.is_empty():
					prev["kind"] = "build_remove"
					removed.append(prev)
	return removed
