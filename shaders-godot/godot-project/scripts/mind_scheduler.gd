extends RefCounted

# CONSCIOUSNESS_ENGINEERING §C + §I — continuous thought scheduler (System 2 queue).

const MindNarrator = preload("res://scripts/mind_narrator.gd")
const CognitiveSchema = preload("res://scripts/cognitive_schema.gd")
const _MindNarratorWorkerScript = preload("res://scripts/mind_narrator_worker.gd")
const MindWriteback = preload("res://scripts/mind_writeback.gd")
const MindDaring = preload("res://scripts/mind_daring.gd")
const EpisodicMemory = preload("res://scripts/episodic_memory.gd")
const FishMind = preload("res://scripts/fish_mind.gd")

const THOUGHT_INTERVAL_CALM: float = 8.0
const THOUGHT_INTERVAL_IGNITED: float = 2.5
const THOUGHT_INTERVAL_AMBIENT: float = 22.0
const SN_IDLE := &"idle"
const SN_SITUATION := &"situation"
const MAX_QUEUE: int = 12
const AMBIENT_QUEUE_CUTOFF: int = 8
const MEMORY_PRESSURE_BYTES: int = 2_200_000_000

# Likely next situations — pre-computed template ops (#87).
const PRECACHE_SITUATIONS: Array = ["food", "player", "idle", "threat"]

static var _queue: Array = []
static var _in_flight: bool = false
static var _stats: Dictionary = {
	"cycles": 0, "queue_depth": 0, "cache_hits": 0, "reflections": 0,
	"last_latency_ms": 0,
}
static var _op_cache: Dictionary = {}
static var _pending_async: Dictionary = {}
static var _worker_mutex: Mutex = Mutex.new()
static var _worker_results: Dictionary = {}  # cache_key -> {op, prompt}
static var _worker_inflight: Dictionary = {}  # cache_key -> {fish, ctx, task_id, use_glm}
static var _ai_director: Node = null
static var _guardian_llm: Node = null
static var _tank_config: Node = null


static func _resolve_autoloads() -> void:
	if _tank_config != null and is_instance_valid(_tank_config):
		return
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return
	var st: SceneTree = ml as SceneTree
	if st == null or st.root == null or not st.root.is_inside_tree():
		return
	_tank_config = st.root.get_node_or_null("/root/TankConfig")
	_ai_director = st.root.get_node_or_null("/root/AIDirector")
	_guardian_llm = st.root.get_node_or_null("/root/GuardianLlm")


static func _autoload(name: String) -> Node:
	_resolve_autoloads()
	match name:
		"TankConfig": return _tank_config
		"AIDirector": return _ai_director
		"GuardianLlm": return _guardian_llm
		_:
			var ml: MainLoop = Engine.get_main_loop()
			if ml == null:
				return null
			var st: SceneTree = ml as SceneTree
			if st == null or st.root == null or not st.root.is_inside_tree():
				return null
			return st.root.get_node_or_null("/root/" + name)


static func stats() -> Dictionary:
	_stats["queue_depth"] = _queue.size()
	_stats["in_flight"] = _in_flight
	_stats["pending_async"] = _pending_async.size()
	_stats["op_cache_size"] = _op_cache.size()
	_stats["worker_inflight"] = _worker_inflight.size()
	return _stats.duplicate()


static func reset_stats_for_test() -> void:
	_stats = {
		"cycles": 0, "queue_depth": 0, "cache_hits": 0, "reflections": 0,
		"last_latency_ms": 0, "in_flight": false, "pending_async": 0,
		"op_cache_size": 0, "throttled_external": 0,
	}
	_queue.clear()
	_in_flight = false
	_pending_async.clear()
	_worker_mutex.lock()
	_worker_results.clear()
	_worker_inflight.clear()
	_worker_mutex.unlock()


