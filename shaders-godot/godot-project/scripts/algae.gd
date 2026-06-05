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

# Distinct algae morphologies. Same lifetime + sim behavior, but each
# type lays out its voxels differently and lives in a different niche so
# the tank reads as a real ecosystem with multiple algae species rather
# than identical green blobs.
#   CLUSTER  — classic biofilm clump, scattered cluster of small cubes (default)
#   SURFACE  — flat scum on the water surface, single wide thin sheet
#   HAIR     — tall filamentous strands attached near a rock or driftwood
#   GSA      — green-spot algae, tiny tightly-packed dots on the tank glass
enum AlgaeKind { CLUSTER, SURFACE, HAIR, GSA }

# Up to 5 voxels make up the cluster; new ones appear at growth milestones.
# Each voxel is a per-instance entry in a per-cluster MultiMesh batch — one
# draw call for the whole cluster instead of one per voxel. The Handle
# carries the API the old MeshInstance3D path used (hide on nibble; color
# read for shading) so the rest of the file barely changes.
var _voxels: Array[VoxelBatch.Handle] = []
var _batch: VoxelBatch = null
var _age: float = 0.0
var _phase: float = 0.0
var _color: Color = Color8(120, 165, 60)
var _kind: int = AlgaeKind.CLUSTER


func init(color: Color = Color8(120, 165, 60), kind: int = AlgaeKind.CLUSTER) -> void:
	_color = color
	_kind = kind
	_phase = randf() * TAU
	# Surface scum is born as a wide thin sheet, hair as a thin vertical
	# strand, GSA as a single tiny dot; the cluster grows the normal way.
	match _kind:
		AlgaeKind.SURFACE:
			_add_voxel(Vector3.ZERO, 1.6, Vector3(2.4, 0.18, 2.4))
		AlgaeKind.HAIR:
			_add_voxel(Vector3.ZERO, 1.0, Vector3(0.22, 1.4, 0.22))
		AlgaeKind.GSA:
			_add_voxel(Vector3.ZERO, 0.7)
		_:
			_add_voxel(Vector3.ZERO, 1.0)


# ---- Save / load ----

func to_save_dict() -> Dictionary:
	return {
		"pos": SaveHelpers.vec3_to_array(global_position),
		"color": SaveHelpers.color_to_array(_color),
		"age": _age,
		"phase": _phase,
		"voxel_count": _voxels.size(),
		"kind": _kind,
	}


func apply_save_dict(d: Dictionary) -> void:
	init(SaveHelpers.array_to_color(d.get("color", []), _color),
		int(d.get("kind", AlgaeKind.CLUSTER)))
	_age = float(d.get("age", 0.0))
	_phase = float(d.get("phase", randf() * TAU))
	# Re-add voxels to roughly match the saved cluster size. tick() will
	# rebuild the precise shape, but starting with the right count avoids
	# a visible "shrinking and regrowing" snap on restore.
	var target_count: int = int(d.get("voxel_count", 1))
	while _voxels.size() < target_count:
		_add_voxel(Vector3(randf_range(-0.2, 0.2), randf_range(-0.1, 0.1),
			randf_range(-0.2, 0.2)), randf_range(0.6, 1.0))


