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

const SeedBankStore = preload("res://scripts/substrate_seed_bank.gd")
const RootCompetition = preload("res://scripts/substrate_root_competition.gd")
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
const IRON_MAX: float = 1.5
const CO2_MAX: float = 1.2
const MULM_MAX: float = 8.0
const MULM_MINERALIZE_RATE: float = 0.0025
const IRON_LEGACY_DEFAULT: float = 0.7
const CO2_LEGACY_DEFAULT: float = 0.42
const CHANNEL_DIFFUSION: float = 0.06
const CHANNEL_DECAY: float = 0.008
const AVAILABILITY_RELAX_RATE: float = 0.08

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
var iron_availability: Array = []
var co2_availability: Array = []
var mulm: Array = []
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
var _seed_lots = SeedBankStore.new()
var _root_competition = RootCompetition.new()


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
	_init_channel_grid(iron_availability, IRON_LEGACY_DEFAULT)
	_init_channel_grid(co2_availability, CO2_LEGACY_DEFAULT)
	_init_channel_grid(mulm)
	_seed_lots.init(cells_x, cells_z)
	_root_competition.init(cells_x, cells_z)
	_dirty_channels.clear()


func _init_channel_grid(grid: Array, initial: float = 0.0) -> void:
	grid.clear()
	for x in cells_x:
		var col: Array = []
		col.resize(cells_z)
		col.fill(initial)
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


func begin_root_footprint_refresh() -> void:
	_root_competition.begin_refresh()


func register_root_footprint(plant_id: int, world_pos: Vector3,
		radius_cells: int, active_mass: float) -> void:
	_root_competition.register(
		plant_id, _cell_at(world_pos), radius_cells, active_mass)


func end_root_footprint_refresh() -> void:
	_root_competition.end_refresh()


func root_footprint_for(plant_id: int) -> Dictionary:
	return _root_competition.footprint_for(plant_id)


func consume_root_uptake(plant_id: int, world_pos: Vector3, amount: float) -> float:
	var plan: Array = _root_competition.uptake_plan(plant_id, amount)
	if plan.is_empty():
		return consume_at(world_pos, amount)
	var taken: float = 0.0
	for part_v in plan:
		var part: Dictionary = part_v
		taken += _consume_cell(
			part.get("cell", _cell_at(world_pos)), float(part.get("amount", 0.0)))
	return taken


func _consume_cell(c: Vector2i, amount: float) -> float:
	var available: float = nutrients[c.x][c.y] - _active_baseline()
	if available <= 0.0:
		return 0.0
	var taken: float = minf(maxf(0.0, amount), available)
	nutrients[c.x][c.y] -= taken
	_mark_dirty(c)
	return taken


func get_seed_bank_at(world_pos: Vector3) -> float:
	var c := _cell_at(world_pos)
	return _seed_lots.total_at(c)


func add_seed_bank_at(world_pos: Vector3, amount: float) -> void:
	add_seed_lot_at(world_pos, {}, amount, {})


func add_seed_lot_at(world_pos: Vector3, genome: Dictionary, amount: float,
		dormancy: Dictionary = {}) -> float:
	var c := _cell_at(world_pos)
	var accepted: float = _seed_lots.add_lot(c, genome, amount, dormancy)
	_sync_seed_scalar(c)
	if accepted > 0.0:
		_mark_channel_dirty(c)
	return accepted


func consume_seed_bank_at(world_pos: Vector3, amount: float) -> float:
	var lot: Dictionary = take_seed_lot_at(world_pos, amount)
	return float(lot.get("quantity", 0.0))


func take_seed_lot_at(world_pos: Vector3, amount: float) -> Dictionary:
	var c := _cell_at(world_pos)
	var lot: Dictionary = _seed_lots.consume(c, amount)
	_sync_seed_scalar(c)
	if float(lot.get("quantity", 0.0)) > 0.0:
		_mark_channel_dirty(c)
	return lot


func get_seed_lots_at(world_pos: Vector3) -> Array:
	return _seed_lots.lots_at(_cell_at(world_pos))


func _sync_seed_scalar(c: Vector2i) -> void:
	seed_bank[c.x][c.y] = _seed_lots.total_at(c)


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


func get_iron_availability_at(world_pos: Vector3) -> float:
	var c := _cell_at(world_pos)
	return iron_availability[c.x][c.y]


func get_co2_availability_at(world_pos: Vector3) -> float:
	var c := _cell_at(world_pos)
	return co2_availability[c.x][c.y]


# Exchange water-column chemistry into pore water only where roots make the
# cell active. This keeps work proportional to planted/dirty cells.
func exchange_water_availability_at(world_pos: Vector3, water_iron: float,
		water_co2: float, dt: float) -> void:
	var c := _cell_at(world_pos)
	var k: float = clampf(dt * AVAILABILITY_RELAX_RATE, 0.0, 1.0)
	var soil_iron: float = clampf(_active_reservoir_leak() * 900.0, 0.0, 0.35)
	var iron_target: float = clampf(water_iron + soil_iron, 0.0, IRON_MAX)
	var co2_target: float = clampf(water_co2, 0.0, CO2_MAX)
	iron_availability[c.x][c.y] = lerpf(iron_availability[c.x][c.y], iron_target, k)
	co2_availability[c.x][c.y] = lerpf(co2_availability[c.x][c.y], co2_target, k)
	_mark_channel_dirty(c)


func consume_iron_at(world_pos: Vector3, amount: float) -> float:
	return _consume_availability_at(iron_availability, world_pos, amount)


func consume_co2_at(world_pos: Vector3, amount: float) -> float:
	return _consume_availability_at(co2_availability, world_pos, amount)


