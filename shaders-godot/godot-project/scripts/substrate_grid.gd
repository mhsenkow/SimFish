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

# Secondary scalar fields (Plants v2) — sparse dirty tracking like nutrients.
const SEED_BANK_MAX: float = 1.0
const ALLELO_MAX: float = 0.8
const ROOT_O2_MAX: float = 1.0
const ANAEROBIC_MAX: float = 1.0
const CHANNEL_DIFFUSION: float = 0.06
const CHANNEL_DECAY: float = 0.008

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

# Aquasoil aging (#1). Fresh soil leaches richly; over a couple of sim-months
# the organic reservoir is spent and the leak tapers toward a quarter strength.
# A mature tank therefore transitions from soil-fed to fish-waste-fed — the
# real Walstad arc and a reason to keep livestock / drop a root tab.
const SIM_DAY_S_LOCAL: float = 864.0
const SOIL_DEPLETION_DAYS: float = 60.0
const SOIL_AGED_LEAK_FRAC: float = 0.25
var soil_age_s: float = 0.0
var soil_age_mult: float = 1.0


func _active_baseline() -> float:
	return baseline_override if baseline_override >= 0.0 else NUTRIENT_BASELINE


func _active_reservoir_leak() -> float:
	var base: float = reservoir_leak_override if reservoir_leak_override >= 0.0 else RESERVOIR_LEAK_PER_TICK
	return base * soil_age_mult


# Local root-tab injection (#14): bump a cell's nutrients well above baseline.
func add_root_tab_at(world_pos: Vector3, amount: float = 1.4) -> void:
	add_at(world_pos, amount)


# Total dissolved anaerobic gas across the bed — denitrification potential (#5).
func total_anaerobic() -> float:
	var s: float = 0.0
	for x in cells_x:
		for z in cells_z:
			s += anaerobic_gas[x][z]
	return s


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
var seed_bank: Array = []
var allelochemical: Array = []
var root_oxygen: Array = []
var anaerobic_gas: Array = []
var _dirty_channels: Dictionary = {}
var _next_dirty_channels: Dictionary = {}
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
	_init_channel_grid(seed_bank)
	_init_channel_grid(allelochemical)
	_init_channel_grid(root_oxygen)
	_init_channel_grid(anaerobic_gas)
	_dirty_channels.clear()


func _init_channel_grid(grid: Array) -> void:
	grid.clear()
	for x in cells_x:
		var col: Array = []
		col.resize(cells_z)
		col.fill(0.0)
		grid.append(col)


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


func get_seed_bank_at(world_pos: Vector3) -> float:
	var c := _cell_at(world_pos)
	return seed_bank[c.x][c.y]


func add_seed_bank_at(world_pos: Vector3, amount: float) -> void:
	var c := _cell_at(world_pos)
	seed_bank[c.x][c.y] = minf(seed_bank[c.x][c.y] + amount, SEED_BANK_MAX)
	_mark_channel_dirty(c)


func consume_seed_bank_at(world_pos: Vector3, amount: float) -> float:
	var c := _cell_at(world_pos)
	var taken: float = minf(amount, seed_bank[c.x][c.y])
	seed_bank[c.x][c.y] -= taken
	if taken > 0.0:
		_mark_channel_dirty(c)
	return taken


func get_allelochemical_at(world_pos: Vector3) -> float:
	var c := _cell_at(world_pos)
	return allelochemical[c.x][c.y]


func add_allelochemical_at(world_pos: Vector3, amount: float) -> void:
	var c := _cell_at(world_pos)
	allelochemical[c.x][c.y] = minf(allelochemical[c.x][c.y] + amount, ALLELO_MAX)
	_mark_channel_dirty(c)


func get_root_oxygen_at(world_pos: Vector3) -> float:
	var c := _cell_at(world_pos)
	return root_oxygen[c.x][c.y]


func add_root_oxygen_at(world_pos: Vector3, amount: float) -> void:
	var c := _cell_at(world_pos)
	root_oxygen[c.x][c.y] = minf(root_oxygen[c.x][c.y] + amount, ROOT_O2_MAX)
	anaerobic_gas[c.x][c.y] = maxf(0.0, anaerobic_gas[c.x][c.y] - amount * 0.6)
	_mark_channel_dirty(c)


func get_anaerobic_at(world_pos: Vector3) -> float:
	var c := _cell_at(world_pos)
	return anaerobic_gas[c.x][c.y]


func add_anaerobic_at(world_pos: Vector3, amount: float) -> void:
	var c := _cell_at(world_pos)
	anaerobic_gas[c.x][c.y] = minf(anaerobic_gas[c.x][c.y] + amount, ANAEROBIC_MAX)
	_mark_channel_dirty(c)


func release_anaerobic_at(world_pos: Vector3, amount: float) -> float:
	var c := _cell_at(world_pos)
	var released: float = minf(amount, anaerobic_gas[c.x][c.y])
	anaerobic_gas[c.x][c.y] -= released
	if released > 0.0:
		_mark_channel_dirty(c)
	return released


func _mark_channel_dirty(cell: Vector2i) -> void:
	_dirty_channels[cell] = true
	for off in NEIGHBOR_OFFSETS:
		var n := Vector2i(cell.x + off.x, cell.y + off.y)
		if n.x < 0 or n.y < 0 or n.x >= cells_x or n.y >= cells_z:
			continue
		_dirty_channels[n] = true