static func poll_workers() -> void:
	if _worker_inflight.is_empty():
		return
	var finished: Array[String] = []
	for key in _worker_inflight:
		var job: Dictionary = _worker_inflight[key]
		var task_id: int = int(job.get("task_id", -1))
		if task_id < 0 or not WorkerThreadPool.is_task_completed(task_id):
			continue
		WorkerThreadPool.wait_for_task_completion(task_id)
		finished.append(str(key))
	for key in finished:
		_finish_worker_job(key)


static func _finish_worker_job(cache_key: String) -> void:
	var job: Variant = _worker_inflight.get(cache_key, null)
	if job == null:
		return
	_worker_inflight.erase(cache_key)
	_worker_mutex.lock()
	var packed: Variant = _worker_results.get(cache_key, null)
	if packed is Dictionary:
		_worker_results.erase(cache_key)
	_worker_mutex.unlock()
	if not (packed is Dictionary):
		_in_flight = false
		if not _queue.is_empty():
			_pump()
		return
	var result: Dictionary = packed as Dictionary
	var f: Fish = job.get("fish")
	var ctx: Dictionary = job.get("ctx", {})
	var line: String = str(result.get("line", ""))
	if line != "" and f != null and is_instance_valid(f):
		f._thought_stream = line
		f._current_thought = line
	var fb: Dictionary = result.get("op", {}) as Dictionary
	if bool(job.get("use_glm", false)):
		var glm: Node = _autoload("GuardianLlm")
		if glm != null and glm.has_method("queue_generate"):
			ctx["fish_id"] = str(f.id) if f != null else ""
			_pending_async[cache_key] = {"fish": f, "ctx": ctx, "t0": Time.get_ticks_msec()}
			glm.call("queue_generate", "cog|" + cache_key,
					String(result.get("prompt", "")), fb.get("line", ""), ctx,
					MindNarrator.NUM_PREDICT_FISH_THOUGHT)
		_apply_cached(f, fb, ctx)
		return
	_op_cache[cache_key] = fb
	_apply_cached(f, fb, ctx)
	_stats["reflections"] += 1
	_in_flight = false
	if not _queue.is_empty():
		_pump()


static func _worker_build_thought(cache_key: String, ctx: Dictionary) -> void:
	var pkg: Dictionary = _MindNarratorWorkerScript.build_thought_package(ctx)
	_worker_mutex.lock()
	_worker_results[cache_key] = pkg
	_worker_mutex.unlock()


static func run_worker_smoke(ctx: Dictionary) -> bool:
	reset_stats_for_test()
	var key: String = "smoke|worker"
	var tid: int = WorkerThreadPool.add_task(_worker_build_thought.bind(key, ctx.duplicate(true)))
	while not WorkerThreadPool.is_task_completed(tid):
		pass
	WorkerThreadPool.wait_for_task_completion(tid)
	_worker_mutex.lock()
	var ok: bool = _worker_results.has(key) and (_worker_results[key] as Dictionary).has("op")
	_worker_results.erase(key)
	_worker_mutex.unlock()
	return ok


static func should_throttle_external() -> bool:
	if _queue.size() >= MAX_QUEUE - 2:
		return true
	if _in_flight and _queue.size() >= AMBIENT_QUEUE_CUTOFF:
		return true
	if int(OS.get_static_memory_usage()) > MEMORY_PRESSURE_BYTES:
		return true
	return false


static func note_external_throttled() -> void:
	_stats["throttled_external"] = int(_stats.get("throttled_external", 0)) + 1


static func precache_for_fish(f: Fish, sim: Node) -> void:
	if f == null or not is_instance_valid(f):
		return
	for sit in PRECACHE_SITUATIONS:
		var ctx: Dictionary = MindContext.build_for_fish(f, sim, sit)
		var key: String = _cache_key(f, ctx)
		if not _op_cache.has(key):
			_op_cache[key] = CognitiveSchema.template_op(ctx)


static func priority_for(f: Fish, sim: Node) -> float:
	var p: float = 0.1
	if f.is_guardian:
		p += 1.0
	if sim != null and sim.has_method("is_creature_favorited"):
		if sim.is_creature_favorited(f):
			p += 0.6
	if bool(f.get("_workspace_ignited")):
		p += 0.8
	if f.familiarity > 0.5:
		p += 0.3
	if f.fish_name != "":
		p += 0.15
	return p


