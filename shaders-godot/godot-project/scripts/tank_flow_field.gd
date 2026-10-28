# The tank's water current (#37, #48; REAL_TANK top-10 #4).
#
# This used to be its own little fake: an 8x4x8 grid that decayed every tick,
# re-seeded one jet and added sine "eddies", with no advection, no pressure and
# no obstacles, and a floor set to WATER_HEIGHT - SUBSTRATE_DEPTH so the grid
# only spanned the top 1.6 units of the water. Everything that reads the
# current - fish, shrimp, plants, floaters, waste, microfauna, algae, coral -
# already came through here, so the API stays and the water underneath it is
# now a real incompressible solve (WaterCurrent): plumes lift, filters
# circulate, rocks block, plant beds slow it, eddies persist.
#
# The solve runs on a WorkerThreadPool task. Readers on the main thread sample
# a snapshot taken when the last step finished, so sample() is lock-free and
# never sees a half-written field. Everything that changes the solver's inputs
# (impulses, solids, porosity, sources) is staged here on the main thread and
# handed over only while no task is running.
class_name TankFlowField
extends RefCounted

const WaterCurrentScript = preload("res://scripts/water_current.gd")

# Seconds of water time per solver step. 10 Hz is well under the timescale of
# anything visible in the current and keeps the worker at a few % of a core.
const STEP_INTERVAL: float = 0.1
# Longest stretch one step may cover (a stall, a fast-forward frame).
const MAX_STEP_DT: float = 0.12
# Impulse scale for deposit(): `strength` units of velocity change per call.
# Calls arrive per motion substep, so this is a small number.
const DEPOSIT_GAIN: float = 0.35

var _wc: WaterCurrent = null
var _threaded: bool = true
var _task_id: int = -1
var _accum: float = 0.0

# Main-thread snapshot of the last completed step.
var _su := PackedFloat32Array()
var _sv := PackedFloat32Array()
var _sw := PackedFloat32Array()
var _st := PackedFloat32Array()
var _nx: int = 0
var _ny: int = 0
var _nz: int = 0
var _cell: float = 1.0
var _origin: Vector3 = Vector3.ZERO
var _snapshot_serial: int = 0

# Staged inputs.
var _imp_u := PackedFloat32Array()
var _imp_v := PackedFloat32Array()
var _imp_w := PackedFloat32Array()
var _imp_any: bool = false
var _pending_solids := PackedByteArray()
var _pending_porosity := PackedFloat32Array()
var _sources: Array[Dictionary] = []
var _sources_dirty: bool = false

var _tex: ImageTexture3D = null


func _init() -> void:
	_wc = WaterCurrentScript.new()
	# Web builds without thread support run tasks inline; stepping directly is
	# the same work without the pool's bookkeeping.
	_threaded = OS.has_feature("threads") or not OS.has_feature("web")


# Build the water volume. `is_solid(world_pos) -> bool` marks substrate,
# hardscape and anything outside a curved tank.
func setup(half_w: float, half_d: float, floor_y: float, surface_y: float,
		is_solid: Callable = Callable(),
		max_cells: int = WaterCurrentScript.DEFAULT_MAX_CELLS) -> void:
	_wait()
	_wc.build(half_w, half_d, floor_y, surface_y, is_solid, max_cells)
	_nx = _wc.nx
	_ny = _wc.ny
	_nz = _wc.nz
	_cell = _wc.cell
	_origin = _wc.origin
	var n: int = _nx * _ny * _nz
	_imp_u = WaterCurrentScript._zeros(n)
	_imp_v = WaterCurrentScript._zeros(n)
	_imp_w = WaterCurrentScript._zeros(n)
	_imp_any = false
	_pending_solids = PackedByteArray()
	_pending_porosity = PackedFloat32Array()
	_take_snapshot()
	_sources_dirty = true


