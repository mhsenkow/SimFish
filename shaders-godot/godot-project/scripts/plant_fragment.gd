# Drifting stem fragment — roots when it settles on viable substrate.
extends Node3D
class_name PlantFragment

const VOXEL_SIZE: float = 0.32
const ROOT_TIME_S: float = 8.0
const DRIFT_DECAY: float = 0.12

var genome: Dictionary = {}
var ramp_override: Array = []
var biomass_units: int = 2
var _age: float = 0.0
var _rooting: bool = false
var _root_timer: float = 0.0
var _velocity: Vector3 = Vector3.ZERO
var _mesh: MeshInstance3D = null


func init(from_pos: Vector3, g: Dictionary, ramp: Array, units: int,
		velocity: Vector3) -> void:
	global_position = from_pos
	genome = g.duplicate(true)
	ramp_override = ramp.duplicate()
	biomass_units = maxi(1, units)
	_velocity = velocity
	_build_mesh()


func _build_mesh() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE * 0.7, VOXEL_SIZE * 0.35, VOXEL_SIZE * 0.7))
	var c: Color = Color8(44, 90, 48)
	if ramp_override.size() >= 3:
		c = ramp_override[2]
	_mesh.material_override = VoxelMat.make_foliage(c)
	add_child(_mesh)


func tick(dt: float, sim: SimDriver, world: Node) -> void:
	_age += dt
	_velocity *= 1.0 - DRIFT_DECAY * dt
	global_position += _velocity * dt
	# Sink slowly
	global_position.y = maxf(0.2, global_position.y - dt * 0.08)
	if world != null and world.has_method("clamp_to_tank"):
		global_position = world.clamp_to_tank(global_position)
	if not _rooting:
		if _velocity.length() < 0.04 and global_position.y < 1.2:
			_rooting = true
			_root_timer = 0.0
	else:
		_root_timer += dt
		if _root_timer >= ROOT_TIME_S:
			_try_root(sim, world)


func _try_root(sim: SimDriver, world: Node) -> void:
	if sim == null or world == null:
		queue_free()
		return
	if sim.substrate == null:
		queue_free()
		return
	var n: float = sim.substrate.get_at(global_position)
	if n < SubstrateGrid.NUTRIENT_BASELINE + 0.06:
		queue_free()
		return
	if world.has_method("spawn_seedling"):
		var cfg: Dictionary = genome.duplicate(true)
		cfg["generation"] = int(cfg.get("generation", 0)) + 1
		world.spawn_seedling(global_position, ramp_override, int(cfg.generation), cfg)
	queue_free()


func to_save_dict() -> Dictionary:
	return {
		"pos": SaveHelpers.vec3_to_array(global_position),
		"velocity": SaveHelpers.vec3_to_array(_velocity),
		"genome": genome,
		"ramp": SaveHelpers.colors_to_array(ramp_override),
		"biomass_units": biomass_units,
		"age": _age,
		"rooting": _rooting,
		"root_timer": _root_timer,
	}


func apply_save_dict(d: Dictionary) -> void:
	global_position = SaveHelpers.array_to_vec3(d.get("pos", [0, 0, 0]))
	_velocity = SaveHelpers.array_to_vec3(d.get("velocity", [0, 0, 0]))
	genome = d.get("genome", {})
	ramp_override = SaveHelpers.array_to_colors(d.get("ramp", []))
	biomass_units = int(d.get("biomass_units", 2))
	_age = float(d.get("age", 0.0))
	_rooting = not not d.get("rooting", false)
	_root_timer = float(d.get("root_timer", 0.0))
	_build_mesh()
