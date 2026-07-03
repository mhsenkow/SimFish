extends SceneTree

const MindSoul = preload("res://scripts/mind_soul.gd")
const MindCycle = preload("res://scripts/mind_cycle.gd")
const GlobalWorkspace = preload("res://scripts/global_workspace.gd")


func _initialize() -> void:
	await process_frame
	var f: Fish = Fish.new()
	f.id = "proxy-soul"
	f.fish_name = "ProxySmoke"
	f.familiarity = 0.5
	var proxy: MindFishProxy = MindFishProxy.from_dict(MindFishProxy.capture(f))
	const FishSignals = preload("res://scripts/fish_signals.gd")
	proxy._signal_state = {"heard": FishSignals.FOOD, "heard_str": 0.6, "learn": {FishSignals.FOOD: 0.8}}
	proxy._prospective = {"intent": "food", "t": 4.0}
	var bold: float = proxy._trait("boldness")
	if bold < 0.0 or bold > 1.0:
		push_error("_trait out of range on proxy")
		quit(1)
		return
	var ms: MindState = MindState.new()
	ms.workspace = [{"label": "food", "salience": 0.7}]
	ms.attention_focus = "food"
	MindSoul.predict_self_before_competition(proxy, ms)
	var soul: Dictionary = MindSoul.ensure(proxy)
	if soul.is_empty():
		push_error("soul empty on proxy after predict")
		quit(1)
		return
	var sim: MindSimSnap = MindSimSnap.new()
	# Co-ignition path (≥2 workspace winners) — must accept MindFishProxy on workers.
	var ms2: MindState = MindState.new()
	ms2.workspace = [
		{"label": "food", "salience": 0.72, "affordance": "edible"},
		{"label": "threat", "salience": 0.58, "affordance": "hide_from"},
	]
	GlobalWorkspace.broadcast(proxy, {"contents": ms2.workspace, "ignited": true}, ms2)
	if proxy._behavior_ws_bias.length_squared() < 1e-6:
		push_error("blend_behavior_bias produced zero bias on proxy")
		quit(1)
		return
	MindCycle.set_worker_workspace_enabled(true)
	MindCycle.run_attention_phase_worker(proxy, sim, ms, 0.05)
	var bids: Array = GlobalWorkspace.collect_bids(proxy, sim)
	if bids.is_empty():
		push_error("collect_bids returned empty on proxy")
		quit(1)
		return
	if MindSoul.ensure(proxy).is_empty():
		push_error("soul cleared after attention worker")
		quit(1)
		return
	var p2: MindFishProxy = MindFishProxy.from_dict(proxy.to_dict())
	if p2._soul_mind.is_empty():
		push_error("soul not round-tripped on proxy dict")
		quit(1)
		return
	print("[smoke_soul_proxy] OK")
	quit(0)
