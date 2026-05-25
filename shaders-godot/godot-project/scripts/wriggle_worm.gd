# Wriggle worm — tiny detrital worm visible squirming in mulm patches.
#
# Spawned by world.gd's mulm-maintenance pass at random mulm-voxel
# positions, capped at ~half the mulm count. Pure visual proof that
# the detritivore loop is alive — real Walstad tanks always have a
# carpet of small worms working the mulm, and seeing them sells the
# "this is a working ecosystem" feel.
#
# Each worm is two stacked thin voxels (head + body) that oscillate
# laterally with a phase offset, producing a wave-like wriggle. Worms
# slowly drift along the substrate within a small home range so the
# carpet animation reads as movement, not just twitch-in-place. They
# despawn after WORM_LIFESPAN_S so the population turns over with the
# mulm carpet.

class_name WriggleWorm
extends Node3D


const WORM_LIFESPAN_S: float = 90.0
const WRIGGLE_FREQ: float = 6.0
const WRIGGLE_AMP: float = 0.022
const DRIFT_SPEED: float = 0.045
const HOME_RADIUS: float = 0.45


var sim: Node = null
var substrate_top_y: float = 0.0
var _age: float = 0.0
var _phase: float = 0.0
var _home: Vector3 = Vector3.ZERO
var _drift: Vector3 = Vector3.ZERO
var _next_jitter_t: float = 0.0
var _head: MeshInstance3D = null
var _body: MeshInstance3D = null


func _ready() -> void:
	_phase = randf() * TAU
	_home = position
	_seed_drift()
	_next_jitter_t = randf_range(1.2, 3.0)
	# Two segments: a slightly darker head + a body. Both very thin voxels.
	# The head leads with the phase wave; the body trails by ~PI/2 to
	# produce a visible undulation.
	var v: float = 0.045
	_head = _make_seg(Vector3(v * 0.9, v * 0.7, v * 0.45), Color8(95, 70, 50))
	_head.position = Vector3(0, v * 0.35, 0)
	add_child(_head)
	_body = _make_seg(Vector3(v * 0.7, v * 0.6, v * 0.85), Color8(115, 85, 60))
	_body.position = Vector3(0, v * 0.2, v * 0.5)
	add_child(_body)


func _make_seg(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	return mi


func _seed_drift() -> void:
	# Drift only along the substrate plane (worms don't swim up).
	_drift = Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized() \
		* DRIFT_SPEED * randf_range(0.6, 1.2)


func _process(dt: float) -> void:
	if sim != null:
		dt *= sim.time_scale
		if dt <= 0.0:
			return
	dt = minf(dt, 0.08)
	_age += dt
	if _age >= WORM_LIFESPAN_S:
		queue_free()
		return

	_phase += dt * WRIGGLE_FREQ

	# Slow drift, biased to stay within HOME_RADIUS of the spawn point —
	# worms wander a bit but don't wander off the mulm patch they
	# represent. Without the home pull the carpet would visibly drift
	# off-center over a few minutes.
	position += _drift * dt
	var to_home: Vector3 = _home - position
	to_home.y = 0.0
	if to_home.length() > HOME_RADIUS:
		position += to_home.normalized() * (DRIFT_SPEED * 0.5) * dt

	# Pin to substrate. Y stays just above substrate_top_y so the worm
	# crawls on the surface rather than burying.
	position.y = substrate_top_y + 0.025

	_next_jitter_t -= dt
	if _next_jitter_t <= 0.0:
		_seed_drift()
		_next_jitter_t = randf_range(1.2, 3.0)

	# Wriggle the segments laterally with a phase offset. Real worm
	# undulation is a head-leading wave; we approximate with two
	# segments to keep the cost trivial.
	if _head != null:
		_head.position.x = sin(_phase) * WRIGGLE_AMP
	if _body != null:
		_body.position.x = sin(_phase - PI * 0.5) * WRIGGLE_AMP
