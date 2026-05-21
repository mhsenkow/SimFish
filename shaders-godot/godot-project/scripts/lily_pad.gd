# Lily pad - radial surface plant.
#
# Mathematically constructed pad: a circular array of leaf voxels arranged
# in a logarithmic-spiral disc (Vogel's model, same golden-angle pattern
# as a sunflower head) at the water surface, with one stem voxel descending
# to the substrate.
#
# Lily pads in real planted tanks (Nymphaea spp.) grow from a rhizome on
# the substrate, send a stalk to the surface, and produce a single round
# pad. Multiple pads stack on the surface to form a canopy.
#
# Parameters:
#   pad_radius    visual extent of the pad (in units, ~0.6-1.2)
#   pad_voxels    how many leaf voxels make up the disc (12-40)
#   stem_y        y of substrate top - stem reaches from there to the pad
#
# The pad bobs gently on a sine curve like the floaters, slightly out of
# phase with its neighbors. Each pad logs a deterministic phase so the
# motion isn't synchronized across the bed.

extends Node3D
class_name LilyPad

const VOXEL_SIZE: float = 0.18

@export var pad_radius: float = 0.95
@export var pad_voxels: int = 28
@export var stem_y: float = 1.6

var _t: float = 0.0
var _phase: float = 0.0
# Color of the pad surface (sun-side) and underside.
var pad_top: Color = Color8(90, 145, 70)
var pad_bot: Color = Color8(45, 90, 50)
# Optional bright flower pop in the centre (Nymphaea blooms).
var has_flower: bool = false


func init_at(world_pos: Vector3, base_y: float) -> void:
	global_position = Vector3(world_pos.x, world_pos.y, world_pos.z)
	stem_y = base_y
	_phase = randf() * TAU
	# 1-in-4 pads bloom at spawn for visual variety.
	has_flower = randf() < 0.25
	_build()


func _build() -> void:
	# Stem - thin dark voxel column from substrate up to pad.
	var stem_top_y: float = global_position.y - VOXEL_SIZE * 0.5
	var stem_h: float = stem_top_y - stem_y
	if stem_h > 0.0:
		var stem := MeshInstance3D.new()
		var stem_mesh := BoxMesh.new()
		stem_mesh.size = Vector3(VOXEL_SIZE * 0.45, stem_h, VOXEL_SIZE * 0.45)
		stem.mesh = stem_mesh
		stem.material_override = _make_mat(Color8(70, 90, 50))
		stem.position = Vector3(0, -stem_h * 0.5, 0)
		add_child(stem)

	# Pad voxels arranged via Vogel's spiral / sunflower phyllotaxis: for
	# each i, theta = i * golden_angle, r = sqrt(i / n) * pad_radius. The
	# golden angle (137.508°) produces a maximally even packing - no two
	# voxels ever overlap and the disc fills uniformly.
	var golden_angle: float = TAU * (1.0 - 1.0 / 1.618033988)
	var mat_top := _make_mat(pad_top)
	var mat_bot := _make_mat(pad_bot)
	for i in pad_voxels:
		var t: float = float(i + 1) / float(pad_voxels)
		var r: float = sqrt(t) * pad_radius
		var theta: float = float(i) * golden_angle
		var x: float = cos(theta) * r
		var z: float = sin(theta) * r
		# Top voxel.
		var top := MeshInstance3D.new()
		var top_mesh := BoxMesh.new()
		top_mesh.size = Vector3(VOXEL_SIZE * 1.5, VOXEL_SIZE * 0.45, VOXEL_SIZE * 1.5)
		top.mesh = top_mesh
		top.material_override = mat_top
		top.position = Vector3(x, 0.0, z)
		add_child(top)
		# Darker underside for the edge ring only (visible from below).
		if t > 0.55:
			var under := MeshInstance3D.new()
			var under_mesh := BoxMesh.new()
			under_mesh.size = Vector3(VOXEL_SIZE * 1.3, VOXEL_SIZE * 0.20, VOXEL_SIZE * 1.3)
			under.mesh = under_mesh
			under.material_override = mat_bot
			under.position = Vector3(x, -VOXEL_SIZE * 0.3, z)
			add_child(under)

	# Optional flower pop in the centre.
	if has_flower:
		var palette: Array[Color] = [
			Color8(245, 220, 220),  # pale pink
			Color8(255, 245, 220),  # ivory
			Color8(245, 195, 100),  # gold center
		]
		for i in palette.size():
			var f := MeshInstance3D.new()
			var fm := BoxMesh.new()
			fm.size = Vector3(VOXEL_SIZE * (1.0 - i * 0.25),
				VOXEL_SIZE * 0.35,
				VOXEL_SIZE * (1.0 - i * 0.25))
			f.mesh = fm
			f.material_override = _make_mat(palette[i])
			f.position = Vector3(0, VOXEL_SIZE * 0.3 + i * VOXEL_SIZE * 0.18, 0)
			add_child(f)


func tick(dt: float) -> void:
	# Slow vertical bob - keeps the pad sitting on the meniscus without
	# leaving it static. Each pad uses its own phase so a bed of pads
	# undulates with visible delay between them.
	_t += dt
	position.y = global_position.y - 0.0  # no-op marker; the actual bob
	# lives in the rotation below since position.y is anchored to the world.
	rotation.z = sin(_t * 0.6 + _phase) * 0.03
	rotation.x = cos(_t * 0.55 + _phase * 1.1) * 0.025


func _make_mat(c: Color) -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
