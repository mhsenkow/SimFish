# A single growing plant (one stem/blade).
#
# Each plant owns a chain of voxels stacked vertically. It grows over time when
# given access to nutrients from the substrate grid below it. Fish can nibble
# the top of the plant, removing voxels and gaining food. If a plant is reduced
# to 0 voxels, it dies (queues itself for removal).

extends Node3D
class_name Plant

const PLANT_RAMP: Array[Color] = [
	Color8(16, 38, 20),
	Color8(29, 59, 34),
	Color8(44, 90, 48),
	Color8(62, 127, 64),
	Color8(87, 162, 83),
	Color8(121, 192, 105),
]
const VOXEL_SIZE: float = 0.32

# Optional per-species ramp override. World assigns this before init() so each
# species reads a different color band.
var ramp_override: Array = []

# Per-plant params (set on spawn).
var max_height: int = 22
var growth_rate: float = 0.18  # voxels per second at saturated nutrients
var nutrient_demand: float = 0.05  # nutrients consumed per voxel grown
var sway_amplitude: float = 0.25

var current_height: int = 0
var growth_progress: float = 0.0
var voxels: Array[MeshInstance3D] = []
var has_flower: bool = false
var _flower_voxel: MeshInstance3D = null
var _phase: float = 0.0
var _t: float = 0.0
var _world_pos: Vector3 = Vector3.ZERO


func init(initial_height: int = 1, params: Dictionary = {}) -> void:
	max_height = params.get("max_height", max_height)
	growth_rate = params.get("growth_rate", growth_rate)
	nutrient_demand = params.get("nutrient_demand", nutrient_demand)
	sway_amplitude = params.get("sway_amplitude", sway_amplitude)
	for i in initial_height:
		_grow_one()


func _ready() -> void:
	_phase = float(get_instance_id() % 1000) * 0.013
	_world_pos = global_position


func _grow_one() -> bool:
	if current_height >= max_height:
		return false
	var rel: float = float(current_height) / float(maxi(1, max_height - 1))
	var ramp_idx: int = clampi(int(rel * 5.0), 0, 5)
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	var color: Color = ramp[ramp_idx]
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
	mi.mesh = bm
	mi.material_override = VoxelMat.make(color)
	# Stack the new voxel on top, with a small lateral offset that curves
	# the blade as it grows.
	var lat: float = sin(rel * PI * 0.6) * sway_amplitude * 0.6
	mi.position = Vector3(lat, current_height * VOXEL_SIZE + VOXEL_SIZE * 0.5, 0)
	add_child(mi)
	voxels.append(mi)
	current_height += 1
	return true


func biomass() -> int:
	return current_height


# Called by SimDriver each tick.
func tick(dt: float, substrate: SubstrateGrid) -> void:
	_t += dt
	# Sway the whole blade based on phase.
	rotation.z = sin(_t * 0.7 + _phase) * 0.08

	if current_height >= max_height:
		return

	var available: float = substrate.get_at(_world_pos)
	# Map nutrient (0..NUTRIENT_MAX) to growth multiplier.
	var nutrient_mult: float = clampf((available - substrate.NUTRIENT_BASELINE) / 1.0, 0.0, 1.0)
	var effective_rate: float = growth_rate * (0.2 + 0.8 * nutrient_mult)
	growth_progress += effective_rate * dt
	if growth_progress >= 1.0:
		growth_progress = 0.0
		if _grow_one():
			substrate.consume_at(_world_pos, nutrient_demand)
	# Rare flowering: mature plant (close to max_height) occasionally pops a
	# bright tip voxel. Gets cleared next time it's nibbled or it dies.
	if not has_flower and current_height >= max_height - 1 and randf() < 0.0005:
		_flower()


func _flower() -> void:
	if has_flower or voxels.is_empty():
		return
	has_flower = true
	var palette: Array[Color] = [
		Color8(230, 130, 200),  # pink
		Color8(245, 220, 90),   # yellow
		Color8(220, 100, 100),  # red
		Color8(170, 130, 220),  # lavender
		Color8(240, 240, 240),  # white
	]
	var flower_color: Color = palette[randi() % palette.size()]
	_flower_voxel = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(VOXEL_SIZE * 1.1, VOXEL_SIZE * 1.1, VOXEL_SIZE * 1.1)
	_flower_voxel.mesh = bm
	_flower_voxel.material_override = VoxelMat.make(flower_color)
	_flower_voxel.position = Vector3(0, current_height * VOXEL_SIZE + VOXEL_SIZE * 1.2, 0)
	add_child(_flower_voxel)


# Fish nibbling: remove up to `amount` voxels from the top. Returns the
# number removed (= food value the fish gained).
func nibble(amount: int) -> int:
	var removed: int = 0
	for i in amount:
		if voxels.is_empty():
			break
		var v: MeshInstance3D = voxels.pop_back()
		v.queue_free()
		current_height -= 1
		removed += 1
		# Reset growth progress so the regrow doesn't snap a new voxel in instantly.
		growth_progress = 0.0
	if current_height <= 0:
		_on_death()
		queue_free()
	return removed


func _on_death() -> void:
	# When a plant is fully eaten, its roots + decay matter return some
	# nutrients to the substrate. Closes the cycle: without this the nutrient
	# pool drifts down over time because waste gets eaten before settling.
	# We add directly to the substrate grid since the plant's about to free.
	var sim_driver: Node = _find_sim()
	if sim_driver != null and sim_driver.substrate != null:
		sim_driver.substrate.add_at(global_position, 0.35)


func _find_sim() -> Node:
	var n: Node = get_parent()
	while n != null:
		var d := n.get_node_or_null("SimDriver")
		if d != null:
			return d
		n = n.get_parent()
	return null


# Quick world-space height of the top voxel (for fish to target nibbling).
func top_world_y() -> float:
	return global_position.y + current_height * VOXEL_SIZE