# Legacy entry point (smoke tests, old callers): an open box with one
# filter-like jet at `jet_origin` pointing along `jet_dir`.
func configure(half_w: float, half_d: float, floor_y: float, water_y: float,
		jet_origin: Vector3, jet_dir: Vector3, flow_rate: float) -> void:
	setup(half_w, half_d, floor_y, water_y)
	var dir: Vector3 = jet_dir.normalized() if jet_dir.length_squared() > 1e-6 \
		else Vector3(0.0, 0.0, 1.0)
	set_sources([{"kind": "jet", "outlet": jet_origin, "dir": dir,
		"speed": clampf(0.6 + flow_rate * 1.6, 0.4, 2.6)}])


# Equipment that drives the water. Each entry:
#   {"kind": "plume", "pos": Vector3, "buoyancy": float, "radius": float}
#   {"kind": "filter", "outlet": Vector3, "dir": Vector3, "speed": float,
#    "intake": Vector3, "flow": float}
#   {"kind": "jet", "outlet": Vector3, "dir": Vector3, "speed": float}
func set_sources(sources: Array) -> void:
	_sources.clear()
	for s in sources:
		if s is Dictionary:
			_sources.append(s)
	_sources_dirty = true


func set_solid_mask(mask: PackedByteArray) -> void:
	if mask.size() == _nx * _ny * _nz:
		_pending_solids = mask


func set_porosity(values: PackedFloat32Array) -> void:
	if values.size() == _nx * _ny * _nz:
		_pending_porosity = values


func is_threaded() -> bool:
	return _threaded


func set_threaded(on: bool) -> void:
	_wait()
	_threaded = on


func grid_dims() -> Vector3i:
	return Vector3i(_nx, _ny, _nz)


func grid_cell() -> float:
	return _cell


func grid_origin() -> Vector3:
	return _origin


func cell_center(x: int, y: int, z: int) -> Vector3:
	return _origin + Vector3((x + 0.5) * _cell, (y + 0.5) * _cell, (z + 0.5) * _cell)


func solver() -> WaterCurrent:
	return _wc


func snapshot_serial() -> int:
	return _snapshot_serial


func tick(dt: float) -> void:
	if _nx == 0:
		return
	_accum += maxf(dt, 0.0)
	if _task_id >= 0:
		if not WorkerThreadPool.is_task_completed(_task_id):
			return
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		_take_snapshot()
	if _accum < STEP_INTERVAL:
		return
	var step_dt: float = minf(_accum, MAX_STEP_DT)
	_accum = 0.0
	_hand_over_inputs()
	if _threaded:
		_task_id = WorkerThreadPool.add_task(_wc.step.bind(step_dt), false,
			"water_current")
	else:
		_wc.step(step_dt)
		_take_snapshot()


# Step synchronously `seconds` of water time - used once at build so a new
# tank opens with its circulation already established, not spinning up.
func prewarm(seconds: float, step_dt: float = 0.25) -> void:
	_wait()
	_hand_over_inputs()
	var t: float = 0.0
	while t < seconds:
		_wc.step_coarse(step_dt)
		t += step_dt
	_take_snapshot()


func _wait() -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


func _hand_over_inputs() -> void:
	if not _pending_solids.is_empty():
		_wc.replace_solids(_pending_solids)
		_pending_solids = PackedByteArray()
	if not _pending_porosity.is_empty():
		_wc.set_porosity(_pending_porosity)
		_pending_porosity = PackedFloat32Array()
	if _sources_dirty:
		_wc.clear_sources()
		for s in _sources:
			match String(s.get("kind", "")):
				"plume":
					_wc.add_plume(s["pos"], float(s.get("buoyancy", 1.5)),
						float(s.get("radius", 0.35)))
				"filter":
					_wc.add_filter(s["outlet"], s["dir"], float(s.get("speed", 1.5)),
						s["intake"], float(s.get("flow", 0.5)), float(s.get("width", 0.0)))
				"jet":
					_wc.add_filter(s["outlet"], s["dir"], float(s.get("speed", 1.5)),
						s["outlet"], 0.0)
		_sources_dirty = false
	if _imp_any:
		_wc.set_impulse_field(_imp_u, _imp_v, _imp_w)
		var n: int = _nx * _ny * _nz
		_imp_u = WaterCurrentScript._zeros(n)
		_imp_v = WaterCurrentScript._zeros(n)
		_imp_w = WaterCurrentScript._zeros(n)
		_imp_any = false


