extends SceneTree

# Fish minds that remember, learn words, and speak from what they hold.
#
# Pins the mind-pipeline fixes that made the template voice worth grounding:
#   - episodic memory decays (weights used to grow geometrically, ~0.6 -> 1880
#     in four seconds) and rehearsal on recall is bounded
#   - episodic memory survives a JSON save/load with its relevance (the saved
#     embedding came back as a plain Array and every loaded memory scored 0)
#     and its position (came back as the string "(x, y, z)")
#   - a learned word is recognised inside real punctuation ("dinner!") and is
#     not forgotten ~20 s after the lesson
#   - the keeper model actually initialises on a Fish (its `{}` default made
#     ensure() return the empty dict) and survives JSON
#   - the template voice draws on THIS fish's memories / words / needs, stays
#     within the reply budget, varies, and two fish no longer share one cached
#     thought

const EpisodicMemory = preload("res://scripts/episodic_memory.gd")
const MindLexicon = preload("res://scripts/mind_lexicon.gd")
const MindKeeperModel = preload("res://scripts/mind_keeper_model.gd")
const MindNarrator = preload("res://scripts/mind_narrator.gd")
const FishMind = preload("res://scripts/fish_mind.gd")


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_mind_grounding")
	EpisodicMemory.clear_caches_for_test()
	_test_episodic_decay(t)
	_test_episodic_roundtrip(t)
	_test_lexicon(t)
	_test_keeper_model(t)
	_test_voice(t)
	quit(t.finish())


func _mk(id: String) -> Fish:
	var f: Fish = Fish.new()
	root.add_child(f)
	f.set_process(false)
	f.set_physics_process(false)
	f.id = id
	f.fish_name = id.capitalize()
	return f


func _json_roundtrip(v: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(SaveHelpers.sanitize_for_json(v)))


func _test_episodic_decay(t: TestSupport.Suite) -> void:
	var f: Fish = _mk("decay")
	EpisodicMemory.encode_episode(f, "fed", "hand-fed near the glass", 0.6, Vector3(1, 2, 3))
	EpisodicMemory.encode_episode(f, "startled", "a sudden fright", 0.3)
	for _i in 60:
		EpisodicMemory.tick_decay(f, 1.0 / 15.0)
	var store: Array = f._episodic_store
	t.check(store.size() == 2, "both episodes survive a few seconds (%d)" % store.size())
	var w0: float = float((store[0] as Dictionary).get("weight", 0.0))
	t.in_range(w0, 0.5, 0.6, "episode weight decays slowly, never grows")
	# Long neglect: minutes of mind time forget the weak memory first.
	for _i in 400:
		EpisodicMemory.tick_decay(f, 10.0)
	var kinds: Array = []
	for e in f._episodic_store:
		kinds.append(str(e.get("kind", "")))
	t.check(not kinds.has("startled"), "a weak memory is eventually forgotten (%s)" % str(kinds))
	# Recall rehearses but stays bounded.
	var g: Fish = _mk("rehearse")
	EpisodicMemory.encode_episode(g, "fed", "hand-fed near the glass", 0.95)
	for _i in 50:
		EpisodicMemory.retrieve(g, EpisodicMemory.embed("fed", "hand-fed near the glass"), 1)
	t.check(float((g._episodic_store[0] as Dictionary).get("weight", 0.0)) <= 1.0,
			"rehearsal keeps weight <= 1")