# Called by SimDriver each tick. Returns true if the algae should die off.
func tick(dt: float, conditions_favor: bool) -> bool:
	# Aging rate: 1× when conditions favor growth, 1.5× when they don't.
	# The previous code did `_age += dt` then `_age += dt * 1.5`, summing to
	# 2.5× under unfavorable conditions — algae died 67% faster than the
	# comment promised.
	if conditions_favor:
		_age += dt
	else:
		_age += dt * 1.5
	_phase += dt
	# Cluster + GSA ripple with flow; surface scum slides without rotating
	# (it's anchored to the water film); hair algae waves in two axes.
	match _kind:
		AlgaeKind.SURFACE:
			# Hardly moves — just a soft bob.
			position.y += sin(_phase * 0.8) * 0.0008
		AlgaeKind.HAIR:
			rotation.z = sin(_phase * 1.2) * 0.22
			rotation.x = cos(_phase * 0.9) * 0.10
		AlgaeKind.GSA:
			pass  # GSA dots stick rigidly to glass
		_:
			rotation.y = sin(_phase * 0.6) * 0.18
	# Slow undulating brightness wave across the cluster — looks like
	# sunlight hitting different parts of a wet algae mat as the water
	# above ripples. Only meaningful for cluster + surface kinds (HAIR
	# already sways visibly, GSA voxels are too small for the shimmer to
	# read). Per-instance index drives the phase offset so the wave
	# visibly travels through the cluster instead of pulsing in unison.
	if _kind == AlgaeKind.CLUSTER or _kind == AlgaeKind.SURFACE:
		for i in _voxels.size():
			var h: VoxelBatch.Handle = _voxels[i]
			if h == null or not h.alive:
				continue
			var wave: float = 0.5 + 0.5 * sin(_phase * 0.85 + float(i) * 0.85)
			# Subtle lift — 0..30% toward a lightened version. Quantizer
			# bounces between the base and one-step-brighter palette slot
			# along the wave, reading as a slow shimmer.
			var lit: Color = h.base_color.lerp(h.base_color.lightened(0.30), wave)
			h.set_color(lit)
	# Growth milestones differ per kind: cluster spreads in 3D, surface
	# scum widens, hair gets taller, GSA spreads as a clump of dots.
	var life_frac: float = _age / MAX_LIFE
	match _kind:
		AlgaeKind.SURFACE:
			if _voxels.size() < 2 and life_frac > 0.35:
				_add_voxel(Vector3(VOXEL_SIZE * 2.0, 0, 0), 1.4,
					Vector3(2.0, 0.16, 2.0))
			if _voxels.size() < 3 and life_frac > 0.6:
				_add_voxel(Vector3(-VOXEL_SIZE * 1.4, 0, VOXEL_SIZE * 1.6), 1.2,
					Vector3(1.8, 0.14, 1.8))
		AlgaeKind.HAIR:
			if _voxels.size() < 2 and life_frac > 0.25:
				_add_voxel(Vector3(0, VOXEL_SIZE * 1.1, 0), 1.0,
					Vector3(0.22, 1.4, 0.22))
			if _voxels.size() < 3 and life_frac > 0.55:
				_add_voxel(Vector3(VOXEL_SIZE * 0.3, VOXEL_SIZE * 0.5, 0), 0.85,
					Vector3(0.20, 1.0, 0.20))
			if _voxels.size() < 4 and life_frac > 0.8:
				_add_voxel(Vector3(-VOXEL_SIZE * 0.3, VOXEL_SIZE * 1.7, 0), 0.7,
					Vector3(0.18, 0.7, 0.18))
		AlgaeKind.GSA:
			if _voxels.size() < 3 and life_frac > 0.25:
				_add_voxel(Vector3(VOXEL_SIZE * 0.5, 0, 0), 0.6)
			if _voxels.size() < 6 and life_frac > 0.45:
				_add_voxel(Vector3(0, VOXEL_SIZE * 0.5, 0), 0.55)
			if _voxels.size() < 10 and life_frac > 0.7:
				_add_voxel(Vector3(randf_range(-0.4, 0.4) * VOXEL_SIZE,
					randf_range(-0.3, 0.3) * VOXEL_SIZE, 0), 0.45)
		_:
			if _voxels.size() < 2 and life_frac > 0.25:
				_add_voxel(Vector3(VOXEL_SIZE * 0.9, 0, 0), 0.9)
			if _voxels.size() < 3 and life_frac > 0.5:
				_add_voxel(Vector3(-VOXEL_SIZE * 0.7, VOXEL_SIZE * 0.6, VOXEL_SIZE * 0.4), 0.8)
			if _voxels.size() < 4 and life_frac > 0.7:
				_add_voxel(Vector3(VOXEL_SIZE * 0.4, VOXEL_SIZE * 0.9, -VOXEL_SIZE * 0.6), 0.7)
			if _voxels.size() < 5 and life_frac > 0.85:
				_add_voxel(Vector3(0, VOXEL_SIZE * 1.4, 0), 0.6)
	var w: Node = null
	if get_tree() != null:
		w = get_tree().current_scene.get_node_or_null("SubViewport/World")
	if w != null and w.has_method("clamp_xyz_in_tank"):
		global_position = w.clamp_xyz_in_tank(global_position, 0.22, VOXEL_SIZE * 2.0)
	# Senescence fade: in the last 15 % of life, scale shrinks slightly so
	# the cluster visibly retreats before disappearing.
	if life_frac > 0.85:
		var fade_t: float = clampf((1.0 - life_frac) / 0.15, 0.0, 1.0)
		scale = Vector3.ONE * (0.65 + 0.35 * fade_t)
	return _age >= MAX_LIFE


func _add_voxel(local_pos: Vector3, scale_factor: float,
		shape_scale: Vector3 = Vector3.ONE) -> void:
	if _batch == null:
		# One MultiMesh per algae cluster — its parent is this Algae Node3D,
		# so when tick() rotates this node the whole batch rotates with it.
		# Capacity 8 covers every kind's max voxel count (HAIR=4, GSA=10,
		# others ≤5); the batch auto-grows if needed.
		_batch = VoxelBatch.new(self, VoxelMat.make_voxel_mm(), 8)
	# shape_scale lets each algae kind pick a non-cube voxel: flat sheet
	# (surface scum), thin column (hair), tiny dot (GSA). Defaults to a
	# uniform cube for the classic cluster. The size is baked into the
	# per-instance basis scale instead of a unique BoxMesh per voxel.
	var size: Vector3 = Vector3(
		VOXEL_SIZE * scale_factor * shape_scale.x,
		VOXEL_SIZE * scale_factor * shape_scale.y,
		VOXEL_SIZE * scale_factor * shape_scale.z)
	var xform := Transform3D(Basis().scaled(size), local_pos)
	# Slight per-voxel color variation so the cluster reads as organic
	# rather than monolithic. boost_life_color matches the saturation +
	# value lift the old make_fauna() path applied via its color_vibrancy
	# shader uniform — bake it into the per-instance color now that
	# voxel_mm.gdshader reads COLOR directly.
	var shade: float = randf_range(-0.08, 0.08)
	var voxel_color: Color = Color(
		clampf(_color.r + shade, 0.0, 1.0),
		clampf(_color.g + shade, 0.0, 1.0),
		clampf(_color.b + shade, 0.0, 1.0),
	)
	var boosted: Color = VoxelMat.boost_life_color(voxel_color)
	_voxels.append(_batch.add(xform, boosted))
	_batch.flush()


func biomass() -> int:
	return _voxels.size()


func nibble(amount: int) -> int:
	var taken: int = 0
	for i in amount:
		if _voxels.is_empty():
			break
		var h: VoxelBatch.Handle = _voxels.pop_back()
		if h != null and h.alive:
			h.hide()
		taken += 1
	if _voxels.is_empty():
		_age = MAX_LIFE # mark for death
	return taken
