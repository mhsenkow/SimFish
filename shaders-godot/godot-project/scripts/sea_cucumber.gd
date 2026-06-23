# Sea cucumber — slow saltwater floor-sifter.
#
# Holothurian invertebrate that crawls the sand bed at glacial speed,
# eats substrate detritus through one end, and excretes oxygenating
# pellets through the other. The clean-up crew member that's actually
# essential in a reef tank — they prevent the sand bed from going
# anaerobic by constantly turning it over.
#
# Visual: a fat tube of segmented voxels with a tuft of feeding
# tentacles at the head end. Mostly browns + warm tans with darker
# tubercles down the back. Moves about half the speed of a snail.

class_name SeaCucumber
extends Node3D


const SEGMENT_COUNT: int = 6
const VOXEL_SIZE: float = 0.09
const CRAWL_SPEED: float = 0.04
const TENTACLE_PULSE_FREQ: float = 1.6
const REJITTER_INTERVAL_MIN: float = 12.0
const REJITTER_INTERVAL_MAX: float = 25.0
const LIFESPAN_S: float = 800.0
const FEED_RADIUS: float = 0.55
const FEED_INTERVAL_S: float = 4.5


var sim: Node = null
var substrate_top_y: float = 0.0
var _age: float = 0.0
var _drift: Vector3 = Vector3.ZERO
var _jitter_t: float = 0.0
var _feed_t: float = 0.0
var _phase: float = 0.0
var _segments: Array[MeshInstance3D] = []
var _tentacles: Array[MeshInstance3D] = []
var _tubercles: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("sea_cucumbers")
	# Body: 6 stacked thick voxels with darker tubercle dots on top.
	# Real sea cucumbers come in many color schemes; we pick warm-tans
	# so they read as sand-bed life, not coral.
	var body_dark := Color8(112, 84, 56)
	var body_mid  := Color8(150, 116, 80)
	var body_light := Color8(180, 148, 110)
	var tube_col := Color8(80, 58, 40)
	for i in SEGMENT_COUNT:
		var t: float = float(i) / float(maxi(1, SEGMENT_COUNT - 1))
		# Slight taper at each end so the silhouette isn't a uniform tube.
		var bulge: float = 1.0 - pow(2.0 * t - 1.0, 2.0) * 0.18
		var size := Vector3(
			VOXEL_SIZE * 0.95 * bulge,
			VOXEL_SIZE * 0.75 * bulge,
			VOXEL_SIZE * 0.9)
		var mi := MeshInstance3D.new()
		mi.mesh = VoxelMat.get_box(size)
		# Slight per-segment color variation.
		var col: Color
		if i == 0 or i == SEGMENT_COUNT - 1:
			col = body_dark
		elif i % 2 == 0:
			col = body_mid
		else:
			col = body_light
		mi.material_override = VoxelMat.make_fauna(col)
		mi.position = Vector3(0.0, VOXEL_SIZE * 0.4, VOXEL_SIZE * 0.9 * float(i)
			- VOXEL_SIZE * 0.9 * float(SEGMENT_COUNT - 1) * 0.5)
		add_child(mi)
		_segments.append(mi)
		# Tubercles on every other middle segment.
		if i > 0 and i < SEGMENT_COUNT - 1 and i % 2 == 1:
			var tub := MeshInstance3D.new()
			tub.mesh = VoxelMat.get_box(Vector3(
				VOXEL_SIZE * 0.18, VOXEL_SIZE * 0.18, VOXEL_SIZE * 0.18))
			tub.material_override = VoxelMat.make_fauna(tube_col)
			tub.position = mi.position + Vector3(0, VOXEL_SIZE * 0.5, 0)
			add_child(tub)
			_tubercles.append(tub)
	# Feeding tentacles at the head (front) end — small fan of voxels
	# that visibly pulse.
	var head_seg: MeshInstance3D = _segments[0]
	for i in 5:
		var ang: float = (float(i) / 5.0) * TAU
		var tent := MeshInstance3D.new()
		tent.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * 0.18, VOXEL_SIZE * 0.30, VOXEL_SIZE * 0.18))
		tent.material_override = VoxelMat.make_fauna(Color8(195, 165, 125))
		tent.position = head_seg.position + Vector3(
			cos(ang) * VOXEL_SIZE * 0.35,
			VOXEL_SIZE * 0.55,
			sin(ang) * VOXEL_SIZE * 0.35 - VOXEL_SIZE * 0.45)
		add_child(tent)
		_tentacles.append(tent)
	_phase = randf() * TAU
	_jitter_t = randf_range(REJITTER_INTERVAL_MIN, REJITTER_INTERVAL_MAX)
	_drift = _new_drift()


func _new_drift() -> Vector3:
	return Vector3(
		randf_range(-CRAWL_SPEED, CRAWL_SPEED),
		0.0,
		randf_range(-CRAWL_SPEED, CRAWL_SPEED))


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
	_phase += sdt * TENTACLE_PULSE_FREQ

	# Glacial crawl across substrate.
	position.x += _drift.x * sdt
	position.z += _drift.z * sdt
	_jitter_t -= sdt
	if _jitter_t <= 0.0:
		_jitter_t = randf_range(REJITTER_INTERVAL_MIN, REJITTER_INTERVAL_MAX)
		_drift = _new_drift()

	# Tentacle pulse — feeding tendrils flick in/out as the cucumber
	# scoops sand. Cheap: just scale animation on the tentacle list.
	for i in _tentacles.size():
		var t: Node3D = _tentacles[i]
		if t == null or not is_instance_valid(t):
			continue
		var s: float = 0.75 + 0.25 * (0.5 + 0.5 * sin(_phase * 1.6 + float(i) * 0.8))
		t.scale = Vector3(s, s, s)

	# Detritivore feeding — every FEED_INTERVAL_S seconds, sweep nearby
	# waste particles into the body and deposit a small amount back
	# into the substrate (the cucumber's mineralization output).
	_feed_t += sdt
	if _feed_t >= FEED_INTERVAL_S and sim != null:
		_feed_t = 0.0
		_consume_local_waste()


func _consume_local_waste() -> void:
	if sim == null or sim.waste == null:
		return
	var consumed: int = 0
	var radius2: float = FEED_RADIUS * FEED_RADIUS
	var waste_near: Array = sim.waste
	if sim.has_method("query_waste_in_radius"):
		waste_near = sim.query_waste_in_radius(global_position, FEED_RADIUS)
	for w in waste_near:
		if w == null or not is_instance_valid(w):
			continue
		var d2: float = (w.global_position - global_position).length_squared()
		if d2 < radius2:
			sim.waste.erase(w)
			if sim.has_method("recycle_waste"):
				sim.recycle_waste(w)
			else:
				w.queue_free()
			consumed += 1
			if consumed >= 3:
				break
	if consumed > 0 and sim.substrate != null:
		# Sea cucumbers redistribute nutrients — small boost to the
		# substrate cell at their position, simulating the mineralized
		# pellet output that aerates sand beds.
		sim.substrate.add_at(global_position, 0.06)


func to_save_dict() -> Dictionary:
	return {
		"pos": SaveHelpers.vec3_to_array(global_position),
		"age": _age,
	}


func apply_save_dict(d: Dictionary) -> void:
	_age = float(d.get("age", 0.0))
