# Microfauna — copepods / daphnia / tiny crustaceans drifting in the water
# column. Pure decoration with light ecological hooks:
#
#  - About 80–150 individuals at any time, maintained by world.gd's refill
#    loop so the swarm doesn't fade out over a long session.
#  - Each one wanders with re-jittered Brownian-ish drift + a slow vertical
#    bob. Faint emission so they read as tiny living dots against the
#    dark water rather than getting eaten by the palette.
#  - Lifespan ~3 sim minutes — they "live and die" so the swarm constantly
#    refreshes its composition.
#  - Filter intake: if sim.filter_intake_pos is set and a microfauna drifts
#    within FILTER_PULL_RADIUS, it accelerates toward the intake and is
#    "filtered out" on arrival. Closes the visible loop "tiny life → filter".
#
# Performance: each one is a single MeshInstance3D with a shared StandardMaterial3D
# (created in _ready). 100 of them at the default render rate is cheap
# relative to fish (which build dozens of voxels each).

class_name Microfauna
extends Node3D


const SCALE_MIN: float = 0.020
const SCALE_MAX: float = 0.038
const DRIFT_SPEED: float = 0.06
const BOB_SPEED: float = 1.4
const BOB_AMP: float = 0.010
const REJITTER_INTERVAL_MIN: float = 0.5
const REJITTER_INTERVAL_MAX: float = 1.6
const LIFESPAN_S: float = 180.0
const FILTER_PULL_RADIUS: float = 0.6
const FILTER_PULL_STRENGTH: float = 0.55  # m/s toward intake
const FILTER_CONSUME_DIST: float = 0.10


var sim: Node = null
var _age: float = 0.0
var _drift: Vector3 = Vector3.ZERO
var _next_jitter_t: float = 0.0
var _bob_phase: float = 0.0


func _ready() -> void:
	_bob_phase = randf() * TAU
	_next_jitter_t = randf_range(REJITTER_INTERVAL_MIN, REJITTER_INTERVAL_MAX)
	_seed_drift()
	# Two visual variants jittered randomly: small whitish copepods, larger
	# pale-blue daphnia. The size + tint pick is per-instance, not per-class,
	# so the swarm reads as biodiverse without a second entity type.
	var scale_v: float = randf_range(SCALE_MIN, SCALE_MAX)
	var is_daphnia: bool = randf() < 0.35
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * scale_v
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	if is_daphnia:
		mat.albedo_color = Color8(190, 215, 225)
		mat.emission = Color8(150, 180, 200)
	else:
		mat.albedo_color = Color8(232, 228, 215)
		mat.emission = Color8(200, 200, 180)
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 0.35
	# Unshaded so the palette quantize pass picks them up cleanly; they're
	# too small for shading detail to read anyway.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	add_child(mi)


func _seed_drift() -> void:
	_drift = Vector3(
		randf_range(-1, 1),
		randf_range(-0.4, 0.4),
		randf_range(-1, 1),
	).normalized() * DRIFT_SPEED * randf_range(0.7, 1.3)


func _process(dt: float) -> void:
	if sim != null:
		dt *= sim.time_scale
		if dt <= 0.0:
			return
	# Cap to keep integration stable at high time_scale (same reason
	# fish + shrimp do this).
	dt = minf(dt, 0.08)
	_age += dt
	# Lifespan — fade-out is just the natural endpoint. We don't drop
	# waste because microfauna biomass is too small to bother modeling
	# and the death is supposed to feel quiet.
	if _age >= LIFESPAN_S:
		queue_free()
		return

	# Drift + bob + occasional re-jitter to keep paths from feeling rail-
	# locked. Real copepods do exactly this: brief swims punctuated by hops.
	position += _drift * dt
	_bob_phase += dt * BOB_SPEED
	position.y += sin(_bob_phase) * BOB_AMP * dt * 6.0  # gentle vertical sway
	_next_jitter_t -= dt
	if _next_jitter_t <= 0.0:
		_seed_drift()
		_next_jitter_t = randf_range(REJITTER_INTERVAL_MIN, REJITTER_INTERVAL_MAX)

	# Filter intake pull. Once close, accelerate toward the intake and
	# despawn on contact — the visible "tiny life sucked into the filter"
	# loop that filtration tanks always have.
	if sim != null and sim.get("filter_intake_pos") != null:
		var intake: Vector3 = sim.filter_intake_pos
		if intake != Vector3.ZERO:
			var to_intake: Vector3 = intake - position
			var d2: float = to_intake.length_squared()
			if d2 < FILTER_PULL_RADIUS * FILTER_PULL_RADIUS:
				var dir: Vector3 = to_intake.normalized()
				# Pull strength ramps as we approach so the suck-in reads
				# as accelerating, not constant-speed.
				var d: float = sqrt(d2)
				var pull: float = FILTER_PULL_STRENGTH * (1.0 - d / FILTER_PULL_RADIUS) + 0.15
				position += dir * pull * dt
				if d < FILTER_CONSUME_DIST:
					queue_free()
					return

	# Stay inside the water column AABB. Microfauna in glass / substrate
	# look glitchy, so we clamp rather than letting drift escape.
	if sim != null:
		var b: AABB = sim.world_bounds
		position.x = clampf(position.x, b.position.x, b.position.x + b.size.x)
		position.y = clampf(position.y, b.position.y, b.position.y + b.size.y)
		position.z = clampf(position.z, b.position.z, b.position.z + b.size.z)
