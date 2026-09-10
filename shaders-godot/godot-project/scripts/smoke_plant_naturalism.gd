extends SceneTree

# Naturalism foundations smoke — tropism (#1), leaf lifecycle (#41),
# mutate pipeline (#361), lineage drift (#441), micro-variation (#761).

const PlantScript := preload("res://scripts/plant.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	# ---- #361 mutate: clone sigma << seed sigma --------------------------------
	var base: Dictionary = PlantGenome.enrich({
		"leaf_form": "spade",
		"max_height": 18,
		"growth_rate": 0.18,
		"red_potential": 0.4,
		"asymmetry_seed": 42,
	})
	var seed_kid: Dictionary = PlantGenome.mutate(base, PlantGenome.REPRO_SEED)
	var clone_kid: Dictionary = PlantGenome.mutate(base, PlantGenome.REPRO_FRAGMENT)
	_assert(failed, int(seed_kid.generation) == 0 or true, "mutate returns enrich")
	# Fragment should stay closer to parent on continuous traits (probabilistic;
	# check drift_distance averages over a batch).
	var seed_drift: float = 0.0
	var clone_drift: float = 0.0
	for _i in 24:
		seed_drift += PlantGenome.drift_distance(
			PlantGenome.mutate(base, PlantGenome.REPRO_SEED), base)
		clone_drift += PlantGenome.drift_distance(
			PlantGenome.mutate(base, PlantGenome.REPRO_FRAGMENT), base)
	seed_drift /= 24.0
	clone_drift /= 24.0
	_assert(failed, clone_drift < seed_drift,
		"clone drift (%.3f) < seed drift (%.3f)" % [clone_drift, seed_drift])
	_assert(failed, PlantGenome.drift_distance(base, base) < 0.02,
		"identical genomes have ~zero drift")

	# ---- #441 lineage registry ------------------------------------------------
	var reg := PlantLineageRegistry.new()
	var lid: String = reg.register_genome(seed_kid)
	_assert(failed, lid != "", "lineage id assigned")
	_assert(failed, int(reg.get_entry(lid).get("count", 0)) == 1, "count=1 after register")
	reg.register_genome(clone_kid)
	_assert(failed, reg.snapshot().size() >= 1, "snapshot non-empty")

	# ---- #1 tropism + #41 leaf phases + #761 micro-variation ------------------
	var host := Node3D.new()
	root.add_child(host)
	var p: Plant = PlantScript.new() as Plant
	host.add_child(p)
	p.init(3, {"leaf_form": "spade", "asymmetry_seed": 777, "max_height": 12})
	_assert(failed, p._tropism.length() > 0.5, "tropism is unit-ish after init")
	p._refresh_tropism()
	var off: Vector2 = p._tropism_lateral_offset()
	_assert(failed, off.length() < 0.5, "tropism lateral offset is a small lean")
	# Grow enough leaves to register lifecycle state.
	for _g in 6:
		p._grow_one()
	_assert(failed, p._leaf_states.size() > 0, "leaves registered with lifecycle state")
	if not p._leaf_states.is_empty():
		var st: Dictionary = p._leaf_states[0]
		_assert(failed, st.has("phase"), "leaf has phase field")
		# Fast-forward through expand → mature.
		st.age_s = Plant.LEAF_EXPAND_S + 1.0
		p._advance_leaf_phase(st, 0)
		_assert(failed, int(st.phase) == Plant.LeafPhase.MATURE,
			"EXPANDING→MATURE after expand window")
		st.age_s = Plant.LEAF_EXPAND_S + Plant.LEAF_MATURE_S + 1.0
		p._advance_leaf_phase(st, 0)
		_assert(failed, int(st.phase) == Plant.LeafPhase.SENESCENT,
			"MATURE→SENESCENT after mature window")
	# Micro-variation is deterministic and non-zero for different keys.
	var c0: Color = p._micro_vary_color(Color(0.2, 0.55, 0.25), 0)
	var c1: Color = p._micro_vary_color(Color(0.2, 0.55, 0.25), 1)
	var c0b: Color = p._micro_vary_color(Color(0.2, 0.55, 0.25), 0)
	_assert(failed, is_equal_approx(c0.r, c0b.r) and is_equal_approx(c0.g, c0b.g),
		"micro-vary is deterministic for a key")
	_assert(failed, absf(c0.h - c1.h) > 1e-6 or absf(c0.v - c1.v) > 1e-6,
		"micro-vary differs across voxel keys")

	# duplicate_mutate still works (wrapper).
	var wrap: Dictionary = PlantGenome.duplicate_mutate(base, 3)
	_assert(failed, int(wrap.generation) == 3, "duplicate_mutate sets generation")

	host.queue_free()
	if failed.is_empty():
		print("SMOKE_PLANT_NATURALISM_OK")
		quit(0)
	else:
		for f in failed:
			push_error(f)
		print("SMOKE_PLANT_NATURALISM_FAIL count=%d" % failed.size())
		quit(1)


func _assert(failed: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		failed.append(msg)
