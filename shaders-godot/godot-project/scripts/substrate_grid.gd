# Substrate nutrient field.
#
# A coarse 2D grid (X, Z) covering the tank floor. Each cell tracks an
# accumulated nutrient value (proxy for poop + plant litter + leached fertilizer).
# Plants pull from this when they grow; waste particles deposit into it.
#
# The grid is sparse and small (e.g. 16x8 cells) - plenty for planting decisions
# and cheap to tick at the sim rate.

extends Node
class_name SubstrateGrid

const NUTRIENT_BASELINE: float = 0.3
const NUTRIENT_MAX: float = 3.0
const DIFFUSION_RATE: float = 0.04  # per tick - smooths the field
const DECAY_RATE: float = 0.003     # per tick - represents plant uptake without nearby plant
# Aquasoil reservoir leak: the bedrock substrate slowly releases nutrients
# into the active layer, mimicking real planted-tank substrate kept months on
# a single dose. Without this the nutrient pool drifts down because waste
# gets snapped up before settling.
const RESERVOIR_LEAK_PER_TICK: float = 0.00015

var cells_x: int
var cells_z: int
var cell_size: float
var origin: Vector3   # world-space corner of cell (0,0)
var nutrients: Array  # of Array[float], [x][z]


func init(half_w: float, half_d: float, cells_per_unit: float = 1.0) -> void:
	cells_x = int(half_w * 2.0 * cells_per_unit)
	cells_z = int(half_d * 2.0 * cells_per_unit)
	cell_size = 1.0 / cells_per_unit
	origin = Vector3(-half_w, 0, -half_d)
	nutrients = []
	for x in cells_x:
		var col: Array = []
		col.resize(cells_z)
		col.fill(NUTRIENT_BASELINE)
		nutrients.append(col)


func _cell_at(world_pos: Vector3) -> Vector2i:
	var local := world_pos - origin
	var cx: int = clampi(int(local.x / cell_size), 0, cells_x - 1)
	var cz: int = clampi(int(local.z / cell_size), 0, cells_z - 1)
	return Vector2i(cx, cz)


func get_at(world_pos: Vector3) -> float:
	var c := _cell_at(world_pos)
	return nutrients[c.x][c.y]


func add_at(world_pos: Vector3, amount: float) -> void:
	var c := _cell_at(world_pos)
	nutrients[c.x][c.y] = minf(nutrients[c.x][c.y] + amount, NUTRIENT_MAX)


func consume_at(world_pos: Vector3, amount: float) -> float:
	# Take up to `amount` from the cell. Return actually-consumed value.
	var c := _cell_at(world_pos)
	var available: float = nutrients[c.x][c.y] - NUTRIENT_BASELINE
	if available <= 0.0:
		return 0.0
	var taken: float = minf(amount, available)
	nutrients[c.x][c.y] -= taken
	return taken


func tick(_dt: float) -> void:
	# Diffuse + decay. Cheap explicit step; substepping not needed at this resolution.
	var scratch: Array = []
	for x in cells_x:
		var col: Array = []
		col.resize(cells_z)
		for z in cells_z:
			col[z] = nutrients[x][z]
		scratch.append(col)

	for x in cells_x:
		for z in cells_z:
			var c: float = scratch[x][z]
			var sum: float = 0.0
			var count: float = 0.0
			for off in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var nx: int = x + off.x
				var nz: int = z + off.y
				if nx < 0 or nz < 0 or nx >= cells_x or nz >= cells_z:
					continue
				sum += scratch[nx][nz]
				count += 1.0
			var avg: float = sum / maxf(count, 1.0)
			var new_val: float = c + (avg - c) * DIFFUSION_RATE
			# Slow decay toward baseline.
			new_val += (NUTRIENT_BASELINE - new_val) * DECAY_RATE
			# Reservoir leak from bedrock aquasoil.
			new_val += RESERVOIR_LEAK_PER_TICK
			nutrients[x][z] = clampf(new_val, 0.0, NUTRIENT_MAX)


func total_above_baseline() -> float:
	var sum: float = 0.0
	for x in cells_x:
		for z in cells_z:
			sum += maxf(0.0, nutrients[x][z] - NUTRIENT_BASELINE)
	return sum
