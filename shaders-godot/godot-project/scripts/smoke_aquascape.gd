extends SceneTree

const AquascapeCraft = preload("res://scripts/aquascape_craft.gd")

const ObjectMeshes := preload("res://scripts/aquascape_object_meshes.gd")

# Compile + exercise aquascape build grid, object library, blueprints, save round-trip.
func _initialize() -> void:
	await process_frame
	var w: Node3D = load("res://scripts/smoke_aquascape_stub.gd").new() as Node3D
	w.name = "SmokeAquascapeStub"
	root.add_child(w)
	var hs := Node3D.new()
	hs.name = "Hardscape"
	w.add_child(hs)
	await process_frame

	var grid := AquascapeBuildGrid.new()
	grid.setup(hs, w)
	var g := Vector3i(1, 3, 1)
	if grid.place_cell(g, Color8(120, 110, 100), "matte").is_empty():
		push_error("[smoke_aquascape] place_cell failed")
		quit(1)
		return
	var wp: Vector3 = grid.grid_to_world(g)
	var back: Vector3i = grid.world_to_grid(wp)
	if back != g:
		push_error("[smoke_aquascape] grid coord round-trip failed %s -> %s" % [g, back])
		quit(1)
		return
	var saved: Array = grid.to_save_arr()
	grid.clear()
	grid.restore_from_save(saved)
	if grid.voxel_count() != 1:
		push_error("[smoke_aquascape] round-trip count %d" % grid.voxel_count())
		quit(1)
		return
	if grid.place_cell(Vector3i(2, 3, 2), Color8(200, 220, 240), "glass").is_empty():
		push_error("[smoke_aquascape] glass place_cell failed")
		quit(1)
		return
	var batch_mat: Material = grid._batch.mmi.material_override
	if batch_mat is ShaderMaterial:
		var sh: Shader = (batch_mat as ShaderMaterial).shader
		if sh != null and sh.resource_path.ends_with("voxel_translucent.gdshader"):
			push_error("[smoke_aquascape] glass finish must not make whole batch translucent")
			quit(1)
			return
		if sh != null and not sh.resource_path.ends_with("voxel_mm.gdshader"):
			push_error("[smoke_aquascape] build batch must use voxel_mm shader")
			quit(1)
			return

	var bed: Vector3i = Vector3i(3, 2, 1)
	var cap: Vector3 = grid.grid_to_world(bed)
	if grid.covers_substrate_center(cap):
		push_error("[smoke_aquascape] empty grid should not cover substrate")
		quit(1)
		return
	if not grid.place_cell(bed, Color8(100, 90, 80), "matte").is_empty():
		pass
	if not grid.covers_substrate_center(cap):
		push_error("[smoke_aquascape] build voxel must hide same-cell substrate")
		quit(1)
		return

	var surface_y: float = 1.6
	var snap: Vector3i = grid.snap_cell_on_surface(0.0, 0.0, surface_y)
	var snap_wp: Vector3 = grid.grid_to_world(snap)
	if absf(snap_wp.y + TerrainVoxelGrid.CELL_SIZE * 0.5 - surface_y) > 0.02:
		push_error("[smoke_aquascape] snap_cell_on_surface top should match bed surface")
		quit(1)
		return

	AquascapeObjectLibrary._ensure_objects()
	var castle: Array = AquascapeObjectLibrary.voxels_for("castle")
	if castle.is_empty():
		push_error("[smoke_aquascape] castle voxels empty")
		quit(1)
		return
	var param_castle: Array = AquascapeObjectLibrary.voxels_for(
		"castle", {"towers": 6, "height": 9})
	if param_castle.size() <= castle.size():
		push_error("[smoke_aquascape] parametric castle not larger")
		quit(1)
		return
	if grid.place_object_voxels(castle, Vector3(0, 2, 0), Color8(130, 125, 135)).is_empty():
		push_error("[smoke_aquascape] castle placement failed")
		quit(1)
		return

	var epiphytes: Array = grid.compute_epiphyte_anchors()
	if epiphytes.is_empty():
		push_error("[smoke_aquascape] epiphyte anchors empty")
		quit(1)
		return

	var grad: Array = AquascapeCraft.gradient_fill(
		grid, Vector3i(4, 2, 1), Color8(100, 140, 180), Color8(40, 60, 90), "matte", 24)
	if grad.is_empty():
		push_error("[smoke_aquascape] gradient fill failed")
		quit(1)
		return

	var recolored: int = AquascapeCraft.recolor_build(grid, "zen")
	if recolored <= 0:
		push_error("[smoke_aquascape] recolor failed")
		quit(1)
		return

	var export_list: Array = grid.export_voxel_list()
	var code: String = AquascapeBlueprint.encode_voxels(export_list, {"name": "smoke"})
	if code.is_empty() or not (code.begins_with("WLBP1:") or code.begins_with("WLBP2:")):
		push_error("[smoke_aquascape] encode failed")
		quit(1)
		return
	var decoded: Dictionary = AquascapeBlueprint.decode_voxels(code)
	if decoded.is_empty() or not (decoded.get("voxels") is Array):
		push_error("[smoke_aquascape] decode failed")
		quit(1)
		return

	if TerrainVoxelGrid.material_from_tool("lava_rock") != TerrainVoxelGrid.CellMaterial.LAVA_ROCK:
		push_error("[smoke_aquascape] terrain material mapping failed")
		quit(1)
		return
	if TerrainVoxelGrid.tool_from_material(TerrainVoxelGrid.CellMaterial.PEAT) != "peat":
		push_error("[smoke_aquascape] terrain tool reverse mapping failed")
		quit(1)
		return

	var pebble: Array = AquascapeObjectLibrary.voxels_for("pebble")
	grid.clear()
	var pebble_g: Vector3i = grid.snap_cell_on_surface(0.0, 0.0, surface_y)
	var pebble_origin: Vector3 = grid.grid_to_world(pebble_g)
	if grid.place_object_voxels(pebble, pebble_origin, Color8(180, 180, 190)).is_empty():
		push_error("[smoke_aquascape] pebble voxel placement failed")
		quit(1)
		return

	var boulder: Node3D = ObjectMeshes.spawn("boulder", {})
	if boulder.get_child_count() < 2:
		push_error("[smoke_aquascape] boulder mesh spawn failed")
		quit(1)
		return
	var bfp: Vector3 = ObjectMeshes.footprint("boulder", {})
	if bfp.y < 0.5:
		push_error("[smoke_aquascape] boulder footprint too small")
		quit(1)
		return

	if AquascapeBlueprint.showcase_blueprints().is_empty():
		push_error("[smoke_aquascape] showcase empty")
		quit(1)
		return

	var analysis: Dictionary = AquascapeCraft.analyze_scape(w, grid, [])
	if String(analysis.get("style", "")).is_empty():
		push_error("[smoke_aquascape] analyze_scape failed")
		quit(1)
		return

	print("[smoke] aquascape build grid + library + blueprint OK")
	quit(0)