func _take_snapshot() -> void:
	var s: Array = _wc.snapshot()
	_su = s[0]
	_sv = s[1]
	_sw = s[2]
	_st = s[3]
	_snapshot_serial += 1


func sample(pos: Vector3) -> Vector3:
	if _nx == 0 or _su.size() < _nx * _ny * _nz:
		return Vector3.ZERO
	var gx: float = clampf((pos.x - _origin.x) / _cell - 0.5, 0.0, _nx - 1.001)
	var gy: float = clampf((pos.y - _origin.y) / _cell - 0.5, 0.0, _ny - 1.001)
	var gz: float = clampf((pos.z - _origin.z) / _cell - 0.5, 0.0, _nz - 1.001)
	var x0: int = int(gx)
	var y0: int = int(gy)
	var z0: int = int(gz)
	var fx: float = gx - x0
	var fy: float = gy - y0
	var fz: float = gz - z0
	var sy: int = _nx
	var sz: int = _nx * _ny
	var i0: int = x0 + y0 * sy + z0 * sz
	var i1: int = i0 + sz
	var a: float = (1.0 - fx) * (1.0 - fy)
	var b: float = fx * (1.0 - fy)
	var c: float = (1.0 - fx) * fy
	var d: float = fx * fy
	var gz0: float = 1.0 - fz
	var u: float = (_su[i0] * a + _su[i0 + 1] * b + _su[i0 + sy] * c + _su[i0 + sy + 1] * d) * gz0 \
		+ (_su[i1] * a + _su[i1 + 1] * b + _su[i1 + sy] * c + _su[i1 + sy + 1] * d) * fz
	var v: float = (_sv[i0] * a + _sv[i0 + 1] * b + _sv[i0 + sy] * c + _sv[i0 + sy + 1] * d) * gz0 \
		+ (_sv[i1] * a + _sv[i1 + 1] * b + _sv[i1 + sy] * c + _sv[i1 + sy + 1] * d) * fz
	var w: float = (_sw[i0] * a + _sw[i0 + 1] * b + _sw[i0 + sy] * c + _sw[i0 + sy + 1] * d) * gz0 \
		+ (_sw[i1] * a + _sw[i1 + 1] * b + _sw[i1 + sy] * c + _sw[i1 + sy + 1] * d) * fz
	return Vector3(u, v, w)


# |vorticity| (1/s) at the nearest cell: how churned the water is here.
func turbulence_at(pos: Vector3) -> float:
	if _nx == 0 or _st.size() < _nx * _ny * _nz:
		return 0.0
	var x: int = clampi(int((pos.x - _origin.x) / _cell), 0, _nx - 1)
	var y: int = clampi(int((pos.y - _origin.y) / _cell), 0, _ny - 1)
	var z: int = clampi(int((pos.z - _origin.z) / _cell), 0, _nz - 1)
	return _st[x + _nx * (y + _ny * z)]


func strength_at(pos: Vector3) -> float:
	return sample(pos).length()


# Push the water at `pos` along `vel`. Trilinear splat into the staged
# impulse buffer; the solver takes it at the next step.
func deposit(pos: Vector3, vel: Vector3, strength: float) -> void:
	if _nx == 0 or vel.length_squared() < 1e-8 or strength <= 0.0:
		return
	_splat(pos, vel.normalized() * strength * DEPOSIT_GAIN)


# A swimming body's wake: thrust pushes water back off the tail while the
# body drags a little forward along its flank. Net momentum is near zero, as
# it is for a real fish at steady speed, so a wake stirs a local eddy instead
# of accelerating the whole tank.
func deposit_wake(pos: Vector3, swim_vel: Vector3, body_size: float) -> void:
	if _nx == 0:
		return
	var spd: float = swim_vel.length()
	if spd < 0.05:
		return
	var dir: Vector3 = swim_vel / spd
	var k: float = clampf(body_size, 0.05, 1.5) * minf(spd, 3.0) * 0.0025
	var tail: Vector3 = pos - dir * maxf(body_size * 0.9, 0.12)
	_splat(tail, -dir * k)
	_splat(pos + dir * maxf(body_size * 0.4, 0.06), dir * k)


