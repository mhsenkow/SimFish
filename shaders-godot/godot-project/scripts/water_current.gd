extends RefCounted
class_name WaterCurrent

# The tank's water as a fluid (REAL_TANK top-10 #4).
#
# WHY. Every moving thing in the tank faked its own water. Plants swayed on a
# sine with a gust term, motes drifted on noise, bubbles rose straight up, the
# surface rippled on its own clock and fish swam through still air. Nothing
# agreed with anything else, so nothing read as one body of water. In a real
# tank one current does all of it: the airstone plume lifts water up its
# column, spreads it along the surface and sends it down the far glass; the
# filter outlet throws a jet the plants lean away from; fish hang nose-first
# into it; mulm collects in the dead spot behind the driftwood.
#
# WHAT. A coarse incompressible fluid solve over the water volume - Stam's
# stable fluids on a collocated grid:
#
#   forces    buoyancy plumes, filter jets, fish wakes, plant-bed drag
#   advect    semi-Lagrangian self-advection (unconditionally stable)
#   confine   vorticity confinement, so the swirls a coarse grid would smear
#             out in a second keep turning the way real eddies do
#   project   red-black Gauss-Seidel pressure solve. A filter is a true
#             source/sink pair (water leaves at the intake, returns at the
#             outlet), carried as a target divergence, not faked as a push.
#
# Solids (walls, substrate, hardscape, the outside of a curved tank) are a
# mask with no-penetration; the surface is a free-slip lid.
#
# THREADING. step() touches only this object's arrays, so a WorkerThreadPool
# task can run it. publish() hands a snapshot to readers under a mutex;
# sample_*() read that snapshot and never see a half-written field.
#
# UNITS. World units (a 48 in tank is 20 units, so 1 unit ~ 6 cm) and
# seconds. A hang-on-back outlet runs ~2-3 units/s, the bulk circulation it
# drives ~0.2-0.6.

const MAX_CELLS_X: int = 24
const MAX_CELLS_Y: int = 12
const MAX_CELLS_Z: int = 12
const MIN_CELL: float = 0.55
# Total cell budget. The solve is linear in cells; ~2,500 is ~6 ms a step on
# a desktop worker thread. Mobile and low-tier devices pass less.
const DEFAULT_MAX_CELLS: int = 2600

# Pressure iterations per step. Red-black Gauss-Seidel, warm-started from the
# previous step's pressure: the field changes slowly, so a handful of sweeps
# a step keeps the residual divergence low once the flow has developed.
const PRESSURE_ITERS: int = 10
# Vorticity confinement strength (dimensionless, times cell size). Kept low:
# at this resolution it amplifies grid noise as readily as real eddies, and
# at 0.9 it buried the filter's circulation cell under random swirl and
# tripled the tank's kinetic energy. 0.25 keeps the eddies off the rocks and
# the plume edges turning without inventing new ones.
var confinement: float = 0.25
# Linear drag on the whole field per second: sub-grid dissipation. Without it
# the closed box spins up without limit under a constant source.
const BULK_DRAG: float = 0.05
# Extra drag at a fully plant-filled cell, per second.
const PLANT_DRAG: float = 2.4
# Speed ceiling. A coarse step can overshoot near a strong source; nothing in
# an aquarium moves water faster than this.
const MAX_SPEED: float = 4.0

var nx: int = 0
var ny: int = 0
var nz: int = 0
var cell: float = 1.0
var origin: Vector3 = Vector3.ZERO  # world position of cell (0,0,0)'s corner

