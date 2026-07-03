class_name WastePhysicsBatch
extends RefCounted

# PERFORMANCE_UNTHROTTLED #61 — packed drift/fall integration for unsettled waste.

const FALL_SPEED: float = 0.38
const MAX_BATCH: int = 240

static var _pos: PackedVector3Array = PackedVector3Array()
static var _life: PackedFloat32Array = PackedFloat32Array()
static var _map: Array[WasteParticle] = []


static func reset_for_test() -> void:
	_pos = PackedVector3Array()
	_life = PackedFloat32Array()
	_map.clear()


static func integrate(waste: Array, dt: float, sim: Node, substrate_top_y: float) -> void:
	if waste.is_empty() or dt <= 0.0:
		return
	var w: Node = sim.get_parent() if sim != null else null
	var intake: Vector3 = Vector3.ZERO
	var have_intake: bool = false
	if sim != null and sim.get("filter_intake_pos") != null:
		intake = sim.filter_intake_pos
		have_intake = true
	var flow_fn: Callable
	if w != null and w.has_method("sample_flow"):
		flow_fn = Callable(w, "sample_flow")
	var floor_fn: Callable
	if w != null and w.has_method("column_surface_y"):
		floor_fn = Callable(w, "column_surface_y")
	_pos.clear()
	_life.clear()
	_map.clear()
	for particle in waste:
		if not is_instance_valid(particle) or particle.settled:
			continue
		if particle.kind == 3:  # KIND_FOOD
			continue
		if _map.size() >= MAX_BATCH:
			break
		_map.append(particle)
		_pos.append(particle.position)
		_life.append(particle._life)
	var n: int = _map.size()
	if n == 0:
		return
	for i in n:
		var p: Vector3 = _pos[i]
		var life: float = _life[i]
		var floor_y: float = substrate_top_y
		if floor_fn.is_valid():
			floor_y = float(floor_fn.call(p.x, p.z))
		p.y -= FALL_SPEED * dt
		var swirl_t: float = life * 1.1
		var swirl := Vector2(
			sin(swirl_t + p.z * 0.55) * 0.085,
			cos(swirl_t * 0.83 - p.x * 0.55) * 0.085)
		var wander := Vector2(
			sin(life * 2.3 + p.x * 0.4) * 0.04,
			sin(life * 1.9 + p.z * 0.4 + 1.3) * 0.04)
		p.x += (swirl.x + wander.x) * dt
		p.z += (swirl.y + wander.y) * dt
		if have_intake:
			var dx: float = intake.x - p.x
			var dz: float = intake.z - p.z
			var d2: float = dx * dx + dz * dz
			var pull: float = 0.18 / (1.0 + d2 * 0.6)
			p.x += dx * pull * dt
			p.z += dz * pull * dt
		if flow_fn.is_valid():
			var flow: Vector3 = flow_fn.call(Vector3(p.x, p.y, p.z))
			p += flow * dt * 0.48
		if p.y <= floor_y + _map[i].voxel_size * 0.5:
			p.y = floor_y + _map[i].voxel_size * 0.5
			_map[i].settled = true
		_pos[i] = p
		_map[i].position = p
		_map[i]._interp_to = p
