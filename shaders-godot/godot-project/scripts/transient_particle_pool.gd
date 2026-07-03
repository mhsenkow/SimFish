class_name TransientParticlePool
extends RefCounted

# PERFORMANCE_UNTHROTTLED #71 — pre-spawned GPUParticles3D for splash/cavitation events.

static var _pools: Dictionary = {}  # parent_id -> {kind: GPUParticles3D}


static func reset_for_test() -> void:
	for row in _pools.values():
		if row is Dictionary:
			for p in (row as Dictionary).values():
				if p is Node and is_instance_valid(p):
					(p as Node).queue_free()
	_pools.clear()


static func _process_material(kind: String) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 28.0 if kind == "splash" else 18.0
	pm.initial_velocity_min = 0.35 if kind == "splash" else 0.18
	pm.initial_velocity_max = 1.1 if kind == "splash" else 0.55
	pm.gravity = Vector3(0.0, -1.8 if kind == "splash" else -0.6, 0.0)
	pm.scale_min = 0.04
	pm.scale_max = 0.12 if kind == "splash" else 0.07
	pm.color = Color(0.82, 0.92, 1.0, 0.55) if kind == "cavitation" else Color(1.0, 1.0, 1.0, 0.7)
	return pm


static func _ensure(parent: Node, kind: String) -> GPUParticles3D:
	var pid: int = parent.get_instance_id()
	if not _pools.has(pid):
		_pools[pid] = {}
	var row: Dictionary = _pools[pid] as Dictionary
	if row.has(kind) and is_instance_valid(row[kind]):
		return row[kind] as GPUParticles3D
	var gp := GPUParticles3D.new()
	gp.name = "Pooled_%s" % kind
	gp.emitting = false
	gp.one_shot = true
	gp.amount = 12 if kind == "splash" else 8
	gp.lifetime = 0.45 if kind == "splash" else 0.28
	gp.process_material = _process_material(kind)
	parent.add_child(gp)
	row[kind] = gp
	return gp


static func burst(parent: Node, kind: String, pos: Vector3) -> void:
	if parent == null:
		return
	var gp: GPUParticles3D = _ensure(parent, kind)
	gp.global_position = pos
	gp.restart()
	gp.emitting = true


static func pool_count(parent: Node) -> int:
	if parent == null:
		return 0
	var pid: int = parent.get_instance_id()
	if not _pools.has(pid):
		return 0
	return (_pools[pid] as Dictionary).size()
