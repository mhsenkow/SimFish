# Batched microfauna swarm.
#
# Replaces the old per-creature `Microfauna` nodes — each a Node3D with several
# child MeshInstance3D pieces and its own per-frame `_process` — with ONE manager
# driving 3 MultiMesh instances (one per morph). ~100 plankton now cost a single
# `_process` (array math) + 3 draw calls instead of ~100 node ticks + hundreds of
# meshes, with the identical drift / bob / boundary / filter / lifespan behaviour
# and look (per-morph emissive material, per-instance colour, body bob + roll).
#
# Pure visual + light ecological hooks (filter intake), exactly as before.

# class_name intentionally omitted — world.gd preloads this as a const
# (`const MicrofaunaSwarm = preload(...)`) so the type resolves without depending
# on the global class-name cache being rescanned. Same pattern as FaunaVoxelBuilder.
extends Node3D

const SCALE_MIN: float = 0.020
const SCALE_MAX: float = 0.038
const DRIFT_SPEED: float = 0.06
const BOB_SPEED: float = 1.4
const BOB_AMP: float = 0.010
const REJITTER_MIN: float = 0.5
const REJITTER_MAX: float = 1.6
const LIFESPAN_S: float = 180.0
const FILTER_PULL_RADIUS: float = 0.6
const FILTER_PULL_STRENGTH: float = 0.55
const FILTER_CONSUME_DIST: float = 0.10
const STEP: float = 1.0 / 30.0
const MORPHS: int = 3
const INSTANCE_CAP: int = 320


class Plankton:
	var pos: Vector3 = Vector3.ZERO
	var drift: Vector3 = Vector3.ZERO
	var bob: float = 0.0
	var age: float = 0.0
	var life: float = 180.0
	var jitter_t: float = 0.0
	var scale: float = 0.03
	var morph: int = 0
	var color: Color = Color.WHITE
	var alive: bool = false
	var hop_t: float = 0.0
	var hop_cd: float = 0.0


var sim: Node = null
var presence: float = 1.0
var _target: int = 0
var _accum: float = 0.0
var _refill_t: float = 0.0
var _plankton: Array = []     # Array[Plankton] — dead slots are recycled
var _alive_count: int = 0
var _mm: Array = []           # Array[MultiMesh]
var _mmi: Array = []          # Array[MultiMeshInstance3D]
var MORPH_BODY: Array = [Color8(232, 228, 215), Color8(190, 215, 225), Color8(208, 226, 196)]
var MORPH_GLOW: Array = [Color8(200, 200, 180), Color8(150, 180, 200), Color8(176, 206, 160)]


func _ready() -> void:
	for m in MORPHS:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _bake_morph_mesh(m)
		mm.instance_count = INSTANCE_CAP
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _morph_material(m)
		# Generous AABB so the tiny instances aren't frustum-culled wholesale.
		mmi.custom_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
		add_child(mmi)
		_mm.append(mm)
		_mmi.append(mmi)


func set_target(n: int) -> void:
	_target = maxi(0, n)


func count() -> int:
	return _alive_count


# Immediately populate up to `n` plankton (startup base population).
func seed(n: int) -> void:
	for i in n:
		_spawn_one()


# Spawn a single plankton at an explicit world position. Public so the world's
# shape-aware sampler (and tests) can drive it; morph -1 = random.
func spawn_at(pos: Vector3, morph: int = -1) -> void:
	var p: Plankton = _free_slot()
	p.morph = (randi() % MORPHS) if morph < 0 else (morph % MORPHS)
	p.scale = randf_range(SCALE_MIN, SCALE_MAX)
	p.pos = pos
	p.bob = randf() * TAU
	p.age = randf_range(0.0, LIFESPAN_S * 0.6)
	p.life = LIFESPAN_S
	p.jitter_t = randf_range(REJITTER_MIN, REJITTER_MAX)
	p.drift = _seed_drift()
	p.color = (MORPH_BODY[p.morph] as Color).lerp(Color(randf(), randf(), randf()), 0.06)
	if not p.alive:
		p.alive = true
		_alive_count += 1


var _last_written_alive: int = -1


func _process(dt: float) -> void:
	if sim != null:
		dt *= sim.time_scale
	if dt <= 0.0:
		return
	dt = minf(dt, 0.08)
	_accum += dt
	var steps: int = 0
	while _accum >= STEP and steps < 3:
		_accum -= STEP
		_step(STEP)
		steps += 1
	_refill(dt)
	# Presence: plankton read slightly larger as the swarm fills (matches the
	# old set_swarm_presence(fill) behaviour) — computed here, no per-node calls.
	var fill: float = clampf(float(_alive_count) / maxf(1.0, float(_target)), 0.0, 1.0)
	presence = lerpf(1.0, 1.85, fill)
	if steps > 0 or _alive_count != _last_written_alive:
		_write_instances()
		_last_written_alive = _alive_count


