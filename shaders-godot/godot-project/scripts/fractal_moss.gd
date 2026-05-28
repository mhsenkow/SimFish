# Fractal moss / java-moss cluster.
#
# True recursive fractal: a parent voxel spawns N children at random angles
# off its surface, each of which spawns N children of its own, down to a
# depth cap. Each generation shrinks by a fixed factor (~0.75x). The
# result is a chaotic dense cluster that reads as moss/algae carpet -
# mathematically a stochastic L-system with fixed-angle branching.
#
# === Dynamic growth ===
# Now grows incrementally over time instead of being built all at once.
# Starts at depth=1, adds new recursive branches every few seconds up to
# the configured max depth. This makes moss visibly "spread" like real
# java moss in a Walstad tank. Can also propagate to nearby hardscape
# surfaces by spawning new FractalMoss nodes adjacent to driftwood.
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

# ---- Dynamic growth state ----
var _current_depth: int = 0     # how deep we've actually built so far
var _growth_timer: float = 0.0
var _growth_interval: float = 8.0   # seconds between adding a new depth level
var _all_voxels: Array[MeshInstance3D] = []
# Track leaf-tip positions for potential propagation.
var _tip_positions: Array[Vector3] = []
# Grazing: shrimp can nibble the outermost generation.
var _outermost_voxels: Array[MeshInstance3D] = []
# Propagation.
var _propagation_timer: float = 0.0
var _has_propagated: bool = false


func init_at(world_pos: Vector3, color_ramp: Array) -> void:
	global_position = world_pos
	ramp = color_ramp
	_phase = randf() * TAU
	_current_depth = 0
	# Start with just the seed voxel (depth 0).
	_build_node(Vector3.ZERO, VOXEL_SIZE, 0, self, true)
	_current_depth = 0


# Recursive builder. `parent` is the Node3D we attach voxels under; for
# the root call it's `self`. We use the parent transform to position
# children, which means a future "moss propagation" pass could just
# spawn a new fractal subtree on an existing parent.
func _build_node(local_pos: Vector3, size: float, gen: int, parent: Node3D,
		is_initial: bool = false) -> void:
	if size < VOXEL_SIZE * 0.35:
		return
	var color: Color
	if ramp.size() >= 5:
		var idx: int = clampi(gen, 0, ramp.size() - 1)
		color = ramp[idx]
	else:
		color = Color8(60, 130, 70)

	# New growth is slightly brighter to show where the moss is actively expanding.
	if gen == _current_depth and not is_initial:
		color = color.lightened(0.15)

	# Drop one voxel at this node.
	var mi := MeshInstance3D.new()
	var scale_v: float = size / VOXEL_SIZE
	mi.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE))
	mi.scale = Vector3(scale_v, scale_v, scale_v)
	mi.material_override = VoxelMat.make_foliage(color)
	mi.position = local_pos
	parent.add_child(mi)
	_all_voxels.append(mi)

	# Track outermost generation for grazing.
	if gen == _current_depth:
		_outermost_voxels.append(mi)
		_tip_positions.append(local_pos)

	# Only recurse if we've grown deep enough.
	if gen >= _current_depth:
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


func _rebuild_at_depth(new_depth: int) -> void:
	# APPENDATIVE GROWTH. Previously this nuked every voxel and re-built the
	# whole fractal with fresh random angles, so every growth step (every
	# 8s) visibly *popped* and shuffled the cluster — the player could see
	# moss flicker into a different shape every time it grew. Now we keep
	# all existing voxels and only spawn new ones off the previous
	# outermost generation, demoting the old outermost back to its natural
	# (un-lightened) ramp color so the highlight tracks the actual growing
	# tip rather than the whole tree.
	if new_depth <= _current_depth:
		return

	# Demote the previous outermost voxels: re-color them to ramp[_current_depth]
	# without the +0.15 lightening that marked them as "new growth."
	if ramp.size() >= 5:
		var natural_idx: int = clampi(_current_depth, 0, ramp.size() - 1)
		var natural_color: Color = ramp[natural_idx]
		for v in _outermost_voxels:
			if not is_instance_valid(v):
				continue
			v.material_override = VoxelMat.make_foliage(natural_color)

	var prev_tip_positions: Array[Vector3] = _tip_positions.duplicate()
	_outermost_voxels = []
	_tip_positions = []
	# Step depth by one — incremental growth, not a full re-leap.
	_current_depth = mini(_current_depth + 1, new_depth)
	var size: float = VOXEL_SIZE * pow(shrink, _current_depth)
	for parent_pos in prev_tip_positions:
		_spawn_children_off(parent_pos, size, _current_depth)


