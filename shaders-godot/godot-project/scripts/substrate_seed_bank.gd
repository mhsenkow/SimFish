extends RefCounted

const MAX_LOTS_PER_CELL: int = 8
const MAX_QUANTITY_PER_CELL: float = 1.0
const VIABILITY_HALF_LIFE_S: float = 7200.0

var _cells_x: int = 0
var _cells_z: int = 0
var _lots: Array = []


func init(cells_x: int, cells_z: int) -> void:
	_cells_x = cells_x
	_cells_z = cells_z
	_lots.clear()
	for x in cells_x:
		var col: Array = []
		for _z in cells_z:
			col.append([])
		_lots.append(col)


func total_at(cell: Vector2i) -> float:
	var total: float = 0.0
	for lot_v in _cell_lots(cell):
		var lot: Dictionary = lot_v
		total += float(lot.get("quantity", 0.0))
	return clampf(total, 0.0, MAX_QUANTITY_PER_CELL)


func lots_at(cell: Vector2i) -> Array:
	return (_cell_lots(cell) as Array).duplicate(true)


func add_lot(cell: Vector2i, genome: Dictionary, quantity: float,
		dormancy: Dictionary = {}) -> float:
	var room: float = MAX_QUANTITY_PER_CELL - total_at(cell)
	var accepted: float = minf(maxf(0.0, quantity), maxf(0.0, room))
	if accepted <= 0.0:
		return 0.0
	var identity: String = _genome_identity(genome)
	var lots: Array = _cell_lots(cell)
	for lot_v in lots:
		var lot: Dictionary = lot_v
		if String(lot.get("genome_id", "")) == identity \
				and lot.get("dormancy", {}) == dormancy:
			lot.quantity = float(lot.get("quantity", 0.0)) + accepted
			lot.viability = maxf(float(lot.get("viability", 1.0)), 1.0)
			return accepted
	if lots.size() >= MAX_LOTS_PER_CELL:
		var weakest_i: int = 0
		var weakest: float = INF
		for i in lots.size():
			var score: float = float((lots[i] as Dictionary).get("viability", 0.0)) \
				* float((lots[i] as Dictionary).get("quantity", 0.0))
			if score < weakest:
				weakest = score
				weakest_i = i
		# Preserve total mass by folding the displaced lot into the incoming
		# anonymous mixture rather than growing an unbounded family list.
		var displaced: Dictionary = lots[weakest_i]
		accepted += float(displaced.get("quantity", 0.0))
		lots.remove_at(weakest_i)
		identity = "mixed:%s" % identity
		genome = {}
	lots.append({
		"genome_id": identity,
		"genome": genome.duplicate(true),
		"quantity": accepted,
		"age_s": 0.0,
		"viability": 1.0,
		"dormancy": dormancy.duplicate(true),
	})
	return minf(quantity, room)


func consume(cell: Vector2i, amount: float) -> Dictionary:
	var lots: Array = _cell_lots(cell)
	var best_i: int = -1
	var best_score: float = -1.0
	for i in lots.size():
		var lot: Dictionary = lots[i]
		var score: float = float(lot.get("viability", 0.0)) \
			* float(lot.get("quantity", 0.0))
		if score > best_score:
			best_score = score
			best_i = i
	if best_i < 0:
		return {}
	var chosen: Dictionary = lots[best_i]
	var taken: float = minf(maxf(0.0, amount), float(chosen.get("quantity", 0.0)))
	chosen.quantity = float(chosen.get("quantity", 0.0)) - taken
	var out: Dictionary = chosen.duplicate(true)
	out.quantity = taken
	if float(chosen.quantity) <= 0.0001:
		lots.remove_at(best_i)
	return out


func tick_cells(cells: Array, dt: float) -> void:
	if dt <= 0.0:
		return
	var decay: float = pow(0.5, dt / VIABILITY_HALF_LIFE_S)
	for cell_v in cells:
		var cell: Vector2i = cell_v
		var lots: Array = _cell_lots(cell)
		for i in range(lots.size() - 1, -1, -1):
			var lot: Dictionary = lots[i]
			lot.age_s = maxf(0.0, float(lot.get("age_s", 0.0)) + dt)
			lot.viability = clampf(float(lot.get("viability", 1.0)) * decay, 0.0, 1.0)
			if float(lot.viability) < 0.01 or float(lot.get("quantity", 0.0)) <= 0.0001:
				lots.remove_at(i)


func to_sparse_save() -> Array:
	var out: Array = []
	for x in _cells_x:
		for z in _cells_z:
			var lots: Array = _lots[x][z]
			if not lots.is_empty():
				out.append({"x": x, "z": z, "lots": lots.duplicate(true)})
	return out


func apply_sparse_save(entries: Array) -> void:
	for entry_v in entries:
		if not (entry_v is Dictionary):
			continue
		var entry: Dictionary = entry_v
		var cell := Vector2i(int(entry.get("x", -1)), int(entry.get("z", -1)))
		if not _valid(cell):
			continue
		var incoming: Variant = entry.get("lots", [])
		if not (incoming is Array):
			continue
		for lot_v in incoming:
			if not (lot_v is Dictionary):
				continue
			var lot: Dictionary = lot_v
			var accepted: float = add_lot(cell, lot.get("genome", {}),
				float(lot.get("quantity", 0.0)), lot.get("dormancy", {}))
			if accepted <= 0.0:
				continue
			var dst: Dictionary = (_cell_lots(cell) as Array).back()
			dst.genome_id = String(lot.get("genome_id", dst.genome_id))
			dst.age_s = maxf(0.0, float(lot.get("age_s", 0.0)))
			dst.viability = clampf(float(lot.get("viability", 1.0)), 0.0, 1.0)


func migrate_scalar(cell: Vector2i, quantity: float) -> void:
	if quantity > 0.0:
		add_lot(cell, {}, quantity, {})


func _cell_lots(cell: Vector2i) -> Array:
	return _lots[cell.x][cell.y]


func _valid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _cells_x and cell.y < _cells_z


func _genome_identity(genome: Dictionary) -> String:
	if genome.is_empty():
		return "legacy:anonymous"
	var species: String = String(genome.get("species_id", ""))
	var lineage: String = String(genome.get("plant_name",
		genome.get("parent_lineage", "Founders")))
	return "%s|%s|g%d" % [species, lineage, int(genome.get("generation", 0))]
