extends SceneTree

# Mind worker threading contract.
#
# 1. MindWorkerCfg used to be one shared mutable dict: the worker filled it at
#    batch start and cleared it at batch end, and flush_tick could start a
#    second batch before the first joined. One thread's clear() freed storage
#    the other was reading -> signal 11 in a headless soak. The snapshot is now
#    published on the main thread only, read-only, and replaced wholesale.
# 2. MindFishProxy copied `_episodic_store` and `_keeper_model` back from the
#    worker wholesale, erasing episodes / keeper updates the main thread made
#    while the job was pending. They are merged now.
# 3. MindTick: a cadence above the 10 Hz sim rate grew each fish's accumulator
#    without bound; fish were never staggered (the `== null` guard never fired
#    on a typed float).

const MindWorkerCfg = preload("res://scripts/mind_worker_cfg.gd")
const EpisodicMemory = preload("res://scripts/episodic_memory.gd")


func _initialize() -> void:
	var t := TestSupport.Suite.new("mind_worker_writeback")
	_cfg_snapshot(t)
	_episodic_merge(t)
	_keeper_merge(t)
	_cadence(t)
	await _pool_roundtrip(t)
	quit(t.finish())


func _cfg_snapshot(t: TestSupport.Suite) -> void:
	MindWorkerCfg.publish({"felt_self_enabled": false, "nested": {"k": 1}})
	var first: Dictionary = MindWorkerCfg.snapshot()
	t.check(first.is_read_only(), "published worker cfg is read-only")
	t.check(not MindWorkerCfg.read_bool("felt_self_enabled", true), "published value readable")
	MindWorkerCfg.publish({"felt_self_enabled": true})
	t.check(first.get("felt_self_enabled") == false,
		"a new publish swaps the snapshot; the old reference is never mutated")
	t.check(MindWorkerCfg.read_bool("felt_self_enabled", false), "new snapshot visible")
	t.check(not MindWorkerCfg.snapshot().has("nested"), "publish replaces, never merges")


func _new_fish(id: String) -> Fish:
	var f := Fish.new()
	f.id = id
	f.personality = {"boldness": 0.5, "curiosity": 0.5, "calm": 0.5, "sociability": 0.5}
	return f


