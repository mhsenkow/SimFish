extends SceneTree

const Learned = preload("res://scripts/fish_learned_mind.gd")
const Scheduler = preload("res://scripts/mind_scheduler.gd")
const Memory = preload("res://scripts/episodic_memory.gd")

func _initialize() -> void:
	await process_frame
	root.get_node("TankConfig").capture_mode = true
	root.get_node("TankConfig").mind_brain_threads = true
	var t := TestSupport.Suite.new("smoke_session_retention")
	MindBrainPool.reset_for_test()
	Scheduler.reset_stats_for_test()
	var tank := Node3D.new()
	root.add_child(tank)
	# Real Node removal, with completed and still-running cognition jobs.
	for generation in 24:
		var f: Fish = _fish(tank, "retired-%d" % generation)
		Learned.tick(f, null, 0.1)
		MindPromptSkeleton.skeleton_for(f, null)
		MindContext._lexicon_cache[f.id] = {"food": {"weight": 0.8}}
		MindBoundaryCache._entries[f.id] = {"lateral": {"clearance": 1.0}}
		MindDirtySave.mark(f, "full")
		MindBrainPool.queue_cognition(f, MindChannel.for_cycle(f), 0.1)
		MindBrainPool.flush_tick()
		if generation % 2 == 0:
			t.check(MindBrainPool.wait_for_batch(), "completed brain job joins")
		f.free()
		t.check(MindBrainPool.wait_for_batch(), "departed brain job still joins")
		t.equals(Learned._tick_acc.size(), 0, "learning clocks follow the fish lifetime")
		t.equals(MindPromptSkeleton._cache.size(), 0, "prompt cache releases departed fish")
		t.equals(MindContext._lexicon_cache.size(), 0, "lexicon cache releases departed fish")
		t.equals(MindBoundaryCache._entries.size(), 0, "boundary cache releases departed fish")
		t.equals(MindDirtySave._dirty.size(), 0, "late worker dirty marks are discarded")
		t.equals(MindBrainPool._pending_jobs.size(), 0, "departed fish leave no queued brain jobs")
		t.equals(MindBrainPool._results.size(), 0, "departed fish leave no brain results")
		t.equals(MindBrainPool._owners.size(), 0, "departed fish leave no worker owners")
	# A replacement with the same persisted id must never receive old state.
	var old: Fish = _fish(tank, "reloaded-id")
	MindBrainPool.queue_cognition(old, MindChannel.for_cycle(old), 0.1)
	MindBrainPool.flush_tick()
	var replacement: Fish = _fish(tank, "reloaded-id")
	MindBrainPool.queue_cognition(replacement, MindChannel.for_cycle(replacement), 0.1)
	MindDirtySave.mark(replacement, "full")
	old.free()
	t.check(MindDirtySave.is_dirty(replacement), "old lifetime cannot clear replacement's save marks")
	t.check(MindBrainPool.wait_for_batch(), "old lifetime joins during reload")
	t.check(not MindBrainPool.apply_pending(replacement), "replacement rejects old lifetime's result")
	MindBrainPool.flush_tick()
	t.check(MindBrainPool.wait_for_batch(), "replacement job joins")
	t.check(MindBrainPool.apply_pending(replacement), "replacement receives its own cognition")
	replacement.free()
	# Leaving the scene clears transient work, not personal experience.
	var traveler: Fish = _fish(tank, "traveler")
	Memory.encode_episode(traveler, "keeper_word", "the keeper says food", 0.9, Vector3(1, 2, 3))
	traveler._felt_self = {"self": "continuity", "nested": {"trust": 0.7}}
	var memories: Array = traveler._episodic_store.duplicate(true)
	var felt: Dictionary = traveler._felt_self.duplicate(true)
	tank.remove_child(traveler)
	t.equals(traveler._episodic_store, memories, "tank transfer preserves learned episodes")
	t.equals(traveler._felt_self, felt, "tank transfer preserves personal continuity")
	tank.add_child(traveler)
	t.check(MindDirtySave.fields(traveler).has("full"), "transfer requests a complete mind in the destination's next delta save")
	traveler.free()
	# Repeated situations cannot grow narrator memoization forever.
	for i in Scheduler.MAX_OP_CACHE * 3:
		Scheduler._store_op("voice-%d|calm|drift|idle" % i, {"line": "familiar water"})
	t.equals(Scheduler._op_cache.size(), Scheduler.MAX_OP_CACHE, "narrator memoization stays bounded")
	t.check(Scheduler._op_cache.has("voice-%d|calm|drift|idle" % (Scheduler.MAX_OP_CACHE * 3 - 1)), "recent thought remains cached")
	Scheduler.reset_stats_for_test()
	var voiced: Fish = _fish(tank, "voiced")
	var other: Fish = _fish(tank, "other")
	Scheduler._pending_async["voiced|calm|drift|idle"] = {"fish": voiced, "ctx": {}, "t0": 0}
	Scheduler._in_flight = true
	voiced.free()
	t.equals(Scheduler._pending_async.size(), 0, "departure cancels model request tracking")
	Scheduler._pending_async["other|calm|drift|idle"] = {"fish": other, "ctx": {}, "t0": 0}
	Scheduler._in_flight = true
	Scheduler.on_model_result("voiced|calm|drift|idle", "late old thought", {})
	t.check(Scheduler._in_flight, "late cancelled response cannot release another fish's gate")
	t.equals(Scheduler._op_cache.size(), 0, "late cancelled response cannot resurrect cache")
	other.free()
	var before_reload: Fish = _fish(tank, "voice-reloaded")
	var same_key: String = "voice-reloaded|calm|drift|idle"
	var cancelled_key: String = Scheduler._begin_model_request(same_key, before_reload, {})
	before_reload.free()
	var after_reload: Fish = _fish(tank, "voice-reloaded")
	var current_key: String = Scheduler._begin_model_request(same_key, after_reload, {})
	Scheduler._in_flight = true
	Scheduler.on_model_result(cancelled_key, "old tank thought", {})
	t.check(Scheduler._pending_async.has(current_key), "same saved id retains its new voice request")
	t.check(Scheduler._in_flight, "same situation in a reloaded tank rejects old model response")
	t.equals(Scheduler._op_cache.size(), 0, "old voice lifetime cannot populate a replacement's cache")
	after_reload.free()
	# Real narrator task cancellation still joins its worker.
	var worker_fish: Fish = _fish(tank, "worker")
	Scheduler._queue.append({"fish": worker_fish, "ctx": {"species": "guppy", "situation": "idle"},
		"cache_key": "worker|calm|drift|idle", "priority": 1.0})
	Scheduler._pump()
	worker_fish.free()
	var deadline: int = Time.get_ticks_msec() + 5000
	while not Scheduler._worker_inflight.is_empty() and Time.get_ticks_msec() < deadline:
		Scheduler.poll_workers()
	t.equals(Scheduler._worker_inflight.size(), 0, "cancelled narrator task is joined and released")
	t.equals(Scheduler._worker_results.size(), 0, "cancelled narrator result is released")
	t.equals(Scheduler._op_cache.size(), 0, "cancelled narrator result is not cached")
	t.check(not Scheduler._in_flight, "narrator becomes available after cancelled worker joins")
	tank.free()
	MindBrainPool.reset_for_test()
	Scheduler.reset_stats_for_test()
	quit(t.finish())

func _fish(tank: Node3D, fish_id: String) -> Fish:
	var f := Fish.new()
	f.id = fish_id
	tank.add_child(f)
	f.set_process(false)
	return f
