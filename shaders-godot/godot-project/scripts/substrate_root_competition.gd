extends RefCounted

const MAX_RADIUS_CELLS: int = 2
const MAX_FOOTPRINT_CELLS: int = 13

var _cells_x: int = 0
var _cells_z: int = 0
var _footprints: Dictionary = {} # plant id -> {cell: weight}
var _masses: Dictionary = {}
var _cell_mass: Dictionary = {}
var _seen: Dictionary = {}


func init(cells_x: int, cells_z: int) -> void:
	_cells_x = cells_x
	_cells_z = cells_z
	_footprints.clear()
	_masses.clear()
	_cell_mass.clear()
	_seen.clear()


func begin_refresh() -> void:
	_seen.clear()


func register(plant_id: int, center: Vector2i, radius_cells: int,
		active_mass: float) -> void:
	_seen[plant_id] = true
	_remove_contribution(plant_id)
	var radius: int = clampi(radius_cells, 0, MAX_RADIUS_CELLS)
	var footprint: Dictionary = {}
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if dx * dx + dz * dz > radius * radius:
				continue
			var cell := Vector2i(center.x + dx, center.y + dz)
			if not _valid(cell) or footprint.size() >= MAX_FOOTPRINT_CELLS:
				continue
			var distance: float = Vector2(dx, dz).length()
			footprint[cell] = maxf(0.2, 1.0 - distance / float(radius + 1))
	_footprints[plant_id] = footprint
	var mass: float = clampf(active_mass, 0.01, 64.0)
	_masses[plant_id] = mass
	for cell_v in footprint:
		var cell: Vector2i = cell_v
		_cell_mass[cell] = float(_cell_mass.get(cell, 0.0)) \
			+ mass * float(footprint[cell])


func end_refresh() -> void:
	for id_v in _footprints.keys():
		if not _seen.has(id_v):
			_remove_contribution(int(id_v))


func uptake_plan(plant_id: int, requested: float) -> Array:
	var out: Array = []
	if requested <= 0.0 or not _footprints.has(plant_id):
		return out
	var footprint: Dictionary = _footprints[plant_id]
	var weight_sum: float = 0.0
	for weight_v in footprint.values():
		weight_sum += float(weight_v)
	var mass: float = float(_masses.get(plant_id, 0.0))
	for cell_v in footprint:
		var cell: Vector2i = cell_v
		var weight: float = float(footprint[cell])
		var overlap_mass: float = maxf(0.0001, float(_cell_mass.get(cell, mass * weight)))
		var overlap_share: float = clampf(mass * weight / overlap_mass, 0.0, 1.0)
		out.append({
			"cell": cell,
			"amount": requested * weight / maxf(weight_sum, 0.0001) * overlap_share,
		})
	return out


func footprint_for(plant_id: int) -> Dictionary:
	return (_footprints.get(plant_id, {}) as Dictionary).duplicate()


func _remove_contribution(plant_id: int) -> void:
	if not _footprints.has(plant_id):
		return
	var footprint: Dictionary = _footprints[plant_id]
	var mass: float = float(_masses.get(plant_id, 0.0))
	for cell_v in footprint:
		var cell: Vector2i = cell_v
		var remaining: float = float(_cell_mass.get(cell, 0.0)) \
			- mass * float(footprint[cell])
		if remaining <= 0.0001:
			_cell_mass.erase(cell)
		else:
			_cell_mass[cell] = remaining
	_footprints.erase(plant_id)
	_masses.erase(plant_id)


func _valid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _cells_x and cell.y < _cells_z
