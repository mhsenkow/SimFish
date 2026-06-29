extends RefCounted

# CONSCIOUSNESS_ENGINEERING §E — episodic vector memory (on-device, no external embed model).

const FishMind = preload("res://scripts/fish_mind.gd")

const VECTOR_DIM: int = 32
const STORE_MAX: int = 64
const DECAY_RATE: float = 0.0008


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


static func similarity(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var dot: float = 0.0
	var n: int = mini(a.size(), b.size())
	for i in n:
		dot += a[i] * b[i]
	return dot


static func ensure_store(f: Fish) -> Array:
	if f.get("_episodic_store") == null or not (f._episodic_store is Array):
		f._episodic_store = []
	return f._episodic_store as Array


static func encode_episode(f: Fish, kind: String, text: String, salience: float,
		pos: Vector3 = Vector3.INF) -> void:
	var store: Array = ensure_store(f)
	var entry: Dictionary = {
		"kind": kind,
		"text": text,
		"weight": clampf(salience + (0.18 if kind == "keeper_word" else 0.0), 0.1, 1.0),
		"vec": embed(kind, text),
		"access_count": 0,
		"age": 0.0,
	}
	if kind == "keeper_word":
		entry["persistent"] = true
	if pos.is_finite() and not is_inf(pos.x):
		entry["pos"] = pos
	store.append(entry)
	while store.size() > STORE_MAX:
		_prune_weakest(store)
	# Mirror into salient ring for legacy paths
	FishMind.record_salient(f, kind, text, salience, pos)


static func retrieve(f: Fish, query: PackedFloat32Array, k: int = 3) -> Array:
	var store: Array = ensure_store(f)
	if store.is_empty():
		return []
	var scored: Array = []
	for e in store:
		var vec: Variant = e.get("vec", null)
		if vec is not PackedFloat32Array:
			continue
		var sim: float = similarity(query, vec as PackedFloat32Array)
		sim *= float(e.get("weight", 0.5))
		scored.append({"entry": e, "score": sim})
	scored.sort_custom(func(a, b): return float(a.get("score", 0.0)) > float(b.get("score", 0.0)))
	var out: Array = []
	for i in range(mini(k, scored.size())):
		var hit: Dictionary = scored[i]["entry"]
		hit["access_count"] = int(hit.get("access_count", 0)) + 1
		out.append(hit)
	return out


static func retrieve_for_situation(f: Fish, situation: String, k: int = 2) -> PackedStringArray:
	var q: PackedFloat32Array = embed(situation, f.attention_focus)
	var hits: Array = retrieve(f, q, k)
	var out: PackedStringArray = PackedStringArray()
	for h in hits:
		out.append(str(h.get("text", "")))
		if float(h.get("score", 0.0)) > 0.35:
			f._episodic_retrieval_hint = {
				"kind": str(h.get("kind", "")),
				"salience": float(h.get("weight", 0.4)),
				"pos": h.get("pos", Vector3.ZERO),
			}
	return out


static func tick_decay(f: Fish, dt: float) -> void:
	var store: Array = ensure_store(f)
	var keep: Array = []
	for e in store:
		e["age"] = float(e.get("age", 0.0)) + dt
		var w: float = float(e.get("weight", 0.5))
		w -= DECAY_RATE * dt * (1.0 + float(e.get("age", 0.0)) * 0.01)
		if bool(e.get("persistent", false)):
			w -= DECAY_RATE * dt * 0.15
		w += float(e.get("access_count", 0)) * 0.002
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
			if float(e.get("weight", 0.0)) >= 0.35:
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
			var w: float = float(e.get("weight", 0.0))
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
		return absf(float(a["valence"]) * float(a["strength"])) \
				> absf(float(b["valence"]) * float(b["strength"])))
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
			total += float(s.get("valence", 0.0)) * float(s.get("strength", 0.0)) * (1.0 - d / SCHEMA_RADIUS)
	return total


# A caution bid when the fish sits in a region its schemas have learned is bad —
# acting on a generalized rule, not a single fresh memory.
static func collect_schema_bid(f: Fish) -> Dictionary:
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
	for i in store.size():
		var w: float = float(store[i].get("weight", 0.0))
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