func _splat(pos: Vector3, dv: Vector3) -> void:
	var gx: float = (pos.x - _origin.x) / _cell - 0.5
	var gy: float = (pos.y - _origin.y) / _cell - 0.5
	var gz: float = (pos.z - _origin.z) / _cell - 0.5
	if gx < -1.0 or gy < -1.0 or gz < -1.0 or gx > _nx or gy > _ny or gz > _nz:
		return
	var x0: int = int(floor(gx))
	var y0: int = int(floor(gy))
	var z0: int = int(floor(gz))
	var fx: float = gx - x0
	var fy: float = gy - y0
	var fz: float = gz - z0
	for dz in 2:
		var zz: int = z0 + dz
		if zz < 0 or zz >= _nz:
			continue
		var wz: float = fz if dz == 1 else 1.0 - fz
		for dy in 2:
			var yy: int = y0 + dy
			if yy < 0 or yy >= _ny:
				continue
			var wy: float = (fy if dy == 1 else 1.0 - fy) * wz
			for dx in 2:
				var xx: int = x0 + dx
				if xx < 0 or xx >= _nx:
					continue
				var wgt: float = (fx if dx == 1 else 1.0 - fx) * wy
				var i: int = xx + _nx * (yy + _ny * zz)
				_imp_u[i] += dv.x * wgt
				_imp_v[i] += dv.y * wgt
				_imp_w[i] += dv.z * wgt
	_imp_any = true


func wake_push_at(pos: Vector3) -> Vector3:
	return sample(pos) * 0.55


# How much of a swimmer's effort the water ahead gives back: drafting in a
# school, or riding a current the way it is already going.
func draft_bonus(pos: Vector3, heading: Vector3) -> float:
	var flow: Vector3 = sample(pos)
	if flow.length_squared() < 1e-6:
		return 0.0
	var aligned: float = flow.normalized().dot(heading)
	return clampf(aligned * flow.length() * 2.2, 0.0, 0.35)


# Kept for MotionField's daily convection call. Thermal convection is now a
# source like any other (the heater plume), so the day only nudges its
# strength: a warm lit room weakens the overturn, a cooling night strengthens it.
func tick_convection(_dt: float, daylight: float) -> void:
	var changed: bool = false
	for s in _sources:
		if String(s.get("kind", "")) == "plume" and bool(s.get("thermal", false)):
			var base: float = float(s.get("base_buoyancy", s.get("buoyancy", 0.2)))
			s["base_buoyancy"] = base
			var want: float = base * lerpf(1.25, 0.85, clampf(daylight, 0.0, 1.0))
			if absf(want - float(s.get("buoyancy", 0.0))) > 0.01:
				s["buoyancy"] = want
				changed = true
	if changed:
		_sources_dirty = true


# ---- the field as a shader texture ----------------------------------------
#
# RGB = velocity (units/s), A = turbulence (|vorticity|, 1/s), half floats.
# One texel per cell; shaders map world -> uvw with iaq_flow_box / iaq_flow_dims.
func texture() -> ImageTexture3D:
	if _nx == 0:
		return null
	var images: Array[Image] = []
	var slice := PackedFloat32Array()
	slice.resize(_nx * _ny * 4)
	for z in _nz:
		var k: int = 0
		for y in _ny:
			for x in _nx:
				var i: int = x + _nx * (y + _ny * z)
				slice[k] = _su[i]
				slice[k + 1] = _sv[i]
				slice[k + 2] = _sw[i]
				slice[k + 3] = _st[i]
				k += 4
		# Half floats: linear filtering of 32-bit float textures is optional
		# on mobile GPUs, of 16-bit ones it is not.
		var img: Image = Image.create_from_data(_nx, _ny, false, Image.FORMAT_RGBAF,
			slice.to_byte_array())
		img.convert(Image.FORMAT_RGBAH)
		images.append(img)
	if _tex == null or _tex.get_width() != _nx or _tex.get_height() != _ny \
			or _tex.get_depth() != _nz:
		_tex = ImageTexture3D.new()
		_tex.create(Image.FORMAT_RGBAH, _nx, _ny, _nz, false, images)
	else:
		_tex.update(images)
	return _tex