static func tick_fish(f: Fish, sim: Node, dt: float) -> void:
	if f == null or not is_instance_valid(f):
		return
	if not _stream_enabled():
		return
	MindWriteback.tick_cooldown(f, dt)
	f._thought_tick_cd = maxf(0.0, float(f.get("_thought_tick_cd") if f.get("_thought_tick_cd") != null else 0.0) - dt)
	if f._thought_tick_cd > 0.0:
		return
	var ignited: bool = bool(f.get("_workspace_ignited"))
	var interval: float = THOUGHT_INTERVAL_IGNITED if ignited else THOUGHT_INTERVAL_CALM
	var ai: Node = _autoload("AIDirector")
	if ai != null and ai.has_method("fish_deserves_model_voice"):
		if not ai.fish_deserves_model_voice(f, sim):
			interval = THOUGHT_INTERVAL_AMBIENT
	if sim != null and sim.get("_room_idle_s") != null:
		var idle: float = float(sim._room_idle_s)
		if idle > 45.0:
			interval *= lerpf(1.0, 3.2, clampf(idle / 180.0, 0.0, 1.0))
	# #3 — asleep fish poll thoughts ~4× slower; dreams still fire on their cadence.
	if f._asleep:
		interval *= 4.0
	f._thought_tick_cd = interval
	_run_internal_thought(f, sim, ignited)


static func _audience_wants_prose(f: Fish, sim: Node) -> bool:
	if f.is_voiced_individual() or f.is_guardian:
		return true
	if sim != null and sim.has_method("is_creature_favorited"):
		if sim.is_creature_favorited(f):
			return true
	var cfg: Node = _autoload("TankConfig")
	if cfg != null and bool(cfg.get("inner_life_panel")):
		return true
	return false


static func _room_idle_no_panel(sim: Node) -> bool:
	if sim == null or sim.get("_room_idle_s") == null:
		return false
	if float(sim._room_idle_s) < 45.0:
		return false
	var cfg: Node = _autoload("TankConfig")
	if cfg != null and bool(cfg.get("inner_life_panel")):
		return false
	return true


static func _run_internal_thought(f: Fish, sim: Node, deep: bool) -> void:
	var situation: String = f.attention_focus if f.attention_focus != "" else str(SN_IDLE)
	var want_prose: bool = _audience_wants_prose(f, sim) and not _room_idle_no_panel(sim)
	var ctx: Dictionary = MindContext.build_for_fish(f, sim, situation, null, want_prose)
	_stats["cycles"] += 1
	# #4/#17 — keep thought state; defer narrator prose when nobody is listening.
	if want_prose:
		var internal: String = _internal_template(f, ctx)
		f._thought_stream = internal
		f._thought_stream_age = 0.0
		f._current_thought = internal
	else:
		f._thought_stream_age = 0.0
		f._current_thought = ""
	# System 2 gate (#27)
	if not deep and f.surprise < 0.35 and f.stress < 0.5:
		return
	if MindContext.context_is_thin(ctx) and not deep:
		return
	# Adaptive degradation (#86): ambient fish skip System 2 when queue is full.
	var prio: float = priority_for(f, sim)
	if prio < 0.55 and (_queue.size() >= AMBIENT_QUEUE_CUTOFF or _in_flight):
		return
	var cache_key: String = _cache_key(f, ctx)
	if _op_cache.has(cache_key):
		_stats["cache_hits"] += 1
		_apply_cached(f, _op_cache[cache_key], ctx)
		return
	if _queue.size() >= MAX_QUEUE:
		return
	_queue.append({"fish": f, "sim": sim, "ctx": ctx, "cache_key": cache_key,
			"priority": priority_for(f, sim)})
	_pump()


static var _pass3_script: GDScript = null


static func _pass3() -> GDScript:
	if _pass3_script == null:
		_pass3_script = load("res://scripts/mind_soul_pass3.gd") as GDScript
	return _pass3_script


