extends RefCounted

const MAX_FAMILIES_PER_CELL: int = 4
const MAX_TOTAL_PER_CELL: float = 0.8
const DECAY_PER_S: float = 0.008

var _cells_x: int = 0
var _cells_z: int = 0
var _mixes: Array = []


func init(cells_x: int, cells_z: int) -> void:
	_cells_x = cells_x
	_cells_z = cells_z
	_mixes.clear()
	for x in cells_x:
		var col: Array = []
		for _z in cells_z:
			col.append({})
		_mixes.append(col)


func add(cell: Vector2i, family: String, amount: float) -> float:
	var mix: Dictionary = _mixes[cell.x][cell.y]
	var key: String = family if family != "" else "legacy:anonymous"
	var room: float = MAX_TOTAL_PER_CELL - total(cell)
	var accepted: float = minf(maxf(0.0, amount), maxf(0.0, room))
	if accepted <= 0.0:
		return 0.0
	if not mix.has(key) and mix.size() >= MAX_FAMILIES_PER_CELL:
		var smallest_key: String = ""
		var smallest: float = INF
		for k in mix:
			if float(mix[k]) < smallest:
				smallest = float(mix[k])
				smallest_key = String(k)
		accepted += smallest
		mix.erase(smallest_key)
		key = "mixed:other"
	mix[key] = float(mix.get(key, 0.0)) + accepted
	return minf(amount, room)


func total(cell: Vector2i) -> float:
	var sum: float = 0.0
	for amount_v in (_mixes[cell.x][cell.y] as Dictionary).values():
		sum += float(amount_v)
	return clampf(sum, 0.0, MAX_TOTAL_PER_CELL)


func pressure(cell: Vector2i, family: String, resistance: float) -> float:
	var pressure_total: float = 0.0
	var r: float = clampf(resistance, 0.0, 1.0)
	for key_v in (_mixes[cell.x][cell.y] as Dictionary):
		var key: String = String(key_v)
		var amount: float = float(_mixes[cell.x][cell.y][key])
		if family != "" and key == family:
			amount *= 1.0 - maxf(r, 0.85)
		else:
			amount *= 1.0 - r
		pressure_total += amount
	return clampf(pressure_total, 0.0, MAX_TOTAL_PER_CELL)


func mix_at(cell: Vector2i) -> Dictionary:
	return (_mixes[cell.x][cell.y] as Dictionary).duplicate()


func tick_cells(cells: Array, dt: float) -> void:
	var decay: float = maxf(0.0, DECAY_PER_S * maxf(0.0, dt))
	for cell_v in cells:
		var cell: Vector2i = cell_v
		var mix: Dictionary = _mixes[cell.x][cell.y]
		for key_v in mix.keys():
			var next: float = maxf(0.0, float(mix[key_v]) - decay)
			if next <= 0.0001:
				mix.erase(key_v)
			else:
				mix[key_v] = next


func to_sparse_save() -> Array:
	var out: Array = []
	for x in _cells_x:
		for z in _cells_z:
			var mix: Dictionary = _mixes[x][z]
			if not mix.is_empty():
				out.append({"x": x, "z": z, "mix": mix.duplicate()})
	return out


func apply_sparse_save(entries: Array) -> void:
	for entry_v in entries:
		if not (entry_v is Dictionary):
			continue
		var entry: Dictionary = entry_v
		var cell := Vector2i(int(entry.get("x", -1)), int(entry.get("z", -1)))
		if cell.x < 0 or cell.y < 0 or cell.x >= _cells_x or cell.y >= _cells_z:
			continue
		var mix_v: Variant = entry.get("mix", {})
		if not (mix_v is Dictionary):
			continue
		for family_v in (mix_v as Dictionary):
			add(cell, String(family_v), float(mix_v[family_v]))
