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
@export var radius_step: float = 0.005
@export var height_step: float = 0.18    # vertical rise per voxel (vs VOXEL_SIZE for stems)
@export var radius_cap: float = 0.15      # maximum radius before the spiral plateaus


func _grow_one() -> bool:
	if current_height >= max_height:
		return false
	var idx: int = current_height
	# Phyllotaxis: theta = idx * golden_angle, r = radius_step * sqrt(idx).
	var theta: float = float(idx) * GOLDEN_ANGLE
	var r: float = minf(radius_step * sqrt(float(idx) + 1.0), radius_cap)
	
	# Color ramp: outer / older leaves (low idx) are deeper green, inner / new
	# leaves (high idx, central rosette) are brighter.
	var rel: float = float(idx) / float(maxi(1, max_height - 1))
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	
	# Tight vertical leaves.
	var leaf_len: int = clampi(2 + int((1.0 - rel) * 2.0), 2, 4)
	var leaf_voxels: Array = LeafShapes.build_paddle(leaf_len, ramp, 1.0 - rel, 2, 0.45)
	
	var leaf_root := Node3D.new()
	var outward := Vector3(cos(theta), 0.0, sin(theta))
	leaf_root.position = Vector3(0.0, float(idx) * height_step, 0.0) + outward * r
	leaf_root.look_at(leaf_root.position + outward, Vector3.UP)
	
	# Godot look_at makes local -Z point outward.
	# Pitching by -X tilts the leaf (which grows along +Y) towards -Z (outward).
	leaf_root.rotation.x = -lerpf(PI * 0.08, PI * 0.01, rel)
	
	add_child(leaf_root)
	
	# Add to our internal tracking so decay and shedding works exactly like other plants.
	for v in leaf_voxels:
		leaf_root.add_child(v)
		voxels.append(v)
		
	_leaf_nodes.append(leaf_root)
	_leaf_ages.append(0.0)
	
	current_height += 1
	return true


# top_world_y reads the top of the spiral rosette - which is the crown height
# plus the vertical extension of the newest, most upright leaf.
func top_world_y() -> float:
	if voxels.is_empty():
		return global_position.y
	var crown_y: float = float(current_height) * height_step
	# Leaf is ~8 voxels long, each 0.85 * VOXEL_SIZE, pitched at ~PI*0.05 (almost vertical).
	var leaf_extension: float = 8.0 * VOXEL_SIZE * 0.85 * cos(PI * 0.05)
	return global_position.y + crown_y + leaf_extension


func get_seed_config() -> Dictionary:
	var cfg: Dictionary = super.get_seed_config()
	cfg["radius_step"] = radius_step
	cfg["height_step"] = height_step
	cfg["radius_cap"] = radius_cap
	return cfg
