extends SceneTree

# First sculpt row above the bed must exist in the terrain grid AND survive mesh culling.
func _initialize() -> void:
	var fp := TankFootprint.new()
	fp.half_w = 4.0
	fp.half_d = 2.0
	fp.substrate_y = 1.61
	fp.water_y = 6.5
	const SUB: float = 1.61
	const WH: float = 6.5
	const CELL: float = TerrainVoxelGrid.CELL_SIZE

	var sculpt_y: float = SUB + CELL * 0.5  # first row stacked on bed cap
	if fp.is_substrate_voxel(0.0, sculpt_y, 0.0, 0.12):
		push_error("[smoke_terrain_sculpt] stacked row must not pass substrate prism")
		quit(1)
		return

	var terrain_ok := func(x: float, y: float, z: float, margin: float) -> bool:
		if y <= SUB + CELL * 0.6:
			if fp.is_substrate_voxel(x, y, z, margin):
				return true
		return y > -0.05 and y < WH - 0.35 and fp.is_inside(x, z, margin)

	if not terrain_ok.call(0.0, sculpt_y, 0.0, 0.12):
		push_error("[smoke_terrain_sculpt] dead-zone row must render via sculpt fallback")
		quit(1)
		return

	var tg := TerrainVoxelGrid.new()
	tg.configure(4.0, 2.0, SUB, 4.0, 2.0, 0.0)
	var sculpt_ok := func(x: float, y: float, z: float, margin: float) -> bool:
		return terrain_ok.call(x, y, z, margin)
	tg.populate_initial(
		sculpt_ok,
		TerrainVoxelGrid.CellMaterial.AQUASOIL,
		RandomNumberGenerator.new(),
		"box",
		{},
	)
	if tg.place_at_column(0.0, 0.0, TerrainVoxelGrid.CellMaterial.AQUASOIL, sculpt_ok).is_empty():
		push_error("[smoke_terrain_sculpt] first sculpt failed")
		quit(1)
		return
	if tg.place_at_column(0.0, 0.0, TerrainVoxelGrid.CellMaterial.AQUASOIL, sculpt_ok).is_empty():
		push_error("[smoke_terrain_sculpt] second sculpt failed")
		quit(1)
		return
	var buckets: Dictionary = tg.build_render_buckets(SUB, 2, sculpt_ok)
	var rendered: int = 0
	for b_key in buckets:
		rendered += (buckets[b_key]["transforms"] as Array).size()
	if rendered < 5:
		push_error("[smoke_terrain_sculpt] expected bed+stack voxels in mesh, got %d" % rendered)
		quit(1)
		return
	if tg.surface_material_at(0.0, 0.0) != TerrainVoxelGrid.CellMaterial.AQUASOIL:
		push_error("[smoke_terrain_sculpt] surface material readback failed")
		quit(1)
		return

	# Enlarged tank: overlay a small saved bed onto a larger fresh grid.
	var small := TerrainVoxelGrid.new()
	small.configure(4.0, 2.0, SUB, 4.0, 2.0, 0.0)
	small.populate_initial(sculpt_ok, TerrainVoxelGrid.CellMaterial.AQUASOIL,
		RandomNumberGenerator.new(), "box", {})
	var snap: Dictionary = small.to_save_dict()
	var large_fp := TankFootprint.new()
	large_fp.half_w = 8.0
	large_fp.half_d = 4.0
	large_fp.substrate_y = SUB
	large_fp.water_y = WH
	var large_ok := func(x: float, y: float, z: float, margin: float) -> bool:
		if y <= SUB + CELL * 0.6:
			return large_fp.is_substrate_voxel(x, y, z, margin)
		return y > -0.05 and y < WH - 0.35 and large_fp.is_inside(x, z, margin)
	var large := TerrainVoxelGrid.new()
	large.configure(8.0, 4.0, SUB, 8.0, 4.0, 0.0)
	large.populate_initial(large_ok, TerrainVoxelGrid.CellMaterial.SAND,
		RandomNumberGenerator.new(), "box", {})
	if not large.overlay_save_dict(snap):
		push_error("[smoke_terrain_sculpt] overlay_save_dict failed")
		quit(1)
		return
	var edge_mat: int = large.get_material(large.cols - 1, 1, large.depths - 1)
	if edge_mat == TerrainVoxelGrid.CellMaterial.EMPTY:
		push_error("[smoke_terrain_sculpt] expanded region still bare after overlay")
		quit(1)
		return
	var center_mat: int = large.get_material(large.cols / 2, 2, large.depths / 2)
	if center_mat == TerrainVoxelGrid.CellMaterial.EMPTY:
		push_error("[smoke_terrain_sculpt] saved sculpt not overlaid at center")
		quit(1)
		return

	print("[smoke] terrain sculpt row renders OK")
	quit(0)
