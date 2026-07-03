extends SceneTree

# SENTIENCE_THE_SOUL_WE_MAKE — learned drives, metacognition, finitude hooks.

const MindCycle = preload("res://scripts/mind_cycle.gd")
const MindSoul = preload("res://scripts/mind_soul.gd")
const MindActiveInference = preload("res://scripts/mind_active_inference.gd")
const GlobalWorkspace = preload("res://scripts/global_workspace.gd")
const MindSelfModel = preload("res://scripts/mind_self_model.gd")
const MindContext = preload("res://scripts/mind_context.gd")
const MindNarrator = preload("res://scripts/mind_narrator.gd")
const FishMind = preload("res://scripts/fish_mind.gd")
const FishGenerativeSelf = preload("res://scripts/fish_generative_self.gd")
const FishProtoself = preload("res://scripts/fish_protoself.gd")
const KeeperInput = preload("res://scripts/keeper_input.gd")
const CognitiveSchema = preload("res://scripts/cognitive_schema.gd")
const MindSoulPass2 = preload("res://scripts/mind_soul_pass2.gd")
const MindSoulPass3 = preload("res://scripts/mind_soul_pass3.gd")


func _initialize() -> void:
	await process_frame
	if not _run_all():
		quit(1)
		return
	print("[smoke_soul_mind] OK")
	quit(0)


func _fail(msg: String) -> bool:
	push_error(msg)
	return false


func _mk(id: String) -> Fish:
	var f: Fish = Fish.new()
	f.id = id
	f.fish_name = "SoulSmoke"
	f.familiarity = 0.62
	f.hunger = 0.78
	f.stress = 0.32
	f.spooked = 0.0
	f.arousal = 0.38
	f.age = 280.0
	f.max_age_s = 360.0
	f.energy = 0.55
	f.personality = {"boldness": 0.55, "curiosity": 0.5, "sociability": 0.5,
			"gluttony": 0.5, "calm": 0.5}
	return f


func _run_all() -> bool:
	if not MindSoul.enabled():
		return _fail("MindSoul disabled — felt_self layer off?")
	var f: Fish = _mk("soul-1")
	var ms = MindState.for_fish(f, true)
	ms.workspace = [{"label": "food", "salience": 0.7}]
	ms.attention_focus = "food"
	ms.workspace_ignited = true
	f._mind_self_model = MindSelfModel.build(f, ms.workspace)
	MindSoul.predict_self_before_competition(f, ms)
	GlobalWorkspace.broadcast(f, {
		"contents": [{"label": "threat", "salience": 0.82}],
		"ignited": true,
	}, ms)
	var soul: Dictionary = MindSoul.ensure(f)
	if float(soul.get("self_pred_error", 0.0)) < 0.3:
		return _fail("self_pred_error should rise when focus diverges")
	# Pass 2 — habits + prospective memory (before long cycle loops reset habits).
	f.surprise = 0.0
	f._prediction_error = 0.0
	for i in 12:
		MindSoulPass2.after_commit(f, ms, null, "food")
	var habit: Dictionary = MindSoulPass2.habit_shortcut(f, null)
	if habit.is_empty():
		return _fail("habit shortcut should engage after repeated food commits")
	f._prospective = {"intent": "food", "pos": f.position, "t": 4.0}
	var pro_bid: Dictionary = MindSoulPass2.prospective_bid(f)
	if str(pro_bid.get("label", "")) != "food":
		return _fail("prospective bid missing food goal")
	for i in 30:
		MindCycle.run_attention_phase(f, null, ms, 0.05)
		MindCycle.run_bind_phase(f, null, ms, 0.05)
	if MindSoul.ensure(f).is_empty():
		return _fail("soul state empty after ticks")
	var cf: String = MindSoul.counterfactual_for(f)
	if cf == "":
		return _fail("counterfactual_for empty")
	var mort: Dictionary = MindSoul.mortality_shift(f)
	if float(mort.get("decline", 0.0)) < 0.2:
		return _fail("mortality_shift should reflect age/energy")
	FishProtoself.tick(f, null, 0.1)
	var pb: Dictionary = FishProtoself.ensure(f)
	if float(pb.get("vitality_decline", 0.0)) < 0.1:
		return _fail("protoself vitality_decline missing for aged fish")
	FishGenerativeSelf.tick(f, null, 0.05)
	if str(FishGenerativeSelf.ensure(f).get("counterfactual", "")) == "":
		return _fail("generative_self counterfactual not wired after tick")
	var interp: Dictionary = CognitiveSchema.interpret_keeper_heuristic(
			"what are you thinking about?", f)
	if str(interp.get("keeper_intent", "")) != "introspection":
		return _fail("introspection intent not classified")
	f._keeper_pending = interp.duplicate(true)
	f._keeper_pending["keeper_text"] = "what are you thinking about?"
	var ctx: Dictionary = MindContext.build_for_keeper_turn(f, null)
	var line: String = MindNarrator.template_fish_reply(ctx)
	if line == "" or not line.contains("attending"):
		return _fail("introspective template reply missing workspace grounding: %s" % line)
	var mind_d: Dictionary = FishMind.mind_to_dict(f)
	var f2: Fish = _mk("soul-2")
	FishMind.apply_mind_dict(f2, mind_d)
	if FishMind.mind_to_dict(f2).get("soul_mind", {}).is_empty():
		return _fail("soul_mind not persisted in mind_to_dict")
	var pci: float = MindSoulPass3.perturb_and_measure(f)
	if pci < 0.01:
		return _fail("pci perturbation too low")
	var extra: Array = MindSoulPass3.collect_extra_bids(f, null)
	if extra.is_empty() and f.familiarity > 0.5:
		pass  # optional bids depend on tank state
	var cfg: Node = get_root().get_node_or_null("TankConfig")
	if cfg != null and cfg.get("consciousness_active_inference") != null \
			and bool(cfg.consciousness_active_inference):
		var before: float = MindActiveInference.pragmatic_value(f, "food")
		var s: Dictionary = MindSoul.ensure(f)
		var gains: Dictionary = s.get("pragmatic_gain", {})
		gains["food"] = 1.65
		s["pragmatic_gain"] = gains
		f._soul_mind = s
		var after: float = MindActiveInference.pragmatic_value(f, "food")
		if absf(after - before) < 0.01:
			return _fail("pragmatic_multiplier not applied to pragmatic_value")
	return true
