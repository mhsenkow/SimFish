# Detritus particle. Spawned by every creature in the tank: fish drop the
# largest particles, shrimp drop medium ones (lighter color because they eat
# plants), snails drop tiny pellets. All fall to the substrate, deposit their
# nutrient_value there, and persist briefly before despawning.
#
# Other creatures can claim a waste particle as food via SimDriver._claim_waste.
# When claimed, the particle is consumed (no nutrient deposit) and the eater
# gains its nutrient_value as energy/food.

extends Node3D
class_name WasteParticle

const FALL_SPEED: float = 0.6
const MAX_LIFE: float = 30.0
const KIND_FISH: int = 0
const KIND_SHRIMP: int = 1
const KIND_SNAIL: int = 2
const KIND_FOOD: int = 3

# Player-dropped food variants (only meaningful when kind == KIND_FOOD).
const FOOD_SUB_FLAKE: int = 0   # floats on surface — top feeders rush
const FOOD_SUB_PELLET: int = 1  # sinks to substrate — bottom feeders
const FOOD_SUB_WORM: int = 2    # mid-water wriggle — carnivores frenzy
const FOOD_SUB_WAFER: int = 3   # slow sink — herbivores / algae grazers

var nutrient_value: float = 0.2
var substrate_top_y: float = 1.6
var kind: int = KIND_FISH
var food_subtype: int = FOOD_SUB_PELLET
var voxel_size: float = 0.12
var settled: bool = false
var _life: float = 0.0
var _settle_timer: float = 0.0
var last_deposit_amount: float = 0.0
# Cached tank World node. tick() ran a string-path node lookup every tick for
# every particle (up to ~240 × the sim rate); the World ref is stable for the
# particle's life, so resolve it once.
var _world: Node = null
var _batch_slot: int = WasteParticleBatch.SLOT_NONE
var _vis_color: Color = Color.WHITE
var _interp_from: Vector3 = Vector3.ZERO
var _interp_to: Vector3 = Vector3.ZERO
var _was_camera_visible: bool = true
var _fallback_mesh: MeshInstance3D = null


func prepare_for_pool() -> void:
	_life = 0.0
	_settle_timer = 0.0
	settled = false
	last_deposit_amount = 0.0
	_release_batch_slot()
	_hide_fallback_mesh()
	visible = false
	scale = Vector3.ONE


# ---- Save / load ----

func to_save_dict() -> Dictionary:
	return {
		"pos": SaveHelpers.vec3_to_array(global_position),
		"nutrient_value": nutrient_value,
		"substrate_top_y": substrate_top_y,
		"kind": kind,
		"food_subtype": food_subtype,
		"settled": settled,
		"life": _life,
		"settle_timer": _settle_timer,
	}


func apply_save_dict(d: Dictionary) -> void:
	# init() builds the visual + sets kind/value; we re-call it then patch
	# the dynamic settle state.
	init(float(d.get("nutrient_value", 0.2)),
		float(d.get("substrate_top_y", 1.6)),
		int(d.get("kind", KIND_FISH)),
		int(d.get("food_subtype", FOOD_SUB_PELLET)))
	settled = not not d.get("settled", false)
	_life = float(d.get("life", 0.0))
	_settle_timer = float(d.get("settle_timer", 0.0))


func init(value: float, top_y: float, particle_kind: int = KIND_FISH,
		subtype: int = FOOD_SUB_PELLET) -> void:
	nutrient_value = value
	substrate_top_y = top_y
	kind = particle_kind
	food_subtype = subtype
	var color: Color
	match kind:
		KIND_SHRIMP:
			voxel_size = 0.08
			color = Color8(95, 80, 50)  # olive-brown, plant-fed
		KIND_SNAIL:
			voxel_size = 0.05
			color = Color8(40, 32, 22)  # tiny dark pellet
		KIND_FOOD:
			match food_subtype:
				FOOD_SUB_FLAKE:
					voxel_size = 0.11
					color = Color8(255, 235, 120)
				FOOD_SUB_WORM:
					voxel_size = 0.13
					color = Color8(220, 70, 55)
				FOOD_SUB_WAFER:
					voxel_size = 0.30
					color = Color8(150, 230, 95)
				_:
					voxel_size = 0.22
					color = Color8(255, 200, 110)  # sinking pellet — bright enough to spot
		_:
			voxel_size = 0.12
			color = Color8(60, 45, 30)  # standard fish brown
	_vis_color = color
	if kind == KIND_FOOD:
		_release_batch_slot()
		_reset_motion_interp()
		_push_visual()
		return
	_claim_batch_slot()
	_reset_motion_interp()
	_push_visual()


