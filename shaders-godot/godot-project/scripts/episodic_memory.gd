extends RefCounted

# CONSCIOUSNESS_ENGINEERING §E — episodic vector memory (on-device, no external embed model).

const FishMind = preload("res://scripts/fish_mind.gd")
const FishConcepts = preload("res://scripts/fish_concepts.gd")
const _MindDirtySaveScript = preload("res://scripts/mind_dirty_save.gd")
const _MindWorkerCfgScript = preload("res://scripts/mind_worker_cfg.gd")
const _MindCacheStatsScript = preload("res://scripts/mind_cache_stats.gd")
const _TankConfigWarnScript = preload("res://scripts/tank_config_warn.gd")

const VECTOR_DIM: int = 32
const STORE_MAX: int = 64
const DECAY_RATE: float = 0.0008
const DECAY_AGE_S: float = 600.0     # decay halves again every ~10 min of age
const FORGET_WEIGHT: float = 0.08    # below this an episode is gone
const REHEARSAL_GAIN: float = 0.03   # weight regained per retrieval
const SALIENT_PROMOTE_WEIGHT: float = 0.62

static var _pass3_script: GDScript = null
static var _retrieve_cache: Dictionary = {}  # fish_id|sit_hash → {t, hits}
const RETRIEVE_TTL_S: float = 2.0


static func clear_caches_for_test() -> void:
	_retrieve_cache.clear()


static func clear_retrieve_cache_for(f) -> void:
	if f == null or not (f is Fish) or str((f as Fish).id) == "":
		return
	var prefix: String = "%s|" % str((f as Fish).id)
	var stale: Array[String] = []
	for k in _retrieve_cache.keys():
		if str(k).begins_with(prefix):
			stale.append(str(k))
	for k in stale:
		_retrieve_cache.erase(k)


static func _pass3() -> GDScript:
	if _pass3_script == null:
		_pass3_script = load("res://scripts/mind_soul_pass3.gd") as GDScript
	return _pass3_script


static func _quantize_enabled() -> bool:
	if not Thread.is_main_thread() and _MindWorkerCfgScript.active:
		return _MindWorkerCfgScript.read_bool("episodic_quant_8bit", true)
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree and (ml as SceneTree).root != null:
		var cfg: Node = (ml as SceneTree).root.get_node_or_null("TankConfig")
		if cfg != null and cfg.get("episodic_quant_8bit") != null:
			return bool(cfg.episodic_quant_8bit)
		return _TankConfigWarnScript.bool_or_warn(cfg, "episodic_quant_8bit", true)
	return true


static func _quantize_vec(v: PackedFloat32Array) -> PackedByteArray:
	var q := PackedByteArray()
	q.resize(v.size())
	for i in v.size():
		q[i] = int(clampf(v[i] * 127.0 + 128.0, 0.0, 255.0))
	return q


static func _dot_quant(query: PackedFloat32Array, q: PackedByteArray) -> float:
	var dot: float = 0.0
	var n: int = mini(query.size(), q.size())
	for i in n:
		var b: float = (float(q[i]) - 128.0) / 127.0
		dot += query[i] * b
	return dot


static func embed(kind: String, text: String, tags: PackedStringArray = PackedStringArray()) -> PackedFloat32Array:
	var v := PackedFloat32Array()
	v.resize(VECTOR_DIM)
	v.fill(0.0)
	_hash_into(v, kind)
	_hash_into(v, text)
	for t in tags:
		_hash_into(v, t)
	_normalize(v)
	return v


static func _hash_into(v: PackedFloat32Array, s: String) -> void:
	for i in s.length():
		var h: int = (hash(s.substr(i, 1)) ^ (i * 131)) & 0x7fffffff
		v[h % VECTOR_DIM] += 1.0


static func _normalize(v: PackedFloat32Array) -> void:
	var sum: float = 0.0
	for x in v:
		sum += x * x
	if sum < 1e-6:
		return
	var inv: float = 1.0 / sqrt(sum)
	for i in v.size():
		v[i] *= inv


static func vec_norm(v: PackedFloat32Array) -> float:
	var sum: float = 0.0
	for x in v:
		sum += x * x
	return sqrt(sum) if sum > 1e-6 else 1.0


