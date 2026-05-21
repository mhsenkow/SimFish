# A branching plant. Extends Plant by occasionally spawning side branches
# at angles as it grows taller. Branches are themselves Plant nodes (smaller
# max_height, slower growth) attached as children, so they're still tickable,
# nibble-able, and follow all the same chemistry rules.
#
# Growth pattern is L-system inspired: every N voxels along the main stem,
# probabilistically spawn a side shoot rotated by branch_angle around the
# vertical axis. Branches branch again at lower probability, capped by
# depth so the tree doesn't explode.

extends Plant
class_name BranchPlant

@export var branch_chance: float = 0.35    # per-voxel chance to fork
@export var branch_interval: int = 3       # min stem voxels between branches
@export var branch_angle_deg: float = 35.0
@export var branch_depth: int = 0          # increments per generation; capped
@export var max_branch_depth: int = 2

var _last_branch_at: int = -99
var _branches: Array[BranchPlant] = []


func _grow_one() -> bool:
	# Grow a stem voxel like the parent class does, then maybe spawn a branch.
	var grew: bool = super._grow_one()
	if not grew:
		return false
	if branch_depth < max_branch_depth \
			and current_height >= _last_branch_at + branch_interval \
			and current_height >= 2 \
			and randf() < branch_chance:
		_spawn_branch()
		_last_branch_at = current_height
	return true


func _spawn_branch() -> void:
	# Spawn a child BranchPlant tilted at branch_angle_deg around a random
	# Y rotation off the current top voxel. It grows independently with a
	# shorter max height than the parent.
	var child := BranchPlant.new()
	add_child(child)
	# Local position: at the top of our current stem.
	child.position = Vector3(0, current_height * VOXEL_SIZE, 0)
	# Random horizontal direction.
	var yaw_rad: float = randf() * TAU
	child.rotation.y = yaw_rad
	child.rotation.z = deg_to_rad(branch_angle_deg) * (1.0 if randf() < 0.5 else -1.0)
	# Children grow smaller, slower, with progressively less branching.
	var child_max: int = maxi(2, max_height - current_height - branch_depth * 2)
	child.ramp_override = ramp_override
	child.water_surface_y = water_surface_y
	child.generation = generation  # branches are part of the same plant
	child.branch_depth = branch_depth + 1
	child.branch_chance = branch_chance * 0.55     # less branching at depth
	child.init(0, {
		"max_height": child_max,
		"growth_rate": growth_rate * 0.9,
		"sway_amplitude": sway_amplitude * 1.2,    # branches sway more
	})
	_branches.append(child)


func biomass() -> int:
	# A branching plant's total biomass = main stem + all branches recursively.
	# This matters because shrimp + fish gate plant nibbling on a minimum
	# biomass threshold; the whole tree counts as one biomass pool.
	var total: int = current_height
	for b in _branches:
		if is_instance_valid(b):
			total += b.biomass()
	return total


# Nibble prioritizes the outermost branches to simulate natural grazing.
# It delegates the bite to the heaviest valid branch. Only if no valid
# branches remain will the main stem itself be eaten. This prevents the
# whole tree from being felled like a beaver chewed the trunk!
func nibble(amount: int) -> int:
	var valid_branches: Array[BranchPlant] = []
	for b in _branches:
		if is_instance_valid(b) and b.biomass() > 0:
			valid_branches.append(b)
			
	if valid_branches.size() > 0:
		var heaviest: BranchPlant = valid_branches[0]
		for b in valid_branches:
			if b.biomass() > heaviest.biomass():
				heaviest = b
		return heaviest.nibble(amount)
	
	# Fall through to base behavior only if no valid branches are left.
	return super.nibble(amount)


func _on_death() -> void:
	# When a branching plant dies, it returns nutrients proportional to
	# its total biomass, not just the root mass. This prevents massive
	# nutrient loss when a complex tree is killed.
	var total_mass: int = biomass()
	var sim_driver: Node = _find_sim()
	if sim_driver != null and sim_driver.substrate != null:
		# A base plant returns 0.35. We add ~0.05 per voxel of total biomass.
		sim_driver.substrate.add_at(global_position, 0.35 + float(total_mass) * 0.05)


func get_seed_config() -> Dictionary:
	var cfg: Dictionary = super.get_seed_config()
	cfg["branch_chance"] = branch_chance
	cfg["branch_interval"] = branch_interval
	cfg["branch_angle_deg"] = branch_angle_deg
	return cfg
