extends RefCounted

# CONSCIOUSNESS_ENGINEERING §C + §I — continuous thought scheduler (System 2 queue).

const MindContext = preload("res://scripts/mind_context.gd")
const MindNarrator = preload("res://scripts/mind_narrator.gd")
const CognitiveSchema = preload("res://scripts/cognitive_schema.gd")
const MindWriteback = preload("res://scripts/mind_writeback.gd")
const MindDaring = preload("res://scripts/mind_daring.gd")
const EpisodicMemory = preload("res://scripts/episodic_memory.gd")
const FishMind = preload("res://scripts/fish_mind.gd")

const THOUGHT_INTERVAL_CALM: float = 8.0
const THOUGHT_INTERVAL_IGNITED: float = 2.5
const THOUGHT_INTERVAL_AMBIENT: float = 22.0
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


static func _autoload(name: String) -> Node:
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
	f._thought_tick_cd = interval
	_run_internal_thought(f, sim, ignited)


static func _run_internal_thought(f: Fish, sim: Node, deep: bool) -> void:
	var situation: String = f.attention_focus if f.attention_focus != "" else "idle"
	var ctx: Dictionary = MindContext.build_for_fish(f, sim, situation)
	_stats["cycles"] += 1
	# Internal monologue (#22) — template always; model when eligible
	var internal: String = _internal_template(f, ctx)
	f._thought_stream = internal
	f._thought_stream_age = 0.0
	f._current_thought = internal
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


static func _internal_template(f: Fish, ctx: Dictionary) -> String:
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
		str(ctx.get("situation", "")),
	]


static func _pump() -> void:
	if _in_flight or _queue.is_empty():
		return
	_queue.sort_custom(func(a, b): return float(a.get("priority", 0.0)) > float(b.get("priority", 0.0)))
	var job: Dictionary = _queue[0]
	_queue.remove_at(0)
	_in_flight = true
	var f: Fish = job.get("fish")
	var ctx: Dictionary = job.get("ctx", {})
	var cache_key: String = String(job.get("cache_key", ""))
	var fb: Dictionary = CognitiveSchema.template_op(ctx)
	var glm: Node = _autoload("GuardianLlm")
	if glm != null and glm.has_method("is_ready") and bool(glm.call("is_ready")) \
			and glm.has_method("queue_generate"):
		var prompt: String = MindNarrator.build_fish_thought_prompt(ctx)
		ctx["fish_id"] = str(f.id)
		_pending_async[cache_key] = {"fish": f, "ctx": ctx, "t0": Time.get_ticks_msec()}
		glm.call("queue_generate", "cog|" + cache_key, prompt, fb.get("line", ""), ctx,
				MindNarrator.FISH_THOUGHT_MAX_WORDS + 4)
		_apply_cached(f, fb, ctx)
		return
	_op_cache[cache_key] = fb
	_apply_cached(f, fb, ctx)
	_stats["reflections"] += 1
	_in_flight = false
	if not _queue.is_empty():
		_pump()


static func _apply_cached(f: Fish, op: Dictionary, ctx: Dictionary) -> void:
	if f == null or not is_instance_valid(f):
		return
	var line: String = str(op.get("line", ""))
	if line != "":
		f._thought_stream = line
		f._current_thought = line
		f._last_cog_op = op.duplicate(true)
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
