# Lily pad - radial surface plant.
#
# === Dynamic growth ===
# Now grows incrementally: starts as a small 4-voxel pad that expands over
# time by adding new phyllotaxis-arranged leaf voxels. The stem grows first
# (reaching from substrate to the surface), then the pad expands. Flower
# buds appear once the pad reaches maturity and open into the layered bloom.
# Mature pads can produce runner stems that spawn new pads nearby.
#
# Mathematical structure: Vogel's spiral / sunflower phyllotaxis for the pad
# voxels, with golden angle spacing for maximally even coverage.
#
# Parameters:
#   pad_radius    visual extent of the pad (in units, ~0.6-1.2)
#   pad_voxels    how many leaf voxels make up the disc (12-40)
#   stem_y        y of substrate top - stem reaches from there to the pad

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

# ---- Dynamic growth state ----
var _current_pad_voxels: int = 0
var _growth_timer: float = 0.0
var _growth_interval: float = 3.0   # seconds per pad voxel
var _stem_built: bool = false
var _pad_voxel_nodes: Array[MeshInstance3D] = []
# Flower lifecycle.
enum FlowerStage { NONE, BUD, OPENING, FULL, FADING }
var _flower_stage: int = FlowerStage.NONE
var _flower_timer: float = 0.0
var _flower_open_frac: float = 0.0
var _flower_nodes: Array[MeshInstance3D] = []
# Runner propagation.
var _runner_timer: float = 0.0
var _has_run: bool = false

# Precomputed golden angle.
const GOLDEN_ANGLE: float = 2.39996322972865332  # TAU * (1 - 1/φ)


func init_at(world_pos: Vector3, base_y: float) -> void:
	global_position = Vector3(world_pos.x, world_pos.y, world_pos.z)
	stem_y = base_y
	_phase = randf() * TAU
	# Build the stem first, then start adding pad voxels.
	_build_stem()
	# Start with a small pad (4 voxels).
	for i in 4:
		_add_pad_voxel()


func _build_stem() -> void:
	if _stem_built:
		return
	_stem_built = true
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


func _add_pad_voxel() -> void:
	if _current_pad_voxels >= pad_voxels:
		return
	var i: int = _current_pad_voxels
	var t: float = float(i + 1) / float(pad_voxels)
	var r: float = sqrt(t) * pad_radius
	var theta: float = float(i) * GOLDEN_ANGLE
	var x: float = cos(theta) * r
	var z: float = sin(theta) * r
	# Top voxel - new growth is slightly brighter.
	var is_new: bool = (_current_pad_voxels > pad_voxels * 0.7)
	var top_color: Color = pad_top.lightened(0.1) if is_new else pad_top
	var top := MeshInstance3D.new()
	var top_mesh := BoxMesh.new()
	top_mesh.size = Vector3(VOXEL_SIZE * 1.5, VOXEL_SIZE * 0.45, VOXEL_SIZE * 1.5)
	top.mesh = top_mesh
	top.material_override = _make_mat(top_color)
	top.position = Vector3(x, 0.0, z)
	add_child(top)
	_pad_voxel_nodes.append(top)
	# Darker underside for the edge ring only (visible from below).
	if t > 0.55:
		var under := MeshInstance3D.new()
		var under_mesh := BoxMesh.new()
		under_mesh.size = Vector3(VOXEL_SIZE * 1.3, VOXEL_SIZE * 0.20, VOXEL_SIZE * 1.3)
		under.mesh = under_mesh
		under.material_override = _make_mat(pad_bot)
		under.position = Vector3(x, -VOXEL_SIZE * 0.3, z)
		add_child(under)
	_current_pad_voxels += 1


func tick(dt: float) -> void:
	_t += dt

	# ---- Incremental pad growth ----
	_growth_timer += dt
	if _current_pad_voxels < pad_voxels and _growth_timer >= _growth_interval:
		_growth_timer = 0.0
		_add_pad_voxel()

	# ---- Flower lifecycle ----
	# Flower bud appears once the pad is ~70% grown.
	if _flower_stage == FlowerStage.NONE \
			and _current_pad_voxels >= int(pad_voxels * 0.7) \
			and randf() < 0.002:
		_begin_flower()
	_tick_flower(dt)

	# ---- Runner propagation ----
	if _current_pad_voxels >= pad_voxels:
		_runner_timer += dt
		if not _has_run and _runner_timer > 45.0 and randf() < 0.15:
			_has_run = true
			_try_propagate()


func _begin_flower() -> void:
	_flower_stage = FlowerStage.BUD
	_flower_timer = 0.0
	# Small green bud in the center.
	var bud := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(VOXEL_SIZE * 0.5, VOXEL_SIZE * 0.5, VOXEL_SIZE * 0.5)
	bud.mesh = bm
	bud.material_override = _make_mat(pad_top.darkened(0.1))
	bud.position = Vector3(0, VOXEL_SIZE * 0.3, 0)
	add_child(bud)
	_flower_nodes.append(bud)


func _tick_flower(dt: float) -> void:
	if _flower_stage == FlowerStage.NONE:
		return
	_flower_timer += dt
	match _flower_stage:
		FlowerStage.BUD:
			if _flower_timer > 6.0:
				_flower_stage = FlowerStage.OPENING
				_flower_timer = 0.0
				_flower_open_frac = 0.0
				_build_flower_meshes()
		FlowerStage.OPENING:
			_flower_open_frac = clampf(_flower_timer / 5.0, 0.0, 1.0)
			_update_flower(_flower_open_frac)
			if _flower_timer > 5.0:
				_flower_stage = FlowerStage.FULL
				_flower_timer = 0.0
		FlowerStage.FULL:
			# Full bloom for 30 seconds.
			if _flower_timer > 30.0:
				_flower_stage = FlowerStage.FADING
				_flower_timer = 0.0
		FlowerStage.FADING:
			# Petals darken and shrink.
			var fade: float = clampf(_flower_timer / 8.0, 0.0, 1.0)
			for fn in _flower_nodes:
				if is_instance_valid(fn):
					fn.scale = Vector3.ONE * (1.0 - fade * 0.4)
			if _flower_timer > 8.0:
				_clear_flower()
				_flower_stage = FlowerStage.NONE


