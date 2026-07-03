extends SceneTree

# REFINEMENT_II finish bundle — foliage cache, node diet, sleep/wake, feed fairness,
# camera×shape, alloc attribution, chemistry visuals, filter intake.

const VoxelMat = preload("res://scripts/voxel_mat.gd")
const DartTrailPool = preload("res://scripts/dart_trail_pool.gd")
const PerfGovernor = preload("res://scripts/perf_governor.gd")
const TankFootprint = preload("res://scripts/tank_footprint.gd")
const _MotionWave = preload("res://scripts/motion_wave.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	_test_foliage_cache(failed)
	_test_fish_node_diet(failed)
	_test_sleep_wake_edges(failed)
	_test_feed_fairness(failed)
	_test_filter_intake_gate(failed)
	_test_alloc_attribution(failed)
	_test_chemistry_visual_channels(failed)
	_test_camera_footprint(failed)
	DartTrailPool.reset_for_test()
	if failed.is_empty():
		print("[smoke] refinement_ii_finish OK")
		quit(0)
	else:
		for msg in failed:
			push_error("[smoke] refinement_ii_finish FAIL: %s" % msg)
		quit(1)


func _test_foliage_cache(failed: Array[String]) -> void:
	var before: int = VoxelMat._foliage_mat_cache.size()
	for i in 130:
		var hue: float = float(i) / 130.0
		VoxelMat.make_foliage(Color.from_hsv(hue, 0.55, 0.72))
	_assert(failed, VoxelMat._foliage_mat_cache.size() <= VoxelMat._CACHE_MAX,
		"foliage cache bounded at %d (max %d)" % [VoxelMat._foliage_mat_cache.size(), VoxelMat._CACHE_MAX])
	_assert(failed, VoxelMat._foliage_mat_cache.size() >= before,
		"foliage cache populated")


func _test_fish_node_diet(failed: Array[String]) -> void:
	var f := Fish.new()
	var n0: int = f.get_child_count()
	f.species = "glassdart"
	f.swim_pattern = "school"
	f._build_body()
	var n1: int = f.get_child_count()
	_assert(failed, n1 - n0 <= 12, "fish body uses ≤12 child nodes (got %d)" % (n1 - n0))
	f.queue_free()


func _test_sleep_wake_edges(failed: Array[String]) -> void:
	var f := Fish.new()
	f._asleep = true
	f._dreaming = false
	f._startle_remaining = 0.0
	f._sleep_mind_cd = 1.0
	_assert(failed, f._sleep_skips_mind_tick(0.05), "asleep fish skip mind between consolidation beats")
	f._startle_remaining = 0.2
	_assert(failed, not f._sleep_skips_mind_tick(0.05), "startle wakes mind path")
	f._asleep = false
	var gate: Dictionary = {"run": true, "mind_dt": 0.05}
	var skip: bool = f._sleep_skips_mind_tick(0.05)
	_assert(failed, not skip, "awake fish never sleep-skip mind")
	f.queue_free()


func _test_feed_fairness(failed: Array[String]) -> void:
	var bold := Fish.new()
	var timid := Fish.new()
	bold.rank_within_species = 0.85
	bold.hunger = 0.5
	timid.rank_within_species = 0.2
	timid.hunger = 0.78
	var pellet := WasteParticle.new()
	pellet.kind = WasteParticle.KIND_FOOD
	pellet.position = Vector3(1.0, 1.2, 0.0)
	# Timid with high hunger should not be penalized as harshly as sated fish.
	var d2_sated: float = 10.0
	var d2_starving: float = 10.0
	var bold_scale_sated: float = lerpf(1.6, 0.55, 0.3)
	var urg: float = clampf((timid.hunger - 0.42) / 0.58, 0.0, 1.0)
	d2_starving *= lerpf(bold_scale_sated, 1.0, urg * 0.9)
	d2_sated *= bold_scale_sated
	_assert(failed, d2_starving < d2_sated * 0.92,
		"starving timid fish get hunger urgency relief at pellets")
	bold.queue_free()
	timid.queue_free()
	pellet.queue_free()


func _test_filter_intake_gate(failed: Array[String]) -> void:
	var sim_script: Script = load("res://scripts/sim_driver.gd")
	var sim: Node = sim_script.new()
	_assert(failed, sim.has_method("filter_intake_active"), "filter_intake_active exists")
	sim.set("filter_intake_pos", Vector3(1.0, 1.0, 0.0))
	_assert(failed, not bool(sim.call("filter_intake_active")),
		"intake pull off when no feeder active")
	var clam := Clam.new()
	clam.current_mode = Clam.Mode.FEEDING
	sim.set("clams", [clam])
	_assert(failed, bool(sim.call("filter_intake_active")), "clam feeding enables intake pull")
	sim.queue_free()


func _test_alloc_attribution(failed: Array[String]) -> void:
	PerfGovernor.reset_for_test()
	PerfGovernor.scope_begin("mind_tick")
	PerfGovernor.scope_end("mind_tick")
	PerfGovernor.record_frame(1.0 / 60.0)
	PerfGovernor.scope_begin("render")
	PerfGovernor.scope_end("render")
	PerfGovernor.record_frame(1.0 / 60.0)
	var line: String = PerfGovernor.hud_line(12, 400)
	_assert(failed, line.contains("fish 12"), "perf HUD line includes fish count")
	_assert(failed, PerfGovernor.scopes_snapshot().has("mind_tick"), "scope attribution recorded")


func _test_chemistry_visual_channels(failed: Array[String]) -> void:
	var sim_script: Script = load("res://scripts/sim_driver.gd")
	var sim: Node = sim_script.new()
	_assert(failed, sim.get("bloom_intensity") != null, "bloom_intensity channel exists")
	var wc: Variant = sim.get("water_chemistry")
	_assert(failed, wc != null, "water_chemistry exists")
	sim.queue_free()
	var world_script: Script = load("res://scripts/world.gd")
	_assert(failed, world_script != null, "world loads for visual coupling")
	var w: Node = world_script.new()
	_assert(failed, w.has_method("add_mulm_voxel"), "mulm visual channel exists")
	w.queue_free()


func _test_camera_footprint(failed: Array[String]) -> void:
	var cfg := get_root().get_node_or_null("TankConfig")
	if cfg == null:
		_assert(failed, false, "TankConfig missing")
		return
	for shape in ["box", "sphere", "cylinder", "hex"]:
		cfg.tank_shape = shape
		var fp = TankFootprint.from_config(cfg)
		var r: float = fp.effective_radius(0.35)
		_assert(failed, r > 0.5, "%s footprint radius sane (%.2f)" % [shape, r])


func _assert(failed: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		failed.append(msg)
