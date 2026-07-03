extends SceneTree

# REFINEMENT_II §L/M proof bundle — spawn audit, settings, dart pool, time auth,
# golden rng, short soak, boot hygiene, residents wiring.

const _MotionWave = preload("res://scripts/motion_wave.gd")
const DartTrailPool = preload("res://scripts/dart_trail_pool.gd")
const TimeAuthority = preload("res://scripts/time_authority.gd")
const SimRng = preload("res://scripts/sim_rng.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	_test_spawn_spacing(failed)
	_test_tank_config_roundtrip(failed)
	_test_dart_trail_pool(failed)
	_test_time_authority(failed)
	_test_golden_rng(failed)
	_test_short_soak(failed)
	_test_script_todos(failed)
	_test_residents_signals(failed)
	_test_intent_decay(failed)
	DartTrailPool.reset_for_test()
	await process_frame
	await process_frame
	if failed.is_empty():
		print("[smoke] refinement_ii_proof OK")
		quit(0)
	else:
		for msg in failed:
			push_error("[smoke] refinement_ii_proof FAIL: %s" % msg)
		quit(1)


func _test_spawn_spacing(failed: Array[String]) -> void:
	var world_script: Script = load("res://scripts/world.gd")
	var w: Node3D = world_script.new() as Node3D
	root.add_child(w)
	await process_frame
	await process_frame
	if w.fauna_root == null:
		_assert(failed, false, "world fauna_root missing")
		w.queue_free()
		return
	var f1 := Fish.new()
	w.fauna_root.add_child(f1)
	f1.position = Vector3(0.0, 1.2, 0.0)
	f1.adult_voxel_scale = 0.2
	var body_r: float = float(w.call("_fish_spawn_body_radius", {"adult_voxel_scale": 0.2}))
	var too_close: bool = bool(w.call("_spawn_pos_clear_of_fish", Vector3(0.15, 1.2, 0.0), body_r))
	_assert(failed, not too_close, "spawn rejects overlap with existing fish")
	var clear: bool = bool(w.call("_spawn_pos_clear_of_fish", Vector3(2.5, 1.2, 0.0), body_r))
	_assert(failed, clear, "spawn accepts distant point")
	w.queue_free()


func _test_tank_config_roundtrip(failed: Array[String]) -> void:
	var cfg := get_root().get_node_or_null("TankConfig")
	if cfg == null:
		_assert(failed, false, "TankConfig autoload missing")
		return
	var saved_w: int = int(cfg.render_width)
	var saved_h: int = int(cfg.render_height)
	var saved_msaa: int = int(cfg.msaa)
	cfg.render_width = 512
	cfg.render_height = 288
	cfg.msaa = 2
	var snap: ConfigFile = cfg.call("_build_save_config_file") as ConfigFile
	var path: String = String(cfg.call("_current_save_path"))
	snap.save(path)
	cfg.render_width = 640
	cfg.render_height = 360
	cfg.load_from_disk()
	_assert(failed, int(cfg.render_width) == 512, "settings width round-trips (got %d)" % int(cfg.render_width))
	_assert(failed, int(cfg.render_height) == 288, "settings height round-trips")
	_assert(failed, int(cfg.msaa) == 2, "settings msaa round-trips")
	cfg.render_width = saved_w
	cfg.render_height = saved_h
	cfg.msaa = saved_msaa
	var restore: ConfigFile = cfg.call("_build_save_config_file") as ConfigFile
	restore.save(path)


func _test_dart_trail_pool(failed: Array[String]) -> void:
	DartTrailPool.reset_for_test()
	var parent := Node3D.new()
	root.add_child(parent)
	var gp := Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var ok_count: int = 0
	for i in DartTrailPool.POOL_SIZE + 2:
		if DartTrailPool.spawn(parent, gp, Color.WHITE, Vector3.FORWARD, Callable()):
			ok_count += 1
	_assert(failed, ok_count >= DartTrailPool.POOL_SIZE,
		"dart pool serves %d slots (got %d ok)" % [DartTrailPool.POOL_SIZE, ok_count])
	DartTrailPool.reset_for_test()
	parent.queue_free()


func _test_time_authority(failed: Array[String]) -> void:
	TimeAuthority.reset_for_test()
	var sim := Node.new()
	sim.set_script(load("res://scripts/smoke_sim_stub.gd"))
	sim.set("time_scale", 1.0)
	root.add_child(sim)
	TimeAuthority.set_base_scale(4.0)
	TimeAuthority.push_pause(sim, "aquascape")
	_assert(failed, float(sim.time_scale) == 0.0, "aquascape pause freezes sim")
	TimeAuthority.push_pause(sim, "player")
	TimeAuthority.pop_pause(sim, "aquascape")
	_assert(failed, float(sim.time_scale) == 0.0, "player pause still holds")
	TimeAuthority.pop_pause(sim, "player")
	_assert(failed, absf(float(sim.time_scale) - 4.0) < 0.001, "resume restores base scale")
	sim.queue_free()
	TimeAuthority.reset_for_test()


func _test_golden_rng(failed: Array[String]) -> void:
	var h1: int = _golden_hash()
	var h2: int = _golden_hash()
	_assert(failed, h1 == h2, "golden replay hash stable across runs")
	_assert(failed, h1 != 0, "golden replay hash non-zero")


func _golden_hash() -> int:
	var rng := SimRng.new()
	rng.reset(4242)
	var h: int = 0
	for _i in 64:
		h = (h * 31 + int(rng.randf(SimRng.STREAM_EVENTS) * 1000000.0)) & 0x7fffffff
	return h


func _test_short_soak(failed: Array[String]) -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	var fish: Array[Fish] = []
	for i in 6:
		var f := Fish.new()
		parent.add_child(f)
		f.id = "soak_%d" % i
		f.species = "glassdart"
		f.swim_pattern = "school"
		f.schooling_strength = 1.4
		f.position = Vector3(float(i) * 0.4, 1.0, 0.0)
		fish.append(f)
	_MotionWave.reset_for_test()
	var hit: Variant = _MotionWave.inject_at(fish, Vector3(0.2, 1.0, 0.0), 0.85)
	_assert(failed, hit != null, "soak inject finds a schooler")
	if hit is Fish:
		var ag0: float = float((hit as Fish).motion_agitation)
		_assert(failed, ag0 > 0.5, "soak inject raises agitation")
		_MotionWave.tick(fish, 0.025 * 16.0)
		_assert(failed, float((hit as Fish).motion_agitation) > ag0 * 0.35,
			"one 16× sim tick does not instantly zero agitation")
	parent.queue_free()


func _test_script_todos(failed: Array[String]) -> void:
	var dir := DirAccess.open("res://scripts")
	if dir == null:
		return
	var offenders: Array[String] = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".gd") and not name.begins_with("smoke_"):
			var text := FileAccess.get_file_as_string("res://scripts/" + name)
			if text.contains("# TODO") or text.contains("#TODO"):
				offenders.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	_assert(failed, offenders.is_empty(),
		"production scripts should not carry TODO markers: %s" % ", ".join(offenders))


func _test_residents_signals(failed: Array[String]) -> void:
	var sim_script: Script = load("res://scripts/sim_driver.gd")
	_assert(failed, sim_script != null, "sim_driver loads")
	if sim_script == null:
		return
	var inst: Object = sim_script.new()
	_assert(failed, inst.has_signal("creature_added"), "creature_added signal exists")
	_assert(failed, inst.has_signal("creature_removed"), "creature_removed signal exists")


func _test_intent_decay(failed: Array[String]) -> void:
	var dir_script: Script = load("res://scripts/ai_director.gd")
	var dir: Node = dir_script.new() as Node
	root.add_child(dir)
	dir.set("_intent_cells", [null, {"drift": Vector3(0.1, 0.0, 0.0), "intensity": 0.8}])
	dir.set("_intent_last_refresh_unix", int(Time.get_unix_time_from_system()) - 120)
	if dir.has_method("_decay_intent_staleness"):
		dir.call("_decay_intent_staleness", 1.0)
	var cells: Array = dir.get("_intent_cells")
	_assert(failed, cells[1] == null or float((cells[1] as Dictionary).get("intensity", 1.0)) < 0.5,
		"stale intent cells decay")
	dir.queue_free()


func _assert(failed: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		failed.append(msg)
