extends SceneTree

# Headless smoke: consciousness engineering — integration spine + §J verification.
const GlobalWorkspace = preload("res://scripts/global_workspace.gd")
const EpisodicMemory = preload("res://scripts/episodic_memory.gd")
const CognitiveSchema = preload("res://scripts/cognitive_schema.gd")
const MindContext = preload("res://scripts/mind_context.gd")
const MindDebug = preload("res://scripts/mind_debug.gd")
const MindScheduler = preload("res://scripts/mind_scheduler.gd")
const MindCycle = preload("res://scripts/mind_cycle.gd")
const MindSelfModel = preload("res://scripts/mind_self_model.gd")
const MindWriteback = preload("res://scripts/mind_writeback.gd")
const MindNarrator = preload("res://scripts/mind_narrator.gd")


func _initialize() -> void:
	MindScheduler.reset_stats_for_test()
	if not _run_all():
		quit(1)
		return
	print("[smoke_consciousness_engineering] OK")
	quit(0)


func _run_all() -> bool:
	if not _test_workspace_spine():
		return false
	if not _test_integration_assert():
		return false
	if not _test_functional_probes():
		return false
	if not _test_grounding_fuzz():
		return false
	if not _test_determinism():
		return false
	if not _test_writeback_bounded():
		return false
	if not _test_precache_and_perf():
		return false
	if not _test_cognitive_schema_fuzz():
		return false
	return true


func _fail(msg: String) -> bool:
	push_error(msg)
	return false


func _make_fish(hunger: float = 0.7) -> Fish:
	var f: Fish = Fish.new()
	f.id = "smoke-fish-1"
	f.fish_name = "Nix"
	f.mood = 0.1
	f.hunger = hunger
	f._cached_glance_strength = 0.0
	f.position = Vector3(2, 1, 3)
	return f


func _test_workspace_spine() -> bool:
	var f: Fish = _make_fish()
	var bids: Array = GlobalWorkspace.collect_bids(f, null)
	var result: Dictionary = GlobalWorkspace.run_competition(bids)
	if not result.has("contents"):
		return _fail("workspace competition failed")
	var ms = MindState.for_fish(f, true)
	GlobalWorkspace.broadcast(f, result, ms)
	if f.attention_focus != "food":
		return _fail("expected food to win salience")
	EpisodicMemory.encode_episode(f, "food", "found pellets near glass", 0.6, f.position)
	var q: PackedFloat32Array = EpisodicMemory.embed("food", "pellets")
	if EpisodicMemory.retrieve(f, q, 1).is_empty():
		return _fail("episodic retrieve failed")
	var ctx: Dictionary = MindContext.build_for_fish(f, null, "food")
	if str(ctx.get("attention_workspace", "")) == "":
		return _fail("context missing workspace")
	var op: Dictionary = CognitiveSchema.template_op(ctx)
	if not CognitiveSchema.validate_op(op, ctx):
		return _fail("cognitive op invalid")
	var d: Dictionary = MindState.for_fish(f, true).to_dict()
	var ms2 = MindState.new()
	ms2.from_dict(d)
	if ms2.mood != f.mood:
		return _fail("mind state round-trip failed")
	return true


func _test_integration_assert() -> bool:
	var f: Fish = _make_fish()
	var ms = MindState.for_fish(f, true)
	var result: Dictionary = GlobalWorkspace.run_competition(GlobalWorkspace.collect_bids(f, null))
	GlobalWorkspace.broadcast(f, result, ms)
	ms.self_model = MindSelfModel.build(f, ms.workspace)
	f._mind_self_model = ms.self_model
	var ctx: Dictionary = MindContext.build_for_fish(f, null, "food")
	var check: Dictionary = MindDebug.integration_assert(f, ctx)
	if not bool(check.get("ok", false)):
		return _fail("integration assert: %s" % check.get("reason", ""))
	return true