func _step(dt: float) -> void:
	var w: Node = FaunaBoundary.world_from_sim(sim) if sim != null else null
	var intake: Vector3 = Vector3.ZERO
	var has_intake: bool = false
	if sim != null and sim.get("filter_intake_pos") != null:
		intake = sim.filter_intake_pos
		has_intake = intake != Vector3.ZERO
	# Phototaxis: real zooplankton rise toward light by day (and sink at night).
	# We bias drift gently upward during daylight so swarms gather in the lit
	# upper column / god-ray shafts, then disperse downward after dark.
	var daylight: float = 1.0
	if sim != null and sim.has_method("daylight"):
		daylight = float(sim.daylight())
	var photo_bias: float = (daylight - 0.45) * DRIFT_SPEED * 0.9
	for p: Plankton in _plankton:
		if not p.alive:
			continue
		p.age += dt
		if p.age >= p.life:
			_kill(p)
			continue
		p.hop_cd = maxf(0.0, p.hop_cd - dt)
		var flow_vel: Vector3 = Vector3.ZERO
		if w != null and w.has_method("sample_flow"):
			flow_vel = w.sample_flow(p.pos)
		var wake_push: Vector3 = Vector3.ZERO
		if w != null and w.has_method("wake_push_at"):
			wake_push = w.wake_push_at(p.pos)
			if wake_push.length_squared() > 0.002 and p.morph == 0 and p.hop_cd <= 0.0:
				p.hop_t = 0.14
				p.hop_cd = randf_range(0.8, 2.0)
				p.drift = wake_push.normalized() * 0.38 + Vector3(0.0, 0.12, 0.0)
		if p.hop_t > 0.0:
			p.hop_t = maxf(0.0, p.hop_t - dt)
			p.pos += p.drift * dt * 2.6
		elif p.morph == 0 and p.hop_cd <= 0.0 and randf() < dt * 0.07:
			p.hop_t = 0.11
			p.hop_cd = randf_range(1.4, 3.8)
			p.drift = Vector3(randf_range(-1, 1), randf_range(0.15, 0.55), randf_range(-1, 1)) \
				.normalized() * 0.40
		elif p.drift.length_squared() > 1e-6 and p.morph != 1:
			p.drift *= exp(-14.0 * dt)
			if p.drift.length_squared() < 0.0004:
				p.drift = Vector3.ZERO
		if p.drift.length_squared() > 1e-6 and p.hop_t <= 0.0:
			p.pos += p.drift * dt
		p.pos += flow_vel * dt * 0.32
		p.pos += wake_push * dt * 0.85
		p.pos.y += photo_bias * dt
		p.bob += dt * BOB_SPEED
		if p.morph == 1:
			var hop_phase: float = sin(p.bob * 1.25)
			if hop_phase > 0.55:
				p.pos.y += 0.042 * dt
			else:
				p.pos.y -= 0.026 * dt
		else:
			p.pos.y += sin(p.bob) * BOB_AMP * dt * 6.0
		if w != null:
			var margin: float = 0.22
			var steer: Vector3 = FaunaBoundary.lateral_push(w, p.pos, margin, 0.55, p.drift)
			steer += FaunaBoundary.vertical_push(w, p.pos, margin * 0.65, 0.38, 0.32, 0.45)
			if steer.length_squared() > 1e-6:
				p.drift += steer * dt * 2.2
				if p.drift.length_squared() > 1e-6:
					p.drift = p.drift.normalized() * DRIFT_SPEED \
						* clampf(p.drift.length() / DRIFT_SPEED, 0.5, 1.4)
		p.jitter_t -= dt
		if p.jitter_t <= 0.0:
			p.drift = _seed_drift()
			p.jitter_t = randf_range(REJITTER_MIN, REJITTER_MAX)
		if has_intake:
			var to_i: Vector3 = intake - p.pos
			var d2: float = to_i.length_squared()
			if d2 < FILTER_PULL_RADIUS * FILTER_PULL_RADIUS:
				if d2 < 1e-8:
					_kill(p)
					continue
				var d: float = sqrt(d2)
				var pull: float = FILTER_PULL_STRENGTH * (1.0 - d / FILTER_PULL_RADIUS) + 0.15
				p.pos += (to_i / d) * pull * dt
				if d < FILTER_CONSUME_DIST:
					_kill(p)
					continue
		if w != null:
			p.pos = FaunaBoundary.clamp_position(w, p.pos, 0.22, 0.04)
		if not p.pos.is_finite():
			_kill(p)


