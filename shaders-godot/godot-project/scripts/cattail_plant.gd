# Cattail / reed - tall vertical stalk with a distinctive cylindrical
# seed head near the top.
#
# Mathematical structure:
#   - Stalk is a chain of voxels along Y with a slight sinusoidal lean
#     (theta = sin(y * 0.4) * lean_amplitude). Real reeds bend gently
#     in the current.
#   - Seed head is a fat cylinder of darker voxels stacked at ~80 % of
#     the stalk's height. Each seed-head voxel inherits the stalk's
#     lean at that Y so the head doesn't float off the stalk.
#   - A few leaf blades sprout near the top, angled outward 0.3-0.7
#     radians from vertical, with their own gentle sway.

extends Node3D
class_name CattailPlant

const VOXEL_SIZE: float = 0.18

@export var height_voxels: int = 22
@export var lean_amplitude: float = 0.6
@export var head_voxels: int = 5

var _t: float = 0.0
var _phase: float = 0.0
var stalk_color: Color = Color8(120, 150, 80)
var head_color: Color = Color8(110, 80, 50)
var leaf_color: Color = Color8(95, 140, 75)


func init_at(world_pos: Vector3, stalk_c: Color, head_c: Color, leaf_c: Color) -> void:
	global_position = world_pos
	stalk_color = stalk_c
	head_color = head_c
	leaf_color = leaf_c
	_phase = randf() * TAU
	_build()


func _build() -> void:
	# Stalk: stack vertical voxels with sinusoidal lateral offset.
	for i in height_voxels:
		var y: float = float(i) * VOXEL_SIZE * 0.95
		# Lean increases with height so the base stays planted.
		var t_frac: float = float(i) / float(maxi(1, height_voxels - 1))
		var lean_x: float = sin(t_frac * PI * 0.7) * lean_amplitude * t_frac
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(VOXEL_SIZE * 0.5, VOXEL_SIZE * 1.05, VOXEL_SIZE * 0.5)
		mi.mesh = bm
		mi.position = Vector3(lean_x, y, 0)
		mi.material_override = _make_mat(stalk_color)
		add_child(mi)
	# Seed head: fat cylinder at ~80% height.
	var head_base_i: int = int(height_voxels * 0.78)
	for j in head_voxels:
		var y: float = (head_base_i + j) * VOXEL_SIZE * 0.95
		var t_frac: float = float(head_base_i + j) / float(maxi(1, height_voxels - 1))
		var lean_x: float = sin(t_frac * PI * 0.7) * lean_amplitude * t_frac
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(VOXEL_SIZE * 1.1, VOXEL_SIZE * 0.9, VOXEL_SIZE * 1.1)
		mi.mesh = bm
		mi.position = Vector3(lean_x, y, 0)
		# Top + bottom voxels of the head are slightly darker (tapered).
		var col: Color = head_color
		if j == 0 or j == head_voxels - 1:
			col = head_color.darkened(0.2)
		mi.material_override = _make_mat(col)
		add_child(mi)
	# Leaf blades: 2-3 thin angled stripes near the upper third.
	var n_leaves: int = 3
	for k in n_leaves:
		var base_y: float = float(height_voxels) * VOXEL_SIZE * 0.5
		var leaf_angle: float = (float(k) / float(n_leaves)) * TAU
		var leaf_pivot := Node3D.new()
		leaf_pivot.position = Vector3(0, base_y, 0)
		leaf_pivot.rotation.y = leaf_angle
		leaf_pivot.rotation.z = -0.4   # 0.4 radians from vertical, splayed out
		add_child(leaf_pivot)
		for j in 5:
			var ly: float = float(j) * VOXEL_SIZE * 0.85
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(VOXEL_SIZE * 0.85, VOXEL_SIZE * 0.7, VOXEL_SIZE * 0.18)
			mi.mesh = bm
			mi.position = Vector3(0, ly, 0)
			mi.material_override = _make_mat(leaf_color)
			leaf_pivot.add_child(mi)


func tick(dt: float) -> void:
	# Entire reed sways gently. The math: rotation around Z proportional to
	# sin(t + phase), so reeds in a stand undulate visibly out of phase.
	_t += dt
	rotation.z = sin(_t * 0.7 + _phase) * 0.05
	rotation.x = cos(_t * 0.65 + _phase * 1.1) * 0.035


func _make_mat(c: Color) -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
