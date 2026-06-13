# Substrate nutrient field.
#
# A coarse 2D grid (X, Z) covering the tank floor. Each cell tracks an
# accumulated nutrient value (proxy for poop + plant litter + leached fertilizer).
# Plants pull from this when they grow; waste particles deposit into it.
#
# The grid is sparse and small (e.g. 16x8 cells) - plenty for planting decisions
# and cheap to tick at the sim rate.
#
# Lazy update: tick() walks only the "dirty" set of cells that have diverged
# from equilibrium (= baseline + leak/decay). When add_at or consume_at touches
# a cell, that cell + its 4 neighbors are marked dirty so diffusion can spread.
# Cells settle back to dormant once their value is within ε of equilibrium AND
# they no longer have a dirty neighbor pushing them. In a steady tank with a
# few active plant clusters, this drops the per-tick cost from O(cells_x ×
# cells_z) to O(active cells), typically 5–20× less work.

extends Node
class_name SubstrateGrid

const NUTRIENT_BASELINE: float = 0.3
const NUTRIENT_MAX: float = 3.0
const DIFFUSION_RATE: float = 0.04
const DECAY_RATE: float = 0.003
const RESERVOIR_LEAK_PER_TICK: float = 0.00015
# Tolerance for "this cell is at equilibrium." Tight enough that visible
# nutrient hotspots near plants still tick, loose enough that the natural
# floating-point noise of diffusion doesn't keep dormant cells active.
const EQUILIBRIUM_EPSILON: float = 0.004

# Hoisted out of tick(): GDScript reallocates an inline array literal
# every time the for-loop is entered, so the old `for off in [Vector2i(...),
# ...]` form was allocating 4 Vector2is per cell per tick.
const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
]

# Per-instance overrides set by world.gd from TankConfig.SUBSTRATE_PROFILES.
# Negative means "use the const default". Allows different substrate types
# (sand, eco-complete, inert gravel) to have different fertility characteristics
# at sim start without touching the global constants.
var baseline_override: float = -1.0
var reservoir_leak_override: float = -1.0


func _active_baseline() -> float:
	return baseline_override if baseline_override >= 0.0 else NUTRIENT_BASELINE


func _active_reservoir_leak() -> float:
	return reservoir_leak_override if reservoir_leak_override >= 0.0 else RESERVOIR_LEAK_PER_TICK


func _equilibrium_value() -> float:
	# Steady-state where reservoir leak balances decay toward baseline.
	# new = old + (baseline - old) * decay + leak
	# Solving for new == old: old = baseline + leak / decay.
	return _active_baseline() + _active_reservoir_leak() / DECAY_RATE


var cells_x: int
var cells_z: int
var cell_size: float
var origin: Vector3   # world-space corner of cell (0,0)
var nutrients: Array  # of Array[float], [x][z]
# Scratch buffer for diffusion. Preallocated once in init() so tick()
# doesn't have to allocate cells_x × cells_z floats every sim frame.
var _scratch: Array = []
# Dirty set — cells that diverged from equilibrium and need ticking.
# Keyed by Vector2i. Bools are just markers; presence is what matters.
var _dirty_cells: Dictionary = {}
# Working buffer reused each tick so we don't allocate a new Dictionary
# per call (or a new Array for the iteration snapshot).
var _next_dirty: Dictionary = {}


func init(half_w: float, half_d: float, cells_per_unit: float = 1.0) -> void:
	cells_x = int(half_w * 2.0 * cells_per_unit)
	cells_z = int(half_d * 2.0 * cells_per_unit)
	cell_size = 1.0 / cells_per_unit
	origin = Vector3(-half_w, 0, -half_d)
	nutrients = []
	_scratch = []
	# Initialize cells AT equilibrium so dormant cells don't need ticking
	# just to absorb the reservoir leak — they're already where they'd
	# settle. add_at/consume_at then mark the cell active when something
	# pushes it away from this steady state.
	var eq: float = _equilibrium_value()
	for x in cells_x:
		var col: Array = []
		col.resize(cells_z)
		col.fill(eq)
		nutrients.append(col)
		var sc: Array = []
		sc.resize(cells_z)
		_scratch.append(sc)
	_dirty_cells.clear()


