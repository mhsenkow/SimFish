# Fibonacci spiral plant.
#
# Voxels are placed in a phyllotaxis pattern - each new voxel is rotated by
# the golden angle (137.5°) around the central axis and placed at a slightly
# greater radius and slightly greater height. This produces the classic
# sunflower-head / pinecone / aloe-vera arrangement seen everywhere in nature.
#
# Still extends Plant so all chemistry (substrate nutrient consumption,
# nibble-ability, lifespan) is inherited unchanged.

extends Plant
class_name SpiralPlant

# The golden angle in radians: 2π × (1 - 1/φ). ~137.508°.
const GOLDEN_ANGLE: float = 2.39996322972865332

# How far each voxel sits from the central axis. Scales with voxel index so
# the spiral spreads outward as it grows.
@export var radius_step: float = 0.06
@export var height_step: float = 0.18    # vertical rise per voxel (vs VOXEL_SIZE for stems)
@export var radius_cap: float = 1.6      # maximum radius before the spiral plateaus


func _grow_one() -> bool:
	if current_height >= max_height:
		return false
	var idx: int = current_height
	# Phyllotaxis: theta = idx * golden_angle, r = radius_step * sqrt(idx).
	# sqrt growth keeps voxel density roughly constant (Vogel's spiral).
	var theta: float = float(idx) * GOLDEN_ANGLE
	var r: float = minf(radius_step * sqrt(float(idx) + 1.0), radius_cap)
	var pos := Vector3(
		cos(theta) * r,
		float(idx) * height_step,
		sin(theta) * r,
	)
	# Color ramp: outer / older voxels (low idx) are deeper green, inner / new
	# voxels (high idx, central rosette) are brighter to make the spiral pattern
	# read clearly.
	var rel: float = float(idx) / float(maxi(1, max_height - 1))
	var ramp_idx: int = clampi(int(rel * 5.0), 0, 5)
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	var color: Color = ramp[ramp_idx]
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(VOXEL_SIZE * 0.95, VOXEL_SIZE * 0.6, VOXEL_SIZE * 0.95)
	mi.mesh = bm
	mi.material_override = VoxelMat.make(color)
	mi.position = pos
	add_child(mi)
	voxels.append(mi)
	current_height += 1
	return true


# top_world_y reads the top of the spiral - which is the most recently placed
# voxel (highest Y position in local coords).
func top_world_y() -> float:
	if voxels.is_empty():
		return global_position.y
	var top_local: float = float(current_height) * height_step
	return global_position.y + top_local