# Working field (owned by the solver).
var _u := PackedFloat32Array()
var _v := PackedFloat32Array()
var _w := PackedFloat32Array()
var _u0 := PackedFloat32Array()
var _v0 := PackedFloat32Array()
var _w0 := PackedFloat32Array()
var _p := PackedFloat32Array()
var _div := PackedFloat32Array()
var _src := PackedFloat32Array()     # target divergence (filter source/sink)
var _curl := PackedFloat32Array()    # |vorticity|, also published as turbulence
var _cx := PackedFloat32Array()
var _cy := PackedFloat32Array()
var _cz := PackedFloat32Array()
var _solid := PackedByteArray()      # 1 = solid
# Topology, rebuilt when solids change. Every field array carries one extra
# slot at index n that is always 0: a closed face's neighbour index points
# there, so the hot loops read neighbours without a single branch.
var _ne := PackedInt32Array()
var _nw := PackedInt32Array()
var _nn := PackedInt32Array()
var _ns := PackedInt32Array()
var _nf := PackedInt32Array()
var _nb := PackedInt32Array()
var _oe := PackedFloat32Array()      # 1 where that face is open water
var _ow := PackedFloat32Array()
var _on := PackedFloat32Array()
var _os := PackedFloat32Array()
var _of := PackedFloat32Array()
var _ob := PackedFloat32Array()
var _inv_cnt := PackedFloat32Array()  # 1 / open-face count (0 when boxed in)
var _red := PackedInt32Array()
var _black := PackedInt32Array()
var _topology_dirty: bool = true
var _porosity := PackedFloat32Array()  # 0 open water .. 1 dense plant bed

# Forces for the next step: Array of Dictionaries (see add_* below).
var _plumes: Array[Dictionary] = []
var _jets: Array[Dictionary] = []
var _splats: Array[Vector4] = []  # xyz = world pos, w unused; impulse in _splat_dir
var _splat_dir: Array[Vector3] = []
# A dense impulse field handed over whole (TankFlowField stages wakes here).
var _imp_u := PackedFloat32Array()
var _imp_v := PackedFloat32Array()
var _imp_w := PackedFloat32Array()

# Published snapshot (read side).
var _mutex := Mutex.new()
var _pub_u := PackedFloat32Array()
var _pub_v := PackedFloat32Array()
var _pub_w := PackedFloat32Array()
var _pub_t := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var time: float = 0.0
# Wall time of the last step, for probes.
var last_step_ms: float = 0.0


# Build the grid over the water volume [-half_w, half_w] x [floor_y, surface_y]
# x [-half_d, half_d]. `is_solid` (optional) is called with a world position
# for each cell centre and returns true for cells that are not water.
func build(half_w: float, half_d: float, floor_y: float, surface_y: float,
		is_solid: Callable = Callable(), max_cells: int = DEFAULT_MAX_CELLS) -> void:
	var ext := Vector3(half_w * 2.0, maxf(surface_y - floor_y, 0.5), half_d * 2.0)
	cell = maxf(MIN_CELL, maxf(ext.x / MAX_CELLS_X,
		maxf(ext.y / MAX_CELLS_Y, ext.z / MAX_CELLS_Z)))
	# Coarsen uniformly until the grid fits the budget.
	var budget: int = maxi(max_cells, 64)
	while true:
		nx = maxi(3, int(ceil(ext.x / cell)))
		ny = maxi(3, int(ceil(ext.y / cell)))
		nz = maxi(3, int(ceil(ext.z / cell)))
		if nx * ny * nz <= budget:
			break
		cell *= 1.08
	# Centre the grid on the volume; the overhang is a sliver of solid wall.
	origin = Vector3(-nx * cell * 0.5, floor_y, -nz * cell * 0.5)
	var n: int = nx * ny * nz
	_u = _zeros(n + 1)
	_v = _zeros(n + 1)
	_w = _zeros(n + 1)
	_u0 = _zeros(n + 1)
	_v0 = _zeros(n + 1)
	_w0 = _zeros(n + 1)
	_p = _zeros(n + 1)
	_div = _zeros(n + 1)
	_src = _zeros(n + 1)
	_curl = _zeros(n + 1)
	_cx = _zeros(n + 1)
	_cy = _zeros(n + 1)
	_cz = _zeros(n + 1)
	_porosity = _zeros(n + 1)
	_solid.resize(n)
	_solid.fill(0)
	for z in nz:
		for y in ny:
			for x in nx:
				var c: Vector3 = cell_center(x, y, z)
				var s: bool = absf(c.x) > half_w or absf(c.z) > half_d \
					or c.y > surface_y
				if not s and is_solid.is_valid():
					s = bool(is_solid.call(c))
				_solid[x + nx * (y + ny * z)] = 1 if s else 0
	_rebuild_topology()
	_mutex.lock()
	_pub_u = _u.duplicate()
	_pub_v = _v.duplicate()
	_pub_w = _w.duplicate()
	_pub_t = _curl.duplicate()
	_mutex.unlock()