func _kill(p: Plankton) -> void:
	if p.alive:
		p.alive = false
		_alive_count -= 1


func _refill(dt: float) -> void:
	_refill_t = maxf(0.0, _refill_t - dt)
	if _refill_t > 0.0:
		return
	_refill_t = 0.8
	var deficit: int = _target - _alive_count
	if deficit <= 0:
		return
	# Cold start fills faster; steady-state trickles ~4/window like the old loop.
	var burst: int = 16 if _alive_count == 0 else 4
	for i in mini(deficit, burst):
		_spawn_one()


func _spawn_one() -> void:
	var world: Node = get_parent()
	if world == null or not world.has_method("_sample_point_in_tank"):
		return
	for _attempt in 8:
		var pt: Vector3 = world._sample_point_in_tank(
			float(world.SUBSTRATE_DEPTH) + 0.2, float(world.WATER_HEIGHT) - 0.3, 0.35)
		if world.is_inside_tank_volume(pt.x, pt.y, pt.z, 0.35):
			spawn_at(world.clamp_xyz_in_tank(pt, 0.35, 0.04))
			return


func _seed_drift() -> Vector3:
	var base := Vector3(randf_range(-1, 1), randf_range(-0.4, 0.4), randf_range(-1, 1))
	if base.length_squared() < 1e-6:
		base = Vector3(1.0, 0.0, 0.0)
	return base.normalized() * DRIFT_SPEED * randf_range(0.7, 1.3)


func _free_slot() -> Plankton:
	for p: Plankton in _plankton:
		if not p.alive:
			return p
	var np := Plankton.new()
	_plankton.append(np)
	return np


func _write_instances() -> void:
	var counters: Array = [0, 0, 0]
	for p: Plankton in _plankton:
		if not p.alive:
			continue
		var m: int = p.morph
		var idx: int = counters[m]
		if idx >= _mm[m].instance_count:
			_mm[m].instance_count = _mm[m].instance_count * 2
		if not p.pos.is_finite():
			continue
		var s: float = p.scale * presence
		var b := Basis().scaled(Vector3(s, s, s)).rotated(Vector3.UP, sin(p.bob * 0.6) * 0.30)
		var xform := Transform3D(b, p.pos)
		if not xform.is_finite():
			continue
		_mm[m].set_instance_transform(idx, xform)
		_mm[m].set_instance_color(idx, p.color)
		counters[m] = idx + 1
	for m in MORPHS:
		_mm[m].visible_instance_count = counters[m]


# Bake a morph's pieces (the same box layout the old Microfauna built) into one
# combined mesh at unit reference scale; per-plankton scale rides the instance
# transform. Geometry only — colour comes from the per-instance buffer.
func _bake_morph_mesh(morph: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s: float = 1.0
	_append_box(st, Vector3.ZERO, Vector3.ONE * s)  # core
	match morph:
		0:  # copepod: head nub + two antenna arms
			_append_box(st, Vector3(0, s * 0.15, -s * 0.48), Vector3(s * 0.65, s * 0.55, s * 0.45))
			for xs in [-1.0, 1.0]:
				_append_box(st, Vector3(xs * s * 0.32, s * 0.08, -s * 0.46),
					Vector3(s * 0.16, s * 0.12, s * 0.55))
		1:  # daphnia: side wings + tail
			for xs in [-1.0, 1.0]:
				_append_box(st, Vector3(xs * s * 0.42, 0, s * 0.02),
					Vector3(s * 0.25, s * 0.58, s * 0.72))
			_append_box(st, Vector3(0, -s * 0.08, s * 0.62), Vector3(s * 0.14, s * 0.12, s * 0.5))
		_:  # larval: segmented chain + side fins
			for i in 3:
				_append_box(st, Vector3(0, 0, -s * 0.16 + i * s * 0.34),
					Vector3(s * (0.78 - i * 0.16), s * (0.72 - i * 0.14), s * 0.46))
			for xs in [-1.0, 1.0]:
				_append_box(st, Vector3(xs * s * 0.30, 0, s * 0.28),
					Vector3(s * 0.13, s * 0.10, s * 0.42))
	return st.commit()


func _append_box(st: SurfaceTool, pos: Vector3, size: Vector3) -> void:
	st.append_from(VoxelMat.get_box(size), 0, Transform3D(Basis(), pos))


func _morph_material(m: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = MORPH_GLOW[m]
	mat.emission_energy_multiplier = 0.55
	return mat
