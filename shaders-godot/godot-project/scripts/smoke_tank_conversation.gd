extends SceneTree

# "Speak to the tank": collective tank-mind reply generator + fish responder
# selection + fish-reply shaping (MindConversation.shape_keeper_reply).

const TankMind = preload("res://scripts/tank_mind.gd")
const MindConversation = preload("res://scripts/mind_conversation.gd")
const KeeperCare = preload("res://scripts/keeper_care.gd")
const _MindContext = preload("res://scripts/mind_context.gd")
const StubScript = preload("res://scripts/tank_conversation_test_stub.gd")

var t := TestSupport.Suite.new("smoke_tank_conversation")
var _sim: Node = null


func _initialize() -> void:
	_sim = StubScript.new()
	_sim.fish = [
		_make_fish("tc-1", "Pip", 0.2, 0.05, 0.7),
		_make_fish("tc-2", "Moss", 0.9, 0.1, 0.3),
		_make_fish("tc-3", "Reed", 0.3, 0.8, 0.2),
		_make_fish("tc-4", "", 0.1, 0.0, 0.1),
	]
	_test_parse()
	_test_non_empty()
	_test_low_o2_grounding()
	_test_hungry_grounding()
	_test_no_immediate_repeat()
	_test_responders()
	_test_fish_reply_shaping()
	_test_tank_feedback()
	_test_intimacy()
	for f in _sim.fish:
		(f as Fish).free()
	_sim.free()
	quit(t.finish())


func _make_fish(id: String, nm: String, hunger: float, stress: float, fam: float) -> Fish:
	var f: Fish = Fish.new()
	f.id = id
	f.fish_name = nm
	f.hunger = hunger
	f.stress = stress
	f.familiarity = fam
	f.personality = {"boldness": 0.5, "curiosity": 0.5, "sociability": 0.5,
			"gluttony": 0.5, "calm": 0.5}
	return f


func _reset_state() -> void:
	_sim.dissolved_o2 = 0.9
	_sim.water_chemistry.ammonia = 0.02
	_sim.daylight_value = 0.8
	for f in _sim.fish:
		(f as Fish).hunger = 0.2
	(_sim.fish[1] as Fish).hunger = 0.9
	(_sim.fish[2] as Fish).stress = 0.8


func _test_parse() -> void:
	var p: Dictionary = TankMind.parse_keeper_words("Are you hungry? Food soon!")
	var topics: PackedStringArray = p["topics"]
	t.check(topics.has("food"), "food topic parsed from 'hungry/food' (got %s)" % str(topics))
	t.check((p["heard"] as PackedStringArray).has("hungry"), "heard contains 'hungry'")
	var q: Dictionary = TankMind.parse_keeper_words("blorp?")
	t.check((q["topics"] as PackedStringArray).has("wellbeing"), "bare question → wellbeing")


func _test_non_empty() -> void:
	_reset_state()
	for text in ["hello", "how are you?", "zzkrrt", "who is here", "goodnight", "I love you"]:
		var r: Dictionary = TankMind.keeper_reply(_sim, text)
		t.has_keys(r, ["line", "topics", "heard", "understood"], "reply shape for '%s'" % text)
		t.check(str(r["line"]).strip_edges() != "", "non-empty tank reply for '%s'" % text)


func _test_low_o2_grounding() -> void:
	_reset_state()
	_sim.dissolved_o2 = 0.3
	var r: Dictionary = TankMind.keeper_reply(_sim, "can you breathe? is the air ok")
	var line: String = str(r["line"]).to_lower()
	t.check(line.contains("o2") or line.contains("thin") or line.contains("breath")
			or line.contains("air"), "low-O2 reply is grounded (got '%s')" % line)
	t.check(line.contains("30%") or line.contains("thin") or line.contains("gasp")
			or line.contains("low") or line.contains("hard"),
			"low-O2 reply names the problem (got '%s')" % line)
	# Unrelated words still surface the pressing low-O2 state.
	var r2: Dictionary = TankMind.keeper_reply(_sim, "hello")
	var l2: String = str(r2["line"]).to_lower()
	t.check(l2.contains("thin") or l2.contains("o2") or l2.contains("gills") or l2.contains("breathing"),
			"greeting under low O2 still grounds in O2 (got '%s')" % l2)


func _test_hungry_grounding() -> void:
	_reset_state()
	for f in _sim.fish:
		(f as Fish).hunger = 0.85
	var r: Dictionary = TankMind.keeper_reply(_sim, "are you hungry? food?")
	var line: String = str(r["line"]).to_lower()
	t.check(line.contains("hungry") or line.contains("bellies") or line.contains("looking up"),
			"hungry reply grounded (got '%s')" % line)
	t.check(line.contains("food") or line.contains("hungry"),
			"hungry reply echoes the keeper's word (got '%s')" % line)
	t.check((r["understood"] as PackedStringArray).size() > 0, "understood words reported")
	# Fed tank answers differently to the same words.
	for f in _sim.fish:
		(f as Fish).hunger = 0.05
	var fed: String = str(TankMind.keeper_reply(_sim, "food?")["line"]).to_lower()
	t.check(fed.contains("fed") or fed.contains("wait") or fed.contains("not yet") or fed.contains("heavy"),
			"fed tank says it is fed (got '%s')" % fed)