static func similarity(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var dot: float = 0.0
	var n: int = mini(a.size(), b.size())
	for i in n:
		dot += a[i] * b[i]
	return dot


static func similarity_entry(query: PackedFloat32Array, entry: Dictionary) -> float:
	var vq: Variant = entry.get("vec_q", null)
	if vq is PackedByteArray and _quantize_enabled():
		var q_dot: float = _dot_quant(query, vq as PackedByteArray)
		var nq: float = vec_norm(query)
		var q_nb: float = float(entry.get("norm_q", entry.get("norm", 1.0)))
		if q_nb > 1e-6 and nq > 1e-6:
			return q_dot / (nq * q_nb)
		return q_dot
	var vec: Variant = entry.get("vec", null)
	if vec is not PackedFloat32Array:
		return 0.0
	var b: PackedFloat32Array = vec as PackedFloat32Array
	var dot: float = similarity(query, b)
	var nb: float = float(entry.get("norm", 0.0))
	if nb > 1e-6:
		var nq: float = vec_norm(query)
		if nq > 1e-6:
			return dot / (nq * nb)
	return dot


static func ensure_store(f) -> Array:
	if f.get("_episodic_store") == null or not (f._episodic_store is Array):
		f._episodic_store = []
	return f._episodic_store as Array


static func encode_episode(f, kind: String, text: String, salience: float,
		pos: Vector3 = Vector3.INF) -> void:
	_append_episode(f, kind, text, salience, pos)


static func ingest_salient_entry(f, entry: Dictionary) -> void:
	var kind: String = str(entry.get("kind", "self"))
	var text: String = str(entry.get("text", ""))
	if text == "":
		return
	var weight: float = SaveHelpers._num(entry.get("weight", 0.5), 0.5)
	var pos: Vector3 = Vector3.INF
	var p: Variant = entry.get("pos", null)
	if p is Vector3:
		pos = p as Vector3
	_append_episode(f, kind, text, weight, pos)


# Accepts Fish or MindFishProxy — worker cognition promotes salient moments
# through the same path as the main thread.
static func _append_episode(f, kind: String, text: String, salience: float,
		pos: Vector3 = Vector3.INF) -> void:
	var store: Array = ensure_store(f)
	var entry: Dictionary = {
		"kind": kind,
		"text": text,
		"weight": clampf(salience + (0.18 if kind == "keeper_word" else 0.0), 0.1, 1.0),
		# Encoding-time salience: how strongly this moment resists forgetting.
		# Kept separate from the (decaying) weight so protection doesn't fade
		# along with the memory it protects.
		"salience": clampf(salience, 0.0, 1.0),
		"vec": embed(kind, text),
		"norm": 0.0,
		"access_count": 0,
		"age": 0.0,
	}
	entry["norm"] = vec_norm(entry["vec"] as PackedFloat32Array)
	if _quantize_enabled():
		entry["vec_q"] = _quantize_vec(entry["vec"] as PackedFloat32Array)
		entry["norm_q"] = entry["norm"]
	if kind == "keeper_word":
		entry["persistent"] = true
	if pos.is_finite() and not is_inf(pos.x):
		entry["pos"] = pos
	store.append(entry)
	_MindDirtySaveScript.mark(f, "episodic_store")
	FishConcepts.ingest_episode(f, kind, text, float(entry.get("weight", salience)), entry)
	while store.size() > STORE_MAX:
		_prune_weakest(store)


static func _kind_bucket(situation: String) -> String:
	var s: String = situation.strip_edges()
	if s in ["food", "threat", "mate", "player", "memory", "dream", "keeper_word", "startled"]:
		return s
	return ""


static func _scan_store(store: Array, query: PackedFloat32Array, k: int, best: Array) -> void:
	for e in store:
		if not (e is Dictionary):
			continue
		var sim: float = similarity_entry(query, e as Dictionary)
		sim *= SaveHelpers._num(e.get("weight", 0.5), 0.5)
		var score: float = sim
		var insert_at: int = best.size()
		for i in best.size():
			if score > float(best[i].get("score", 0.0)):
				insert_at = i
				break
		if best.size() < k:
			best.insert(insert_at, {"entry": e, "score": score})
		elif insert_at < k:
			best.insert(insert_at, {"entry": e, "score": score})
			best.remove_at(k)


static func retrieve(f, query: PackedFloat32Array, k: int = 3, kind_hint: String = "") -> Array:
	var store: Array = ensure_store(f)
	if store.is_empty():
		return []
	var best: Array = []
	var bucket: String = kind_hint if kind_hint != "" else ""
	if bucket != "":
		var primary: Array = []
		var rest: Array = []
		for e in store:
			if str((e as Dictionary).get("kind", "")) == bucket:
				primary.append(e)
			else:
				rest.append(e)
		_scan_store(primary, query, k, best)
		if best.size() < k:
			_scan_store(rest, query, k, best)
	else:
		_scan_store(store, query, k, best)
	var out: Array = []
	for hit_wrap in best:
		var hit: Dictionary = hit_wrap["entry"]
		hit["access_count"] = int(hit.get("access_count", 0)) + 1
		# Rehearsal: recalling a memory strengthens it (bounded).
		hit["weight"] = minf(1.0, SaveHelpers._num(hit.get("weight", 0.5), 0.5) + REHEARSAL_GAIN)
		out.append(hit)
	return out


static func _situation_hash(f, situation: String) -> int:
	return hash("%s|%s|%s" % [str(f.id), situation, f.attention_focus])


static func retrieve_for_situation(f, situation: String, k: int = 2) -> PackedStringArray:
	var cache_key: String = "%s|%d" % [str(f.id), _situation_hash(f, situation)]
	var now: float = Time.get_ticks_msec() / 1000.0
	var cached: Variant = _retrieve_cache.get(cache_key, null)
	if cached is Dictionary:
		var cd: Dictionary = cached as Dictionary
		if now - float(cd.get("t", 0.0)) < RETRIEVE_TTL_S:
			_MindCacheStatsScript.retrieval_hits += 1
			return cd.get("out", PackedStringArray()) as PackedStringArray
	_MindCacheStatsScript.retrieval_misses += 1
	var t0: int = Time.get_ticks_usec()
	var q: PackedFloat32Array = embed(situation, f.attention_focus)
	var hint: String = _kind_bucket(situation)
	if hint == "" and f.attention_focus != "":
		hint = _kind_bucket(f.attention_focus)
	var hits: Array = retrieve(f, q, k, hint)
	var out: PackedStringArray = PackedStringArray()
	for h in hits:
		out.append(str(h.get("text", "")))
		if SaveHelpers._num(h.get("score", 0.0), 0.0) > 0.35:
			f._episodic_retrieval_hint = {
				"kind": str(h.get("kind", "")),
				"salience": SaveHelpers._num(h.get("weight", 0.4), 0.4),
				"pos": h.get("pos", Vector3.ZERO),
			}
			f._episodic_retrieval_hint_ttl = 0.42
	_retrieve_cache[cache_key] = {"t": now, "out": out}
	PerfGovernor.record_ledger(17, Time.get_ticks_usec(), t0)
	return out


static func tick_decay(f: Fish, dt: float) -> void:
	# Forgetting curve: weight falls linearly in time, decelerating with age
	# (Ebbinghaus / power-law: old memories that survived are sturdier) and
	# slowed by encoding salience and surprise. Rehearsal happens at RETRIEVAL
	# (see retrieve()), not here.
	#
	# The previous version multiplied the weight by (1 + salience*0.35 + ...)
	# every tick and added access_count*0.002 per tick, so weights grew
	# geometrically (0.6 -> ~1880 in four seconds at 15 Hz) and nothing was
	# ever forgotten; on save the INF weights were nulled by sanitize_for_json.
	var store: Array = ensure_store(f)
	var keep: Array = []
	var step: float = maxf(dt, 0.0)
	for e in store:
		if not (e is Dictionary):
			continue
		var age: float = SaveHelpers._num(e.get("age", 0.0), 0.0) + step
		e["age"] = age
		var w: float = clampf(SaveHelpers._num(e.get("weight", 0.5), 0.5), 0.0, 1.0)
		var sal: float = clampf(SaveHelpers._num(e.get("salience", w), w), 0.0, 1.0)
		var surprise: float = clampf(SaveHelpers._num(e.get("surprise", 0.0), 0.0), 0.0, 1.0)
		var protect: float = 1.0 + sal * 0.35 + surprise * 0.25
		var rate: float = DECAY_RATE * step / (protect * (1.0 + age / DECAY_AGE_S))
		if bool(e.get("persistent", false)):
			rate *= 0.15
		w -= rate
		e["weight"] = w
		if w > FORGET_WEIGHT:
			keep.append(e)
	f._episodic_store = keep


static func consolidate_sleep(f: Fish) -> void:
	var store: Array = ensure_store(f)
	if store.size() < 4:
		return
	# Merge near-duplicate kinds into semantic facts
	var by_kind: Dictionary = {}
	for e in store:
		var k: String = str(e.get("kind", ""))
		if not by_kind.has(k):
			by_kind[k] = []
		(by_kind[k] as Array).append(e)
	for k in by_kind.keys():
		var group: Array = by_kind[k]
		var strong: int = 0
		for e in group:
			if SaveHelpers._num(e.get("weight", 0.0), 0.0) >= 0.35:
				strong += 1
		if group.size() >= 3 and strong >= 2:
			var fact: String = "learned: %s matters here" % k
			if not f.semantic_memory.has(fact):
				f.semantic_memory.append(fact)
			while f.semantic_memory.size() > 16:
				f.semantic_memory.pop_front()
	# META #8 — distil reusable SPATIAL schemas the fish wakes up acting on:
	# cluster same-kind positioned episodes into "this region is dangerous/good".
	_consolidate_schemas(f, by_kind)


const SCHEMA_RADIUS: float = 4.0
const SCHEMA_MAX: int = 8


# Map an episode kind to a hedonic valence: danger negative, reward positive.
static func _kind_valence(kind: String) -> float:
	match kind:
		"startled", "bullied", "scared", "threat", "predator", "attacked":
			return -1.0
		"fed", "food", "ate", "bred", "spawned":
			return 1.0
		"saw_player", "keeper_word", "player":
			return 0.4
		_:
			return 0.0


# Build generalized spatial rules from clustered episodes. Each schema is the
# weighted-mean location of strong same-kind episodes + its valence/strength.
static func _consolidate_schemas(f: Fish, by_kind: Dictionary) -> void:
	var schemas: Array = []
	for k in by_kind.keys():
		var val: float = _kind_valence(str(k))
		if absf(val) < 0.01:
			continue
		var sum_pos: Vector3 = Vector3.ZERO
		var sum_w: float = 0.0
		var n: int = 0
		for e in (by_kind[k] as Array):
			var p: Variant = e.get("pos", null)
			var w: float = SaveHelpers._num(e.get("weight", 0.0), 0.0)
			if not (p is Vector3) or w < 0.2:
				continue
			sum_pos += (p as Vector3) * w
			sum_w += w
			n += 1
		if n < 2 or sum_w < 0.4:
			continue
		schemas.append({
			"kind": str(k), "center": sum_pos / sum_w,
			"valence": val, "strength": clampf(sum_w, 0.0, 3.0),
		})
	schemas.sort_custom(func(a, b):
		return absf(SaveHelpers._num(a["valence"], 0.0) * SaveHelpers._num(a["strength"], 0.0)) \
				> absf(SaveHelpers._num(b["valence"], 0.0) * SaveHelpers._num(b["strength"], 0.0)))
	f._semantic_schemas = schemas.slice(0, mini(SCHEMA_MAX, schemas.size()))


# How good/bad the learned schemas say a location is (sum of nearby schema
# valence×strength, proximity-weighted). Negative = learned-dangerous region.
static func schema_valence_at(f: Fish, pos: Vector3) -> float:
	var total: float = 0.0
	for s in (f._semantic_schemas as Array):
		var c: Variant = s.get("center", null)
		if not (c is Vector3):
			continue
		var d: float = pos.distance_to(c as Vector3)
		if d < SCHEMA_RADIUS:
			total += SaveHelpers._num(s.get("valence", 0.0), 0.0) * SaveHelpers._num(s.get("strength", 0.0), 0.0) * (1.0 - d / SCHEMA_RADIUS)
	return total


# A caution bid when the fish sits in a region its schemas have learned is bad —
# acting on a generalized rule, not a single fresh memory.
static func collect_schema_bid(f) -> Dictionary:
	if (f._semantic_schemas as Array).is_empty():
		return {}
	var v: float = schema_valence_at(f, f.position)
	if v < -0.4:
		return {"label": "threat", "salience": clampf(-v * 0.4, 0.0, 0.8),
				"coalition": ["threat", "safety", "memory", "schema"]}
	return {}


static func _prune_weakest(store: Array) -> void:
	var worst_i: int = 0
	var worst_w: float = 999.0
	var pass3: GDScript = _pass3()
	for i in store.size():
		var w: float = SaveHelpers._num(store[i].get("weight", 0.0), 0.0)
		if pass3 != null and pass3.has_method("episode_usefulness_weight"):
			w = pass3.episode_usefulness_weight(store[i])
		if w < worst_w:
			worst_w = w
			worst_i = i
	store.remove_at(worst_i)


# Save form: JSON-safe. The embedding is NOT saved — it is a deterministic
# hash of kind+text, so it is rebuilt on load (smaller state.json, and a
# Packed*Array would come back from JSON as a plain Array anyway).
static func store_to_dict(f: Fish) -> Array:
	var store: Array = ensure_store(f)
	var out: Array = []
	for e in store:
		if not (e is Dictionary):
			continue
		var d: Dictionary = (e as Dictionary).duplicate(true)
		d.erase("vec")
		d.erase("vec_q")
		d.erase("norm_q")
		d.erase("norm")
		var p: Variant = d.get("pos", null)
		if p is Vector3:
			d["pos"] = SaveHelpers.vec3_to_array(p as Vector3)
		out.append(d)
	return out


# Load form: accepts the current save format AND older saves, which stored
# the embedding as a JSON array (similarity_entry rejected it, so every loaded
# memory scored 0 and recall after a reload was insertion order, not
# relevance) and the position as the string "(x, y, z)" (so loaded episodes
# never fed sleep schemas).
static func apply_store_dict(f: Fish, arr: Variant) -> void:
	if arr is not Array:
		return
	var out: Array = []
	for raw in (arr as Array):
		if not (raw is Dictionary):
			continue
		var e: Dictionary = (raw as Dictionary).duplicate(true)
		var kind: String = str(e.get("kind", "self"))
		var text: String = str(e.get("text", ""))
		if text == "":
			continue
		e["kind"] = kind
		e["text"] = text
		var w: float = clampf(SaveHelpers._num(e.get("weight", 0.5), 0.5), 0.0, 1.0)
		e["weight"] = w
		if e.has("salience"):
			e["salience"] = clampf(SaveHelpers._num(e.get("salience", w), w), 0.0, 1.0)
		e["age"] = maxf(0.0, SaveHelpers._num(e.get("age", 0.0), 0.0))
		e["access_count"] = int(SaveHelpers._num(e.get("access_count", 0), 0.0))
		var vec: PackedFloat32Array = embed(kind, text)
		e["vec"] = vec
		e["norm"] = vec_norm(vec)
		e.erase("vec_q")
		e.erase("norm_q")
		if _quantize_enabled():
			e["vec_q"] = _quantize_vec(vec)
			e["norm_q"] = e["norm"]
		var pos: Variant = _parse_pos(e.get("pos", null))
		if pos is Vector3:
			e["pos"] = pos
		else:
			e.erase("pos")
		if w > FORGET_WEIGHT:
			out.append(e)
	while out.size() > STORE_MAX:
		_prune_weakest(out)
	f._episodic_store = out


static func _parse_pos(p: Variant) -> Variant:
	if p is Vector3:
		if (p as Vector3).is_finite():
			return p
		return null
	if p is Array and (p as Array).size() >= 3:
		return SaveHelpers.array_to_vec3(p)
	if p is String:
		var parts: PackedStringArray = (p as String).strip_edges().trim_prefix("(") \
				.trim_suffix(")").split(",", false)
		if parts.size() >= 3 and parts[0].strip_edges().is_valid_float() \
				and parts[1].strip_edges().is_valid_float() and parts[2].strip_edges().is_valid_float():
			var v := Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
			if v.is_finite():
				return v
			return null
	return null
