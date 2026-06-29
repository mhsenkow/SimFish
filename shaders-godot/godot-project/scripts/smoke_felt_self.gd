extends SceneTree

# Headless smoke: SENTIENCE_THE_FELT_SELF — ten-module spine + binding integration.

const MindCycle = preload("res://scripts/mind_cycle.gd")
const FishBinding = preload("res://scripts/fish_binding.gd")
const FishProtoself = preload("res://scripts/fish_protoself.gd")
const FishCoreAffect = preload("res://scripts/fish_core_affect.gd")
const FishFeltNow = preload("res://scripts/fish_felt_now.gd")
const FishRelevance = preload("res://scripts/fish_relevance.gd")
const FishGenerativeSelf = preload("res://scripts/fish_generative_self.gd")
const FishConcepts = preload("res://scripts/fish_concepts.gd")
const FishContinuity = preload("res://scripts/fish_continuity.gd")
const FishQualia = preload("res://scripts/fish_qualia.gd")
const FishVolition = preload("res://scripts/fish_volition.gd")
const GlobalWorkspace = preload("res://scripts/global_workspace.gd")
const MindSelfModel = preload("res://scripts/mind_self_model.gd")
const FishMind = preload("res://scripts/fish_mind.gd")


func _initialize() -> void:
	if not _run_all():
		quit(1)
		return
	print("[smoke_felt_self] OK")
	quit(0)


func _fail(msg: String) -> bool:
	push_error(msg)
	return false


func _make_fish() -> Fish:
	var f: Fish = Fish.new()
	f.id = "felt-smoke-1"
	f.fish_name = "Mira"
	f.mood = 0.15
	f.hunger = 0.72
	f.stress = 0.35
	f.arousal = 0.4
	f.familiarity = 0.55
	f._cached_glance_strength = 0.0
	f.position = Vector3(1, 2, 3)
	return f


func _run_all() -> bool:
	var f: Fish = _make_fish()
	var ms = MindState.for_fish(f, true)
	for i in 24:
		MindCycle.run_attention_phase(f, null, ms, 0.05)
		MindCycle.run_bind_phase(f, null, ms, 0.05)
		MindCycle.run_encode_phase(f, ms)
	if FishProtoself.ensure(f).is_empty():
		return _fail("protoself empty after ticks")
	if FishCoreAffect.texture(f) == "":
		return _fail("core affect texture missing")
	if FishFeltNow.ensure(f).is_empty():
		return _fail("felt_now empty after ticks")
	if FishRelevance.ensure(f).is_empty():
		return _fail("relevance empty after ticks")
	if FishGenerativeSelf.ensure(f).is_empty():
		return _fail("generative_self empty after ticks")
	if FishConcepts.ensure(f).is_empty():
		return _fail("concepts empty after ticks")
	if FishContinuity.ensure(f).is_empty():
		return _fail("continuity empty after ticks")
	if FishQualia.ensure(f).is_empty():
		return _fail("qualia empty after ticks")
	if FishVolition.ensure(f).is_empty():
		return _fail("volition empty after ticks")
	var test: Dictionary = FishBinding.integration_test(f)
	if not bool(test.get("ok", false)):
		return _fail("binding integration failed: %s" % JSON.stringify(test))
	var bids: Array = GlobalWorkspace.collect_bids(f, null)
	if bids.is_empty():
		return _fail("expected baseline body bids")
	var sm: Dictionary = MindSelfModel.build(f, ms.workspace)
	if not sm.has("body") or not sm.has("felt_texture"):
		return _fail("self_model missing felt fields")
	var ctx: Dictionary = MindContext.build_for_fish(f, null, f.attention_focus)
	if str(ctx.get("felt_texture", "")) == "":
		return _fail("context missing felt_texture")
	var saved: Dictionary = FishBinding.to_dict(f)
	FishBinding.from_dict(f, {})
	if not FishBinding.to_dict(f).is_empty():
		return _fail("from_dict empty should clear felt_self")
	FishBinding.from_dict(f, saved)
	if FishBinding.to_dict(f).is_empty():
		return _fail("from_dict restore failed")
	var thread_before: float = FishContinuity.thread_strength(f)
	var mind_d: Dictionary = FishMind.mind_to_dict(f)
	var f2: Fish = _make_fish()
	FishMind.apply_mind_dict(f2, mind_d)
	if absf(FishContinuity.thread_strength(f2) - thread_before) > 0.05:
		return _fail("continuity thread lost on mind save/load")
	return true
