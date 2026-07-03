class_name MindArousalField
extends RefCounted

# PERFORMANCE_UNTHROTTLED #39 — O(N) arousal contagion via 4×4×4 tank field.

const GRID: int = 4
const CELL_COUNT: int = GRID * GRID * GRID
const DECAY_PER_S: float = 0.35

static var _cells: PackedFloat32Array = PackedFloat32Array()
static var _weights: PackedFloat32Array = PackedFloat32Array()


static func reset_for_test() -> void:
	_cells = PackedFloat32Array()
	_weights = PackedFloat32Array()
	_cells.resize(CELL_COUNT)
	_weights.resize(CELL_COUNT)
	_cells.fill(0.0)
	_weights.fill(0.0)


static func _ensure() -> void:
	if _cells.size() != CELL_COUNT:
		reset_for_test()


static func _idx(rel: Vector3) -> int:
	var ix: int = clampi(int(rel.x * GRID), 0, GRID - 1)
	var iy: int = clampi(int(rel.y * GRID), 0, GRID - 1)
	var iz: int = clampi(int(rel.z * GRID), 0, GRID - 1)
	return ix + iy * GRID + iz * GRID * GRID


static func rel_pos_for(world: Node, gp: Vector3) -> Vector3:
	if world == null:
		return Vector3(0.5, 0.5, 0.5)
	var hw: float = float(world.get("TANK_HALF_W") if world.get("TANK_HALF_W") != null else 8.0)
	var hd: float = float(world.get("TANK_HALF_D") if world.get("TANK_HALF_D") != null else 4.0)
	var hh: float = float(world.get("TANK_HEIGHT") if world.get("TANK_HEIGHT") != null else 7.0)
	return Vector3(
		clampf((gp.x + hw) / maxf(hw * 2.0, 0.1), 0.0, 0.999),
		clampf(gp.y / maxf(hh, 0.1), 0.0, 0.999),
		clampf((gp.z + hd) / maxf(hd * 2.0, 0.1), 0.0, 0.999))


static func begin_tick(dt: float) -> void:
	_ensure()
	var decay: float = exp(-DECAY_PER_S * maxf(dt, 0.0))
	for i in CELL_COUNT:
		_cells[i] *= decay
		_weights[i] *= decay


static func deposit(f: Fish, amount: float) -> void:
	if f == null or amount <= 0.0:
		return
	_ensure()
	var w: Node = f.get_parent()
	if w == null and f.sim != null:
		w = f.sim.get_parent()
	var rel: Vector3 = rel_pos_for(w, f.global_position)
	var i: int = _idx(rel)
	_cells[i] += amount
	_weights[i] += 1.0


static func sample_at(world: Node, gp: Vector3) -> float:
	_ensure()
	var rel: Vector3 = rel_pos_for(world, gp)
	var i: int = _idx(rel)
	var w: float = _weights[i]
	if w < 0.01:
		return 0.0
	return clampf(_cells[i] / w, 0.0, 1.0)