func _texts(store: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for e in store:
		if e is Dictionary:
			out.append(str((e as Dictionary).get("text", "")))
	return out


func _episodic_merge(t: TestSupport.Suite) -> void:
	var f := _new_fish("wb-episodic")
	EpisodicMemory.encode_episode(f, "food", "old crumbs by the glass", 0.6)
	var job: Dictionary = MindFishProxy.capture(f)
	# Main thread keeps encoding while the job is pending...
	EpisodicMemory.encode_episode(f, "keeper_word", "the keeper said hello", 0.8)
	# ...and the worker appends its own moment.
	var proxy: MindFishProxy = MindFishProxy.from_dict(job, true)
	EpisodicMemory.encode_episode(proxy, "threat", "a shadow crossed overhead", 0.7)
	var result: MindFishProxy = MindFishProxy.from_dict(proxy.to_dict(false), true)
	result.apply_mind_to(f, true)
	var texts: PackedStringArray = _texts(f._episodic_store)
	t.check(texts.has("the keeper said hello"),
		"main-thread episode encoded while the job was pending survives write-back (%s)" % str(texts))
	t.check(texts.has("a shadow crossed overhead"), "worker-appended episode is merged in")
	t.check(texts.has("old crumbs by the glass"), "pre-existing episode kept")
	var dup: int = 0
	for s in texts:
		if s == "old crumbs by the glass":
			dup += 1
	t.equals(dup, 1, "captured episodes are not duplicated by the merge")
	var big: Array = []
	for i in EpisodicMemory.STORE_MAX:
		big.append({"kind": "self", "text": "m%d" % i, "weight": 0.5})
	var merged: Array = MindFishProxy.merge_episodic_store(big, [{"kind": "self", "text": "extra", "weight": 0.9}],
			PackedStringArray())
	t.check(merged.size() <= EpisodicMemory.STORE_MAX, "merge respects STORE_MAX")
	f.free()


func _keeper_merge(t: TestSupport.Suite) -> void:
	var f := _new_fish("wb-keeper")
	f._keeper_model = {"trust": 0.4}
	var job: Dictionary = MindFishProxy.capture(f)
	f._keeper_model["trust"] = 0.9  # a keeper line landed mid-job
	var proxy: MindFishProxy = MindFishProxy.from_dict(job, true)
	proxy._keeper_model["trust"] = 0.1
	proxy._keeper_model["worker_only"] = true
	proxy.apply_mind_to(f, true)
	t.approx(float(f._keeper_model.get("trust", 0.0)), 0.9,
		"main-thread keeper change made while pending is not overwritten")
	t.check(bool(f._keeper_model.get("worker_only", false)), "worker may add keys main lacks")
	# Untouched on main -> the worker's model is taken as-is.
	var job2: Dictionary = MindFishProxy.capture(f)
	var proxy2: MindFishProxy = MindFishProxy.from_dict(job2, true)
	proxy2._keeper_model["trust"] = 0.33
	proxy2.apply_mind_to(f, true)
	t.approx(float(f._keeper_model.get("trust", 0.0)), 0.33,
		"worker keeper result applies when main did not change it")
	f.free()


func _cadence(t: TestSupport.Suite) -> void:
	var f := _new_fish("wb-cadence")
	MindTick.reset_stats_for_test()
	MindTick.apply_ambient_snap({"mind_cadence_hz": 15.0, "mind_idle_mult": 1.0})
	var runs: int = 0
	for _i in 100:
		if bool(MindTick.advance(f, null, 0.1).get("run", false)):
			runs += 1
	t.equals(runs, 100, "15 Hz on a 10 Hz sim runs every tick")
	t.check(float(f._mind_accum) <= 0.1 + 1e-4,
		"accumulator stays bounded (got %.3f)" % float(f._mind_accum))
	MindTick.reset_stats_for_test()
	MindTick.apply_ambient_snap({"mind_cadence_hz": 5.0, "mind_idle_mult": 1.0})
	f._mind_stagger = -1.0
	runs = 0
	var used: float = 0.0
	for _i in 100:
		var g: Dictionary = MindTick.advance(f, null, 0.1)
		if bool(g.get("run", false)):
			runs += 1
			used += float(g.get("mind_dt", 0.0))
	t.in_range(float(runs), 49.0, 51.0, "5 Hz on a 10 Hz sim runs every other tick")
	t.approx(used, float(runs) * 0.2, "mind_dt is the 5 Hz step", 1e-3)
	# Stagger: sequential ids spread across both tick phases.
	var phase0: int = 0
	for i in 40:
		var p: float = MindTick.phase01("e_%d" % (i + 1))
		if p < 0.5:
			phase0 += 1
	t.in_range(float(phase0), 12.0, 28.0, "sequential ids are staggered across ticks")
	MindTick.reset_stats_for_test()
	f.free()


func _pool_roundtrip(t: TestSupport.Suite) -> void:
	await process_frame
	var f := _new_fish("wb-pool")
	f._mind_lod_tier = MindLOD.T2_WORLD_MODEL
	MindBrainPool.reset_for_test()
	MindBrainPool.begin_tick(null)
	var ms := MindState.new()
	ms.attention_focus = "food"
	MindBrainPool.queue_cognition(f, ms, 0.1)
	MindBrainPool.flush_tick()
	# A second flush while the first may still run must not start a second batch.
	MindBrainPool.queue_cognition(f, ms, 0.1)
	MindBrainPool.flush_tick()
	var st: Dictionary = MindBrainPool.stats()
	t.check(int(st.get("worker_batches", 0)) + int(st.get("deferred_flushes", 0)) >= 2,
		"second flush either deferred or ran after the first joined")
	t.check(MindBrainPool.wait_for_batch(), "batch joins")
	MindBrainPool.flush_tick()
	t.check(MindBrainPool.wait_for_batch(), "deferred jobs flush and join")
	t.check(MindBrainPool.apply_pending(f, ms), "worker result applies")
	t.check(f._bid_pool.is_empty() or f._bid_pool.size() >= MindBidPool.POOL_SIZE,
		"bid pool scratch is not shipped back from the worker")
	MindBrainPool.reset_for_test()
	f.free()