func _cell_at(world_pos: Vector3) -> Vector2i:
	var local := world_pos - origin
	var cx: int = clampi(int(local.x / cell_size), 0, cells_x - 1)
	var cz: int = clampi(int(local.z / cell_size), 0, cells_z - 1)
	return Vector2i(cx, cz)


# Flag a cell and its 4 immediate neighbors as dirty. Anything that
# diffuses into them on the next tick will still spread.
func _mark_dirty(cell: Vector2i) -> void:
	_dirty_cells[cell] = true
	for off in NEIGHBOR_OFFSETS:
		var n := Vector2i(cell.x + off.x, cell.y + off.y)
		if n.x < 0 or n.y < 0 or n.x >= cells_x or n.y >= cells_z:
			continue
		_dirty_cells[n] = true


func get_at(world_pos: Vector3) -> float:
	var c := _cell_at(world_pos)
	return nutrients[c.x][c.y]


func add_at(world_pos: Vector3, amount: float) -> void:
	var c := _cell_at(world_pos)
	nutrients[c.x][c.y] = minf(nutrients[c.x][c.y] + amount, NUTRIENT_MAX)
	_mark_dirty(c)


func consume_at(world_pos: Vector3, amount: float) -> float:
	# Take up to `amount` from the cell. Return actually-consumed value.
	var c := _cell_at(world_pos)
	var available: float = nutrients[c.x][c.y] - _active_baseline()
	if available <= 0.0:
		return 0.0
	var taken: float = minf(amount, available)
	nutrients[c.x][c.y] -= taken
	_mark_dirty(c)
	return taken


func tick(_dt: float) -> void:
	# Lazy diffusion + decay. Only walks dirty cells (and their immediate
	# neighbors, captured via _mark_dirty on add/consume). Empty dirty set
	# = nothing to do this tick — common case once the tank settles.
	if _dirty_cells.is_empty():
		return

	# Snapshot the dirty set's cells into the scratch buffer. We only need
	# to copy cells that will be read this tick (the dirty cells plus
	# their neighbors), not the whole grid.
	var to_process: Array = _dirty_cells.keys()
	for cell_v in to_process:
		var cell: Vector2i = cell_v
		# Copy current value to scratch. Neighbors are read straight from
		# `nutrients` since they may or may not be dirty themselves — the
		# scratch is only needed for the cells we'll WRITE this tick.
		_scratch[cell.x][cell.y] = nutrients[cell.x][cell.y]
		# Also copy neighbors that ARE dirty so cross-diffusion uses the
		# pre-tick state symmetrically.
		for off in NEIGHBOR_OFFSETS:
			var n := Vector2i(cell.x + off.x, cell.y + off.y)
			if n.x < 0 or n.y < 0 or n.x >= cells_x or n.y >= cells_z:
				continue
			if _dirty_cells.has(n):
				_scratch[n.x][n.y] = nutrients[n.x][n.y]

	var baseline: float = _active_baseline()
	var leak: float = _active_reservoir_leak()
	var eq: float = baseline + leak / DECAY_RATE
	_next_dirty.clear()
	for cell_v in to_process:
		var cell: Vector2i = cell_v
		var x: int = cell.x
		var z: int = cell.y
		var c: float = _scratch[x][z]
		var sum: float = 0.0
		var count: float = 0.0
		for off in NEIGHBOR_OFFSETS:
			var nx: int = x + off.x
			var nz: int = z + off.y
			if nx < 0 or nz < 0 or nx >= cells_x or nz >= cells_z:
				continue
			# Use scratch value if neighbor is in the working set; else
			# read live nutrients (equivalent at this point).
			var n_cell := Vector2i(nx, nz)
			var nv: float = _scratch[nx][nz] if _dirty_cells.has(n_cell) else nutrients[nx][nz]
			sum += nv
			count += 1.0
		var avg: float = sum / maxf(count, 1.0)
		var new_val: float = c + (avg - c) * DIFFUSION_RATE
		new_val += (baseline - new_val) * DECAY_RATE
		new_val += leak
		new_val = clampf(new_val, 0.0, NUTRIENT_MAX)
		nutrients[x][z] = new_val

		# Stay dirty if we haven't reached equilibrium yet OR if a sizable
		# value change just happened (diffusion will still spread).
		if absf(new_val - eq) > EQUILIBRIUM_EPSILON:
			_next_dirty[cell] = true
			# Re-dirty neighbors so diffusion has somewhere to go.
			for off in NEIGHBOR_OFFSETS:
				var nnx: int = x + off.x
				var nnz: int = z + off.y
				if nnx < 0 or nnz < 0 or nnx >= cells_x or nnz >= cells_z:
					continue
				_next_dirty[Vector2i(nnx, nnz)] = true
	# Swap. _dirty_cells is now the surviving set; _next_dirty becomes the
	# empty scratch buffer for the next tick.
	var swap: Dictionary = _dirty_cells
	_dirty_cells = _next_dirty
	_next_dirty = swap