func get_mulm_at(world_pos: Vector3) -> float:
	var c := _cell_at(world_pos)
	return mulm[c.x][c.y]


func deposit_litter_at(world_pos: Vector3, biomass: float) -> float:
	var c := _cell_at(world_pos)
	var room: float = MULM_MAX - float(mulm[c.x][c.y])
	var accepted: float = minf(maxf(0.0, biomass), maxf(0.0, room))
	if accepted > 0.0:
		mulm[c.x][c.y] = float(mulm[c.x][c.y]) + accepted
		_mark_channel_dirty(c)
	return accepted


func _consume_availability_at(grid: Array, world_pos: Vector3, amount: float) -> float:
	var c := _cell_at(world_pos)
	var taken: float = minf(maxf(0.0, amount), float(grid[c.x][c.y]))
	grid[c.x][c.y] = maxf(0.0, float(grid[c.x][c.y]) - taken)
	if taken > 0.0:
		_mark_channel_dirty(c)
	return taken


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
	var active_cells: Array = _dirty_channels.keys()
	_seed_lots.tick_cells(active_cells, dt)
	for cell_v in active_cells:
		_sync_seed_scalar(cell_v)
	_tick_channel_field(allelochemical, ALLELO_MAX, dt)
	_tick_channel_field(root_oxygen, ROOT_O2_MAX, dt)
	_tick_channel_field(anaerobic_gas, ANAEROBIC_MAX, dt)
	_tick_availability_field(iron_availability, IRON_MAX)
	_tick_availability_field(co2_availability, CO2_MAX)
	_tick_mulm(dt)
	# Re-dirty cells with residual values for slow diffusion
	_next_dirty_channels.clear()
	for cell_v in _dirty_channels.keys():
		var cell: Vector2i = cell_v
		if seed_bank[cell.x][cell.y] > 0.01 \
				or allelochemical[cell.x][cell.y] > 0.01 \
				or root_oxygen[cell.x][cell.y] > 0.01 \
				or anaerobic_gas[cell.x][cell.y] > 0.01 \
				or absf(iron_availability[cell.x][cell.y] - IRON_LEGACY_DEFAULT) > 0.01 \
				or absf(co2_availability[cell.x][cell.y] - CO2_LEGACY_DEFAULT) > 0.01 \
				or mulm[cell.x][cell.y] > 0.001:
			_next_dirty_channels[cell] = true
	var swap: Dictionary = _dirty_channels
	_dirty_channels = _next_dirty_channels
	_next_dirty_channels = swap


func _tick_availability_field(grid: Array, max_val: float) -> void:
	var to_process: Array = _dirty_channels.keys()
	for cell_v in to_process:
		var cell: Vector2i = cell_v
		var sum: float = 0.0
		var count: float = 0.0
		for off in NEIGHBOR_OFFSETS:
			var nx: int = cell.x + off.x
			var nz: int = cell.y + off.y
			if nx < 0 or nz < 0 or nx >= cells_x or nz >= cells_z:
				continue
			sum += float(grid[nx][nz])
			count += 1.0
		var current: float = float(grid[cell.x][cell.y])
		grid[cell.x][cell.y] = clampf(
			current + (sum / maxf(count, 1.0) - current) * CHANNEL_DIFFUSION,
			0.0, max_val)


func _tick_mulm(dt: float) -> void:
	for cell_v in _dirty_channels.keys():
		var cell: Vector2i = cell_v
		var reservoir: float = float(mulm[cell.x][cell.y])
		if reservoir <= 0.0:
			continue
		var released: float = minf(
			reservoir, reservoir * MULM_MINERALIZE_RATE * maxf(0.0, dt))
		var nutrient_room: float = NUTRIENT_MAX - float(nutrients[cell.x][cell.y])
		released = minf(released, maxf(0.0, nutrient_room))
		if released <= 0.0:
			continue
		mulm[cell.x][cell.y] = reservoir - released
		nutrients[cell.x][cell.y] = float(nutrients[cell.x][cell.y]) + released
		_mark_dirty(cell)


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
		tick_channels(_dt)
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
		"iron_availability_flat": _pack_channel_flat(iron_availability),
		"co2_availability_flat": _pack_channel_flat(co2_availability),
		"mulm_flat": _pack_channel_flat(mulm),
		"seed_lots": _seed_lots.to_sparse_save(),
		"schema_version": 4,
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
	var structured: Variant = d.get("seed_lots", [])
	if structured is Array and not (structured as Array).is_empty():
		_seed_lots.apply_sparse_save(structured)
		for x in cells_x:
			for z in cells_z:
				_sync_seed_scalar(Vector2i(x, z))
	else:
		# Legacy scalar cells become anonymous lots with unchanged quantity.
		for x in mini(cells_x, sx):
			for z in mini(cells_z, sz):
				_seed_lots.migrate_scalar(Vector2i(x, z), float(seed_bank[x][z]))
				_sync_seed_scalar(Vector2i(x, z))
	_apply_channel_flat(allelochemical, d.get("allelochemical_flat", []), sx, sz)
	_apply_channel_flat(root_oxygen, d.get("root_oxygen_flat", []), sx, sz)
	_apply_channel_flat(anaerobic_gas, d.get("anaerobic_flat", []), sx, sz)
	# Saves before schema 2 had only global chemistry. init() deliberately
	# leaves legacy-equivalent defaults when these fields are absent.
	_apply_channel_flat(iron_availability, d.get("iron_availability_flat", []), sx, sz)
	_apply_channel_flat(co2_availability, d.get("co2_availability_flat", []), sx, sz)
	# Pre-v3 saves already realized their flat detritus return, so an absent
	# reservoir correctly migrates to zero rather than duplicating nutrients.
	_apply_channel_flat(mulm, d.get("mulm_flat", []), sx, sz)
