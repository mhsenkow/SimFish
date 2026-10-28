class_name MotionSchool
extends RefCounted

const _MotionWaveScript = preload("res://scripts/motion_wave.gd")

# LIVING_MOTION §A — per-school identity, fission–fusion, bank correlation, leaders.

const FISSION_VARIANCE: float = 2.8
const FISSION_HOLD_S: float = 2.0
const MERGE_DIST: float = 1.6

static var _next_school_id: int = 1
static var _fission_timer: Dictionary = {}


static func reset_for_test() -> void:
	_next_school_id = 1
	_fission_timer.clear()


static func tick(fish_arr: Array, dt: float) -> void:
	if MindBoidsBuffer.backend == "none":
		return
	_union_find_ids(fish_arr)
	_tick_fission_fusion(fish_arr, dt)
	_tick_transient_leaders(fish_arr, dt)


static func _union_find_ids(fish_arr: Array) -> void:
	var parent: Dictionary = {}
	for f_v in fish_arr:
		if not is_instance_valid(f_v) or f_v.get("_dying") == true:
			continue
		if not _MotionWaveScript.uses_wave(f_v):
			f_v.school_id = -1
			continue
		var idx: int = MindBoidsBuffer.index_for(f_v)
		if idx < 0:
			f_v.school_id = -1
			continue
		parent[idx] = idx
	for f_v in fish_arr:
		if not is_instance_valid(f_v) or f_v.get("_dying") == true:
			continue
		if not _MotionWaveScript.uses_wave(f_v):
			continue
		var idx: int = MindBoidsBuffer.index_for(f_v)
		if idx < 0:
			continue
		for t in MindBoidsBuffer.N_TOPO:
			var ni: int = MindBoidsBuffer.topo_neighbor_at(idx, t)
			if ni < 0:
				continue
			var nf: Node = MindBoidsBuffer.fish_refs[ni]
			if nf == null or str(nf.get("species")) != str(f_v.get("species")):
				continue
			_union(parent, idx, ni)
	var clusters: Dictionary = {}
	for f_v in fish_arr:
		if not is_instance_valid(f_v) or f_v.get("_dying") == true:
			continue
		if not _MotionWaveScript.uses_wave(f_v):
			continue
		var idx: int = MindBoidsBuffer.index_for(f_v)
		if idx < 0:
			continue
		var root: int = _find(parent, idx)
		if not clusters.has(root):
			clusters[root] = []
		(clusters[root] as Array).append(f_v)
	# Connected schools keep their identity across ticks. Regenerating IDs
	# every tick prevented fission timers accumulating and leaked old timers.
	var claimed: Dictionary = {}
	for members in clusters.values():
		var sid: int = -1
		for f in members:
			var previous: int = int(f.school_id)
			if previous >= 0:
				_next_school_id = maxi(_next_school_id, previous + 1)
				if not claimed.has(previous) and (sid < 0 or previous < sid):
					sid = previous
		if sid < 0:
			sid = _next_school_id
			_next_school_id += 1
		claimed[sid] = true
		for f in members:
			f.school_id = sid


static func _union(parent: Dictionary, a: int, b: int) -> void:
	var ra: int = _find(parent, a)
	var rb: int = _find(parent, b)
	if ra != rb:
		parent[rb] = ra


static func _find(parent: Dictionary, x: int) -> int:
	while parent.get(x, x) != x:
		parent[x] = parent.get(parent[x], parent[x])
		x = int(parent[x])
	return x


static func _tick_fission_fusion(fish_arr: Array, dt: float) -> void:
	var by_id: Dictionary = {}
	for f_v in fish_arr:
		if not is_instance_valid(f_v) or f_v.get("_dying") == true:
			continue
		if not _MotionWaveScript.uses_wave(f_v):
			continue
		var sid: int = int(f_v.get("school_id") if f_v.get("school_id") != null else -1)
		if sid < 0:
			continue
		if not by_id.has(sid):
			by_id[sid] = []
		(by_id[sid] as Array).append(f_v)
	for previous in _fission_timer.keys():
		if not by_id.has(previous):
			_fission_timer.erase(previous)
	var split_ids: Array[int] = []
	for sid_v in by_id.keys():
		var sid: int = int(sid_v)
		var group: Array = by_id[sid]
		if group.size() < 4:
			_fission_timer.erase(sid)
			continue
		var centroid: Vector3 = Vector3.ZERO
		for g in group:
			centroid += g.position as Vector3
		centroid /= float(group.size())
		var variance: float = 0.0
		for g in group:
			variance += Vector2(
				(g.position as Vector3).x - centroid.x,
				(g.position as Vector3).z - centroid.z).length_squared()
		variance /= float(group.size())
		if variance > FISSION_VARIANCE:
			_fission_timer[sid] = float(_fission_timer.get(sid, 0.0)) + dt
			if float(_fission_timer[sid]) >= FISSION_HOLD_S:
				split_ids.append(sid)
		else:
			_fission_timer[sid] = maxf(0.0, float(_fission_timer.get(sid, 0.0)) - dt * 0.5)
	for sid in split_ids:
		var group: Array = by_id[sid]
		var half: int = int(group.size() / 2.0)
		var new_id: int = _next_school_id
		_next_school_id += 1
		for i in range(half, group.size()):
			group[i].school_id = new_id
		_fission_timer.erase(sid)
	_merge_nearby_schools(fish_arr)