func _test_functional_probes() -> bool:
	var f: Fish = _make_fish()
	f.surprise = 0.5
	var ms = MindState.for_fish(f, true)
	MindCycle.run_attention_phase(f, null, ms)
	ms.apply_to_fish(f)
	var probes: Dictionary = MindDebug.probe_markers(f, null)
	if str(probes.get("salience_winner", "")) != "food":
		return _fail("probe: food should win salience")
	if not bool(probes.get("workspace_nonempty", false)):
		return _fail("probe: workspace empty after broadcast")
	if not bool(probes.get("surprise_elevated", false)):
		return _fail("probe: surprise marker")
	return true


func _test_grounding_fuzz() -> bool:
	var ctx: Dictionary = {
		"feel": "anxious",
		"stress": 0.85,
		"allowed_fish_names": PackedStringArray(["Nix", "Ripple"]),
		"fish_name": "Nix",
	}
	var fuzz: Dictionary = MindDebug.fuzz_grounding(ctx)
	if not bool(fuzz.get("ok", false)):
		return _fail("grounding fuzz leaked %d lines" % int(fuzz.get("leaks", 0)))
	return true


func _test_determinism() -> bool:
	var ctx: Dictionary = MindContext.build_for_fish(_make_fish(), null, "food")
	if not MindDebug.determinism_template(ctx):
		return _fail("template op not deterministic")
	var prefix_a: String = MindNarrator.cog_thought_system_prefix("en")
	var prefix_b: String = MindNarrator.cog_thought_system_prefix("en")
	if prefix_a != prefix_b:
		return _fail("cog prefix not stable")
	return true


func _test_writeback_bounded() -> bool:
	var f: Fish = _make_fish()
	var pos: Vector3 = f.position
	var ctx: Dictionary = MindContext.build_for_fish(f, null, "food")
	var op: Dictionary = {
		"schema_version": 1,
		"appraisal": "content",
		"intention": "seek_food",
		"mood_nudge": 0.08,
		"memory_keep": false,
		"line": "still hungry near the glass",
	}
	var mood_before: float = f.mood
	if not MindWriteback.apply_op(f, op, ctx, "smoke"):
		return _fail("writeback apply failed")
	if not MindWriteback.never_moves_body(f, pos):
		return _fail("writeback moved body")
	if absf(f.mood - mood_before - 0.08) > 0.001:
		return _fail("mood nudge out of band")
	var bad: Dictionary = op.duplicate(true)
	bad["mood_nudge"] = 0.5
	if CognitiveSchema.validate_op(bad, ctx):
		return _fail("schema should reject large mood nudge before writeback")
	return true


func _test_precache_and_perf() -> bool:
	var f: Fish = _make_fish()
	MindScheduler.precache_for_fish(f, null)
	var stats: Dictionary = MindScheduler.stats()
	if int(stats.get("op_cache_size", 0)) < 2:
		return _fail("precache did not populate op cache")
	var ctx: Dictionary = MindContext.build_for_fish(f, null, "food")
	var perf: Dictionary = MindDebug.perf_budget_ms(
			func() -> void:
				for i in 100:
					CognitiveSchema.template_op(ctx),
			100, 2500)
	if not bool(perf.get("ok", false)):
		return _fail("perf budget exceeded: %d ms" % int(perf.get("elapsed_ms", 0)))
	return true


func _test_cognitive_schema_fuzz() -> bool:
	var ctx: Dictionary = MindContext.build_for_fish(_make_fish(), null, "food")
	var bad_ops: Array = [
		{"appraisal": "not_a_mood", "intention": "none", "mood_nudge": 0.0, "line": "x"},
		{"appraisal": "safe", "intention": "fly_away", "mood_nudge": 0.0, "line": "x"},
		{"appraisal": "safe", "intention": "none", "mood_nudge": 0.25, "line": "x"},
	]
	for op in bad_ops:
		if CognitiveSchema.validate_op(op, ctx):
			return _fail("schema should reject invalid op")
	var good: Dictionary = CognitiveSchema.template_op(ctx)
	if not CognitiveSchema.validate_op(good, ctx):
		return _fail("schema should accept template op")
	return true
