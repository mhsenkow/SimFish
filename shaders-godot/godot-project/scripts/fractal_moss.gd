# Fractal moss / java-moss cluster.
#
# True recursive fractal: a parent voxel spawns N children at random angles
# off its surface, each of which spawns N children of its own, down to a
# depth cap. Each generation shrinks by a fixed factor (~0.75x). The
# result is a chaotic dense cluster that reads as moss/algae carpet -
# mathematically a stochastic L-system with fixed-angle branching.
#
# This is what real java moss does in a Walstad tank: it doesn't grow
# in any organized way, it just keeps spitting out tiny offshoots at
# random angles off whatever it has already grown.
#
# Parameters:
#   depth         recursion depth (typical 3-4)
#   children     children per node (3-5)
#   shrink       scale multiplier per generation (~0.7)
#   spread       angular variation per child (~PI/2)

extends Node3D
class_name FractalMoss

const VOXEL_SIZE: float = 0.14

@export var depth: int = 3
@export var children: int = 4
@export var shrink: float = 0.72
@export var spread: float = 1.4  # radians

var _t: float = 0.0
var _phase: float = 0.0
var ramp: Array = []   # 5-color green ramp


func init_at(world_pos: Vector3, color_ramp: Array) -> void:
	global_position = world_pos
	ramp = color_ramp
	_phase = randf() * TAU
	# Seed voxel at the origin.
	_build_node(Vector3.ZERO, VOXEL_SIZE, 0, self)


# Recursive builder. `parent` is the Node3D we attach voxels under; for
# the root call it's `self`. We use the parent transform to position
# children, which means a future "moss propagation" pass could just
# spawn a new fractal subtree on an existing parent.
func _build_node(local_pos: Vector3, size: float, gen: int, parent: Node3D) -> void:
	if size < VOXEL_SIZE * 0.35:
		return
	var color: Color
	if ramp.size() >= 5:
		var idx: int = clampi(gen, 0, ramp.size() - 1)
		color = ramp[idx]
	else:
		color = Color8(60, 130, 70)
	# Drop one voxel at this node.
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size, size, size)
	mi.mesh = bm
	mi.material_override = _make_mat(color)
	mi.position = local_pos
	parent.add_child(mi)
	# Recursion stop at depth.
	if gen >= depth:
		return
	# Spawn N children at random angles around the parent voxel.
	for c in children:
		if randf() > 0.85:
			# Mild thinning so the tree doesn't double-cover itself.
			continue
		var theta: float = randf_range(-spread, spread)
		var phi: float = randf_range(-spread, spread)
		# Direction in spherical coords.
		var dir: Vector3 = Vector3(
			sin(theta) * cos(phi),
			cos(theta) * cos(phi),
			sin(phi),
		)
		# Child voxel sits about size*0.9 away in this direction.
		var child_pos: Vector3 = local_pos + dir * size * 0.9
		_build_node(child_pos, size * shrink, gen + 1, parent)


func tick(dt: float) -> void:
	# Subtle swirl of the whole cluster - moss has a gentle drift in a
	# planted tank when water flow brushes it.
	_t += dt
	rotation.y = sin(_t * 0.3 + _phase) * 0.04
	rotation.x = cos(_t * 0.25 + _phase * 1.3) * 0.025


func _make_mat(c: Color) -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
