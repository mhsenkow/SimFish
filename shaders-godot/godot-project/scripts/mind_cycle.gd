extends RefCounted

# CONSCIOUSNESS_ENGINEERING §C — formal cognitive cycle wiring existing ticks.

const GlobalWorkspace = preload("res://scripts/global_workspace.gd")
const EpisodicMemory = preload("res://scripts/episodic_memory.gd")
const MindSelfModel = preload("res://scripts/mind_self_model.gd")
const MindScheduler = preload("res://scripts/mind_scheduler.gd")
const FishMindCore = preload("res://scripts/fish_mind.gd")

enum Phase { PERCEIVE, APPRAISE, ATTEND, BROADCAST, DELIBERATE, ENCODE, LEARN }


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


static func run_attention_phase(f: Fish, sim: Node, ms) -> void:
	if not workspace_enabled():
		FishMindCore.tick_attention(f, sim)
		return
	EpisodicMemory.retrieve_for_situation(f, f.attention_focus if f.attention_focus != "" else "idle", 2)
	var bids: Array = GlobalWorkspace.collect_bids(f, sim)
	var result: Dictionary = GlobalWorkspace.run_competition(bids)
	GlobalWorkspace.broadcast(f, result, ms)
	ms.self_model = MindSelfModel.build(f, ms.workspace)
	ms.meta_states = MindSelfModel.tick_higher_order(f, ms.self_model, 0.016)


static func run_encode_phase(f: Fish, ms) -> void:
	if ms.workspace_ignited:
		GlobalWorkspace.encode_from_workspace(f, ms)
		if not ms.workspace.is_empty():
			var primary: Dictionary = ms.workspace[0]
			var label: String = str(primary.get("label", "moment"))
			var enc_text: String = f.workspace_thought_for(label)
			EpisodicMemory.encode_episode(f, label, enc_text,
					float(primary.get("salience", 0.5)), f.position)


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
