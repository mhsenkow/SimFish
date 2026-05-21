# Cattail / reed - tall vertical stalk with a distinctive cylindrical
# seed head near the top.
#
# === Dynamic growth ===
# Now grows incrementally over time instead of building all at once. The
# stalk extends voxel-by-voxel upward; the seed head appears once the
# stalk reaches ~80% of its target height. Leaf blades sprout at growth
# milestones. At maturity, the seed head can "puff" — individual fluffy
# seed voxels detach and float to the water surface, potentially seeding
# new cattails in the tank.
#
# Mathematical structure:
#   - Stalk: chain of voxels along Y with sinusoidal lean
#   - Seed head: fat cylinder of darker voxels at ~80% height
#   - Leaf blades: angled outward 0.3-0.7 rad from vertical
#   - Puffing: stochastic detachment of seed-head voxels

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
# Water surface Y in world space. Seed heads only form above this.
var water_surface_y: float = 6.5

# ---- Dynamic growth state ----
var _current_height: int = 0
var _growth_timer: float = 0.0
var _growth_interval: float = 2.5   # seconds per stalk voxel
var _stalk_voxels: Array[MeshInstance3D] = []
var _head_built: bool = false
var _head_voxels_arr: Array[MeshInstance3D] = []
var _leaves_built: int = 0
var _leaf_pivots: Array[Node3D] = []
# Seed puffing state.
var _puff_timer: float = 0.0
var _is_mature: bool = false
var _seeds_released: int = 0
var _max_seed_releases: int = 3


func init_at(world_pos: Vector3, stalk_c: Color, head_c: Color, leaf_c: Color) -> void:
	global_position = world_pos
	stalk_color = stalk_c
	head_color = head_c
	leaf_color = leaf_c
	_phase = randf() * TAU
	# Start with just the first couple of stalk voxels.
	for i in mini(3, height_voxels):
		_add_stalk_voxel()


func _add_stalk_voxel() -> void:
	if _current_height >= height_voxels:
		return
	var i: int = _current_height
	var y: float = float(i) * VOXEL_SIZE * 0.95
	var t_frac: float = float(i) / float(maxi(1, height_voxels - 1))
	var lean_x: float = sin(t_frac * PI * 0.7) * lean_amplitude * t_frac
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(VOXEL_SIZE * 0.5, VOXEL_SIZE * 1.05, VOXEL_SIZE * 0.5)
	mi.mesh = bm
	mi.position = Vector3(lean_x, y, 0)
	# New growth is slightly lighter.
	var growth_color: Color = stalk_color.lightened(0.1) if _current_height > height_voxels * 0.7 else stalk_color
	mi.material_override = _make_mat(growth_color)
	add_child(mi)
	_stalk_voxels.append(mi)
	_current_height += 1


func _build_seed_head() -> void:
	if _head_built:
		return
	_head_built = true
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
		_head_voxels_arr.append(mi)


func _add_leaf_blade(leaf_index: int) -> void:
	var base_y: float = float(_current_height) * VOXEL_SIZE * 0.5
	var leaf_angle: float = (float(leaf_index) / 3.0) * TAU
	var leaf_pivot := Node3D.new()
	leaf_pivot.position = Vector3(0, base_y, 0)
	leaf_pivot.rotation.y = leaf_angle
	leaf_pivot.rotation.z = -0.4   # 0.4 radians from vertical, splayed out
	add_child(leaf_pivot)
	_leaf_pivots.append(leaf_pivot)
	var blade_len: int = 5
	for j in blade_len:
		var ly: float = float(j) * VOXEL_SIZE * 0.85
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		# Taper the blade: wider at base, thinner at tip.
		var taper: float = 1.0 - float(j) / float(blade_len) * 0.5
		bm.size = Vector3(
			VOXEL_SIZE * 0.85 * taper,
			VOXEL_SIZE * 0.7,
			VOXEL_SIZE * 0.18,
		)
		mi.mesh = bm
		mi.position = Vector3(0, ly, 0)
		mi.material_override = _make_mat(leaf_color)
		leaf_pivot.add_child(mi)


func tick(dt: float) -> void:
	# Entire reed sways gently.
	_t += dt
	rotation.z = sin(_t * 0.7 + _phase) * 0.05
	rotation.x = cos(_t * 0.65 + _phase * 1.1) * 0.035

	# Leaf flutter: individual leaf pivots get micro-oscillation.
	for lp in _leaf_pivots:
		if is_instance_valid(lp):
			lp.rotation.z = -0.4 + sin(_t * 1.8 + lp.rotation.y) * 0.03

	# ---- Incremental growth ----
	_growth_timer += dt
	if _current_height < height_voxels and _growth_timer >= _growth_interval:
		_growth_timer = 0.0
		_add_stalk_voxel()

		# Add leaves at milestones (roughly every 1/3 of height).
		if _leaves_built < 3:
			var leaf_milestone: int = (height_voxels / 3) * (_leaves_built + 1)
			if _current_height >= leaf_milestone:
				_add_leaf_blade(_leaves_built)
				_leaves_built += 1

	# Build seed head only when the top of the stalk has emerged above the
	# water surface. Real cattails produce seed heads in the air, not
	# underwater. Check by comparing the world-space Y of the stalk tip
	# against the water surface.
	var tip_world_y: float = global_position.y + float(_current_height) * VOXEL_SIZE * 0.95
	if not _head_built and _current_height >= int(height_voxels * 0.8) \
			and tip_world_y >= water_surface_y:
		_build_seed_head()

	# ---- Maturity + seed puffing (only above water) ----
	if _current_height >= height_voxels and _head_built \
			and tip_world_y >= water_surface_y:
		_is_mature = true
		_puff_timer += dt
		# Every 15-20 seconds, pop a seed head voxel off as a floating "puff."
		if _puff_timer >= 18.0 and _seeds_released < _max_seed_releases:
			_puff_timer = 0.0
			_seeds_released += 1
			_puff_seed()


func _puff_seed() -> void:
	# Remove a head voxel and spawn a tiny floating seed particle.
	if _head_voxels_arr.is_empty():
		return
	var v: MeshInstance3D = _head_voxels_arr.pop_back()
	if is_instance_valid(v):
		# Could spawn a new cattail seedling here in the future.
		# For now, the visual effect is what matters: seed head shrinks.
		v.queue_free()


func _make_mat(c: Color) -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