func _tick_channel_field(grid: Array, max_val: float, dt: float) -> void:
	if _dirty_channels.is_empty():
		return
	var to_process: Array = _dirty_channels.keys()
	for cell_v in to_process:
		var cell: Vector2i = cell_v
		var x: int = cell.x
		var z: int = cell.y
		var c: float = grid[x][z]
		var sum: float = 0.0
		var count: float = 0.0
		for off in NEIGHBOR_OFFSETS:
			var nx: int = x + off.x
			var nz: int = z + off.y
			if nx < 0 or nz < 0 or nx >= cells_x or nz >= cells_z:
				continue
			sum += grid[nx][nz]
			count += 1.0
		var avg: float = sum / maxf(count, 1.0)
		var new_val: float = c + (avg - c) * CHANNEL_DIFFUSION
		new_val = maxf(0.0, new_val - CHANNEL_DECAY * dt * 10.0)
		new_val = minf(new_val, max_val)
		grid[x][z] = new_val


func tick_channels(dt: float) -> void:
	if _dirty_channels.is_empty():
		return
	_tick_channel_field(seed_bank, SEED_BANK_MAX, dt)
	_tick_channel_field(allelochemical, ALLELO_MAX, dt)
	_tick_channel_field(root_oxygen, ROOT_O2_MAX, dt)
	_tick_channel_field(anaerobic_gas, ANAEROBIC_MAX, dt)
	# Re-dirty cells with residual values for slow diffusion
	_next_dirty_channels.clear()
	for cell_v in _dirty_channels.keys():
		var cell: Vector2i = cell_v
		if seed_bank[cell.x][cell.y] > 0.01 \
				or allelochemical[cell.x][cell.y] > 0.01 \
				or root_oxygen[cell.x][cell.y] > 0.01 \
				or anaerobic_gas[cell.x][cell.y] > 0.01:
			_next_dirty_channels[cell] = true
	var swap: Dictionary = _dirty_channels
	_dirty_channels = _next_dirty_channels
	_next_dirty_channels = swap


func tick_night_memory(dt: float, sim) -> void:
	var dl: float = 1.0
	if sim != null and sim.has_method("daylight"):
		dl = float(sim.daylight())
	if dl > 0.32:
		return
	if sim == null or sim.get("waste") is not Array:
		return
	for w in sim.waste:
		if not is_instance_valid(w):
			continue
		var p: Vector3 = w.global_position
		var cx: int = clampi(int((p.x - origin.x) / cell_size), 0, cells_x - 1)
		var cz: int = clampi(int((p.z - origin.z) / cell_size), 0, cells_z - 1)
		nutrients[cx][cz] = clampf(nutrients[cx][cz] + dt * 0.004, 0.0, 2.5)
		_mark_channel_dirty(Vector2i(cx, cz))


func tick(_dt: float) -> void:
	# Soil aging runs every tick (before the dirty-set early-out) so a settled
	# tank still ages its substrate.
	soil_age_s += _dt
	soil_age_mult = lerpf(1.0, SOIL_AGED_LEAK_FRAC,
		clampf(soil_age_s / (SIM_DAY_S_LOCAL * SOIL_DEPLETION_DAYS), 0.0, 1.0))
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

		# Overloaded cells go anaerobic (#11): organics piling up faster than
		# soil bacteria can oxidize them turn into trapped gas pockets, which
		# then feed denitrification (#5) and bioturbation burps (#16).
		if new_val > 2.4:
			anaerobic_gas[x][z] = minf(
				anaerobic_gas[x][z] + (new_val - 2.4) * 0.02 * _dt, ANAEROBIC_MAX)
			_mark_channel_dirty(Vector2i(x, z))

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
	tick_channels(_dt)


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

func _pack_channel_flat(grid: Array) -> Array:
	var flat: PackedFloat32Array = PackedFloat32Array()
	flat.resize(cells_x * cells_z)
	for x in cells_x:
		for z in cells_z:
			flat[x * cells_z + z] = grid[x][z]
	return Array(flat)


func _apply_channel_flat(grid: Array, flat: Array, sx: int, sz: int) -> void:
	if flat.is_empty():
		return
	var copy_x: int = mini(cells_x, sx)
	var copy_z: int = mini(cells_z, sz)
	for x in copy_x:
		for z in copy_z:
			if x * sz + z >= flat.size():
				continue
			var v: float = float(flat[x * sz + z])
			grid[x][z] = v
			if v > 0.01:
				_mark_channel_dirty(Vector2i(x, z))


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
		"soil_age_s": soil_age_s,
		"nutrients_flat": Array(flat),
		"seed_bank_flat": _pack_channel_flat(seed_bank),
		"allelochemical_flat": _pack_channel_flat(allelochemical),
		"root_oxygen_flat": _pack_channel_flat(root_oxygen),
		"anaerobic_flat": _pack_channel_flat(anaerobic_gas),
	}


func apply_save_dict(d: Dictionary) -> void:
	# Caller has already called init() with the tank's current dimensions, so
	# our grid exists with the right shape. We just overwrite the nutrient
	# values. If the saved grid was a different size (player resized the
	# tank between sessions, which shouldn't happen but defensively), we
	# copy only the overlapping cells.
	baseline_override = float(d.get("baseline_override", baseline_override))
	reservoir_leak_override = float(d.get("reservoir_leak_override", reservoir_leak_override))
	soil_age_s = float(d.get("soil_age_s", soil_age_s))
	soil_age_mult = lerpf(1.0, SOIL_AGED_LEAK_FRAC,
		clampf(soil_age_s / (SIM_DAY_S_LOCAL * SOIL_DEPLETION_DAYS), 0.0, 1.0))
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
	_apply_channel_flat(seed_bank, d.get("seed_bank_flat", []), sx, sz)
	_apply_channel_flat(allelochemical, d.get("allelochemical_flat", []), sx, sz)
	_apply_channel_flat(root_oxygen, d.get("root_oxygen_flat", []), sx, sz)
	_apply_channel_flat(anaerobic_gas, d.get("anaerobic_flat", []), sx, sz)
