extends RefCounted

# CONSCIOUSNESS_ENGINEERING §C — formal cognitive cycle wiring existing ticks.

const GlobalWorkspace = preload("res://scripts/global_workspace.gd")
const EpisodicMemory = preload("res://scripts/episodic_memory.gd")
const MindSelfModel = preload("res://scripts/mind_self_model.gd")
const MindScheduler = preload("res://scripts/mind_scheduler.gd")
const FishMindCore = preload("res://scripts/fish_mind.gd")
const FishBinding = preload("res://scripts/fish_binding.gd")
const FishProtoself = preload("res://scripts/fish_protoself.gd")
const FishCoreAffect = preload("res://scripts/fish_core_affect.gd")
const FishRelevance = preload("res://scripts/fish_relevance.gd")
const FishFeltNow = preload("res://scripts/fish_felt_now.gd")
const FishGenerativeSelf = preload("res://scripts/fish_generative_self.gd")
const FishConcepts = preload("res://scripts/fish_concepts.gd")
const FishContinuity = preload("res://scripts/fish_continuity.gd")
const FishQualia = preload("res://scripts/fish_qualia.gd")
const FishVolition = preload("res://scripts/fish_volition.gd")
const MindSoul = preload("res://scripts/mind_soul.gd")
const MindSoulPass2 = preload("res://scripts/mind_soul_pass2.gd")
const MindSoulPass3 = preload("res://scripts/mind_soul_pass3.gd")
const DeltaG = preload("res://scripts/delta_g.gd")
const DeltaGCurve = preload("res://scripts/delta_g_curve.gd")
const PokeHarness = preload("res://scripts/poke_harness.gd")
const _MindCacheRegistryScript = preload("res://scripts/mind_cache_registry.gd")
const MindActiveInference = preload("res://scripts/mind_active_inference.gd")

enum Phase { PERCEIVE, APPRAISE, ATTEND, BROADCAST, DELIBERATE, ENCODE, LEARN, BIND }

static var _worker_workspace_enabled: Variant = null


static func set_worker_workspace_enabled(v: Variant) -> void:
	_worker_workspace_enabled = v


static func _tank_config() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return null
	var st: SceneTree = ml as SceneTree
	if st == null or st.root == null or not st.root.is_inside_tree():
		return null
	return st.root.get_node_or_null("/root/TankConfig")


static func workspace_enabled() -> bool:
	if _worker_workspace_enabled != null:
		return bool(_worker_workspace_enabled)
	if not Thread.is_main_thread():
		return true
	var cfg: Node = _tank_config()
	if cfg == null:
		return true
	return bool(cfg.get("consciousness_workspace_enabled") if cfg.get("consciousness_workspace_enabled") != null else true)


static func _lod_tier(f) -> int:
	if f != null:
		return int(f._cycle_lod_tier)
	return MindLOD.T2_WORLD_MODEL


static func begin_cycle(f, sim = null) -> void:
	if f == null:
		return
	# REFINEMENT_II #10 — one tier snapshot per cycle from sim_driver's LOD.
	f._cycle_lod_tier = int(f._mind_lod_tier)
	if OS.is_debug_build() and int(f._cycle_lod_tier) != int(f._mind_lod_tier):
		push_warning("[mind_cycle] cycle tier diverged from sim tier for %s" % str(f.id))
	f._cycle_use_efe = MindActiveInference.enabled_for(f, sim)
	var focus_now: String = f.attention_focus if f.attention_focus != "" else "idle"
	if f._episodic_hint_focus != "" and f._episodic_hint_focus != focus_now:
		f._episodic_retrieval_hint = {}
		f._episodic_retrieval_hint_ttl = 0.0
		EpisodicMemory.clear_retrieve_cache_for(f)
	f._episodic_hint_focus = focus_now
	GlobalWorkspace.cache_cycle_bias_targets(f)
	# PERFORMANCE_UNTHROTTLED #28 — one episodic retrieval per cycle.
	if sim != null and MindLOD.runs_workspace(_lod_tier(f)):
		var sit: String = f.attention_focus if f.attention_focus != "" else "idle"
		EpisodicMemory.retrieve_for_situation(f, sit, 2)