func _test_episodic_roundtrip(t: TestSupport.Suite) -> void:
	var f: Fish = _mk("save")
	EpisodicMemory.encode_episode(f, "fed", "hand-fed near the glass", 0.7, Vector3(1, 2, 3))
	EpisodicMemory.encode_episode(f, "startled", "a sudden fright by the log", 0.5)
	var back: Variant = _json_roundtrip(EpisodicMemory.store_to_dict(f))
	var g: Fish = _mk("load")
	EpisodicMemory.apply_store_dict(g, back)
	t.check(g._episodic_store.size() == 2, "episodes survive JSON")
	var q: PackedFloat32Array = EpisodicMemory.embed("fed", "hand-fed near the glass")
	var sim_loaded: float = EpisodicMemory.similarity_entry(q, g._episodic_store[0])
	t.check(sim_loaded > 0.9, "loaded memory keeps its relevance (sim %.2f)" % sim_loaded)
	t.check(g._episodic_store[0].get("pos") is Vector3, "loaded memory keeps its place")
	# Salient memories keep WHERE they happened through a full mind save.
	var sf: Fish = _mk("salient")
	FishMind.record_salient(sf, "startled", "a sudden fright", 0.8, Vector3(2, 1, 0))
	var md: Variant = _json_roundtrip(FishMind.mind_to_dict(sf))
	var sg: Fish = _mk("salient2")
	FishMind.apply_mind_dict(sg, md as Dictionary)
	t.check(sg.salient_memories.size() > 0 and sg.salient_memories[0].get("pos") is Vector3,
			"salient memory position survives a mind save")
	t.check(FishMind.salient_avoid_steer(sg, Vector3(2.5, 1, 0)).length() > 0.0,
			"reloaded fish still avoids where it was frightened")
	# Legacy save shape: embedding as a JSON array, position as "(x, y, z)".
	var legacy: Array = [{"kind": "fed", "text": "hand-fed near the glass", "weight": 0.6,
			"vec": [0.1, 0.2], "pos": "(4.0, 1.0, -2.0)", "age": 10.0}]
	var h: Fish = _mk("legacy")
	EpisodicMemory.apply_store_dict(h, _json_roundtrip(legacy))
	t.check(h._episodic_store.size() == 1 \
			and EpisodicMemory.similarity_entry(q, h._episodic_store[0]) > 0.9,
			"legacy-format memory is recallable after migration")
	var p: Variant = h._episodic_store[0].get("pos") if h._episodic_store.size() > 0 else null
	t.check(p is Vector3 and (p as Vector3).is_equal_approx(Vector3(4, 1, -2)),
			"legacy string position is parsed (%s)" % str(p))


func _test_lexicon(t: TestSupport.Suite) -> void:
	var f: Fish = _mk("lex")
	for _i in 3:
		MindLexicon.try_pair_on_keeper_word(f, "dinner", null)
	t.check(MindLexicon.comprehend(f, "dinner!"), "a learned word is heard through punctuation")
	t.equals(MindLexicon.normalize_token("  Food?? "), "food", "normalize strips punctuation")
	for _i in 60:
		MindLexicon.tick_decay(f, 1.0)
	t.check(MindLexicon.comprehend(f, "dinner"), "a learned word survives a minute of play")
	var back: Variant = _json_roundtrip(MindLexicon.to_dict(f))
	var g: Fish = _mk("lex2")
	MindLexicon.from_dict(g, back)
	t.check(MindLexicon.comprehend(g, "dinner"), "learned word survives JSON")
	# Worker attention hosts a MindFishProxy, not a Fish — comprehend must
	# accept it (typed Fish args throw at the call site otherwise).
	var proxy: MindFishProxy = MindFishProxy.from_dict(MindFishProxy.capture(f), true)
	t.check(MindLexicon.comprehend(proxy, "dinner"), "proxy carries learned words")
	# food_bid_boost is the worker hot path (global_workspace). It must accept
	# a proxy without a typed-arg crash; boost itself is 0 unless kind==food.
	t.check(MindLexicon.food_bid_boost(proxy, "dinner") >= 0.0,
			"food_bid_boost accepts a proxy without type error")
	(MindLexicon.ensure_dict(proxy)["dinner"] as Dictionary)["kind"] = "food"
	t.check(MindLexicon.food_bid_boost(proxy, "dinner") > 0.0,
			"proxy food word boosts the food bid")


func _test_keeper_model(t: TestSupport.Suite) -> void:
	var f: Fish = _mk("km")
	var km: Dictionary = MindKeeperModel.ensure(f)
	t.check(km.has("care_trust") and km.has("player_moniker"), "keeper model initialises on a Fish")
	t.check(is_same(km, f._keeper_model), "ensure returns the fish's own model")
	km["speech_themes"] = PackedStringArray(["dinner"])
	var back: Variant = _json_roundtrip(MindKeeperModel.to_dict(f))
	var g: Fish = _mk("km2")
	MindKeeperModel.from_dict(g, back)
	var themes: Variant = MindKeeperModel.ensure(g).get("speech_themes")
	t.check(themes is PackedStringArray and (themes as PackedStringArray).has("dinner"),
			"keeper speech themes survive JSON")
	var ctx: Dictionary = MindKeeperModel.merge_context({}, g)
	t.check(ctx.has("keeper_themes"), "reloaded themes reach the voice context")


