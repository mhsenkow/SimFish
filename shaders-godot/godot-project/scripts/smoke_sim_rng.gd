extends SceneTree

# META_ENGINEERING #31 — SimRng named streams are stable and independent.

const SimRng = preload("res://scripts/sim_rng.gd")


func _initialize() -> void:
	if not _run_all():
		quit(1)
		return
	print("[smoke_sim_rng] OK")
	quit(0)


func _fail(msg: String) -> bool:
	push_error(msg)
	return false


func _run_all() -> bool:
	var a := SimRng.new()
	a.reset(42)
	var b := SimRng.new()
	b.reset(42)
	var seq_a: PackedFloat32Array = PackedFloat32Array()
	var seq_b: PackedFloat32Array = PackedFloat32Array()
	for _i in 5:
		seq_a.append(a.randf(SimRng.STREAM_SPAWN))
		seq_b.append(b.randf(SimRng.STREAM_SPAWN))
	for i in seq_a.size():
		if seq_a[i] != seq_b[i]:
			return _fail("same seed must yield identical spawn stream")
	var c := SimRng.new()
	c.reset(42)
	var spawn_first: float = c.randf(SimRng.STREAM_SPAWN)
	var events_first: float = c.randf(SimRng.STREAM_EVENTS)
	var d := SimRng.new()
	d.reset(42)
	if d.randf(SimRng.STREAM_EVENTS) != events_first:
		return _fail("stream order must not cross-contaminate")
	if d.randf(SimRng.STREAM_SPAWN) != spawn_first:
		return _fail("late spawn draw must match early spawn stream")
	var e := SimRng.new()
	e.reset(99)
	if e.randf(SimRng.STREAM_SPAWN) == spawn_first:
		return _fail("different master seed should change stream output")
	var ent: String = SimRng.entity_stream_name(SimRng.STREAM_COGNITION, "fish-1")
	if ent != "cognition:fish-1":
		return _fail("entity stream naming")
	# META #31 — shrimp offspring genetics are now seeded: same parent id + seed
	# must produce a byte-identical fry genome across runs (replay determinism).
	if not _shrimp_offspring_deterministic():
		return _fail("shrimp produce_offspring_genome must be deterministic under SimRng")
	return true


# Two offspring rolls from the same parent (sim=null → MindRng fallback stream
# keyed on the parent id) must be byte-identical.
func _shrimp_offspring_deterministic() -> bool:
	var a := Shrimp.new()
	a.id = "rng-shrimp-a"
	a.shrimp_name = "A"
	a.adult_voxel_scale = 0.5
	a.defense_spines = 0.3
	a.toxin_level = 0.2
	a.claw_size = 0.4
	var b := Shrimp.new()
	b.id = "rng-shrimp-b"
	b.shrimp_name = "B"
	b.adult_voxel_scale = 0.55
	var g1: Dictionary = a.produce_offspring_genome(b)
	var g2: Dictionary = a.produce_offspring_genome(b)
	a.free()
	b.free()
	return var_to_str(g1) == var_to_str(g2)
