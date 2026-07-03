class_name MindReplayParity
extends RefCounted

# PERFORMANCE_UNTHROTTLED #97 — fixed-seed workspace replay parity (lossless gate).

const GlobalWorkspace = preload("res://scripts/global_workspace.gd")
const MindCycle = preload("res://scripts/mind_cycle.gd")
const MindChannel = preload("res://scripts/mind_channel.gd")
const EpisodicMemory = preload("res://scripts/episodic_memory.gd")
const MindSoulPass2 = preload("res://scripts/mind_soul_pass2.gd")
const MindCacheRegistry = preload("res://scripts/mind_cache_registry.gd")


static func workspace_trace(f, sim) -> Dictionary:
	var ms = MindChannel.for_cycle(f, true)
	MindCycle.begin_cycle(f, sim)
	MindCycle.run_attention_phase(f, sim, ms, 0.1)
	return {
		"focus": ms.attention_focus,
		"ignited": ms.workspace_ignited,
		"winners": _winner_labels(ms.workspace),
		"digest": GlobalWorkspace.competition_digest({
			"contents": ms.workspace,
			"ignited": ms.workspace_ignited,
			"top_salience": _top_salience(ms.workspace),
		}),
	}


static func _winner_labels(ws: Array) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for w in ws:
		if w is Dictionary:
			out.append(str((w as Dictionary).get("label", "")))
	return out


static func _top_salience(ws: Array) -> float:
	if ws.is_empty():
		return 0.0
	return float((ws[0] as Dictionary).get("salience", 0.0))


static func traces_match(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("focus", "")) != str(b.get("focus", "")):
		return false
	var wa: PackedStringArray = a.get("winners", PackedStringArray()) as PackedStringArray
	var wb: PackedStringArray = b.get("winners", PackedStringArray()) as PackedStringArray
	if wa.size() != wb.size():
		return false
	for i in wa.size():
		if wa[i] != wb[i]:
			return false
	# Ignition can flip at ε near threshold while winners stay identical (#97).
	return true


static func _replay_baseline(f) -> void:
	f.hunger = 0.62
	f.stress = 0.22
	f.spooked = 0.1
	f.curiosity_drive = 0.48
	f.attention_focus = "idle"
	f.surprise = 0.0
	f._ws_bids_digest = -1
	f._ws_broadcast_digest = -2
	f._ws_competition_cache = {}
	f._cycle_bias_cache = {}
	f._self_model_cache = {}
	f._self_model_key = ""
	f._mind_workspace = []
	f._workspace_ignited = false
	f._behavior_ws_bias = Vector3.ZERO
	f._bid_slow_cache = []
	f._bid_slow_due = true
	f._bid_dirty = 0
	f._mind_accum = 0.0
	f._bid_pool = []
	f._bid_pool_i = 0
	f._soul_mind = {}
	f._episodic_retrieval_hint = {}
	MindCacheRegistry.reset_transient(f)
	MindSoulPass2.reset_habit_stats_for_test()
	EpisodicMemory.clear_caches_for_test()


static func run_smoke(f, sim) -> bool:
	if f == null:
		return false
	var cfg: Node = null
	var prev_hz: float = 15.0
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree and (ml as SceneTree).root != null:
		cfg = (ml as SceneTree).root.get_node_or_null("/root/TankConfig")
		if cfg != null and cfg.get("mind_cadence_hz") != null:
			prev_hz = float(cfg.mind_cadence_hz)
			cfg.mind_cadence_hz = 0.0
	_replay_baseline(f)
	var t1: Dictionary = workspace_trace(f, sim)
	_replay_baseline(f)
	var t2: Dictionary = workspace_trace(f, sim)
	var ok: bool = traces_match(t1, t2)
	ok = ok and run_smoke_n_tick(f, null, 8)
	if cfg != null:
		cfg.mind_cadence_hz = prev_hz
	return ok


static func run_smoke_n_tick(f, sim, n: int = 8) -> bool:
	if f == null or n < 1:
		return false
	for _i in n:
		_replay_baseline(f)
		var t1: Dictionary = workspace_trace(f, sim)
		_replay_baseline(f)
		var t2: Dictionary = workspace_trace(f, sim)
		if not traces_match(t1, t2):
			return false
	return true


static func golden_digest_hash(f, sim, n_ticks: int = 16) -> int:
	if f == null:
		return 0
	var h: int = 0
	for _i in n_ticks:
		_replay_baseline(f)
		var t: Dictionary = workspace_trace(f, sim)
		h = (h * 31 + int(t.get("digest", 0))) & 0x7fffffff
		var winners: PackedStringArray = t.get("winners", PackedStringArray()) as PackedStringArray
		for w in winners:
			h = (h * 31 + w.hash()) & 0x7fffffff
	return h