func _test_voice(t: TestSupport.Suite) -> void:
	# A fish with a keeper memory, a learned food word, and an empty belly.
	var f: Fish = _mk("pip")
	f.familiarity = 0.7
	f.hunger = 0.8
	f.age = f.max_age_s * 0.3
	FishMind.record_salient(f, "fed", "hand-fed near the glass", 0.8, f.position)
	for _i in 3:
		MindLexicon.try_pair_on_keeper_word(f, "dinner", null)
	(MindLexicon.ensure_dict(f)["dinner"] as Dictionary)["kind"] = "food"
	f._keeper_pending = {"keeper_text": "dinner!", "keeper_intent": "food",
			"keeper_comprehension": 1.0, "keeper_felt": "neutral"}
	var ctx: Dictionary = MindContext.build_for_keeper_turn(f, null, "keeper_reply")
	t.check(ctx.get("understood_words") is PackedStringArray \
			and (ctx["understood_words"] as PackedStringArray).has("dinner"),
			"context knows which keeper words the fish understood")
	t.equals(str(ctx.get("keeper_episode", "")), "hand-fed near the glass",
			"context carries the fish's keeper memory")
	t.equals(str(ctx.get("goal", "")), "eat", "active-inference goal reaches the voice")
	# Speak across several turns: grounded, within budget, not one stock line.
	var lines: Dictionary = {}
	var grounded: int = 0
	for turn in 8:
		ctx["conversation_count"] = turn
		ctx["keeper_intent"] = ["food", "greeting", "comfort", "neutral"][turn % 4]
		var line: String = MindNarrator.template_fish_reply(ctx)
		t.check(line.split(" ", false).size() <= MindNarrator.FISH_REPLY_MAX_WORDS,
				"reply within budget: %s" % line)
		lines[line] = true
		var low: String = line.to_lower()
		for needle in ["dinner", "food", "glass", "belly", "hungry", "remember", "eat"]:
			if low.contains(needle):
				grounded += 1
				break
	t.check(lines.size() >= 4, "replies vary across turns (%d distinct: %s)" % [lines.size(), str(lines.keys())])
	t.check(grounded >= 5, "replies are grounded in memory/words/needs (%d/8: %s)" % [grounded, str(lines.keys())])
	# A question is answered from the fish's own state.
	ctx["keeper_intent"] = "question"
	ctx["keeper_comprehension"] = 0.8
	var ans: String = MindNarrator.template_fish_reply(ctx).to_lower()
	t.check(ans.contains("food") or ans.contains("belly") or ans.contains("hungry") or ans.contains("eat"),
			"a hungry fish answers a question with what it wants: %s" % ans)
	# Two fish in the same mood think their OWN memories (old shared cache bug).
	var a_ctx: Dictionary = {"fish_id": "a", "feel": "calm", "intends": "wander",
			"episodes": [{"kind": "social", "text": "made peace with the tetra", "keeper": false}]}
	var b_ctx: Dictionary = {"fish_id": "b", "feel": "calm", "intends": "wander",
			"episodes": [{"kind": "startled", "text": "a heron shadow at dusk", "keeper": false}]}
	var ta: String = MindNarrator.template_fish_thought(a_ctx)
	var tb: String = MindNarrator.template_fish_thought(b_ctx)
	t.check(ta.contains("tetra") and tb.contains("heron"),
			"each fish thinks its own memory (%s | %s)" % [ta, tb])
	# Unknown speech stays honest, and names the one word it did learn.
	var u_ctx: Dictionary = ctx.duplicate()
	u_ctx["keeper_intent"] = "unknown_sound"
	u_ctx["keeper_comprehension"] = 0.2
	var u: String = MindNarrator.template_fish_reply(u_ctx)
	t.check(u.contains("don't know") and u.contains("dinner"), "partial understanding is honest: %s" % u)
