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
			clusters[root] = _next_school_id
			_next_school_id += 1
		f_v.school_id = int(clusters[root])


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
	# Cheap merge: overlapping school blobs of same species
	for f_a in fish_arr:
		if not is_instance_valid(f_a) or not _MotionWaveScript.uses_wave(f_a):
			continue
		var sid_a: int = int(f_a.school_id)
		if sid_a < 0:
			continue
		for f_b in fish_arr:
			if f_a == f_b or not is_instance_valid(f_b):
				continue
			if f_a.species != f_b.species or not _MotionWaveScript.uses_wave(f_b):
				continue
			var sid_b: int = int(f_b.school_id)
			if sid_b < 0 or sid_a == sid_b:
				continue
			if f_a.position.distance_squared_to(f_b.position) < MERGE_DIST * MERGE_DIST:
				f_b.school_id = sid_a


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
		var nf: Node = MindBoidsBuffer.fish_refs[ni]
		if nf == null or nf.get("_bank_pivot") == null:
			continue
		sum += float((nf._bank_pivot as Node3D).rotation.z)
		n += 1
	if n <= 0:
		return 0.0
	return lerpf(my_bank, sum / float(n), 0.22)