static func _zeros(n: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	a.fill(0.0)
	return a


func cell_count() -> int:
	return nx * ny * nz


func cell_center(x: int, y: int, z: int) -> Vector3:
	return origin + Vector3((x + 0.5) * cell, (y + 0.5) * cell, (z + 0.5) * cell)


func is_solid_cell(x: int, y: int, z: int) -> bool:
	if x < 0 or y < 0 or z < 0 or x >= nx or y >= ny or z >= nz:
		return true
	return _solid[x + nx * (y + ny * z)] == 1


func set_solid_at(world_pos: Vector3, solid: bool) -> void:
	var g: Vector3 = (world_pos - origin) / cell
	var x: int = int(floor(g.x))
	var y: int = int(floor(g.y))
	var z: int = int(floor(g.z))
	if x < 0 or y < 0 or z < 0 or x >= nx or y >= ny or z >= nz:
		return
	_solid[x + nx * (y + ny * z)] = 1 if solid else 0
	_topology_dirty = true


# 0..1 per cell. Plant beds resist flow: water slows inside a valli thicket
# and goes round it.
# Swap the whole solid mask (hardscape moved, a rock was placed). Water in a
# cell that just became solid is dropped; the projection sorts out the rest.
func replace_solids(mask: PackedByteArray) -> void:
	if mask.size() != cell_count():
		return
	_solid = mask
	_topology_dirty = true


# Per-cell velocity changes to add at the start of the next step.
func set_impulse_field(u: PackedFloat32Array, v: PackedFloat32Array,
		w: PackedFloat32Array) -> void:
	if u.size() == cell_count() and v.size() == u.size() and w.size() == u.size():
		_imp_u = u
		_imp_v = v
		_imp_w = w


func set_porosity(values: PackedFloat32Array) -> void:
	if values.size() == cell_count():
		values.append(0.0)
		_porosity = values


# ---- forces ---------------------------------------------------------------

# A bubble plume rising from `base`: buoyancy (units/s^2) at the core, widening
# with height the way a real plume entrains and spreads.
func add_plume(base: Vector3, buoyancy: float, radius: float) -> void:
	_plumes.append({"base": base, "b": buoyancy, "r": maxf(radius, cell * 0.6)})


# A filter return: water appears at `outlet` moving along `dir` at `speed`, and
# the same volume leaves at `intake`. flow is volume per second (units^3/s).
func add_filter(outlet: Vector3, dir: Vector3, speed: float, intake: Vector3,
		flow: float, width: float = 0.0) -> void:
	_jets.append({"outlet": outlet, "dir": dir.normalized(), "speed": speed,
		"intake": intake, "flow": flow, "width": width})


# A momentum impulse (units/s of velocity change, spread over ~one cell) at a
# world point - a fish tail stroke, a dropped pellet, a hand in the water.
func add_impulse(world_pos: Vector3, dv: Vector3) -> void:
	if _splats.size() >= 96:
		return
	_splats.append(Vector4(world_pos.x, world_pos.y, world_pos.z, 0.0))
	_splat_dir.append(dv)


func clear_sources() -> void:
	_plumes.clear()
	_jets.clear()


# ---- the step -------------------------------------------------------------

func step(dt: float) -> void:
	_step_impl(clampf(dt, 0.001, 0.12))


# A long step for prewarming a new tank: semi-Lagrangian advection is stable
# at any dt, so the circulation can be brought up in a few dozen steps.
func step_coarse(dt: float) -> void:
	_step_impl(clampf(dt, 0.001, 0.5))


func _step_impl(dt: float) -> void:
	if nx == 0:
		return
	var t0: int = Time.get_ticks_usec()
	time += dt
	if _topology_dirty:
		_rebuild_topology()
	_apply_forces(dt)
	_advect(dt)
	_confine(dt)
	_project()
	_clamp_speed()
	last_step_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	_publish()


func _apply_forces(dt: float) -> void:
	var sx: int = 1
	var sy: int = nx
	var sz: int = nx * ny
	_src.fill(0.0)
	var inv_c: float = 1.0 / cell
	# Plumes. A real bubble column is unsteady - bubbles shed in bursts and
	# the column wanders - so the force breathes and its axis drifts a little.
	for pl in _plumes:
		var base: Vector3 = pl["base"]
		var b: float = float(pl["b"])
		var r0: float = float(pl["r"])
		var wob := Vector2(sin(time * 1.7 + base.x) , cos(time * 1.3 + base.z)) * cell * 0.35
		var pulse: float = 0.8 + 0.2 * sin(time * 5.1 + base.x * 3.0) \
			+ _rng.randf_range(-0.12, 0.12)
		for z in nz:
			for y in ny:
				for x in nx:
					var i: int = x * sx + y * sy + z * sz
					if _solid[i] == 1:
						continue
					var c: Vector3 = origin + Vector3((x + 0.5) * cell, (y + 0.5) * cell, (z + 0.5) * cell)
					var hgt: float = c.y - base.y
					if hgt < -cell:
						continue
					var r: float = r0 + maxf(hgt, 0.0) * 0.12
					var dx: float = c.x - base.x - wob.x
					var dz: float = c.z - base.z - wob.y
					var d2: float = (dx * dx + dz * dz) / (r * r)
					if d2 > 4.0:
						continue
					_v[i] += dt * b * pulse * exp(-d2)
	# Filters: a jet of momentum at the outlet and a matched source/sink in
	# the divergence target, so the volume really moves from intake to outlet.
	for jt in _jets:
		var outlet: Vector3 = jt["outlet"]
		var dir: Vector3 = jt["dir"]
		var speed: float = float(jt["speed"])
		var flow: float = float(jt["flow"])
		var oi: int = _index_at(outlet)
		var ii: int = _index_at(jt["intake"])
		if oi >= 0 and ii >= 0 and oi != ii:
			var q: float = flow / (cell * cell * cell)
			_src[oi] += q
			_src[ii] -= q
		# Relax the cells along the outlet's first three cells toward jet
		# speed, across the width of the spillway: a hang-on-back pours a
		# sheet, not a pencil.
		var lat := Vector3(dir.z, 0.0, -dir.x)
		if lat.length_squared() < 1e-6:
			lat = Vector3.RIGHT
		lat = lat.normalized()
		var half_n: int = int(round(float(jt.get("width", 0.0)) * 0.5 / cell))
		for o in range(-half_n, half_n + 1):
			for k in 3:
				var jp: Vector3 = outlet + lat * (cell * o) + dir * (cell * k)
				var ji: int = _index_at(jp)
				if ji < 0 or _solid[ji] == 1:
					continue
				var keep: float = clampf(1.0 - dt * (6.0 - k * 1.8), 0.0, 1.0)
				var tgt: Vector3 = dir * speed * (1.0 - k * 0.22)
				_u[ji] = lerpf(tgt.x, _u[ji], keep)
				_v[ji] = lerpf(tgt.y, _v[ji], keep)
				_w[ji] = lerpf(tgt.z, _w[ji], keep)
	# Impulses: trilinear splat so a moving fish leaves a smooth wake.
	for s in _splats.size():
		var sp: Vector4 = _splats[s]
		var dv: Vector3 = _splat_dir[s]
		var g := Vector3((sp.x - origin.x) * inv_c - 0.5, (sp.y - origin.y) * inv_c - 0.5,
			(sp.z - origin.z) * inv_c - 0.5)
		var x0: int = int(floor(g.x))
		var y0: int = int(floor(g.y))
		var z0: int = int(floor(g.z))
		var fx: float = g.x - x0
		var fy: float = g.y - y0
		var fz: float = g.z - z0
		for dz in 2:
			for dy in 2:
				for dx in 2:
					var xx: int = x0 + dx
					var yy: int = y0 + dy
					var zz: int = z0 + dz
					if xx < 0 or yy < 0 or zz < 0 or xx >= nx or yy >= ny or zz >= nz:
						continue
					var wgt: float = (fx if dx == 1 else 1.0 - fx) \
						* (fy if dy == 1 else 1.0 - fy) * (fz if dz == 1 else 1.0 - fz)
					var i: int = xx + yy * sy + zz * sz
					if _solid[i] == 1:
						continue
					_u[i] += dv.x * wgt
					_v[i] += dv.y * wgt
					_w[i] += dv.z * wgt
	_splats.clear()
	_splat_dir.clear()
	if not _imp_u.is_empty():
		for i in _imp_u.size():
			_u[i] += _imp_u[i]
			_v[i] += _imp_v[i]
			_w[i] += _imp_w[i]
		_imp_u = PackedFloat32Array()
		_imp_v = PackedFloat32Array()
		_imp_w = PackedFloat32Array()
	# Drag: bulk dissipation plus the plant beds.
	var n: int = nx * ny * nz
	for i in n:
		if _solid[i] == 1:
			_u[i] = 0.0
			_v[i] = 0.0
			_w[i] = 0.0
			continue
		var k: float = clampf(1.0 - dt * (BULK_DRAG + PLANT_DRAG * _porosity[i]), 0.0, 1.0)
		_u[i] *= k
		_v[i] *= k
		_w[i] *= k


func _index_at(p: Vector3) -> int:
	var g: Vector3 = (p - origin) / cell
	var x: int = clampi(int(floor(g.x)), 0, nx - 1)
	var y: int = clampi(int(floor(g.y)), 0, ny - 1)
	var z: int = clampi(int(floor(g.z)), 0, nz - 1)
	var i: int = x + nx * (y + ny * z)
	return i if _solid[i] == 0 else -1


func _rebuild_topology() -> void:
	var n: int = nx * ny * nz
	var sy: int = nx
	var sz: int = nx * ny
	_ne = _int_fill(n, n)
	_nw = _int_fill(n, n)
	_nn = _int_fill(n, n)
	_ns = _int_fill(n, n)
	_nf = _int_fill(n, n)
	_nb = _int_fill(n, n)
	_oe = _zeros(n)
	_ow = _zeros(n)
	_on = _zeros(n)
	_os = _zeros(n)
	_of = _zeros(n)
	_ob = _zeros(n)
	_inv_cnt = _zeros(n)
	_red = PackedInt32Array()
	_black = PackedInt32Array()
	for z in nz:
		for y in ny:
			for x in nx:
				var i: int = x + y * sy + z * sz
				if _solid[i] == 1:
					continue
				var cnt: int = 0
				if x < nx - 1 and _solid[i + 1] == 0:
					_ne[i] = i + 1
					_oe[i] = 1.0
					cnt += 1
				if x > 0 and _solid[i - 1] == 0:
					_nw[i] = i - 1
					_ow[i] = 1.0
					cnt += 1
				if y < ny - 1 and _solid[i + sy] == 0:
					_nn[i] = i + sy
					_on[i] = 1.0
					cnt += 1
				if y > 0 and _solid[i - sy] == 0:
					_ns[i] = i - sy
					_os[i] = 1.0
					cnt += 1
				if z < nz - 1 and _solid[i + sz] == 0:
					_nf[i] = i + sz
					_of[i] = 1.0
					cnt += 1
				if z > 0 and _solid[i - sz] == 0:
					_nb[i] = i - sz
					_ob[i] = 1.0
					cnt += 1
				_inv_cnt[i] = 1.0 / float(cnt) if cnt > 0 else 0.0
				if ((x + y + z) & 1) == 0:
					_red.append(i)
				else:
					_black.append(i)
	_topology_dirty = false


static func _int_fill(n: int, v: int) -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(n)
	a.fill(v)
	return a


# Make the field divergence-free (apart from the filter's source/sink).
func _project() -> void:
	var half_inv: float = 0.5 / cell
	var h2: float = cell * cell
	# Divergence with no-penetration at solids: a closed face mirrors this
	# cell's own normal velocity, so it carries zero flux.
	for colour in 2:
		var cells: PackedInt32Array = _red if colour == 0 else _black
		for i in cells:
			var ui: float = _u[i]
			var vi: float = _v[i]
			var wi: float = _w[i]
			var ue: float = _u[_ne[i]] - ui * (1.0 - _oe[i])
			var uw: float = _u[_nw[i]] - ui * (1.0 - _ow[i])
			var vn: float = _v[_nn[i]] - vi * (1.0 - _on[i])
			var vs: float = _v[_ns[i]] - vi * (1.0 - _os[i])
			var wf: float = _w[_nf[i]] - wi * (1.0 - _of[i])
			var wb: float = _w[_nb[i]] - wi * (1.0 - _ob[i])
			_div[i] = h2 * (((ue - uw) + (vn - vs) + (wf - wb)) * half_inv - _src[i])
	# Red-black Gauss-Seidel on lap(p) = div with Neumann walls: a closed
	# face drops out of the stencil (its neighbour index reads the zero slot
	# and the count excludes it).
	for _it in PRESSURE_ITERS:
		for i in _red:
			_p[i] = (_p[_ne[i]] + _p[_nw[i]] + _p[_nn[i]] + _p[_ns[i]]
				+ _p[_nf[i]] + _p[_nb[i]] - _div[i]) * _inv_cnt[i]
		for i in _black:
			_p[i] = (_p[_ne[i]] + _p[_nw[i]] + _p[_nn[i]] + _p[_ns[i]]
				+ _p[_nf[i]] + _p[_nb[i]] - _div[i]) * _inv_cnt[i]
	# Subtract the pressure gradient; a closed face takes this cell's own
	# pressure, so there is no push into a wall.
	for colour in 2:
		var cells: PackedInt32Array = _red if colour == 0 else _black
		for i in cells:
			var pc: float = _p[i]
			_u[i] -= ((_p[_ne[i]] + pc * (1.0 - _oe[i])) - (_p[_nw[i]] + pc * (1.0 - _ow[i]))) * half_inv
			_v[i] -= ((_p[_nn[i]] + pc * (1.0 - _on[i])) - (_p[_ns[i]] + pc * (1.0 - _os[i]))) * half_inv
			_w[i] -= ((_p[_nf[i]] + pc * (1.0 - _of[i])) - (_p[_nb[i]] + pc * (1.0 - _ob[i]))) * half_inv


# Semi-Lagrangian: each cell takes the velocity found one step upstream.
func _advect(dt: float) -> void:
	_u0 = _u.duplicate()
	_v0 = _v.duplicate()
	_w0 = _w.duplicate()
	var sy: int = nx
	var sz: int = nx * ny
	var k: float = dt / cell
	var mx: float = nx - 1.001
	var my: float = ny - 1.001
	var mz: float = nz - 1.001
	for z in nz:
		for y in ny:
			for x in nx:
				var i: int = x + y * sy + z * sz
				if _solid[i] == 1:
					continue
				var gx: float = clampf(x - _u0[i] * k, 0.0, mx)
				var gy: float = clampf(y - _v0[i] * k, 0.0, my)
				var gz: float = clampf(z - _w0[i] * k, 0.0, mz)
				var x0: int = int(gx)
				var y0: int = int(gy)
				var z0: int = int(gz)
				var fx: float = gx - x0
				var fy: float = gy - y0
				var fz: float = gz - z0
				var i000: int = x0 + y0 * sy + z0 * sz
				var i100: int = i000 + 1
				var i010: int = i000 + sy
				var i110: int = i010 + 1
				var i001: int = i000 + sz
				var i101: int = i001 + 1
				var i011: int = i001 + sy
				var i111: int = i011 + 1
				var w000: float = (1.0 - fx) * (1.0 - fy) * (1.0 - fz)
				var w100: float = fx * (1.0 - fy) * (1.0 - fz)
				var w010: float = (1.0 - fx) * fy * (1.0 - fz)
				var w110: float = fx * fy * (1.0 - fz)
				var w001: float = (1.0 - fx) * (1.0 - fy) * fz
				var w101: float = fx * (1.0 - fy) * fz
				var w011: float = (1.0 - fx) * fy * fz
				var w111: float = fx * fy * fz
				_u[i] = _u0[i000] * w000 + _u0[i100] * w100 + _u0[i010] * w010 + _u0[i110] * w110 \
					+ _u0[i001] * w001 + _u0[i101] * w101 + _u0[i011] * w011 + _u0[i111] * w111
				_v[i] = _v0[i000] * w000 + _v0[i100] * w100 + _v0[i010] * w010 + _v0[i110] * w110 \
					+ _v0[i001] * w001 + _v0[i101] * w101 + _v0[i011] * w011 + _v0[i111] * w111
				_w[i] = _w0[i000] * w000 + _w0[i100] * w100 + _w0[i010] * w010 + _w0[i110] * w110 \
					+ _w0[i001] * w001 + _w0[i101] * w101 + _w0[i011] * w011 + _w0[i111] * w111


# Vorticity confinement (Fedkiw, Stam & Jensen 2001): push each eddy back
# toward its own core so the coarse grid's numerical viscosity does not
# smear it away. This is what keeps the water visibly turning.
func _confine(dt: float) -> void:
	var sy: int = nx
	var sz: int = nx * ny
	var half_inv: float = 0.5 / cell
	for z in range(1, nz - 1):
		for y in range(1, ny - 1):
			for x in range(1, nx - 1):
				var i: int = x + y * sy + z * sz
				if _solid[i] == 1:
					_curl[i] = 0.0
					continue
				var cx: float = ((_w[i + sy] - _w[i - sy]) - (_v[i + sz] - _v[i - sz])) * half_inv
				var cy: float = ((_u[i + sz] - _u[i - sz]) - (_w[i + 1] - _w[i - 1])) * half_inv
				var cz: float = ((_v[i + 1] - _v[i - 1]) - (_u[i + sy] - _u[i - sy])) * half_inv
				_cx[i] = cx
				_cy[i] = cy
				_cz[i] = cz
				_curl[i] = sqrt(cx * cx + cy * cy + cz * cz)
	var eps: float = confinement * cell * dt
	for z in range(2, nz - 2):
		for y in range(2, ny - 2):
			for x in range(2, nx - 2):
				var i: int = x + y * sy + z * sz
				if _solid[i] == 1:
					continue
				var gx: float = (_curl[i + 1] - _curl[i - 1]) * half_inv
				var gy: float = (_curl[i + sy] - _curl[i - sy]) * half_inv
				var gz: float = (_curl[i + sz] - _curl[i - sz]) * half_inv
				var gl: float = sqrt(gx * gx + gy * gy + gz * gz)
				if gl < 1e-5:
					continue
				gx /= gl
				gy /= gl
				gz /= gl
				_u[i] += eps * (gy * _cz[i] - gz * _cy[i])
				_v[i] += eps * (gz * _cx[i] - gx * _cz[i])
				_w[i] += eps * (gx * _cy[i] - gy * _cx[i])


func _clamp_speed() -> void:
	var m2: float = MAX_SPEED * MAX_SPEED
	for i in nx * ny * nz:
		var s2: float = _u[i] * _u[i] + _v[i] * _v[i] + _w[i] * _w[i]
		if s2 > m2:
			var k: float = MAX_SPEED / sqrt(s2)
			_u[i] *= k
			_v[i] *= k
			_w[i] *= k


func _publish() -> void:
	_mutex.lock()
	_pub_u = _u.duplicate()
	_pub_v = _v.duplicate()
	_pub_w = _w.duplicate()
	_pub_t = _curl.duplicate()
	_mutex.unlock()


# ---- read side ------------------------------------------------------------

# Copy-on-write references to the last published field. Readers that sample
# many points per frame take one snapshot and pass it to sample_snapshot().
func snapshot() -> Array:
	_mutex.lock()
	var s: Array = [_pub_u, _pub_v, _pub_w, _pub_t]
	_mutex.unlock()
	return s


func velocity_at(world_pos: Vector3) -> Vector3:
	return sample_snapshot(snapshot(), world_pos)


func sample_snapshot(snap: Array, world_pos: Vector3) -> Vector3:
	if nx == 0 or snap.is_empty():
		return Vector3.ZERO
	var pu: PackedFloat32Array = snap[0]
	var pv: PackedFloat32Array = snap[1]
	var pw: PackedFloat32Array = snap[2]
	if pu.size() < nx * ny * nz:
		return Vector3.ZERO
	var g: Vector3 = (world_pos - origin) / cell - Vector3(0.5, 0.5, 0.5)
	var gx: float = clampf(g.x, 0.0, nx - 1.001)
	var gy: float = clampf(g.y, 0.0, ny - 1.001)
	var gz: float = clampf(g.z, 0.0, nz - 1.001)
	var x0: int = int(gx)
	var y0: int = int(gy)
	var z0: int = int(gz)
	var fx: float = gx - x0
	var fy: float = gy - y0
	var fz: float = gz - z0
	var sy: int = nx
	var sz: int = nx * ny
	var i000: int = x0 + y0 * sy + z0 * sz
	var w000: float = (1.0 - fx) * (1.0 - fy) * (1.0 - fz)
	var w100: float = fx * (1.0 - fy) * (1.0 - fz)
	var w010: float = (1.0 - fx) * fy * (1.0 - fz)
	var w110: float = fx * fy * (1.0 - fz)
	var w001: float = (1.0 - fx) * (1.0 - fy) * fz
	var w101: float = fx * (1.0 - fy) * fz
	var w011: float = (1.0 - fx) * fy * fz
	var w111: float = fx * fy * fz
	var i100: int = i000 + 1
	var i010: int = i000 + sy
	var i110: int = i010 + 1
	var i001: int = i000 + sz
	var i101: int = i001 + 1
	var i011: int = i001 + sy
	var i111: int = i011 + 1
	return Vector3(
		pu[i000] * w000 + pu[i100] * w100 + pu[i010] * w010 + pu[i110] * w110
			+ pu[i001] * w001 + pu[i101] * w101 + pu[i011] * w011 + pu[i111] * w111,
		pv[i000] * w000 + pv[i100] * w100 + pv[i010] * w010 + pv[i110] * w110
			+ pv[i001] * w001 + pv[i101] * w101 + pv[i011] * w011 + pv[i111] * w111,
		pw[i000] * w000 + pw[i100] * w100 + pw[i010] * w010 + pw[i110] * w110
			+ pw[i001] * w001 + pw[i101] * w101 + pw[i011] * w011 + pw[i111] * w111)


# Turbulence (|vorticity|, 1/s) at a point, nearest cell. Drives flutter and
# particle jitter: a leaf in the plume shivers, one in the dead zone hangs.
func turbulence_at(world_pos: Vector3) -> float:
	var snap: Array = snapshot()
	if nx == 0 or snap.size() < 4:
		return 0.0
	var pt: PackedFloat32Array = snap[3]
	var g: Vector3 = (world_pos - origin) / cell
	var x: int = clampi(int(g.x), 0, nx - 1)
	var y: int = clampi(int(g.y), 0, ny - 1)
	var z: int = clampi(int(g.z), 0, nz - 1)
	var i: int = x + nx * (y + ny * z)
	return pt[i] if i < pt.size() else 0.0


# Largest speed and mean speed over water cells in the published field.
func stats() -> Dictionary:
	var snap: Array = snapshot()
	var pu: PackedFloat32Array = snap[0]
	var pv: PackedFloat32Array = snap[1]
	var pw: PackedFloat32Array = snap[2]
	var mx: float = 0.0
	var sum: float = 0.0
	var n: int = 0
	for i in nx * ny * nz:
		if _solid[i] == 1:
			continue
		var s: float = sqrt(pu[i] * pu[i] + pv[i] * pv[i] + pw[i] * pw[i])
		mx = maxf(mx, s)
		sum += s
		n += 1
	return {"max": mx, "mean": sum / maxf(n, 1), "cells": n}


# Mean |divergence| over water cells after the last projection, as a share of
# mean speed per cell: the solver's own honesty check.
func residual_divergence() -> float:
	var sy: int = nx
	var sz: int = nx * ny
	var half_inv: float = 0.5 / cell
	var acc: float = 0.0
	var spd: float = 0.0
	for z in range(1, nz - 1):
		for y in range(1, ny - 1):
			for x in range(1, nx - 1):
				var i: int = x + y * sy + z * sz
				if _solid[i] == 1 or _src[i] != 0.0:
					continue
				var ue: float = _u[i + 1] if _solid[i + 1] == 0 else -_u[i]
				var uw: float = _u[i - 1] if _solid[i - 1] == 0 else -_u[i]
				var vn: float = _v[i + sy] if _solid[i + sy] == 0 else -_v[i]
				var vs: float = _v[i - sy] if _solid[i - sy] == 0 else -_v[i]
				var wf: float = _w[i + sz] if _solid[i + sz] == 0 else -_w[i]
				var wb: float = _w[i - sz] if _solid[i - sz] == 0 else -_w[i]
				acc += absf(((ue - uw) + (vn - vs) + (wf - wb)) * half_inv) * cell
				spd += sqrt(_u[i] * _u[i] + _v[i] * _v[i] + _w[i] * _w[i])
	return acc / maxf(spd, 1e-5)