# Called by SimDriver each tick. Returns true if the particle should be removed.
func tick(dt: float, substrate: SubstrateGrid) -> bool:
	_interp_from = position
	_life += dt
	if _life >= MAX_LIFE:
		return true
	var w: Node = _resolve_world()
	if not settled:
		var skip_batch_physics: bool = false
		if w != null:
			var sim_n: Variant = w.get("sim")
			if sim_n != null and bool(sim_n.get("_waste_physics_batched")) and kind != KIND_FOOD:
				skip_batch_physics = true
		var floor_y: float = substrate_top_y
		if w != null and w.has_method("column_surface_y"):
			floor_y = w.column_surface_y(position.x, position.z)
		if not skip_batch_physics:
			var can_fall: bool = true
			var fall_rate: float = FALL_SPEED
			if kind == KIND_FOOD:
				var surf_y: float = _food_surface_y(w)
				match food_subtype:
					FOOD_SUB_FLAKE:
						if _life < 16.0:
							can_fall = false
							position.y = maxf(position.y, surf_y + 0.04)
							position.y += sin(_life * 4.2) * 0.02 * dt
							position.x += sin(_life * 1.6 + position.z) * 0.06 * dt
							position.z += cos(_life * 1.3 + position.x) * 0.06 * dt
					FOOD_SUB_WORM:
						if _life < 12.0:
							can_fall = false
							fall_rate = FALL_SPEED * 0.25
							position.y += sin(_life * 6.0) * 0.03 * dt
							position.x += sin(_life * 3.1) * 0.09 * dt
							position.z += cos(_life * 2.4) * 0.09 * dt
					FOOD_SUB_WAFER:
						if _life < 6.0:
							can_fall = false
							position.y = maxf(position.y, surf_y + 0.035)
							position.y += sin(_life * 2.0) * 0.012 * dt
						fall_rate = FALL_SPEED * 0.32
					_:
						if _life < 3.0:
							can_fall = false
							position.y = maxf(position.y, surf_y + 0.02)
							position.y += sin(_life * 3.0) * 0.015 * dt
							position.x += sin(_life * 1.2) * 0.04 * dt
							position.z += cos(_life * 0.9) * 0.04 * dt

			if can_fall:
				position.y -= fall_rate * dt
				var swirl_t: float = _life * 1.1
				var px: float = position.x
				var pz: float = position.z
				var swirl: Vector2 = Vector2(
					sin(swirl_t + pz * 0.55) * 0.085,
					cos(swirl_t * 0.83 - px * 0.55) * 0.085)
				var wander: Vector2 = Vector2(
					sin(_life * 2.3 + px * 0.4) * 0.04,
					sin(_life * 1.9 + pz * 0.4 + 1.3) * 0.04)
				var intake_pull: Vector2 = Vector2.ZERO
				if w != null:
					var sim_batch: Variant = w.get("sim")
					if sim_batch != null:
						var intake_pos_v: Variant = sim_batch.get("filter_intake_pos")
						if intake_pos_v != null and intake_pos_v is Vector3:
							var dx: float = (intake_pos_v as Vector3).x - position.x
							var dz: float = (intake_pos_v as Vector3).z - position.z
							var d2: float = dx * dx + dz * dz
							var pull_k: float = 0.18 / (1.0 + d2 * 0.6)
							intake_pull = Vector2(dx, dz) * pull_k
				position.x += (swirl.x + wander.x + intake_pull.x) * dt
				position.z += (swirl.y + wander.y + intake_pull.y) * dt
				if w != null and w.has_method("sample_flow"):
					var flow_v: Vector3 = w.sample_flow(global_position)
					position += flow_v * dt * 0.48

		if position.y <= floor_y + voxel_size * 0.5:
			position.y = floor_y + voxel_size * 0.5
			settled = true
			var deposit: float = nutrient_value
			if substrate != null:
				var n_total: float = substrate.total_above_baseline()
				if n_total > 6.0:
					deposit *= 0.55
			last_deposit_amount = deposit
			substrate.add_at(position, deposit)
			if randf() < 0.17 and w != null and w.has_method("add_mulm_voxel"):
				w.add_mulm_voxel(global_position)
	else:
		_settle_timer += dt
		_interp_to = position
		_push_visual()
		if _settle_timer > 4.0:
			return true
		return false
	if w != null and w.has_method("clamp_xyz_in_tank"):
		global_position = w.clamp_xyz_in_tank(global_position, 0.18, voxel_size * 0.5)
	_interp_to = position
	_push_visual()
	return false


