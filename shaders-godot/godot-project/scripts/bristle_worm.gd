# Bristle worm — pale secretive substrate detritivore.
#
# Distinct from:
#   - wriggle_worm.gd (brown, lives in mulm carpet, visible all day)
#   - tubifex_patch.gd (red, clusters in high-ammonia zones)
#
# Bristle worms are pale tan/cream colored, hide in substrate during the
# day with only a brief tail end showing, and emerge fully at night to
# crawl and feed on decaying matter. Their long thin segmented body has
# visible white bristles along the flanks.
#
# Ecological role: cleaning crew for decaying organic matter that other
# detritivores miss (large food chunks, dead-fish remnants, plant decay).
# They speed up the substrate carbon turnover.

class_name BristleWorm
extends Node3D


const VOXEL_SIZE: float = 0.045
const BODY_SEGMENTS: int = 5
const WRIGGLE_FREQ: float = 4.5
const WRIGGLE_AMP: float = 0.32
const SURFACE_SPEED: float = 0.06
const HIDE_DEPTH: float = 0.22       # how far below substrate top when hiding
const SHOW_DEPTH: float = 0.02       # just above substrate when emerged
const LIFESPAN_S: float = 280.0


var sim: Node = null
var substrate_top_y: float = 0.0
var _age: float = 0.0
var _phase: float = 0.0
var _segments: Array[MeshInstance3D] = []
var _bristles: Array[MeshInstance3D] = []
var _drift: Vector3 = Vector3.ZERO
var _jitter_t: float = 0.0
var _emerged_t: float = 0.0
# Bristle worms are nocturnal — emerged_target = 1 at night, 0 during day.
# We lerp the actual depth toward this so the surfacing reads as a slow
# rise, not a teleport.


func _ready() -> void:
	# Long thin body — 5 stacked thin voxels with slight Z separation
	# so the wriggle wave reads visibly along the length.
	var body_col := Color8(220, 200, 170)
	var bristle_col := Color8(245, 235, 210)
	for i in BODY_SEGMENTS:
		var t: float = float(i) / float(maxi(1, BODY_SEGMENTS - 1))
		# Taper from head to tail.
		var thickness: float = lerpf(VOXEL_SIZE * 0.8, VOXEL_SIZE * 0.45, t)
		var mi := MeshInstance3D.new()
		mi.mesh = VoxelMat.get_box(Vector3(thickness, thickness, VOXEL_SIZE * 0.6))
		mi.material_override = VoxelMat.make_fauna(body_col)
		mi.position = Vector3(0.0, 0.0, VOXEL_SIZE * 0.6 * float(i))
		add_child(mi)
		_segments.append(mi)
		# Bristles on the middle 3 segments only — head + tail are clean.
		if i > 0 and i < BODY_SEGMENTS - 1:
			for side in [-1.0, 1.0]:
				var br := MeshInstance3D.new()
				br.mesh = VoxelMat.get_box(Vector3(
					VOXEL_SIZE * 0.15, VOXEL_SIZE * 0.15, VOXEL_SIZE * 0.3))
				br.material_override = VoxelMat.make_fauna(bristle_col)
				br.position = Vector3(side * thickness * 0.6, 0.0,
					VOXEL_SIZE * 0.6 * float(i))
				add_child(br)
				_bristles.append(br)
	_phase = randf() * TAU
	_jitter_t = randf_range(2.0, 5.0)
	_drift = Vector3(
		randf_range(-SURFACE_SPEED, SURFACE_SPEED),
		0.0,
		randf_range(-SURFACE_SPEED, SURFACE_SPEED))
	# Start hidden — most bristle worms are buried at any given moment.
	position.y = substrate_top_y - HIDE_DEPTH


func _process(dt: float) -> void:
	var sdt: float = dt
	if sim != null:
		sdt *= float(sim.time_scale)
		if sdt <= 0.0:
			return
	_age += sdt
	if _age >= LIFESPAN_S:
		queue_free()
		return
	_phase += sdt * WRIGGLE_FREQ

	# Day/night gate. Real bristle worms come out at dusk + retreat by
	# dawn. We lerp the emerged amount so the rise is gradual.
	var dl: float = 1.0
	if sim != null and sim.has_method("daylight"):
		dl = float(sim.daylight())
	var emerged_target: float = clampf((0.30 - dl) / 0.30, 0.0, 1.0)
	_emerged_t = lerpf(_emerged_t, emerged_target, sdt * 0.35)
	var target_depth: float = lerpf(-HIDE_DEPTH, SHOW_DEPTH, _emerged_t)
	position.y = lerpf(position.y, substrate_top_y + target_depth, sdt * 0.6)

	# Wriggle the body — each segment offsets laterally based on its
	# index, producing the classic worm wave.
	for i in _segments.size():
		var seg: MeshInstance3D = _segments[i]
		if seg == null or not is_instance_valid(seg):
			continue
		var ph: float = _phase + float(i) * 0.55
		seg.position.x = sin(ph) * WRIGGLE_AMP * VOXEL_SIZE

	# Drift across substrate only while mostly emerged. Slow + random.
	if _emerged_t > 0.5:
		position.x += _drift.x * sdt
		position.z += _drift.z * sdt
	_jitter_t -= sdt
	if _jitter_t <= 0.0:
		_jitter_t = randf_range(2.0, 5.0)
		_drift = Vector3(
			randf_range(-SURFACE_SPEED, SURFACE_SPEED),
			0.0,
			randf_range(-SURFACE_SPEED, SURFACE_SPEED))

	# Detritivore work — eat passing waste when emerged + near the
	# substrate. Same shape as snail.gd's consumption.
	if _emerged_t > 0.4 and sim != null and randf() < sdt * 0.15:
		var best: Node3D = null
		var best_d2: float = 0.5 * 0.5
		for w in sim.waste:
			if w == null or not is_instance_valid(w):
				continue
			var d2: float = (w.global_position - global_position).length_squared()
			if d2 < best_d2:
				best_d2 = d2
				best = w
		if best != null:
			sim.waste.erase(best)
			best.queue_free()


func to_save_dict() -> Dictionary:
	return {
		"pos": SaveHelpers.vec3_to_array(global_position),
		"age": _age,
	}


func apply_save_dict(d: Dictionary) -> void:
	_age = float(d.get("age", 0.0))
