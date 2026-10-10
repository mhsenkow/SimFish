extends SceneTree

const Memory = preload("res://scripts/episodic_memory.gd")

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_memory_recall")
	Memory.clear_caches_for_test()
	var fish := Fish.new()
	fish.id = "recall"
	fish.attention_focus = "food"
	Memory.encode_episode(fish, "food", "food", 0.8, Vector3(2, 1, 3))
	Memory.encode_episode(fish, "food", "food here", 0.5, Vector3(-2, 1, 0))
	var recalled: PackedStringArray = Memory.retrieve_for_situation(fish, "food", 1)
	t.equals(recalled.size(), 1, "one requested memory yields one result")
	t.equals(recalled[0], "food", "the strongest matching memory is recalled")
	t.check(not fish._episodic_retrieval_hint.is_empty(), "recall carries relevance into a steering cue")
	t.check(fish._episodic_retrieval_hint.get("pos") == Vector3(2, 1, 3),
		"the strongest recall supplies its actual remembered location")
	t.equals(Memory.retrieve_for_situation(fish, "food", 2).size(), 2,
		"cached recalls respect a different requested result count")
	Memory.encode_episode(fish, "food", "food", 1.0, Vector3(5, 1, 4))
	Memory.retrieve_for_situation(fish, "food", 1)
	t.check(fish._episodic_retrieval_hint.get("pos") == Vector3(5, 1, 4),
		"a fresh experience invalidates an older cached location immediately")
	var other := Fish.new()
	other.id = fish.id
	other.attention_focus = "food"
	Memory.encode_episode(other, "food", "food elsewhere", 0.8, Vector3(-5, 1, 0))
	t.equals(Memory.retrieve_for_situation(other, "food", 1)[0], "food elsewhere",
		"two hosts with the same save id cannot share recalled experiences")
	var saved: Array = Memory.store_to_dict(fish)
	for episode in saved:
		t.check(not episode.has("score"), "temporary relevance scores stay out of saved memories")
	var proxy: MindFishProxy = MindFishProxy.from_dict(MindFishProxy.capture(fish), true)
	Memory.retrieve_for_situation(proxy, "food", 1)
	Memory.encode_episode(fish, "food", "food", 1.0, Vector3(7, 1, 2))
	# Newest location is more salient than the rehearsed older one.
	fish._episodic_store[-2]["weight"] = 0.5
	Memory.clear_retrieve_cache_for(fish)
	Memory.retrieve_for_situation(fish, "food", 1)
	proxy.apply_mind_to(fish, true)
	t.check(fish._episodic_retrieval_hint.get("pos") == Vector3(7, 1, 2),
		"late worker recall cannot replace a newer main-thread experience")
	t.check(MindBrainPool.run_roundtrip_smoke(other), "real worker batch returns its cognition")
	t.check(other._episodic_retrieval_hint.get("pos") == Vector3(-5, 1, 0),
		"remembered steering cues survive the complete worker handoff")
	MindBrainPool.reset_for_test()
	fish.free()
	other.free()
	quit(t.finish())