static func _internal_template(f: Fish, ctx: Dictionary) -> String:
	var p3: GDScript = _pass3()
	if p3 != null and p3.enabled():
		var rare: String = p3.hard_choice_line(f)
		if rare != "":
			return rare
		rare = p3.surface_counterfactual_line(f, null)
		if rare != "":
			return rare
	var ws: Variant = f.get("_mind_workspace")
	var line: String = ""
	if ws is Array and (ws as Array).size() > 0:
		var label: String = str((ws[0] as Dictionary).get("label", ""))
		if label != "":
			line = f.workspace_thought_for(label)
		if line != "" and line == f._current_thought and (ws as Array).size() > 1:
			var alt: String = str((ws[1] as Dictionary).get("label", ""))
			if alt != "":
				line = f.workspace_thought_for(alt)
	if line == "" or line == f._current_thought:
		var alt_line: String = MindNarrator.template_fish_thought(ctx)
		if alt_line != "":
			line = alt_line
	return line


static func _cache_key(f: Fish, ctx: Dictionary) -> String:
	return "%s|%s|%s|%s" % [
		str(f.id), str(ctx.get("feel", "")),
		str(ctx.get("attention_workspace", "")),
		str(ctx.get(SN_SITUATION, "")),
	]


static func _pump() -> void:
	if _in_flight or _queue.is_empty():
		return
	# #20 — insertion discipline for tiny queues.
	if _queue.size() > 2:
		_queue.sort_custom(func(a, b): return float(a.get("priority", 0.0)) > float(b.get("priority", 0.0)))
	var job: Dictionary = _queue[0]
	_queue.remove_at(0)
	var f: Fish = job.get("fish")
	var ctx: Dictionary = job.get("ctx", {})
	var cache_key: String = String(job.get("cache_key", ""))
	var use_glm: bool = false
	var glm: Node = _autoload("GuardianLlm")
	if glm != null and glm.has_method("is_ready") and bool(glm.call("is_ready")) \
			and glm.has_method("queue_generate"):
		use_glm = true
	_in_flight = true
	var tid: int = WorkerThreadPool.add_task(
			_worker_build_thought.bind(cache_key, ctx.duplicate(true)))
	_worker_inflight[cache_key] = {
		"fish": f, "ctx": ctx, "task_id": tid, "use_glm": use_glm,
	}


static func _apply_cached(f: Fish, op: Dictionary, ctx: Dictionary) -> void:
	if f == null or not is_instance_valid(f):
		return
	var line: String = str(op.get("line", ""))
	if line != "":
		f._thought_stream = line
		f._current_thought = line
		f._last_cog_op = op.duplicate(false)
		f._last_cog_validation = "reflection"
	MindDaring.apply_model_op(f, op, ctx)


static func on_model_result(cache_key: String, raw: String, ctx: Dictionary) -> void:
	var op: Dictionary = CognitiveSchema.parse_line(raw)
	if not CognitiveSchema.validate_op(op, ctx):
		op = CognitiveSchema.template_op(ctx)
	_op_cache[cache_key] = op
	_stats["reflections"] += 1
	var pending: Variant = _pending_async.get(cache_key, null)
	if pending is Dictionary:
		var job: Dictionary = pending as Dictionary
		_pending_async.erase(cache_key)
		var t0: int = int(job.get("t0", 0))
		if t0 > 0:
			_stats["last_latency_ms"] = Time.get_ticks_msec() - t0
		var f: Fish = job.get("fish")
		var job_ctx: Dictionary = job.get("ctx", ctx)
		if f != null and is_instance_valid(f):
			f._last_cog_op = op.duplicate(true)
			f._last_cog_validation = "model_async"
			MindDaring.apply_model_op(f, op, job_ctx)
	_in_flight = false
	if not _queue.is_empty():
		_pump()


static func _stream_enabled() -> bool:
	var cfg: Node = _autoload("TankConfig")
	if cfg == null:
		return true
	return bool(cfg.get("consciousness_stream_enabled") if cfg.get("consciousness_stream_enabled") != null else true)
