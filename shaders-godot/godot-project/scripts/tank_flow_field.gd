# Coarse 3D velocity grid for tank-wide water motion (#37, #48).
# Seeded by aeration; creatures sample (#38) and deposit wakes (#39).
class_name TankFlowField
extends RefCounted

const GRID_X: int = 8
const GRID_Y: int = 4
const GRID_Z: int = 8

var _origin: Vector3 = Vector3.ZERO
var _size: Vector3 = Vector3.ONE
var _vel: Array[Vector3] = []
var _jet_origin: Vector3 = Vector3.ZERO
var _jet_dir: Vector3 = Vector3(0.0, 0.0, 1.0)
var _jet_strength: float = 0.12
var _phase: float = 0.0


func _init() -> void:
	_vel.resize(GRID_X * GRID_Y * GRID_Z)
	for i in _vel.size():
		_vel[i] = Vector3.ZERO


func configure(half_w: float, half_d: float, floor_y: float, water_y: float,
		jet_origin: Vector3, jet_dir: Vector3, flow_rate: float) -> void:
	_origin = Vector3(-half_w, floor_y, -half_d)
	_size = Vector3(half_w * 2.0, maxf(water_y - floor_y, 0.5), half_d * 2.0)
	_jet_origin = jet_origin
	if jet_dir.length_squared() > 1e-6:
		_jet_dir = jet_dir.normalized()
	else:
		_jet_dir = Vector3(0.0, 0.0, 1.0)
	_jet_strength = clampf(0.10 + flow_rate * 0.20, 0.06, 0.52)


func tick(dt: float) -> void:
	_phase += dt
	var decay: float = exp(-2.1 * dt)
	for i in _vel.size():
		_vel[i] *= decay
	_seed_jet(dt)
	_add_eddies(dt)


func sample(pos: Vector3) -> Vector3:
	if _size.x < 0.01 or _size.y < 0.01 or _size.z < 0.01:
		return Vector3.ZERO
	var rel: Vector3 = (pos - _origin) / _size
	rel.x = clampf(rel.x, 0.0, 1.0)
	rel.y = clampf(rel.y, 0.0, 1.0)
	rel.z = clampf(rel.z, 0.0, 1.0)
	var fx: float = rel.x * float(GRID_X - 1)
	var fy: float = rel.y * float(GRID_Y - 1)
	var fz: float = rel.z * float(GRID_Z - 1)
	var x0: int = int(floorf(fx))
	var y0: int = int(floorf(fy))
	var z0: int = int(floorf(fz))
	var x1: int = mini(x0 + 1, GRID_X - 1)
	var y1: int = mini(y0 + 1, GRID_Y - 1)
	var z1: int = mini(z0 + 1, GRID_Z - 1)
	var tx: float = fx - float(x0)
	var ty: float = fy - float(y0)
	var tz: float = fz - float(z0)
	var c000: Vector3 = _at(x0, y0, z0)
	var c100: Vector3 = _at(x1, y0, z0)
	var c010: Vector3 = _at(x0, y1, z0)
	var c110: Vector3 = _at(x1, y1, z0)
	var c001: Vector3 = _at(x0, y0, z1)
	var c101: Vector3 = _at(x1, y0, z1)
	var c011: Vector3 = _at(x0, y1, z1)
	var c111: Vector3 = _at(x1, y1, z1)
	var c00: Vector3 = c000.lerp(c100, tx)
	var c10: Vector3 = c010.lerp(c110, tx)
	var c01: Vector3 = c001.lerp(c101, tx)
	var c11: Vector3 = c011.lerp(c111, tx)
	var c0: Vector3 = c00.lerp(c10, ty)
	var c1: Vector3 = c01.lerp(c11, ty)
	return c0.lerp(c1, tz)


func strength_at(pos: Vector3) -> float:
	return sample(pos).length()


