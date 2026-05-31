# Terrain mesh + sculpt API extracted from world.gd for clearer boundaries.
class_name TerrainWorld
extends RefCounted

static func sculpt_ok(world: Node, px: float, py: float, pz: float, margin: float) -> bool:
	if world != null and world.has_method("_sculpt_voxel_ok"):
		return world._sculpt_voxel_ok(px, py, pz, margin)
	return true


static func place_tool(world: Node, x: float, z: float, tool: String) -> Dictionary:
	if world != null and world.has_method("terrain_place_tool"):
		return world.terrain_place_tool(x, z, tool)
	return {}


static func place_brush(world: Node, x: float, z: float, radius: int, tool: String) -> Array:
	if world != null and world.has_method("terrain_place_brush"):
		return world.terrain_place_brush(x, z, radius, tool)
	return []


static func dig(world: Node, x: float, z: float) -> Dictionary:
	if world != null and world.has_method("terrain_dig"):
		return world.terrain_dig(x, z)
	return {}


static func dig_brush(world: Node, x: float, z: float, radius: int) -> Array:
	if world != null and world.has_method("terrain_dig_brush"):
		return world.terrain_dig_brush(x, z, radius)
	return []


static func restore_cell(world: Node, rec: Dictionary) -> void:
	if world != null and world.has_method("terrain_restore_cell"):
		world.terrain_restore_cell(rec)


static func rebuild_mesh(world: Node) -> void:
	if world != null and world.has_method("rebuild_substrate_mesh"):
		world.rebuild_substrate_mesh()


static func sync_nutrients(world: Node) -> void:
	if world != null and world.has_method("sync_terrain_nutrients"):
		world.sync_terrain_nutrients()
