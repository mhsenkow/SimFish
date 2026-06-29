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

enum Phase { PERCEIVE, APPRAISE, ATTEND, BROADCAST, DELIBERATE, ENCODE, LEARN, BIND }


static func _tank_config() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return null
	var st: SceneTree = ml as SceneTree
	if st == null or st.root == null or not st.root.is_inside_tree():
		return null
	return st.root.get_node_or_null("/root/TankConfig")


static func workspace_enabled() -> bool:
	var cfg: Node = _tank_config()
	if cfg == null:
		return true
	return bool(cfg.get("consciousness_workspace_enabled") if cfg.get("consciousness_workspace_enabled") != null else true)


static func run_perceive_phase(f: Fish, sim: Node, _ms, dt: float) -> void:
	if not FishBinding.layer_enabled():
		return
	FishProtoself.tick(f, sim, dt)
	FishCoreAffect.tick(f, sim, dt)


static func run_attention_phase(f: Fish, sim: Node, ms, dt: float = 0.016) -> void:
	run_perceive_phase(f, sim, ms, dt)
	if not workspace_enabled():
		FishMindCore.tick_attention(f, sim)
		return
	EpisodicMemory.retrieve_for_situation(f, f.attention_focus if f.attention_focus != "" else "idle", 2)
	var bids: Array = GlobalWorkspace.collect_bids(f, sim)
	if FishBinding.layer_enabled():
		bids = FishRelevance.realize(f, sim, bids, dt)
	var result: Dictionary = GlobalWorkspace.run_competition(bids)
	GlobalWorkspace.broadcast(f, result, ms)
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
			ms.meta_states.append(ho)


static func run_bind_phase(f: Fish, sim: Node, ms, dt: float) -> void:
	if not FishBinding.layer_enabled():
		return
	FishFeltNow.tick(f, ms, dt)
	FishGenerativeSelf.tick(f, sim, dt)
	FishConcepts.tick(f, sim, dt)
	FishQualia.tick(f, sim, dt)
	FishVolition.tick(f, sim, dt)
	FishContinuity.tick(f, sim, dt)
	FishBinding.bind_moment(f, ms, dt)


static func run_encode_phase(f: Fish, ms) -> void:
	if ms.workspace_ignited:
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
					enc_text, float(ms.workspace[0].get("salience", 0.5) if not ms.workspace.is_empty() else 0.5),
					f.position)


static func tick_post_cycle(f: Fish, sim: Node, dt: float) -> void:
	EpisodicMemory.tick_decay(f, dt)
	MindSelfModel.tick_trait_change_notice(f, dt)
	if f._asleep and f._dreaming:
		EpisodicMemory.consolidate_sleep(f)
	var rich: bool = f.is_guardian or f.fish_name != "" or f.familiarity > 0.4
	if rich:
		MindScheduler.tick_fish(f, sim, dt)


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
