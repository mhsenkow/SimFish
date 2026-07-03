extends RefCounted

# CONSCIOUSNESS_ENGINEERING §E — episodic vector memory (on-device, no external embed model).

const FishMind = preload("res://scripts/fish_mind.gd")
const FishConcepts = preload("res://scripts/fish_concepts.gd")
const _MindDirtySaveScript = preload("res://scripts/mind_dirty_save.gd")
const _MindWorkerCfgScript = preload("res://scripts/mind_worker_cfg.gd")

const VECTOR_DIM: int = 32
const STORE_MAX: int = 64
const DECAY_RATE: float = 0.0008
const SALIENT_PROMOTE_WEIGHT: float = 0.62

static var _pass3_script: GDScript = null
static var _retrieve_cache: Dictionary = {}  # fish_id|sit_hash → {t, hits}
const RETRIEVE_TTL_S: float = 2.0


static func clear_caches_for_test() -> void:
	_retrieve_cache.clear()


static func _pass3() -> GDScript:
	if _pass3_script == null:
		_pass3_script = load("res://scripts/mind_soul_pass3.gd") as GDScript
	return _pass3_script


static func _quantize_enabled() -> bool:
	if not Thread.is_main_thread() and _MindWorkerCfgScript.active:
		return _MindWorkerCfgScript.read_bool("episodic_quant_8bit", true)
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree and (ml as SceneTree).root != null:
		var cfg: Node = (ml as SceneTree).root.get_node_or_null("/root/TankConfig")
		if cfg != null and cfg.get("episodic_quant_8bit") != null:
			return bool(cfg.episodic_quant_8bit)
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


static func encode_episode(f: Fish, kind: String, text: String, salience: float,
		pos: Vector3 = Vector3.INF) -> void:
	_append_episode(f, kind, text, salience, pos)


static func ingest_salient_entry(f: Fish, entry: Dictionary) -> void:
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


static func _append_episode(f: Fish, kind: String, text: String, salience: float,
		pos: Vector3 = Vector3.INF) -> void:
	var store: Array = ensure_store(f)
	var entry: Dictionary = {
		"kind": kind,
		"text": text,
		"weight": clampf(salience + (0.18 if kind == "keeper_word" else 0.0), 0.1, 1.0),
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
			return cd.get("out", PackedStringArray()) as PackedStringArray
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
	_retrieve_cache[cache_key] = {"t": now, "out": out}
	return out


static func tick_decay(f: Fish, dt: float) -> void:
	var store: Array = ensure_store(f)
	var keep: Array = []
	for e in store:
		e["age"] = SaveHelpers._num(e.get("age", 0.0), 0.0) + dt
		var w: float = SaveHelpers._num(e.get("weight", 0.5), 0.5)
		var sal: float = SaveHelpers._num(e.get("salience", w), w)
		var surprise: float = SaveHelpers._num(e.get("surprise", 0.0), 0.0)
		w = w * (1.0 + sal * 0.35 + surprise * 0.25)
		w -= DECAY_RATE * dt * (1.0 + SaveHelpers._num(e.get("age", 0.0), 0.0) * 0.01)
		if bool(e.get("persistent", false)):
			w -= DECAY_RATE * dt * 0.15
		w += SaveHelpers._num(e.get("access_count", 0), 0.0) * 0.002
		e["weight"] = w
		if w > 0.08:
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


static func store_to_dict(f: Fish) -> Array:
	var store: Array = ensure_store(f)
	var out: Array = []
	for e in store:
		var d: Dictionary = e.duplicate(true)
		out.append(d)
	return out


static func apply_store_dict(f: Fish, arr: Variant) -> void:
	if arr is not Array:
		return
	f._episodic_store = (arr as Array).duplicate(true)
