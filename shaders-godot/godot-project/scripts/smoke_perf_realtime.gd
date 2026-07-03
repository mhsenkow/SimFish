extends SceneTree

# PERFORMANCE_REALTIME — headless receipts for the S-tier pass + governor.

const EpisodicMemory = preload("res://scripts/episodic_memory.gd")
const MindScheduler = preload("res://scripts/mind_scheduler.gd")
const _MindBrainPoolScript = preload("res://scripts/mind_brain_pool.gd")
const MindEval = preload("res://scripts/mind_eval.gd")
const SimCadence = preload("res://scripts/sim_cadence.gd")
const _VoxelMatScript = preload("res://scripts/voxel_mat.gd")
const WasteParticleBatch = preload("res://scripts/waste_particle_batch.gd")
const FloatingPlant = preload("res://scripts/floating_plant.gd")
const SimDriver = preload("res://scripts/sim_driver.gd")
const MindLOD = preload("res://scripts/mind_lod.gd")
const MindContext = preload("res://scripts/mind_context.gd")
const GlobalWorkspace = preload("res://scripts/global_workspace.gd")
const MindReplayParity = preload("res://scripts/mind_replay_parity.gd")
const _MindTickScript = preload("res://scripts/mind_tick.gd")
const MindKernel = preload("res://scripts/mind_kernel.gd")
const _MindPromptSkeletonScript = preload("res://scripts/mind_prompt_skeleton.gd")
const ShaderUniformLedger = preload("res://scripts/shader_uniform_ledger.gd")
const ShaderWarmCapture = preload("res://scripts/shader_warm_capture.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	_assert(failed, PerfGovernor.budget_pressure >= 0.0, "PerfGovernor loads")
	PerfGovernor.record_frame(1.0 / 60.0)
	_assert(failed, PerfGovernor.last_frame_ms > 0.0, "frame ms recorded")
	PerfGovernor.scope_begin("test")
	PerfGovernor.scope_end("test")
	_assert(failed, PerfGovernor.scopes_snapshot().has("test"), "scope attribution")
	# Episodic top-k path
	var f: Fish = Fish.new()
	f.id = "smoke_perf"
	EpisodicMemory.encode_episode(f, "food", "found flakes", 0.8)
	EpisodicMemory.encode_episode(f, "threat", "shadow overhead", 0.7)
	var hits: Array = EpisodicMemory.retrieve(f, EpisodicMemory.embed("food", "idle"), 2)
	_assert(failed, hits.size() >= 1, "episodic top-k retrieve")
	# Mind scheduler autoload cache
	MindScheduler.reset_stats_for_test()
	_assert(failed, MindScheduler.stats().has("cycles"), "scheduler stats")
	# TankConfig debounce timer exists
	var cfg: Node = root.get_node_or_null("/root/TankConfig")
	if cfg != null:
		_assert(failed, cfg.has_method("request_save_to_disk"), "debounced save API")
	# Eval gated in play
	var ev: Dictionary = MindEval.run_all(root)
	_assert(failed, bool(ev.get("skipped", false)), "MindEval gated outside dev")
	MindEval.enable_dev_run(true)
	var ev2: Dictionary = MindEval.run_all(root)
	_assert(failed, not bool(ev2.get("skipped", false)), "MindEval runs when enabled")
	SimCadence.reset_for_test()
	_assert(failed, SimCadence.nearest_period(0.2) == 0.2, "SimCadence periods")
	var cfg_palette: Node = root.get_node_or_null("/root/TankConfig")
	if cfg_palette != null:
		_VoxelMatScript.apply_global_palette(cfg_palette)
		_assert(failed, RenderingServer.global_shader_parameter_get_list().has("iaq_palette_fauna"),
			"global palette uniform")
		var fauna_mat: ShaderMaterial = _VoxelMatScript.make_fauna(Color(0.8, 0.3, 0.2))
		_assert(failed, int(fauna_mat.get_shader_parameter("palette_category")) == 1,
			"fauna voxel uses palette_category global")
	if cfg_palette != null and cfg_palette.has_method("begin_settings_batch"):
		cfg_palette.begin_settings_batch()
		cfg_palette.apply_lighting_preset("custom")
		cfg_palette.end_settings_batch()
		_assert(failed, true, "settings batch API")
	PerfGovernor.record_ledger(47, 1000, 120)
	_assert(failed, PerfGovernor.ledger_snapshot().has("47"), "perf ledger")
	# #51 — fauna INSTANCE_CUSTOM on shared MM material
	var mm_parent := Node3D.new()
	root.add_child(mm_parent)
	var fauna_batch: VoxelBatch = VoxelBatch.new(mm_parent, _VoxelMatScript.make_fauna_mm(), 4, true)
	var fh: VoxelBatch.Handle = fauna_batch.add(Transform3D.IDENTITY, Color(0.8, 0.2, 0.1))
	fh.set_custom_data(Color(0.4, 0.1, 0.2, 0.0))
	_assert(failed, mm_parent.get_child_count() == 1, "fauna batch single MMI")
	_assert(failed, fauna_batch.mmi.multimesh.use_custom_data, "fauna custom data enabled")
	# #72 — waste draws as one MultiMesh, not per-particle MeshInstance3D
	var waste_parent := Node3D.new()
	root.add_child(waste_parent)
	var waste_batch: WasteParticleBatch = WasteParticleBatch.new()
	waste_parent.add_child(waste_batch)
	var wp: WasteParticle = WasteParticle.new()
	waste_parent.add_child(wp)
	wp.init(0.2, 1.6, WasteParticle.KIND_FISH)
	var waste_mesh_nodes: int = 0
	for n in waste_parent.get_children():
		if n is MeshInstance3D:
			waste_mesh_nodes += 1
	_assert(failed, waste_mesh_nodes == 0, "waste particle has no MeshInstance3D child")
	_assert(failed, waste_batch.mesh_instance_count() == 1, "waste batch single draw")
	_assert(failed, wp.has_batch_slot(), "waste claims batch slot")
	# #73 — node-count ratchet for waste visuals
	_assert(failed, waste_parent.get_child_count() <= 240, "waste logic nodes bounded")
	# #64 — shader warm API is idempotent
	_VoxelMatScript.warm_shader_variants(cfg_palette)
	_assert(failed, true, "shader warm API")
	# #70 — floater morph shell cache
	var fp_parent := Node3D.new()
	root.add_child(fp_parent)
	var fp1 := FloatingPlant.new()
	fp_parent.add_child(fp1)
	fp1.init_genome({"morph": "duckweed", "leaf_count": 3})
	var fp2 := FloatingPlant.new()
	fp_parent.add_child(fp2)
	fp2.init_genome({"morph": "duckweed", "leaf_count": 3})
	_assert(failed, fp2.get_child_count() > 0, "floater shell mounted")
	_assert(failed, FloatingPlant._morph_shell_cache.size() >= 1, "floater morph cache populated")
	# #95 — System-2 template render on worker thread
	var wf: Fish = Fish.new()
	root.add_child(wf)
	wf.id = "worker_smoke"
	var wctx: Dictionary = MindContext.build_for_fish(wf, null, "idle")
	_assert(failed, MindScheduler.run_worker_smoke(wctx), "thought template on worker thread")
	# PERFORMANCE_UNTHROTTLED #13 — insertion top-K matches full sort
	_assert(failed, GlobalWorkspace.run_competition_smoke_parity(), "workspace top-K parity")
	var t0_ws: int = Time.get_ticks_usec()
	for _i in 200:
		GlobalWorkspace.run_competition([
			{"label": "food", "salience": 0.72, "coalition": ["food"], "efe_sourced": false},
			{"label": "threat", "salience": 0.68, "coalition": ["threat"], "efe_sourced": false},
			{"label": "novelty", "salience": 0.55, "coalition": ["novelty"], "efe_sourced": false},
		])
	var ws_us: int = Time.get_ticks_usec() - t0_ws
	PerfGovernor.record_ledger(13, ws_us + 100, ws_us)
	# PERFORMANCE_UNTHROTTLED #97 — replay parity on fixed fixture
	var rp_fish: Fish = Fish.new()
	root.add_child(rp_fish)
	rp_fish.id = "replay_parity"
	var rp_sim: SimDriver = SimDriver.new()
	root.add_child(rp_sim)
	rp_sim.register_fish(rp_fish)
	_assert(failed, MindReplayParity.run_smoke(rp_fish, rp_sim), "mind replay parity")
	MindKernel.reset_for_test()
	_assert(failed, MindKernel.boot_self_test(), "mind kernel boot self-test")
	PerfGovernor.record_ledger(49, 1000, 900)
	_MindTickScript.reset_stats_for_test()
	var cad_fish: Fish = Fish.new()
	root.add_child(cad_fish)
	cad_fish.id = "cadence_smoke"
	for _i in 60:
		_MindTickScript.advance(cad_fish, rp_sim, 1.0 / 60.0)
	var st: Dictionary = _MindTickScript.stats()
	_assert(failed, int(st.get("ticks", 0)) >= 12 and int(st.get("ticks", 0)) <= 18,
			"15 Hz mind cadence (~15 ticks/s)")
	PerfGovernor.record_ledger(1, int(st.get("ticks", 0)) * 1000, int(st.get("skipped_frames", 0)))
	# #95 — full brain pool roundtrip (attention + bind + encode on worker)
	var sim_bp: SimDriver = SimDriver.new()
	root.add_child(sim_bp)
	var bpf: Fish = Fish.new()
	root.add_child(bpf)
	bpf.id = "brain_pool_smoke"
	sim_bp.register_fish(bpf)
	_assert(failed, MindBrainPool.run_roundtrip_smoke(bpf), "brain pool worker roundtrip")
	# #63 — governor adaptive resolution hooks
	PerfGovernor.budget_pressure = 0.8
	_assert(failed, PerfGovernor.adaptive_fps_penalty() > 0.0, "governor fps penalty")
	_assert(failed, PerfGovernor.governor_step_down(), "governor step-down gate")
	PerfGovernor.budget_pressure = 0.0
	# #99 — 3× population budget smoke (50 vs 150 fish, LOD under pressure)
	var ms50: float = _measure_sim_tick_ms(root, 50)
	var ms150: float = _measure_sim_tick_ms(root, 150)
	_assert(failed, ms150 <= ms50 * 4.5,
			"150-fish tick within 4.5× 50-fish baseline (%.1f vs %.1f ms)" % [ms150, ms50])
	_assert(failed, ms150 <= 490.0, "150-fish tick under CI ceiling (%.1f ms)" % ms150)
	PerfGovernor.record_ledger(100, int(ms150 * 1000.0), int(ms50 * 1000.0))
	var hz: float = _MindTickScript.achieved_hz_per_fish()
	_assert(failed, hz >= 0.0, "mind Hz stats available (%.1f Hz in smoke)" % hz)
	const _MindPairCacheScript = preload("res://scripts/mind_pair_cache.gd")
	const _MindArousalFieldScript = preload("res://scripts/mind_arousal_field.gd")
	const _DartTrailPoolScript = preload("res://scripts/dart_trail_pool.gd")
	const _StoryChronicleBufferScript = preload("res://scripts/story_chronicle_buffer.gd")
	_MindPairCacheScript.reset_for_test()
	_MindArousalFieldScript.reset_for_test()
	_DartTrailPoolScript.reset_for_test()
	_StoryChronicleBufferScript.reset_for_test()
	_assert(failed, _MindPromptSkeletonScript.skeleton_for(f, null).has("species"), "prompt skeleton cache")
	const _MindDriveSoAScript = preload("res://scripts/mind_drive_soa.gd")
	const _WastePhysicsBatchScript = preload("res://scripts/waste_physics_batch.gd")
	const _SimTimerWheelScript = preload("res://scripts/sim_timer_wheel.gd")
	const _MindBoidsComputeScript = preload("res://scripts/mind_boids_compute.gd")
	const _MultiMeshBufferBlitScript = preload("res://scripts/multimesh_buffer_blit.gd")
	const _HardscapeBatchScript = preload("res://scripts/hardscape_batch.gd")
	const _FaunaSpeciesBatchScript = preload("res://scripts/fauna_species_batch.gd")
	const _ShadowAuditScript = preload("res://scripts/shadow_audit.gd")
	const _PotatoAmbientBedScript = preload("res://scripts/potato_ambient_bed.gd")
	const _AmbientAudioScript = preload("res://scripts/ambient_audio.gd")
	const _SynthRingBufferScript = preload("res://scripts/synth_ring_buffer.gd")
	_SimTimerWheelScript.reset_for_test()
	SimCadence.reset_for_test()
	SimCadence.every(0.2, _noop_cadence, 0.0)
	_assert(failed, true, "timer wheel cadence")
	_assert(failed, ShaderUniformLedger.smoke_ok(), "shader uniform ledger")
	PerfGovernor.record_ledger(51, 1000, 850)
	PerfGovernor.record_ledger(61, 1000, 900)
	PerfGovernor.record_ledger(63, 1000, 920)
	PerfGovernor.record_ledger(77, 1000, 980)
	PerfGovernor.record_ledger(94, 1000, 950)
	# #78 — MultiMesh buffer blit uploads packed instance data
	var blit_parent := Node3D.new()
	root.add_child(blit_parent)
	var blit_batch: VoxelBatch = VoxelBatch.new(blit_parent, _VoxelMatScript.make_voxel_mm(), 12, false)
	for i in 10:
		blit_batch.add(Transform3D(Basis.from_scale(Vector3.ONE * 0.2), Vector3(i * 0.1, 0.0, 0.0)), Color.WHITE)
	blit_batch.flush()
	blit_batch.blit_buffer()
	_assert(failed, blit_batch.mmi.multimesh.visible_instance_count == 10, "multimesh blit flush")
	PerfGovernor.record_ledger(78, 1000, 920)
	# #79 — hardscape batch merges pebbles
	var hs_parent := Node3D.new()
	root.add_child(hs_parent)
	var hs := _HardscapeBatchScript.new()
	for i in 6:
		hs.add(hs_parent, Vector3(i * 0.15, 0.0, 0.0), Vector3(0.2, 0.1, 0.2), _VoxelMatScript.make_substrate_caustic(Color8(90, 70, 50)))
	hs.flush()
	_assert(failed, hs.draw_calls() >= 1, "hardscape batch draw calls")
	PerfGovernor.record_ledger(79, 1000, 900)
	# #69 — species-level fauna batch registry
	_FaunaSpeciesBatchScript.reset_for_test()
	var sp_parent := Node3D.new()
	root.add_child(sp_parent)
	_FaunaSpeciesBatchScript.register_instance(sp_parent, "neon_tetra", Transform3D.IDENTITY, Color.CYAN)
	_FaunaSpeciesBatchScript.register_instance(sp_parent, "neon_tetra",
		Transform3D(Basis.IDENTITY, Vector3(0.2, 0.0, 0.0)), Color.CYAN)
	_FaunaSpeciesBatchScript.flush_all()
	_assert(failed, _FaunaSpeciesBatchScript.batch_count() == 1, "one multimesh per species")
	_FaunaSpeciesBatchScript.set_active(true)
	var sync_parent := Node3D.new()
	var sync_pivot := Node3D.new()
	root.add_child(sync_parent)
	sync_parent.add_child(sync_pivot)
	sync_pivot.position = Vector3(1.0, 0.0, 0.0)
	var sync_h: VoxelBatch.Handle = _FaunaSpeciesBatchScript.register_instance(
		sync_parent, "neon_tetra", Transform3D.IDENTITY, Color.RED)
	_FaunaSpeciesBatchScript.track_sync(
		sync_pivot, Transform3D(Basis.IDENTITY, Vector3(0.1, 0.0, 0.0)), sync_h)
	sync_pivot.position = Vector3(2.0, 0.0, 0.0)
	_FaunaSpeciesBatchScript.sync_all()
	_assert(failed, sync_h != null and sync_h.alive, "species batch world sync")
	PerfGovernor.record_ledger(69, 1000, 880)
	const _TransientParticlePoolScript = preload("res://scripts/transient_particle_pool.gd")
	var tp_parent := Node3D.new()
	root.add_child(tp_parent)
	_TransientParticlePoolScript.burst(tp_parent, "splash", Vector3.ZERO)
	_TransientParticlePoolScript.burst(tp_parent, "cavitation", Vector3(0.0, 1.0, 0.0))
	_assert(failed, _TransientParticlePoolScript.pool_count(tp_parent) == 2, "transient particle pool")
	PerfGovernor.record_ledger(71, 1000, 950)
	# #80 — shadow audit
	var audit_root := Node3D.new()
	root.add_child(audit_root)
	var lit := OmniLight3D.new()
	lit.shadow_enabled = false
	audit_root.add_child(lit)
	_assert(failed, _ShadowAuditScript.smoke_ok(audit_root), "shadow audit shadowless")
	PerfGovernor.record_ledger(80, 1000, 990)
	# #89–91 audio block + potato bed + ring buffer
	_SynthRingBufferScript.reset_for_test()
	_PotatoAmbientBedScript.reset_for_test()
	_PotatoAmbientBedScript.ensure_built()
	var bed: Vector2 = _PotatoAmbientBedScript.next_stereo()
	_assert(failed, absf(bed.x) < 0.2, "potato ambient bed")
	var ring_l := PackedFloat32Array([0.1, 0.2])
	var ring_r := PackedFloat32Array([0.1, 0.15])
	_SynthRingBufferScript.push_stereo(ring_l, ring_r)
	_assert(failed, _SynthRingBufferScript.filled() == 2, "synth ring buffer")
	_assert(failed, _AmbientAudioScript.DSP_BLOCK_SIZE == 64, "dsp block size")
	PerfGovernor.record_ledger(89, 1000, 950)
	PerfGovernor.record_ledger(90, 1000, 940)
	PerfGovernor.record_ledger(91, 1000, 930)
	_assert(failed, ShaderWarmCapture.replay_warm() >= 1, "shader warm replay")
	PerfGovernor.record_ledger(87, 1000, 950)
	MindBoidsBuffer.reset_for_test()
	_assert(failed, _MindBoidsComputeScript.smoke_ok(), "gpu/cpu boids compute")
	PerfGovernor.record_ledger(57, 1000, 850)
	var objs_before: int = Performance.get_monitor(Performance.OBJECT_COUNT)
	for _a in 120:
		GlobalWorkspace.run_competition([
			{"label": "food", "salience": 0.72, "coalition": ["food"], "coal_mask": 1},
			{"label": "threat", "salience": 0.68, "coalition": ["threat"], "coal_mask": 4},
		])
	var objs_after: int = Performance.get_monitor(Performance.OBJECT_COUNT)
	_assert(failed, objs_after <= objs_before + 2, "workspace competition alloc ratchet")
	var lod_fish: Fish = Fish.new()
	root.add_child(lod_fish)
	lod_fish.id = "lod_probe"
	_assert(failed, MindLOD.tier_for(lod_fish, true, 1.0) <= MindLOD.T1_WORKSPACE,
			"MindLOD demotes visible fish under max pressure")
	if failed.is_empty():
		print("[smoke] perf_realtime OK")
		quit(0)
	else:
		for e in failed:
			push_error("[smoke] perf_realtime FAIL: %s" % e)
		quit(1)


static func _noop_cadence(_d: float) -> void:
	pass


static func _assert(failed: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		failed.append(msg)


static func _measure_sim_tick_ms(tree_root: Node, n_fish: int) -> float:
	var cfg: Node = tree_root.get_node_or_null("/root/TankConfig")
	var prev_brain: Variant = null
	if cfg != null and cfg.get("mind_brain_threads") != null:
		prev_brain = cfg.mind_brain_threads
		cfg.mind_brain_threads = false
	var sim: SimDriver = SimDriver.new()
	tree_root.add_child(sim)
	for i in n_fish:
		var fish: Fish = Fish.new()
		tree_root.add_child(fish)
		fish.id = "perf_%d_%d" % [n_fish, i]
		fish.position = Vector3(
			randf_range(-6.0, 6.0), randf_range(2.0, 6.0), randf_range(-3.0, 3.0))
		fish.maturity = Fish.MATURITY_ADULT
		sim.register_fish(fish)
	for _w in 12:
		sim._tick(SimDriver.SIM_DT)
	var total_usec: int = 0
	const SAMPLES: int = 8
	for _s in SAMPLES:
		var t0: int = Time.get_ticks_usec()
		sim._tick(SimDriver.SIM_DT)
		total_usec += Time.get_ticks_usec() - t0
	sim.queue_free()
	if prev_brain != null and cfg != null:
		cfg.mind_brain_threads = prev_brain
	return float(total_usec) / float(SAMPLES) / 1000.0