static func run_perceive_phase(f, sim, _ms, dt: float) -> void:
	if not FishBinding.layer_enabled():
		return
	FishProtoself.tick(f, sim, dt)
	FishCoreAffect.tick(f, sim, dt)


static func run_attention_phase(f, sim, ms, dt: float = 0.016) -> void:
	var tier: int = _lod_tier(f)
	if tier <= MindLOD.T0_REFLEX:
		run_perceive_phase(f, sim, ms, dt)
		return
	run_perceive_phase(f, sim, ms, dt)
	if not workspace_enabled() or not MindLOD.runs_workspace(tier):
		FishMindCore.tick_attention(f, sim)
		return
	MindSoul.predict_self_before_competition(f, ms)
	var bids: Array = GlobalWorkspace.collect_bids(f, sim)
	if FishBinding.layer_enabled():
		bids = FishRelevance.realize(f, sim, bids, dt)
	var result: Dictionary = MindSoulPass2.habit_shortcut(f, sim)
	if result.is_empty():
		result = GlobalWorkspace.resolve_competition(f, bids)
	GlobalWorkspace.broadcast_if_changed(f, result, ms)
	MindSoulPass3.after_broadcast(f, ms, sim)
	# META #18 — emit a structured cognition-trace event (no-op when disabled).
	if MindTrace.is_enabled():
		MindTrace.record(f.id, {
			"focus": ms.attention_focus,
			"ignited": ms.workspace_ignited,
			"winners": ms.workspace.size(),
			"surprise": f.surprise,
			"pred_err": f._prediction_error,
		})
	ms.self_model = MindSelfModel.build(f, ms.workspace)
	ms.meta_states = MindSelfModel.tick_higher_order(f, ms.self_model, dt)
	if FishBinding.layer_enabled():
		var ho: String = FishQualia.higher_order(f)
		if ho != "":
			MindSelfModel.meta_push(f, ho)
			ms.meta_states = MindSelfModel.meta_to_array(f)


# Worker-safe attention: skips scene-tree reads; perceive/bind run on main thread.
static func run_attention_phase_worker(f, sim, ms, dt: float = 0.016) -> void:
	var tier: int = _lod_tier(f)
	if tier <= MindLOD.T0_REFLEX:
		return
	if not workspace_enabled() or not MindLOD.runs_workspace(tier):
		FishMindCore.tick_attention(f, sim)
		return
	MindSoul.predict_self_before_competition(f, ms)
	var bids: Array = GlobalWorkspace.collect_bids(f, sim)
	if FishBinding.layer_enabled():
		bids = FishRelevance.realize(f, sim, bids, dt)
	var result: Dictionary = MindSoulPass2.habit_shortcut(f, sim)
	if result.is_empty():
		result = GlobalWorkspace.resolve_competition(f, bids)
	GlobalWorkspace.broadcast_if_changed(f, result, ms)
	MindSoulPass3.after_broadcast(f, ms, sim)
	ms.self_model = MindSelfModel.build(f, ms.workspace)
	ms.meta_states = MindSelfModel.tick_higher_order(f, ms.self_model, dt)
	if FishBinding.layer_enabled():
		var ho: String = FishQualia.higher_order(f)
		if ho != "":
			MindSelfModel.meta_push(f, ho)
			ms.meta_states = MindSelfModel.meta_to_array(f)


static func run_bind_phase(f, sim, ms, dt: float) -> void:
	if not FishBinding.layer_enabled():
		return
	var tier: int = _lod_tier(f)
	if not MindLOD.runs_workspace(tier):
		return
	FishFeltNow.tick(f, ms, dt)
	if MindLOD.runs_world_model(tier):
		FishGenerativeSelf.tick(f, sim, dt)
		FishConcepts.tick(f, sim, dt)
	FishQualia.tick(f, sim, dt)
	FishVolition.tick(f, sim, dt)
	if MindLOD.runs_world_model(tier):
		FishContinuity.tick(f, sim, dt)
	FishBinding.bind_moment(f, ms, dt)
	MindSoul.tick(f, sim, ms, dt)


