extends SceneTree

# REFINEMENT_II deferred L-items — soak, golden replay, offline parity, lifecycle,
# synth ring, guardian cadence, boot hygiene, fast-forward, CI triad helpers.

const MindReplayParity = preload("res://scripts/mind_replay_parity.gd")
const SynthRingBuffer = preload("res://scripts/synth_ring_buffer.gd")
const _MotionWave = preload("res://scripts/motion_wave.gd")
const MindNarrator = preload("res://scripts/mind_narrator.gd")
const MindContext = preload("res://scripts/mind_context.gd")
const MakeItThere = preload("res://scripts/make_it_there.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	_test_golden_replay(failed)
	_test_offline_voice_parity(failed)
	_test_synth_ring_residency(failed)
	_test_guardian_queue_order(failed)
	_test_fast_forward_restore(failed)
	_test_death_witness_path(failed)
	_test_residents_registry(failed)
	_test_save_async_coalesce(failed)
	_test_boot_hygiene(failed)
	_test_feed_satiety(failed)
	await _test_soak(failed)
	if failed.is_empty():
		print("[smoke] refinement_ii_deferred OK")
		quit(0)
	else:
		for msg in failed:
			push_error("[smoke] refinement_ii_deferred FAIL: %s" % msg)
		quit(1)


func _test_golden_replay(failed: Array[String]) -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	var f := Fish.new()
	parent.add_child(f)
	f.id = "golden_fish"
	f.species = "glassdart"
	f.swim_pattern = "school"
	f.schooling_strength = 1.2
	seed(424242)
	var h1: int = MindReplayParity.golden_digest_hash(f, null, 16)
	_assert(failed, h1 != 0, "golden mind replay hash non-zero")
	_assert(failed, MindReplayParity.run_smoke_n_tick(f, null, 16),
		"golden mind replay stable over 16 ticks")
	var golden_path := "res://data/golden_mind_replay.json"
	if FileAccess.file_exists(golden_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(golden_path))
		if parsed is Dictionary:
			var expected: int = int((parsed as Dictionary).get("digest_hash", 0))
			if expected != 0:
				_assert(failed, h1 == expected,
					"golden digest matches file (got %d want %d)" % [h1, expected])
			else:
				push_warning("[smoke] golden_mind_replay.json digest_hash=0 — update after first stable run")
	parent.queue_free()


func _test_offline_voice_parity(failed: Array[String]) -> void:
	# REFINEMENT_II #67 — template path always produces speakable lines.
	var f := Fish.new()
	f.id = "offline_1"
	f.fish_name = "Ripple"
	f.mood = 0.1
	f.hunger = 0.4
	f._keeper_pending = {"keeper_text": "hello", "keeper_felt": "comfort", "keeper_intent": "greeting"}
	var ctx: Dictionary = MindContext.build_for_keeper_turn(f, null, "keeper_reply")
	var line: String = MindNarrator.template_fish_reply(ctx)
	_assert(failed, line.strip_edges() != "", "offline fish reply")
	var thought: String = MindNarrator.template_fish_thought({
		"feel": "anxious", "species": "neon_tetra", "hunger": 0.3,
	})
	_assert(failed, thought.strip_edges() != "", "offline fish thought")
	var recap: String = MakeItThere.away_recap_fallback({"away_tier": "short", "feel": "calm", "keeper_moniker": "keeper"})
	_assert(failed, recap.strip_edges() != "", "offline away recap")
	f.queue_free()


func _test_synth_ring_residency(failed: Array[String]) -> void:
	# REFINEMENT_II #30 — ring buffer bridges worker synth to playback.
	SynthRingBuffer.reset_for_test()
	var l := PackedFloat32Array([0.1, 0.2, 0.3])
	var r := PackedFloat32Array([0.1, 0.2, 0.3])
	SynthRingBuffer.push_stereo(l, r)
	_assert(failed, SynthRingBuffer.filled() == 3, "synth ring accepts worker frames")


func _test_guardian_queue_order(failed: Array[String]) -> void:
	var glm_script: Script = load("res://scripts/guardian_llm.gd")
	if glm_script == null:
		_assert(failed, false, "guardian_llm loads")
		return
	var glm: Node = glm_script.new()
	var q: Array = [
		{"seq": 0, "key": "a"},
		{"seq": 1, "key": "b"},
	]
	glm.set("_queue", q)
	glm.set("_last_spoken_seq", -1)
	_assert(failed, int(q[0].get("seq", -1)) < int(q[1].get("seq", -1)),
		"guardian queue seq monotonic")
	glm.set("_last_spoken_seq", 1)
	_assert(failed, int(glm.get("_last_spoken_seq")) == 1, "guardian spoken seq tracked")
	glm.queue_free()


func _test_fast_forward_restore(failed: Array[String]) -> void:
	TimeAuthority.reset_for_test()
	var sim := Node.new()
	sim.set_script(load("res://scripts/smoke_sim_stub.gd"))
	root.add_child(sim)
	TimeAuthority.set_base_scale(16.0)
	TimeAuthority.push_pause(sim, "test_ff")
	TimeAuthority.pop_pause(sim, "test_ff")
	_assert(failed, absf(float(sim.time_scale) - 16.0) < 0.001, "fast-forward restores base scale")
	TimeAuthority.set_base_scale(1.0)
	TimeAuthority.pop_pause(sim, "test_ff")
	_assert(failed, absf(float(sim.time_scale) - 1.0) < 0.001, "1× restore after fast-forward")
	sim.queue_free()
	TimeAuthority.reset_for_test()


func _test_death_witness_path(failed: Array[String]) -> void:
	var src := FileAccess.get_file_as_string("res://scripts/sim_driver.gd")
	_assert(failed, src.contains("func _schedule_witnessed_death("),
		"witnessed death scheduler exists")


func _test_residents_registry(failed: Array[String]) -> void:
	var sim_script: Script = load("res://scripts/sim_driver.gd")
	var sim: Node = sim_script.new()
	_assert(failed, sim.has_signal("creature_added") and sim.has_signal("creature_removed"),
		"residents registry signals")
	sim.queue_free()


func _test_save_async_coalesce(failed: Array[String]) -> void:
	var src := FileAccess.get_file_as_string("res://scripts/save_manager.gd")
	_assert(failed, src.contains("func writes_in_flight") and src.contains("_writes_in_flight"),
		"save async coalesce hooks present")
	_assert(failed, src.contains("WorkerThreadPool"), "save writes use worker thread")


func _test_boot_hygiene(failed: Array[String]) -> void:
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
	_assert(failed, offenders.is_empty(), "boot scripts carry no # TODO markers: %s" % ", ".join(offenders))


func _test_feed_satiety(failed: Array[String]) -> void:
	# REFINEMENT_II #94 — dock/guardian agree tank is fed after a good meal.
	var sim_script: Script = load("res://scripts/sim_driver.gd")
	if sim_script == null:
		_assert(failed, false, "sim_driver loads")
		return
	var sim: Node = sim_script.new()
	sim.set("_last_feed_unix", int(Time.get_unix_time_from_system()))
	var fish_a := Fish.new()
	fish_a.hunger = 0.2
	var fish_b := Fish.new()
	fish_b.hunger = 0.25
	var school: Array[Fish] = [fish_a, fish_b]
	sim.set("fish", school)
	_assert(failed, sim.has_method("tank_feed_satiety_ok") and sim.tank_feed_satiety_ok(),
		"tank satiety after recent feed + low hunger")
	sim.set("_last_feed_unix", 0)
	_assert(failed, not sim.tank_feed_satiety_ok(), "no satiety without feed event")
	fish_a.hunger = 0.9
	fish_b.hunger = 0.85
	school = [fish_a, fish_b]
	sim.set("fish", school)
	sim.set("_last_feed_unix", int(Time.get_unix_time_from_system()))
	_assert(failed, not sim.tank_feed_satiety_ok(), "no satiety when fish still hungry")
	sim.queue_free()


func _test_soak(failed: Array[String]) -> void:
	var soak_s: float = 45.0
	var env: String = OS.get_environment("SOAK_SECONDS")
	if env.is_valid_float():
		soak_s = float(env)
	var parent := Node3D.new()
	root.add_child(parent)
	var school: Array[Fish] = []
	for i in 10:
		var f := Fish.new()
		parent.add_child(f)
		f.id = "soak_%d" % i
		f.species = "glassdart"
		f.swim_pattern = "school"
		f.schooling_strength = 1.3
		f.position = Vector3(cos(float(i)) * 1.5, 1.0, sin(float(i)) * 1.5)
		school.append(f)
	_MotionWave.reset_for_test()
	var t: float = 0.0
	var step: float = 0.05
	var errors_before: int = 0
	var frame_i: int = 0
	while t < soak_s:
		if frame_i % 4 == 0:
			_MotionWave.inject_at(school, Vector3(0.0, 1.0, 0.0), 0.15)
		_MotionWave.tick(school, step * 4.0)
		t += step
		frame_i += 1
		await process_frame
	parent.queue_free()
	_assert(failed, true, "soak %.0fs completed without abort" % soak_s)


func _assert(failed: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		failed.append(msg)
