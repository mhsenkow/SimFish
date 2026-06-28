extends SceneTree

# SENTIENCE_THE_DARING_MIND §I #90 — continuity + integration smoke.

const FishMind = preload("res://scripts/fish_mind.gd")
const KeeperInput = preload("res://scripts/keeper_input.gd")
const MindLexicon = preload("res://scripts/mind_lexicon.gd")
const MindWorldModel = preload("res://scripts/mind_world_model.gd")
const MindDaring = preload("res://scripts/mind_daring.gd")
const GlobalWorkspace = preload("res://scripts/global_workspace.gd")
const MindCycle = preload("res://scripts/mind_cycle.gd")
const CognitiveSchema = preload("res://scripts/cognitive_schema.gd")
const MindContext = preload("res://scripts/mind_context.gd")


func _initialize() -> void:
	if not _run_all():
		quit(1)
		return
	print("[smoke_daring_mind] OK")
	quit(0)


func _fail(msg: String) -> bool:
	push_error(msg)
	return false


func _make_fish() -> Fish:
	var f: Fish = Fish.new()
	f.id = "daring-smoke-1"
	f.fish_name = "Pip"
	f.familiarity = 0.55
	f.mood = 0.1
	f.hunger = 0.35
	f.position = Vector3(1, 1, 2)
	return f


func _run_all() -> bool:
	if not _test_keeper_bid():
		return false
	if not _test_lexicon_pairing():
		return false
	if not _test_world_model_tick():
		return false
	if not _test_save_reload():
		return false
	if not _test_schema_extensions():
		return false
	if not _test_deliberation_tie():
		return false
	return true


func _test_keeper_bid() -> bool:
	var f: Fish = _make_fish()
	KeeperInput.submit_to_fish(f, "hello Pip", null)
	if float(f._keeper_message_salience) < 0.2:
		return _fail("keeper salience not set")
	var bids: Array = GlobalWorkspace.collect_bids(f, null)
	var found: bool = false
	for b in bids:
		if str(b.get("label", "")) == "keeper_message":
			found = true
			break
	if not found:
		return _fail("keeper_message bid missing")
	return true


func _test_lexicon_pairing() -> bool:
	var f: Fish = _make_fish()
	for _i in 3:
		MindLexicon.try_pair_on_keeper_word(f, "dinner", null)
	if not MindLexicon.comprehend(f, "dinner"):
		return _fail("lexicon did not ground dinner")
	return true


func _test_world_model_tick() -> bool:
	var f: Fish = _make_fish()
	MindWorldModel.tick(f, null, 0.5)
	if f.get("_world_model") == null:
		return _fail("world model not created")
	if f.get("_prediction_error") == null:
		return _fail("prediction error not set")
	return true


func _test_save_reload() -> bool:
	var f: Fish = _make_fish()
	for _i in 3:
		MindLexicon.try_pair_on_keeper_word(f, "hello", null)
	MindWorldModel.tick(f, null, 1.0)
	f._life_stance = "curious"
	f._self_summary = "a fish that watches"
	var saved: Dictionary = FishMind.mind_to_dict(f)
	var g: Fish = Fish.new()
	g.id = f.id
	FishMind.apply_mind_dict(g, saved)
	if int(saved.get("schema_version", 0)) != FishMind.MIND_SCHEMA_VERSION:
		return _fail("schema version mismatch")
	if not MindLexicon.comprehend(g, "hello"):
		return _fail("lexicon lost on reload")
	if str(g._life_stance) != "curious":
		return _fail("stance lost on reload")
	if g.get("_world_model") == null:
		return _fail("world model lost on reload")
	return true


func _test_schema_extensions() -> bool:
	var f: Fish = _make_fish()
	var ctx: Dictionary = MindContext.build_for_fish(f, null, "idle")
	ctx["keeper_text"] = "quiet"
	ctx["keeper_felt"] = "comfort"
	var op: Dictionary = CognitiveSchema.template_op(ctx)
	op["choice"] = "approach"
	op["plan"] = ["watch"]
	op["certainty"] = 0.8
	op["bid_weight"] = {"food": 0.1}
	if not CognitiveSchema.validate_op(op, ctx):
		return _fail("extended schema rejected valid op")
	return true


func _test_deliberation_tie() -> bool:
	var f: Fish = _make_fish()
	f._delib_active = true
	f._delib_decided = false
	f._delib_ev_approach = 0.52
	f._delib_ev_avoid = 0.51
	f._delib_phase = 1.7
	var choice: int = FishMind.deliberation_tie_break(f, null)
	if choice == 0 and not f._delib_decided:
		return _fail("deliberation tie-break did not decide")
	return true
