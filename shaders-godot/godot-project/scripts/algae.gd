# An algae patch. Appears stochastically when nutrients are high + plant
# biomass is low (N:P imbalance). Slowly spreads, dies off when conditions
# normalize. Just a small green voxel that sits on a surface; visual cue.

extends Node3D
class_name Algae

const MAX_LIFE: float = 90.0

var _age: float = 0.0


func init(color: Color = Color8(120, 165, 60)) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.14, 0.14, 0.14)
	mi.mesh = bm
	mi.material_override = VoxelMat.make(color)
	add_child(mi)


# Called by SimDriver each tick. Returns true if the algae should die off.
func tick(dt: float, conditions_favor: bool) -> bool:
	_age += dt
	if not conditions_favor:
		# Plants outcompete - algae fades faster.
		_age += dt * 1.5
	return _age >= MAX_LIFE
