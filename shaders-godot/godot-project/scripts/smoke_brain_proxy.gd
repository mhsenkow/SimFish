extends SceneTree

# Headless worker-path smoke: MindFishProxy through full attention worker batch.

const MindCycle = preload("res://scripts/mind_cycle.gd")
const FishBinding = preload("res://scripts/fish_binding.gd")


func _initialize() -> void:
	await process_frame
	var f: Fish = Fish.new()
	f.id = "brain-proxy-smoke"
	f.fish_name = "WorkerSmoke"
	f.familiarity = 0.55
	f.hunger = 0.62
	f.stress = 0.28
	f.personality = {"boldness": 0.58, "curiosity": 0.52, "calm": 0.5, "sociability": 0.5}
	f._mind_lod_tier = MindLOD.T2_WORLD_MODEL
	MindBrainPool.reset_for_test()
	MindBrainPool.begin_tick(null)
	var ms: MindState = MindState.new()
	ms.workspace = [{"label": "food", "salience": 0.7}]
	ms.attention_focus = "food"
	MindBrainPool.queue_cognition(f, ms, 0.05)
	MindBrainPool.flush_tick()
	if not MindBrainPool.wait_for_batch():
		push_error("brain proxy worker batch timed out")
		quit(1)
		return
	var ok: bool = MindBrainPool.apply_pending(f, ms)
	if not ok:
		push_error("brain proxy apply_pending failed")
		quit(1)
		return
	if ms.attention_focus == "" and ms.workspace.is_empty():
		push_error("worker produced empty workspace")
		quit(1)
		return
	if FishBinding.layer_enabled() and f._homeostasis.is_empty():
		push_error("homeostasis not round-tripped to fish")
		quit(1)
		return
	print("[smoke_brain_proxy] OK binding=%s focus=%s" % [FishBinding.layer_enabled(), ms.attention_focus])
	quit(0)
