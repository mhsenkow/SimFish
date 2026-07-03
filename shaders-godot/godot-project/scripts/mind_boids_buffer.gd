class_name MindBoidsBuffer
extends RefCounted

# PERFORMANCE_UNTHROTTLED #57 — shared SoA layout for CPU/GPU boids backends.

const MAX_FISH: int = 256
const RADIUS_SQ: float = 9.0
const VIEW_DOT: float = -0.4
const LOOKAHEAD: float = 0.4

static var positions: PackedVector3Array = PackedVector3Array()
static var velocities: PackedVector3Array = PackedVector3Array()
static var headings: PackedVector3Array = PackedVector3Array()
static var separation_radii: PackedFloat32Array = PackedFloat32Array()
static var home_y_radii: PackedFloat32Array = PackedFloat32Array()
static var species_hash: PackedInt32Array = PackedInt32Array()
static var lead_scores: PackedFloat32Array = PackedFloat32Array()
static var fish_refs: Array[Fish] = []

static var sep_accum: PackedVector3Array = PackedVector3Array()
static var ali_accum: PackedVector3Array = PackedVector3Array()
static var coh_center: PackedVector3Array = PackedVector3Array()
static var neighbor_counts: PackedInt32Array = PackedInt32Array()
static var school_speed_milli: PackedInt32Array = PackedInt32Array()

static var count: int = 0
static var tick_serial: int = 0
static var backend: String = "none"
static var _fish_index: Dictionary = {}


static func reset_for_test() -> void:
	positions = PackedVector3Array()
	velocities = PackedVector3Array()
	headings = PackedVector3Array()
	separation_radii = PackedFloat32Array()
	home_y_radii = PackedFloat32Array()
	species_hash = PackedInt32Array()
	lead_scores = PackedFloat32Array()
	fish_refs = []
	sep_accum = PackedVector3Array()
	ali_accum = PackedVector3Array()
	coh_center = PackedVector3Array()
	neighbor_counts = PackedInt32Array()
	school_speed_milli = PackedInt32Array()
	count = 0
	tick_serial = 0
	backend = "none"
	_fish_index.clear()


static func capture(fish_arr: Array, serial: int) -> int:
	tick_serial = serial
	backend = "none"
	_fish_index.clear()
	count = 0
	var need: int = mini(fish_arr.size(), MAX_FISH)
	if positions.size() < need:
		positions.resize(need)
		velocities.resize(need)
		headings.resize(need)
		separation_radii.resize(need)
		home_y_radii.resize(need)
		species_hash.resize(need)
		lead_scores.resize(need)
		fish_refs.resize(need)
	for f in fish_arr:
		if count >= MAX_FISH or not is_instance_valid(f) or f.get("_dying") == true:
			continue
		if not (f is Fish):
			continue
		positions[count] = f.position
		velocities[count] = f.velocity if f.get("velocity") != null else Vector3.ZERO
		headings[count] = f.heading if f.get("heading") != null else Vector3.FORWARD
		separation_radii[count] = float(f.separation_radius if f.get("separation_radius") != null else 0.55)
		home_y_radii[count] = float(f.home_y_radius if f.get("home_y_radius") != null else 0.35)
		species_hash[count] = hash(str(f.species))
		lead_scores[count] = float(f.lead_score if f.get("lead_score") != null else 0.0)
		fish_refs[count] = f
		_fish_index[f] = count
		count += 1
	_trim(count)
	return count


static func _trim(n: int) -> void:
	positions.resize(n)
	velocities.resize(n)
	headings.resize(n)
	separation_radii.resize(n)
	home_y_radii.resize(n)
	species_hash.resize(n)
	lead_scores.resize(n)
	fish_refs.resize(n)
	sep_accum.resize(n)
	ali_accum.resize(n)
	coh_center.resize(n)
	neighbor_counts.resize(n)
	school_speed_milli.resize(n)
	for i in n:
		sep_accum[i] = Vector3.ZERO
		ali_accum[i] = Vector3.ZERO
		coh_center[i] = Vector3.ZERO
		neighbor_counts[i] = 0
		school_speed_milli[i] = 0


static func index_for(f: Fish) -> int:
	if f == null or count <= 0:
		return -1
	return int(_fish_index.get(f, -1))


static func has_outputs_for(f: Fish) -> bool:
	var idx: int = index_for(f)
	return idx >= 0 and backend != "none"


static func neighbor_count_for(f: Fish) -> int:
	var idx: int = index_for(f)
	if idx < 0:
		return 0
	return neighbor_counts[idx]


static func school_avg_speed_for(f: Fish) -> float:
	var idx: int = index_for(f)
	if idx < 0 or neighbor_counts[idx] <= 0:
		return 0.0
	return float(school_speed_milli[idx]) / 1000.0 / float(neighbor_counts[idx])