func _process(_dt: float) -> void:
	var world_n: Node = _resolve_world()
	var sim_n: Variant = world_n.get("sim") if world_n != null else null
	if sim_n == null or not sim_n.has_method("sim_tick_blend"):
		return
	if sim_n.has_method("is_creature_visible_to_camera"):
		var vis: bool = sim_n.is_creature_visible_to_camera(self)
		if vis != _was_camera_visible:
			_interp_from = _interp_to
		_was_camera_visible = vis
	var blend: float = sim_n.sim_tick_blend()
	position = _interp_from.lerp(_interp_to, blend)
	_push_visual()


func _reset_motion_interp() -> void:
	_interp_from = position
	_interp_to = position


func _visual_pos() -> Vector3:
	# MultiMesh instances share waste_root space with particle nodes.
	return position


func _food_surface_y(w: Node) -> float:
	if w != null and w.get("WATER_HEIGHT") != null:
		return float(w.WATER_HEIGHT) - 0.025
	return substrate_top_y + 4.5


func _orphan_batch_slot() -> void:
	_batch_slot = WasteParticleBatch.SLOT_NONE


func _hide_fallback_mesh() -> void:
	if _fallback_mesh != null and is_instance_valid(_fallback_mesh):
		_fallback_mesh.visible = false


func _sync_fallback_mesh() -> void:
	if kind != KIND_FOOD:
		_hide_fallback_mesh()
		return
	if _fallback_mesh == null:
		_fallback_mesh = MeshInstance3D.new()
		_fallback_mesh.name = "FoodFallback"
		_fallback_mesh.mesh = VoxelMat.get_box(Vector3.ONE)
		var food_mat: ShaderMaterial = VoxelMat.make_voxel_mm().duplicate() as ShaderMaterial
		food_mat.set_shader_parameter("albedo", _vis_color)
		_fallback_mesh.material_override = food_mat
		_fallback_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_fallback_mesh)
	_fallback_mesh.visible = true
	var s: float = maxf(voxel_size, 0.08)
	_fallback_mesh.scale = Vector3(s, s, s)
	if _fallback_mesh.material_override is ShaderMaterial:
		(_fallback_mesh.material_override as ShaderMaterial).set_shader_parameter("albedo", _vis_color)


func _resolve_world() -> Node:
	if _world != null and is_instance_valid(_world):
		return _world
	if is_inside_tree():
		var wr: Node = get_parent()
		if wr != null and wr.get_parent() != null:
			_world = wr.get_parent()
	if _world == null and is_inside_tree():
		var ml: MainLoop = Engine.get_main_loop()
		if ml is SceneTree:
			var scene: Node = (ml as SceneTree).current_scene
			if scene != null:
				_world = scene.get_node_or_null("SubViewport/World")
	return _world


func _batch() -> WasteParticleBatch:
	var wr: Node = get_parent()
	if wr != null:
		for c in wr.get_children():
			if c is WasteParticleBatch:
				return c as WasteParticleBatch
	var world_n: Node = _resolve_world()
	if world_n == null:
		return null
	var sim_n: Variant = world_n.get("sim")
	if sim_n == null:
		return null
	var from_sim: Variant = sim_n.get("waste_batch")
	if from_sim is WasteParticleBatch:
		return from_sim as WasteParticleBatch
	return null


func _claim_batch_slot() -> void:
	if _batch_slot >= 0:
		return
	var batch: WasteParticleBatch = _batch()
	if batch == null:
		return
	_batch_slot = batch.claim_slot(self)


func _release_batch_slot() -> void:
	if _batch_slot < 0:
		return
	var batch: WasteParticleBatch = _batch()
	if batch != null:
		batch.release_slot(_batch_slot)
	_batch_slot = WasteParticleBatch.SLOT_NONE


func _push_visual() -> void:
	if kind == KIND_FOOD:
		_sync_fallback_mesh()
		return
	if _batch_slot < 0:
		return
	var batch: WasteParticleBatch = _batch()
	if batch == null:
		return
	batch.sync_slot(_batch_slot, _visual_pos(), voxel_size, _vis_color)


func has_batch_slot() -> bool:
	return _batch_slot >= 0