func _build_flower_meshes() -> void:
	_clear_flower()
	var palette: Array[Color] = [
		Color8(245, 220, 220),  # pale pink
		Color8(255, 245, 220),  # ivory
		Color8(245, 195, 100),  # gold center
	]
	var n_petals: int = 6
	for i in n_petals:
		var f := MeshInstance3D.new()
		var petal_size: float = VOXEL_SIZE * (0.7 - float(i % 2) * 0.15)
		f.mesh = VoxelMat.get_box(Vector3(petal_size, VOXEL_SIZE * 0.2, petal_size * 0.8))
		var petal_color: Color = palette[0] if i % 2 == 0 else palette[1]
		f.material_override = _make_mat(petal_color)
		add_child(f)
		_flower_nodes.append(f)
	
	var center := MeshInstance3D.new()
	center.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE * 0.4, VOXEL_SIZE * 0.25, VOXEL_SIZE * 0.4))
	center.material_override = _make_mat(palette[2])
	center.position = Vector3(0, VOXEL_SIZE * 0.4, 0)
	add_child(center)
	_flower_nodes.append(center)
	
	_update_flower(0.0)


func _update_flower(open_frac: float) -> void:
	var n_petals: int = 6
	if _flower_nodes.size() < n_petals:
		return
	for i in n_petals:
		var angle: float = float(i) / float(n_petals) * TAU
		var petal_spread: float = open_frac * VOXEL_SIZE * 0.9
		var f: Node3D = _flower_nodes[i]
		if is_instance_valid(f):
			f.position = Vector3(
				cos(angle) * petal_spread,
				VOXEL_SIZE * 0.35,
				sin(angle) * petal_spread,
			)
			f.rotation.z = cos(angle) * open_frac * 0.3
			f.rotation.x = sin(angle) * open_frac * 0.3
	# Gold center is already handled by _build_flower_meshes


func _clear_flower() -> void:
	for fn in _flower_nodes:
		if is_instance_valid(fn):
			fn.queue_free()
	_flower_nodes.clear()


func _try_propagate() -> void:
	# Spawn a new pad nearby via a runner. The "runner" itself is a thin
	# chain of dark voxels along the substrate connecting parent → child;
	# without it the new pad just popped into existence with no causal
	# link to its parent. Real lily / Echinodorus runners are exactly
	# this kind of visible stolen-stem along the substrate.
	#
	# Lily pads previously propagated with a ±2.0-unit XZ offset and no
	# bounds check — runners spawned through the glass on any tank smaller
	# than the default 8x4 box. Try a handful of offsets, take the first
	# inside the tank, give up gracefully if none fit.
	var parent_node: Node = get_parent()
	if parent_node == null:
		return
	var new_pos: Vector3 = global_position
	var found: bool = false
	for _attempt in 6:
		var offset := Vector3(
			randf_range(-2.0, 2.0),
			0.0,
			randf_range(-2.0, 2.0),
		)
		var candidate: Vector3 = global_position + offset
		if _is_inside_tank_xz(candidate.x, candidate.z, 0.6):
			new_pos = candidate
			found = true
			break
	if not found:
		return
	# Lay a visible runner trail along the substrate from us to the new
	# spawn. Runners sit just above the mulm so they read as plant
	# tissue, not detritus.
	_lay_runner_trail(global_position, new_pos, parent_node)
	var new_pad := LilyPad.new()
	parent_node.add_child(new_pad)
	new_pad.pad_radius = pad_radius * randf_range(0.75, 1.0)
	new_pad.pad_voxels = maxi(12, int(pad_voxels * randf_range(0.6, 0.9)))
	new_pad.init_at(new_pos, stem_y)


# Drop a chain of 4-7 dark-green voxels along the segment from `a` to `b`
# at substrate height (y from `a.y`). Reads as a stolen-stem runner —
# the visible "this pad came from that pad" causal link that real
# carpet / lily propagation produces.
func _lay_runner_trail(a: Vector3, b: Vector3, parent_node: Node) -> void:
	var segs: int = clampi(int(round((b - a).length() / 0.4)), 4, 8)
	var runner_color := Color8(60, 90, 45)
	for i in segs:
		var t: float = float(i + 1) / float(segs + 1)
		var p: Vector3 = a.lerp(b, t)
		# Substrate-hugging Y plus a tiny lateral wiggle so the chain
		# doesn't read as a perfectly straight ruler line.
		p.y = a.y - 0.02
		p.x += sin(t * PI * 1.5) * 0.06
		p.z += cos(t * PI * 1.3) * 0.06
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.05, 0.12)
		mi.mesh = bm
		mi.material_override = VoxelMat.make(runner_color)
		mi.position = p
		parent_node.add_child(mi)


# Walk up the scene tree to find the world node (which carries
# `_is_inside_tank` and knows about hex/triangle shapes). Falls back to
# allowing the spawn if no world is reachable.
func _is_inside_tank_xz(x: float, z: float, margin: float) -> bool:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("_is_inside_tank"):
			return n._is_inside_tank(x, z, margin)
		n = n.get_parent()
	return true


func _make_mat(c: Color) -> Material:
	return VoxelMat.make_foliage(c)
