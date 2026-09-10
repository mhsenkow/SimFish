extends Node3D
class_name PlantFarFoliageBatch

# Coarse world-owned consolidation for dense, distant vegetation. Rebuilds are
# deliberately infrequent: mirroring is enabled only when population and saved
# draw calls justify measured transfer cost, otherwise private batches remain.

const FAR_DIST_SQ: float = 44.0 * 44.0
const MIN_FAR_PLANTS: int = 12
const MIN_INSTANCES: int = 600
const REBUILD_INTERVAL_S: float = 2.0
const MAX_REBUILD_USEC: int = 1800

var _batch: VoxelBatch = null
var _material: ShaderMaterial = null
var _rebuild_t: float = 0.0
var _mirrored_plants: Array[Plant] = []
var enabled_by_profile: bool = false
var last_rebuild_usec: int = 0
var last_instance_count: int = 0
var last_saved_draws: int = 0


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/foliage_mm.gdshader") as Shader
	VoxelMat.register_foliage_mm(_material)
	_batch = VoxelBatch.new(self, _material, 1024)


func update_far_batch(plants: Array, camera: Camera3D, dt: float) -> void:
	_rebuild_t += dt
	if _rebuild_t < REBUILD_INTERVAL_S:
		return
	_rebuild_t = 0.0
	var far: Array[Plant] = []
	var instances: int = 0
	if camera != null:
		for plant in plants:
			if plant == null or not is_instance_valid(plant):
				continue
			if not _eligible_for_mirroring(plant):
				_set_private_visible(plant, true)
				continue
			if camera.global_position.distance_squared_to(plant.global_position) < FAR_DIST_SQ:
				continue
			far.append(plant)
			instances += _live_render_count(plant._foliage_batch)
			instances += _live_render_count(plant._stem_batch)
	if far.size() < MIN_FAR_PLANTS or instances < MIN_INSTANCES:
		_restore_private_batches()
		_batch.clear()
		enabled_by_profile = false
		last_instance_count = instances
		last_saved_draws = 0
		return

	var started: int = Time.get_ticks_usec()
	_batch.clear()
	for plant in far:
		_mirror_batch(plant, plant._foliage_batch)
		_mirror_batch(plant, plant._stem_batch)
	_batch.flush()
	last_rebuild_usec = Time.get_ticks_usec() - started
	last_instance_count = instances
	last_saved_draws = far.size() * 2 - 1
	if last_rebuild_usec > MAX_REBUILD_USEC:
		# Profiling proved the copy cost loses on this renderer. Keep the
		# shared material registry path and cleanly restore private draws.
		_restore_private_batches()
		_batch.clear()
		enabled_by_profile = false
		return
	_restore_private_batches()
	_mirrored_plants = far
	for plant in _mirrored_plants:
		_set_private_visible(plant, false)
	enabled_by_profile = true


func _eligible_for_mirroring(plant: Plant) -> bool:
	# Flowers and pods remain live Node3D geometry. Mirroring only their
	# stem/leaves would freeze one half of the plant and hide its private
	# anchor, so reproductive plants stay wholly private.
	return plant != null and not plant.has_flower \
		and plant.flower_stage == Plant.FlowerStage.NONE


func _live_render_count(batch: VoxelBatch) -> int:
	if batch == null:
		return 0
	var total: int = 0
	for handle_ref in batch._handles:
		var h: VoxelBatch.Handle = handle_ref.get_ref() as VoxelBatch.Handle
		if h != null and h.alive and h.visible and h.lod_visible:
			total += 1
	return total


func _mirror_batch(plant: Plant, source: VoxelBatch) -> void:
	if source == null:
		return
	var to_local_xform: Transform3D = global_transform.affine_inverse()
	for handle_ref in source._handles:
		var h: VoxelBatch.Handle = handle_ref.get_ref() as VoxelBatch.Handle
		if h == null or not h.alive or not h.visible or not h.lod_visible:
			continue
		var world_xform: Transform3D = plant.global_transform * h.transform
		_batch.add(to_local_xform * world_xform, h.base_color)


func _set_private_visible(plant: Plant, visible: bool) -> void:
	if plant._foliage_batch != null and plant._foliage_batch.mmi != null:
		plant._foliage_batch.mmi.visible = visible
	if plant._stem_batch != null and plant._stem_batch.mmi != null:
		plant._stem_batch.mmi.visible = visible


func _restore_private_batches() -> void:
	for plant in _mirrored_plants:
		if plant != null and is_instance_valid(plant):
			_set_private_visible(plant, true)
	_mirrored_plants.clear()


func _exit_tree() -> void:
	_restore_private_batches()
	if _batch != null:
		_batch.dispose()
		_batch = null
