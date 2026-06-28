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

	print("[smoke] terrain sculpt row renders OK")
	quit(0)