func _test_no_immediate_repeat() -> void:
	_reset_state()
	var prev: String = ""
	var repeats: int = 0
	for i in 24:
		var line: String = str(TankMind.keeper_reply(_sim, "hello")["line"])
		if line == prev:
			repeats += 1
		prev = line
	t.equals(repeats, 0, "no immediate repeats over 24 identical keeper lines")
	var recent: Array = TankMind.ensure(_sim).get("keeper_recent_lines", [])
	t.in_range(float(recent.size()), 1.0, float(TankMind.KEEPER_RECENT_MAX), "recent ring bounded")


func _test_responders() -> void:
	_reset_state()
	var food: Array = TankMind.pick_keeper_responders(_sim, PackedStringArray(["food"]),
			PackedStringArray(["food"]))
	t.in_range(float(food.size()), 1.0, float(TankMind.RESPONDERS_MAX), "1–3 responders for food")
	for f in food:
		t.check(f is Fish and _sim.fish.has(f), "responder is a live tank fish")
	t.check(food.size() > 0 and (food[0] as Fish).id == "tc-2", "hungriest fish answers first about food")
	var calm: Array = TankMind.pick_keeper_responders(_sim, PackedStringArray(["calm"]),
			PackedStringArray(["safe"]))
	t.check(calm.size() > 0 and (calm[0] as Fish).id == "tc-3", "most stressed fish answers 'safe'")
	var named: Array = TankMind.pick_keeper_responders(_sim, PackedStringArray(),
			PackedStringArray(["reed"]))
	t.check(named.size() > 0 and (named[0] as Fish).id == "tc-3", "fish addressed by name answers")
	(_sim.fish[1] as Fish)._asleep = true
	var sleepy: Array = TankMind.pick_keeper_responders(_sim, PackedStringArray(["greeting"]),
			PackedStringArray(["hi"]))
	t.check(sleepy.size() > 0 and (sleepy[0] as Fish).id != "tc-2", "asleep fish is not first to answer")
	(_sim.fish[1] as Fish)._asleep = false
	var empty_sim: Node = StubScript.new()
	t.is_empty_arr(TankMind.pick_keeper_responders(empty_sim, PackedStringArray(), PackedStringArray()),
			"no fish → no responders")
	t.check(str(TankMind.keeper_reply(empty_sim, "hello")["line"]) != "", "empty tank still answers")
	empty_sim.free()


func _test_fish_reply_shaping() -> void:
	var f: Fish = _sim.fish[0]
	f._dialogue_ring = [{"role": "fish", "text": "I hear you", "t": 0}]
	var shaped: String = MindConversation.shape_keeper_reply(f, "I hear you", "hello")
	t.check(shaped != "I hear you", "repeated fish template rerolled (got '%s')" % shaped)
	t.check(shaped != "", "rerolled fish line non-empty")
	t.equals(MindConversation.shape_keeper_reply(f, "…", "hello"), "…", "silence passes through")
	# Echo a word this fish has actually paired.
	f._learned_words = {"food": {"kind": "food", "pairings": 5, "strength": 0.8, "last_t": 0}}
	var echoed: String = MindConversation.shape_keeper_reply(f, "yes, now", "food time")
	t.check(echoed.to_lower().contains("food"), "understood word echoed (got '%s')" % echoed)


func _test_tank_feedback() -> void:
	var line: String = KeeperCare.tank_feedback({"ok": true, "understood": PackedStringArray(["food"]),
			"responder_ids": PackedStringArray(["a", "b"]), "tank_tier": KeeperCare.Tier.STEADY}, _sim)
	t.check(line.contains("food") and line.contains("2 answering"), "tank feedback line (got '%s')" % line)
	t.check(KeeperCare.placeholder_for_tank(_sim) != "", "tank placeholder non-empty")


# Keeper-turn replies (incl. tank-channel responders) must carry a real
# ctx["intimacy"]: mind_narrator greets familiar fish by moniker only above
# 0.45 and treats < 0.35 as a stranger.
func _test_intimacy() -> void:
	var fam: Fish = _sim.fish[0]  # familiarity 0.7
	var stranger: Fish = _sim.fish[3]  # familiarity 0.1
	var ctx: Dictionary = _MindContext.build_for_keeper_turn(fam, _sim, "keeper_reply")
	ctx = MindConversation.enrich_context(ctx, fam, _sim)
	t.check(float(ctx.get("intimacy", 0.0)) >= 0.7 - 0.001,
			"familiar fish keeper-turn intimacy >= familiarity (got %s)" % ctx.get("intimacy"))
	t.check(float(ctx.get("intimacy", 0.0)) > 0.45, "familiar fish clears the narrator's moniker gate")
	var sctx: Dictionary = MindConversation.enrich_context(
			_MindContext.build_for_keeper_turn(stranger, _sim, "keeper_reply"), stranger, _sim)
	t.check(float(sctx.get("intimacy", 1.0)) < 0.35, "stranger stays below the familiar gate (got %s)" % sctx.get("intimacy"))
	var bare: Dictionary = MindConversation.ensure_intimacy({"intimacy": 0.0}, fam)
	t.approx(float(bare["intimacy"]), MindConversation.intimacy_for(fam), "ensure_intimacy fills a flat 0.0")