func total_above_baseline() -> float:
	var sum: float = 0.0
	for x in cells_x:
		for z in cells_z:
			sum += maxf(0.0, nutrients[x][z] - _active_baseline())
	return sum


# Pore-water exchange: organics in the substrate slowly leach nitrate into
# the water column (real aquasoil / mulm behaviour).
func pore_water_nitrate_leak() -> float:
	var excess: float = total_above_baseline()
	if excess <= 1.5:
		return 0.0
	return clampf((excess - 1.5) * 0.00035, 0.0, 0.0045)


# ---- Save / load ----

func to_save_dict() -> Dictionary:
	# Pack the 2D nutrient array as a flat float list so JSON encoding stays
	# small (no nested array headers per row). cells_x/cells_z let us
	# re-shape on load.
	var flat: PackedFloat32Array = PackedFloat32Array()
	flat.resize(cells_x * cells_z)
	for x in cells_x:
		for z in cells_z:
			flat[x * cells_z + z] = nutrients[x][z]
	return {
		"cells_x": cells_x,
		"cells_z": cells_z,
		"cell_size": cell_size,
		"origin": [origin.x, origin.y, origin.z],
		"baseline_override": baseline_override,
		"reservoir_leak_override": reservoir_leak_override,
		"nutrients_flat": Array(flat),
	}


func apply_save_dict(d: Dictionary) -> void:
	# Caller has already called init() with the tank's current dimensions, so
	# our grid exists with the right shape. We just overwrite the nutrient
	# values. If the saved grid was a different size (player resized the
	# tank between sessions, which shouldn't happen but defensively), we
	# copy only the overlapping cells.
	baseline_override = float(d.get("baseline_override", baseline_override))
	reservoir_leak_override = float(d.get("reservoir_leak_override", reservoir_leak_override))
	var sx: int = int(d.get("cells_x", cells_x))
	var sz: int = int(d.get("cells_z", cells_z))
	var flat: Array = d.get("nutrients_flat", [])
	if flat.size() < sx * sz:
		return  # malformed
	var copy_x: int = mini(cells_x, sx)
	var copy_z: int = mini(cells_z, sz)
	var eq: float = _equilibrium_value()
	for x in copy_x:
		for z in copy_z:
			var v: float = float(flat[x * sz + z])
			nutrients[x][z] = v
			# Any saved value that isn't at equilibrium needs a tick to
			# settle (or spread further); mark it dirty so the lazy
			# update picks it up.
			if absf(v - eq) > EQUILIBRIUM_EPSILON:
				_mark_dirty(Vector2i(x, z))