func deposit(pos: Vector3, vel: Vector3, strength: float) -> void:
	if vel.length_squared() < 1e-8 or strength <= 0.0:
		return
	var rel: Vector3 = (pos - _origin) / _size
	if rel.x < -0.05 or rel.x > 1.05 or rel.y < -0.05 or rel.y > 1.05 or rel.z < -0.05 or rel.z > 1.05:
		return
	var cx: int = clampi(int(rel.x * float(GRID_X)), 0, GRID_X - 1)
	var cy: int = clampi(int(rel.y * float(GRID_Y)), 0, GRID_Y - 1)
	var cz: int = clampi(int(rel.z * float(GRID_Z)), 0, GRID_Z - 1)
	var push: Vector3 = vel.normalized() * strength
	for dz in range(-1, 2):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var ix: int = clampi(cx + dx, 0, GRID_X - 1)
				var iy: int = clampi(cy + dy, 0, GRID_Y - 1)
				var iz: int = clampi(cz + dz, 0, GRID_Z - 1)
				var falloff: float = 1.0 / (1.0 + float(dx * dx + dy * dy + dz * dz))
				_at_set(ix, iy, iz, _at(ix, iy, iz) + push * falloff)


func wake_push_at(pos: Vector3) -> Vector3:
	return sample(pos) * 0.55


func draft_bonus(pos: Vector3, heading: Vector3) -> float:
	var flow: Vector3 = sample(pos)
	if flow.length_squared() < 1e-6:
		return 0.0
	var aligned: float = flow.normalized().dot(heading)
	return clampf(aligned * flow.length() * 2.2, 0.0, 0.35)


func _seed_jet(dt: float) -> void:
	var rel: Vector3 = (_jet_origin - _origin) / _size
	var cx: int = clampi(int(rel.x * float(GRID_X)), 0, GRID_X - 1)
	var cy: int = clampi(int(rel.y * float(GRID_Y)), 0, GRID_Y - 1)
	var cz: int = clampi(int(rel.z * float(GRID_Z)), 0, GRID_Z - 1)
	var push: Vector3 = _jet_dir * (_jet_strength * dt * 14.0)
	for dz in range(-1, 2):
		for dy in range(0, 2):
			for dx in range(-1, 2):
				var ix: int = clampi(cx + dx, 0, GRID_X - 1)
				var iy: int = clampi(cy + dy, 0, GRID_Y - 1)
				var iz: int = clampi(cz + dz, 0, GRID_Z - 1)
				var falloff: float = 1.0 / (1.0 + float(dx * dx + dz * dz) * 0.35)
				_at_set(ix, iy, iz, _at(ix, iy, iz) + push * falloff)


func _add_eddies(dt: float) -> void:
	for z in GRID_Z:
		for y in GRID_Y:
			for x in GRID_X:
				var p: Vector3 = _origin + Vector3(
					(float(x) + 0.5) / float(GRID_X) * _size.x,
					(float(y) + 0.5) / float(GRID_Y) * _size.y,
					(float(z) + 0.5) / float(GRID_Z) * _size.z)
				var swirl: Vector3 = Vector3(
					sin(_phase * 0.35 + p.z * 0.4),
					0.0,
					cos(_phase * 0.28 - p.x * 0.35))
				var corner_slack: float = 1.0 - clampf(
					(absf(p.x) / maxf(_size.x * 0.5, 0.1)) * 0.35
					+ (absf(p.z) / maxf(_size.z * 0.5, 0.1)) * 0.35, 0.0, 0.65)
				_at_set(x, y, z, _at(x, y, z) + swirl * dt * 0.012 * corner_slack)


func _idx(x: int, y: int, z: int) -> int:
	return x + GRID_X * (y + GRID_Y * z)


func _at(x: int, y: int, z: int) -> Vector3:
	return _vel[_idx(x, y, z)]


func _at_set(x: int, y: int, z: int, v: Vector3) -> void:
	_vel[_idx(x, y, z)] = v


func tick_convection(dt: float, daylight: float) -> void:
	var rise: Vector3 = Vector3(0.0, 0.08 + daylight * 0.06, 0.0)
	var drift: Vector3 = Vector3(sin(_phase * 0.18), 0.0, cos(_phase * 0.18)) * 0.05
	var night_flip: float = lerpf(-1.0, 1.0, daylight)
	for z in GRID_Z:
		for y in GRID_Y:
			for x in GRID_X:
				var mix: Vector3 = rise * (float(y) / float(GRID_Y)) + drift * night_flip
				_at_set(x, y, z, _at(x, y, z) + mix * dt * 0.35)