static func _merge_nearby_schools(fish_arr: Array) -> void:
	# Preserve the original ordered merge decisions, but inspect only local
	# candidates. Eligibility and species are collected once, not per pair.
	var active: Array[Node3D] = []
	var species: Array[String] = []
	var cells: Array[Vector3i] = []
	var grid: Dictionary = {}
	var schools_by_species: Dictionary = {}
	for f in fish_arr:
		if not is_instance_valid(f) or f.get("_dying") == true or not _MotionWaveScript.uses_wave(f):
			continue
		if int(f.school_id) < 0:
			continue
		var pos: Vector3 = f.position
		var cell := Vector3i(floori(pos.x / MERGE_DIST), floori(pos.y / MERGE_DIST),
			floori(pos.z / MERGE_DIST))
		var index: int = active.size()
		active.append(f)
		var name: String = String(f.species)
		species.append(name)
		if not schools_by_species.has(name):
			schools_by_species[name] = {}
		(schools_by_species[name] as Dictionary)[int(f.school_id)] = true
		cells.append(cell)
		if not grid.has(cell):
			grid[cell] = []
		(grid[cell] as Array).append(index)
	for i in active.size():
		if (schools_by_species[species[i]] as Dictionary).size() < 2:
			continue
		var a: Node3D = active[i]
		var sid: int = int(a.get("school_id"))
		var candidates: Array[int] = []
		for x in range(-1, 2):
			for y in range(-1, 2):
				for z in range(-1, 2):
					var cell: Vector3i = cells[i] + Vector3i(x, y, z)
					if grid.has(cell):
						for j in grid[cell]:
							if j != i and species[i] == species[j]:
								candidates.append(j)
		candidates.sort()
		for j in candidates:
			var b: Node3D = active[j]
			if sid != int(b.get("school_id")) and a.position.distance_squared_to(b.position) < MERGE_DIST * MERGE_DIST:
				b.set("school_id", sid)


static func _tick_transient_leaders(fish_arr: Array, dt: float) -> void:
	for f_v in fish_arr:
		if not is_instance_valid(f_v) or f_v.get("_dying") == true:
			continue
		if not _MotionWaveScript.uses_wave(f_v):
			f_v.motion_lead_boost = maxf(0.0, float(f_v.get("motion_lead_boost") if f_v.get("motion_lead_boost") != null else 0.0) - dt * 1.8)
		var intent: Vector3 = f_v.motion_turn_intent as Vector3
		if intent.length_squared() < 0.02:
			continue
		var front: float = (f_v.heading as Vector3).dot(intent.normalized())
		if front > 0.55 and float(f_v.motion_agitation) > 0.2:
			f_v.motion_lead_boost = clampf(float(f_v.motion_lead_boost) + dt * 2.2, 0.0, 0.85)


# Holistic #086 — school speed matching weight. Keep cohesion / startle
# propagation, but do not lock personal bout paces to neighbours.
static func speed_match_weight(swim_pattern: String, bout_kind: int, bout_env: float,
		burst_remaining: float, startle_remaining: float, agitation: float) -> float:
	# Startle / burst: allow schools to surge together (response propagation).
	if burst_remaining > 0.0 or startle_remaining > 0.0 or agitation > 0.35:
		return 0.24
	var w: float = 0.07 if swim_pattern == "school" else 0.035
	# Decorative hover/dart and off-cruise envelopes own their pace.
	if bout_kind != 0 or bout_env < 0.82 or bout_env > 1.18:
		w *= 0.2
	return w


static func bank_correlation(f: Node) -> float:
	if f == null or not _MotionWaveScript.uses_wave(f):
		return 0.0
	var idx: int = MindBoidsBuffer.index_for(f)
	if idx < 0 or f.get("_bank_pivot") == null:
		return 0.0
	var my_bank: float = float((f._bank_pivot as Node3D).rotation.z)
	var sum: float = 0.0
	var n: int = 0
	for t in MindBoidsBuffer.N_TOPO:
		var ni: int = MindBoidsBuffer.topo_neighbor_at(idx, t)
		if ni < 0:
			continue
		# The boids buffer is captured once per tick; a neighbour can be freed
		# before this runs, and assigning a freed ref to a typed var errors.
		var nf_v: Variant = MindBoidsBuffer.fish_refs[ni]
		if not is_instance_valid(nf_v):
			continue
		var nf: Node = nf_v
		if nf.get("_bank_pivot") == null:
			continue
		sum += float((nf._bank_pivot as Node3D).rotation.z)
		n += 1
	if n <= 0:
		return 0.0
	return lerpf(my_bank, sum / float(n), 0.22)
