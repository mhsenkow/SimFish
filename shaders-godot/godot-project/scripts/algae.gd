# An algae patch. Stochastically appears when nutrients are high + plant
# biomass is low (N:P imbalance), spreads slowly, dies off when conditions
# normalize. Now visually dynamic: grows from a single voxel into a small
# cluster during its life, drifts gently with a sin curve, fades alpha
# during senescence. Algae sit just above the substrate where real algae
# would form a biofilm AND where algae-grazer corydoras can reach them.

extends Node3D
class_name Algae

const MAX_LIFE: float = 90.0
const VOXEL_SIZE: float = 0.12

# Up to 5 voxels make up the cluster; new ones appear at growth milestones.
var _voxels: Array[MeshInstance3D] = []
var _age: float = 0.0
var _phase: float = 0.0
var _color: Color = Color8(120, 165, 60)


func init(color: Color = Color8(120, 165, 60)) -> void:
	_color = color
	_phase = randf() * TAU
	# Start with a single seed voxel; more sprout in tick() as we mature.
	_add_voxel(Vector3.ZERO, 1.0)


# Called by SimDriver each tick. Returns true if the algae should die off.
func tick(dt: float, conditions_favor: bool) -> bool:
	_age += dt
	if not conditions_favor:
		_age += dt * 1.5
	_phase += dt
	# Gentle drift on a sine curve so the cluster has visible life. Real
	# algae biofilms don't sit perfectly still - they ripple with water flow.
	rotation.y = sin(_phase * 0.6) * 0.18
	# Growth milestones: add a voxel at 25 %, 50 %, 75 % of MAX_LIFE.
	# The cluster gets bigger as it spreads, then fades when conditions
	# stop favoring it.
	var life_frac: float = _age / MAX_LIFE
	if _voxels.size() < 2 and life_frac > 0.25:
		_add_voxel(Vector3(VOXEL_SIZE * 0.9, 0, 0), 0.9)
	if _voxels.size() < 3 and life_frac > 0.5:
		_add_voxel(Vector3(-VOXEL_SIZE * 0.7, VOXEL_SIZE * 0.6, VOXEL_SIZE * 0.4), 0.8)
	if _voxels.size() < 4 and life_frac > 0.7:
		_add_voxel(Vector3(VOXEL_SIZE * 0.4, VOXEL_SIZE * 0.9, -VOXEL_SIZE * 0.6), 0.7)
	if _voxels.size() < 5 and life_frac > 0.85:
		_add_voxel(Vector3(0, VOXEL_SIZE * 1.4, 0), 0.6)
	# Senescence fade: in the last 15 % of life, scale shrinks slightly so
	# the cluster visibly retreats before disappearing.
	if life_frac > 0.85:
		var fade_t: float = clampf((1.0 - life_frac) / 0.15, 0.0, 1.0)
		scale = Vector3.ONE * (0.65 + 0.35 * fade_t)
	return _age >= MAX_LIFE


func _add_voxel(local_pos: Vector3, scale_factor: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(VOXEL_SIZE * scale_factor, VOXEL_SIZE * scale_factor,
		VOXEL_SIZE * scale_factor)
	mi.mesh = bm
	# Slight per-voxel color variation so the cluster reads as organic
	# rather than monolithic.
	var shade: float = randf_range(-0.08, 0.08)
	var voxel_color: Color = Color(
		clampf(_color.r + shade, 0.0, 1.0),
		clampf(_color.g + shade, 0.0, 1.0),
		clampf(_color.b + shade, 0.0, 1.0),
	)
	mi.material_override = VoxelMat.make(voxel_color)
	mi.position = local_pos
	add_child(mi)
	_voxels.append(mi)


func biomass() -> int:
	return _voxels.size()


func nibble(amount: int) -> int:
	var taken: int = 0
	for i in amount:
		if _voxels.is_empty():
			break
		var v = _voxels.pop_back()
		if is_instance_valid(v):
			v.queue_free()
		taken += 1
	if _voxels.is_empty():
		_age = MAX_LIFE # mark for death
	return taken