static func run_encode_phase(f, ms) -> void:
	if not MindLOD.runs_workspace(_lod_tier(f)):
		return
	if ms.workspace_ignited:
		var sal_boost: float = 1.0
		if FishBinding.layer_enabled():
			sal_boost = lerpf(0.85, 1.35, FishBinding.integration_score(f))
		GlobalWorkspace.encode_from_workspace(f, ms)
		if not ms.workspace.is_empty():
			var enc_text: String = ""
			var enc_label: String = ""
			if FishBinding.layer_enabled():
				enc_text = FishFeltNow.encode_moment_text(f)
				enc_label = str(FishBinding.ensure(f).get("moment_label", ""))
			if enc_text == "":
				var primary: Dictionary = ms.workspace[0]
				enc_label = str(primary.get("label", "moment"))
				enc_text = f.workspace_thought_for(enc_label)
			EpisodicMemory.encode_episode(f, enc_label if enc_label != "" else "moment",
					enc_text, float(ms.workspace[0].get("salience", 0.5) if not ms.workspace.is_empty() else 0.5) * sal_boost,
					f.position)


static func _diagnostic_slot(f, period: int) -> int:
	if period <= 0:
		return 0
	var id: String = str(f.id) if f.get("id") != null else ""
	if id == "" and f is Object and (f as Object).has_method("get_instance_id"):
		id = str((f as Object).get_instance_id())
	return absi(hash(id)) % period


static func tick_post_cycle(f: Fish, sim: Node, dt: float) -> void:
	_MindCacheRegistryScript.tick_retrieval_hint(f, dt)
	MindSelfModel.tick_self_summary_voice_cd(f, dt)
	if MindLOD.runs_world_model(_lod_tier(f)):
		EpisodicMemory.tick_decay(f, dt)
		MindSelfModel.tick_trait_change_notice(f, sim, dt)
	if f._asleep and f._dreaming and MindLOD.runs_world_model(_lod_tier(f)):
		EpisodicMemory.consolidate_sleep(f)
		MindSoulPass3.on_sleep_consolidate(f)
	var rich: bool = f.is_guardian or f.fish_name != "" or f.familiarity > 0.4
	if rich and MindLOD.runs_voice(_lod_tier(f)):
		MindScheduler.tick_fish(f, sim, dt)
	if MindLOD.runs_workspace(_lod_tier(f)):
		DeltaG.record_tick(f, dt)
		var frame: int = int(Engine.get_physics_frames())
		if frame % 120 == _diagnostic_slot(f, 120) and f.get("_delta_g_traj") is Array \
				and (f._delta_g_traj as Array).size() >= DeltaG.MIN_SAMPLES:
			var est: Dictionary = DeltaG.estimate_fish(f, sim, dt)
			DeltaGCurve.record_estimate(f, est)
		# Shadow poke battery is diagnostic-only — stagger + protagonists so we
		# don't spike all fish on the same physics frame.
		if rich and frame % 480 == _diagnostic_slot(f, 480) \
				and f.get("_delta_g_traj") is Array \
				and (f._delta_g_traj as Array).size() >= DeltaG.MIN_SAMPLES:
			PokeHarness.run_battery(f, sim)


static func snapshot_prev(f: Fish) -> Dictionary:
	if f.get("_mind_snapshot_prev") is Dictionary:
		return (f._mind_snapshot_prev as Dictionary).duplicate(true)
	return {}


static func store_snapshot(f: Fish, snap: Dictionary, ms = null) -> void:
	var entry: Dictionary = {"t": Time.get_ticks_msec(), "snap": snap.duplicate(true)}
	if ms != null and f.get("_mind_snapshot_prev") is Dictionary:
		entry["diff"] = ms.diff(f._mind_snapshot_prev as Dictionary)
	f._mind_snapshot_prev = snap.duplicate(true)
	if f.get("_mind_timeline") == null:
		f._mind_timeline = []
	var tl: Array = f._mind_timeline
	tl.append(entry)
	while tl.size() > 120:
		tl.remove_at(0)