func _spawn_children_off(parent_pos: Vector3, size: float, gen: int) -> void:
	# Emit up to `children` new voxels at random offsets off `parent_pos`.
	# This mirrors the recursive spawn in `_build_node` but without
	# rebuilding everything below — it's how a new generation is appended.
	if size < VOXEL_SIZE * 0.35:
		return
	var parent_size: float = size / shrink
	var color: Color
	if ramp.size() >= 5:
		var idx: int = clampi(gen, 0, ramp.size() - 1)
		color = ramp[idx].lightened(0.15)
	else:
		color = Color8(60, 130, 70).lightened(0.15)
	for c in children:
		if randf() > 0.85:
			# Mild thinning so the tree doesn't double-cover itself.
			continue
		var theta: float = randf_range(-spread, spread)
		var phi: float = randf_range(-spread, spread)
		var dir: Vector3 = Vector3(
			sin(theta) * cos(phi),
			cos(theta) * cos(phi),
			sin(phi),
		)
		var child_pos: Vector3 = parent_pos + dir * parent_size * 0.9
		var mi := MeshInstance3D.new()
		var scale_v: float = size / VOXEL_SIZE
		mi.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE))
		mi.scale = Vector3(scale_v, scale_v, scale_v)
		mi.material_override = VoxelMat.make_foliage(color)
		mi.position = child_pos
		add_child(mi)
		_all_voxels.append(mi)
		_outermost_voxels.append(mi)
		_tip_positions.append(child_pos)


func tick(dt: float) -> void:
	_t += dt

	# ---- Incremental growth ----
	# Every _growth_interval seconds, increase the fractal depth by 1.
	_growth_timer += dt
	if _current_depth < depth and _growth_timer >= _growth_interval:
		_growth_timer = 0.0
		_rebuild_at_depth(_current_depth + 1)

	# ---- Propagation ----
	# Mature moss clusters can spawn a new FractalMoss nearby on hardscape.
	_propagation_timer += dt
	if not _has_propagated and _current_depth >= depth \
			and _propagation_timer > 30.0 and randf() < 0.1:
		_has_propagated = true
		_try_propagate()


func _try_propagate() -> void:
	# Attempt to spawn a new small moss cluster nearby. The world's
	# hardscape_root (driftwood, stones) is the preferred target surface.
	#
	# Reject candidate positions outside the tank — the previous code added
	# a ±1.2-unit XYZ offset with no bounds check, so daughter moss readily
	# spawned through the glass. We try a few random offsets, then give up;
	# the parent flips `_has_propagated` either way so we don't retry every
	# frame.
	var parent_node: Node = get_parent()
	if parent_node == null:
		return
	var new_pos: Vector3 = Vector3.ZERO
	var found: bool = false
	for _attempt in 6:
		var offset := Vector3(
			randf_range(-1.2, 1.2),
			randf_range(-0.3, 0.5),
			randf_range(-1.2, 1.2),
		)
		var candidate: Vector3 = global_position + offset
		if _is_inside_tank_xz(candidate.x, candidate.z, 0.4):
			new_pos = candidate
			found = true
			break
	if not found:
		return
	var new_moss := FractalMoss.new()
	parent_node.add_child(new_moss)
	new_moss.depth = maxi(2, depth - 1)  # daughter is slightly smaller
	new_moss.children = children
	new_moss.shrink = shrink
	new_moss.spread = spread
	# Slightly mutated ramp.
	var mutated: Array = ramp.duplicate()
	if mutated.size() >= 5:
		var jitter := Color(randf(), randf(), randf())
		for i in mutated.size():
			mutated[i] = (mutated[i] as Color).lerp(jitter, 0.06)
	new_moss.init_at(new_pos, mutated)


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


# Shrimp grazing: remove outermost voxels.
func graze(amount: int) -> int:
	var removed: int = 0
	for i in amount:
		if _outermost_voxels.is_empty():
			break
		var v: MeshInstance3D = _outermost_voxels.pop_back()
		if is_instance_valid(v):
			_all_voxels.erase(v)
			v.queue_free()
			removed += 1
	return removed


func _make_mat(c: Color) -> Material:
	return VoxelMat.make_foliage(c)
