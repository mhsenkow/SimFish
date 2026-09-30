extends SceneTree

# The tank feels alive while the keeper is silent (TankDialogue): overheard
# fish chatter is rate-limited, blocked during a keeper exchange and grounded
# in real fish state; the tank dreams at deep night from real event names,
# shares the dream once at dawn, and answers "what are you thinking / what
# did you dream / who is your friend / tell me about <fish>" from real state.

const TankMind = preload("res://scripts/tank_mind.gd")
const TankDialogue = preload("res://scripts/tank_dialogue.gd")
const KeeperInput = preload("res://scripts/keeper_input.gd")
const FishSocial = preload("res://scripts/fish_social.gd")
const StubScript = preload("res://scripts/tank_conversation_test_stub.gd")

var t := TestSupport.Suite.new("smoke_tank_conversation_alive")
var _stubs: Array = []
var _all_fish: Array = []


func _initialize() -> void:
	_test_chatter_gates()
	_test_chatter_grounded()
	_test_dream_from_events()
	_test_dream_via_tick()
	_test_dawn_share_once()
	_test_dawn_initiation()
	_test_intents()
	for f in _all_fish:
		if is_instance_valid(f):
			(f as Fish).free()
	for s in _stubs:
		(s as Node).free()
	quit(t.finish())


func _make_fish(id: String, nm: String, hunger: float, stress: float, pos: Vector3 = Vector3.ZERO) -> Fish:
	var f: Fish = Fish.new()
	f.id = id
	f.fish_name = nm
	f.hunger = hunger
	f.stress = stress
	f.familiarity = 0.5
	f.position = pos
	f.personality = {"boldness": 0.5, "curiosity": 0.5, "sociability": 0.5,
			"gluttony": 0.5, "calm": 0.5}
	_all_fish.append(f)
	return f


func _new_sim() -> Node:
	var sim: Node = StubScript.new()
	var k: int = _stubs.size()
	sim.fish = [
		_make_fish("a-%d-1" % k, "Pip", 0.2, 0.05, Vector3(0, 0, 0)),
		_make_fish("a-%d-2" % k, "Moss", 0.3, 0.1, Vector3(1, 0, 0)),
		_make_fish("a-%d-3" % k, "Reed", 0.2, 0.1, Vector3(30, 0, 0)),
	]
	_stubs.append(sim)
	return sim


func _chat(sim: Node, rt: Dictionary, now_s: float, quiet_s: float = 999.0, busy: bool = false,
		enabled: bool = true) -> Dictionary:
	return TankDialogue.maybe_chatter(sim, rt, sim.fish, quiet_s, busy, now_s, enabled, 0.0)


func _joined(out: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for l in out.get("lines", []) as Array:
		parts.append(str((l as Dictionary).get("line", "")))
	return " | ".join(parts)


func _test_chatter_gates() -> void:
	var sim: Node = _new_sim()
	var rt: Dictionary = {}
	var out: Dictionary = _chat(sim, rt, 1000.0)
	t.check(not out.is_empty(), "silent keeper + two close fish → chatter")
	var lines: Array = out.get("lines", []) as Array
	t.in_range(float(lines.size()), 2.0, 3.0, "chatter is 2–3 lines (got %d)" % lines.size())
	var speakers: Dictionary = {}
	for l in lines:
		speakers[str((l as Dictionary).get("name", ""))] = true
	t.check(speakers.has("Pip") and speakers.has("Moss") and not speakers.has("Reed"),
			"the two nearby fish talk; the far one doesn't (%s)" % str(speakers.keys()))
	t.check(_chat(sim, rt, 1030.0).is_empty(), "min gap between chatter exchanges")
	t.check(not _chat(sim, rt, 1000.0 + TankDialogue.CHATTER_MIN_GAP_S + 1.0).is_empty(),
			"chatter resumes after the gap")
	var rt2: Dictionary = {}
	t.check(_chat(sim, rt2, 5000.0, 999.0, true).is_empty(), "blocked during a keeper conversation")
	t.check(_chat(sim, rt2, 5000.0, 10.0).is_empty(), "blocked right after the keeper spoke")
	t.check(_chat(sim, rt2, 5000.0, 999.0, false, false).is_empty(), "voice off → no chatter")
	t.check(TankDialogue.maybe_chatter(sim, rt2, sim.fish, 999.0, false, 5000.0, true, 0.99).is_empty(),
			"chance roll keeps chatter occasional")
	t.check(TankDialogue.maybe_chatter(sim, rt2, [sim.fish[2]], 999.0, false, 5000.0, true, 0.0).is_empty(),
			"not visible together → no chatter")
	# A live keeper exchange marks the tank busy.
	var ex: Dictionary = {}
	TankDialogue.begin_exchange(ex, PackedStringArray(), PackedStringArray(), 10000)
	t.check(TankDialogue.exchange_active(ex, 12000), "keeper exchange counts as busy")
	t.check(not TankDialogue.exchange_active(ex, 10000 + TankDialogue.FOLLOWUP_EXCHANGE_WINDOW_MS + 1),
			"exchange window closes")
	# Soak: polling every 6 s for an hour stays rate-limited.
	var rt3: Dictionary = {}
	var n: int = 0
	var now: float = 0.0
	while now < 3600.0:
		if not TankDialogue.maybe_chatter(sim, rt3, sim.fish, 999.0, false, now).is_empty():
			n += 1
		now += 6.0
	t.in_range(float(n), 1.0, 3600.0 / TankDialogue.CHATTER_MIN_GAP_S + 1.0,
			"chatter rate-limited over an hour (got %d)" % n)
	# Asleep fish don't chat.
	for f in sim.fish:
		(f as Fish)._asleep = true
	t.check(_chat(sim, {}, 9000.0).is_empty(), "sleeping fish stay quiet")


func _test_chatter_grounded() -> void:
	var sim: Node = _new_sim()
	var pip: Fish = sim.fish[0]
	var moss: Fish = sim.fish[1]
	pip.hunger = 0.8
	moss.hunger = 0.7
	var out: Dictionary = _chat(sim, {}, 100.0)
	t.equals(str(out.get("kind", "")), "both_hungry", "both hungry → they talk about food")
	moss.hunger = 0.1
	out = _chat(sim, {}, 100.0)
	t.equals(str(out.get("kind", "")), "one_hungry", "one hungry → hunger mismatch")
	t.equals(str(((out.get("lines", []) as Array)[0] as Dictionary).get("name", "")), "Pip",
			"the hungry one speaks first")
	pip.hunger = 0.2
	moss.grudges[str(pip.id)] = 12.0
	out = _chat(sim, {}, 100.0)
	t.equals(str(out.get("kind", "")), "chase", "a grudge → they talk about the chase")
	t.equals(str(((out.get("lines", []) as Array)[0] as Dictionary).get("name", "")), "Moss",
			"the chased fish speaks first")
	t.equals(str(((out.get("lines", []) as Array)[1] as Dictionary).get("name", "")), "Pip",
			"the chaser answers (%s)" % _joined(out))
	moss.grudges.clear()
	var baby: Fish = _make_fish("a-baby", "Sprout", 0.2, 0.0, Vector3(20, 0, 0))
	baby.generation = 1
	baby.age = 30.0
	sim.fish.append(baby)
	out = _chat(sim, {}, 100.0)
	t.equals(str(out.get("kind", "")), "newborn", "a new fry nearby → they talk about it")
	t.check(_joined(out).contains("Sprout"), "newborn chatter names the fry (%s)" % _joined(out))
	sim.fish.erase(baby)
	FishSocial.record_event(pip, moss, "schooled", 0.5)
	out = _chat(sim, {}, 100.0)
	t.equals(str(out.get("kind", "")), "friends", "friends → friendly chatter")
	pip.bonds.clear()
	var rt: Dictionary = {}
	sim.daylight_value = 0.8
	_chat(sim, rt, 10.0, 999.0, true)
	sim.daylight_value = 0.3
	out = _chat(sim, rt, 20.0)
	t.equals(str(out.get("kind", "")), "light_dim", "the light going down → they notice it")


func _test_dream_from_events() -> void:
	var sim: Node = _new_sim()
	var tm: Dictionary = TankMind.ensure(sim)
	var rt: Dictionary = {}
	var st: Dictionary = TankMind.keeper_state(sim)
	TankDialogue.observe(sim, tm, rt, st, 0.0)
	var baby: Fish = _make_fish("d-baby", "Sprout", 0.2, 0.0)
	baby.generation = 1
	baby.age = 5.0
	sim.fish.append(baby)
	sim.fish.erase(sim.fish[2])  # Reed dies
	TankDialogue.observe(sim, tm, rt, st, 2.0)
	t.check((tm.get("dream_seeds", []) as Array).size() >= 2, "births/deaths become dream seeds")
	t.check(TankDialogue.maybe_dream(sim, tm, 0.5).is_empty(), "no dream in daylight")
	tm["duration_since_dusk"] = 10.0
	t.check(TankDialogue.maybe_dream(sim, tm, 0.05).is_empty(), "no dream right after dusk")
	tm["duration_since_dusk"] = 200.0
	var v0: float = float(tm.get("mood_valence", 0.0))
	var d: Dictionary = TankDialogue.maybe_dream(sim, tm, 0.05)
	var line: String = str(d.get("line", ""))
	t.check(line.begins_with("we dreamed"), "dream in the tank voice (%s)" % line)
	t.check(line.contains("Reed") and line.contains("Sprout"), "dream recombines real event names (%s)" % line)
	t.check(not is_equal_approx(float(tm.get("mood_valence", 0.0)), v0), "dreams nudge tank mood")
	t.check(TankDialogue.maybe_dream(sim, tm, 0.05).is_empty(), "one dream per night")
	t.is_empty_arr(tm.get("dream_seeds", []) as Array, "the day's seeds are spent")
	var parsed: Variant = JSON.parse_string(JSON.stringify(TankMind.to_dict(sim)))
	var sim2: Node = _new_sim()
	TankMind.from_dict(sim2, parsed)
	t.equals(str((TankMind.ensure(sim2).get("last_dream", {}) as Dictionary).get("line", "")), line,
			"the last dream survives a save round-trip")


func _test_dream_via_tick() -> void:
	var sim: Node = _new_sim()
	var tm: Dictionary = TankMind.ensure(sim)
	TankDialogue.note_dream_seed(tm, "birth", "Tiny", "", 0.8)
	sim.daylight_value = 0.05
	sim.day_phase = 0.75
	TankMind.tick(sim, 100.0, 0.0)
	tm = TankMind.ensure(sim)
	var dline: String = str((tm.get("last_dream", {}) as Dictionary).get("line", ""))
	t.check(dline.contains("Tiny"), "deep night tick dreams from the day (%s)" % dline)
	var ledger_hit: bool = false
	for l in tm.get("night_ledger", []) as Array:
		if str(l).begins_with("the tank dreamed"):
			ledger_hit = true
	t.check(ledger_hit, "the dream lands in the night ledger")


func _dreamt_sim() -> Node:
	var sim: Node = _new_sim()
	var tm: Dictionary = TankMind.ensure(sim)
	TankDialogue.note_dream_seed(tm, "death", "Old Fin", "", 0.9)
	tm["duration_since_dusk"] = 200.0
	TankDialogue.maybe_dream(sim, tm, 0.05)
	sim.daylight_value = 0.8
	return sim


func _test_dawn_share_once() -> void:
	var sim: Node = _dreamt_sim()
	var tm: Dictionary = TankMind.ensure(sim)
	sim.daylight_value = 0.1
	t.check(not TankDialogue.dream_share_ready(tm, TankMind.keeper_state(sim)), "not shared while still dark")
	sim.daylight_value = 0.8
	var r1: Dictionary = TankMind.keeper_reply(sim, "good morning")
	t.check(str(r1.get("line", "")).contains("last night we dreamed") and str(r1.get("line", "")).contains("Old Fin"),
			"morning: the tank tells its dream (%s)" % r1.get("line", ""))
	var r2: Dictionary = TankMind.keeper_reply(sim, "hello again")
	t.check(not str(r2.get("line", "")).contains("we dreamed"), "the dream is shared only once (%s)" % r2.get("line", ""))


func _test_dawn_initiation() -> void:
	var sim: Node = _dreamt_sim()
	var tm: Dictionary = TankMind.ensure(sim)
	var rt: Dictionary = {}
	var st: Dictionary = TankMind.keeper_state(sim)
	var away: Dictionary = TankDialogue.maybe_initiate(sim, tm, rt, st, 100.0, 1000.0, true, false)
	t.check(away.is_empty(), "nobody at the glass → the dream waits")
	var out: Dictionary = TankDialogue.maybe_initiate(sim, tm, rt, st, 100.0, 1002.0, true, true)
	t.equals(str(out.get("kind", "")), "dream", "keeper present at dawn → the tank shares its dream")
	t.check(str(out.get("line", "")).contains("Old Fin"), "shared dream is the real one (%s)" % out.get("line", ""))
	var again: Dictionary = TankDialogue.maybe_initiate(sim, tm, rt, st, 100.0, 5000.0, true, true)
	t.check(str(again.get("kind", "")) != "dream", "dream initiation fires once")


func _test_intents() -> void:
	var sim: Node = _dreamt_sim()
	var pip: Fish = sim.fish[0]
	var moss: Fish = sim.fish[1]
	var tm: Dictionary = TankMind.ensure(sim)
	var dline: String = str((tm["last_dream"] as Dictionary).get("line", ""))
	t.equals(str(TankDialogue.detect_intent(sim, "what did you dream?").get("intent", "")), "dream", "dream intent")
	t.equals(str(TankDialogue.detect_intent(sim, "what are you thinking?").get("intent", "")), "thinking", "thinking intent")
	t.equals(str(TankDialogue.detect_intent(sim, "who is your friend?").get("intent", "")), "friend", "friend intent")
	t.equals(str(TankDialogue.detect_intent(sim, "tell me about Moss").get("intent", "")), "about", "about intent")
	t.equals(str(TankDialogue.detect_intent(sim, "tell me about Nobody").get("intent", "")), "", "unknown names aren't about-intents")
	t.equals(str(TankDialogue.detect_intent(sim, "you're my friend").get("intent", "")), "", "a statement isn't a question")
	var r: Dictionary = TankMind.keeper_reply(sim, "what did you dream?")
	t.equals(str(r.get("intent", "")), "dream", "keeper_reply routes the dream question")
	t.check(str(r.get("line", "")).begins_with(dline), "the tank answers with its real dream (%s)" % r.get("line", ""))
	pip.attention_focus = "food_patch"
	r = TankMind.keeper_reply(sim, "what are you thinking?")
	t.check(str(r.get("line", "")).contains("we're thinking of"), "thinking answer from the workspace (%s)" % r.get("line", ""))
	t.check(str(r.get("line", "")).contains("Pip keeps turning toward food patch"),
			"thinking answer names a fish's real focus (%s)" % r.get("line", ""))
	FishSocial.record_event(pip, moss, "schooled", 0.6)
	r = TankMind.keeper_reply(sim, "who is your friend?")
	t.check(str(r.get("line", "")).contains("Pip and Moss"), "friend answer from the social graph (%s)" % r.get("line", ""))
	t.check(TankDialogue.fish_intent_line(sim, pip, "friend").contains("Moss"),
			"Pip names its friend (%s)" % TankDialogue.fish_intent_line(sim, pip, "friend"))
	moss.hunger = 0.1
	r = TankMind.keeper_reply(sim, "tell me about Moss")
	t.check(str(r.get("line", "")).begins_with("Moss") and str(r.get("line", "")).contains("right now calm"),
			"about answer from real state (%s)" % r.get("line", ""))
	var res: Dictionary = KeeperInput.submit_to_tank(sim, "tell me about Pip")
	var ids: PackedStringArray = res.get("responder_ids", PackedStringArray())
	t.check(not ids.is_empty() and ids[0] == str(pip.id), "the fish asked about answers first")
	var answers: Dictionary = res.get("fish_answers", {}) as Dictionary
	t.check(str(answers.get(str(pip.id), "")).begins_with("me?"), "Pip answers about itself (%s)" % answers.get(str(pip.id), ""))
	if ids.size() > 1:
		t.check(str(answers.get(ids[1], "")).contains("Pip"), "another fish answers about Pip (%s)" % answers.get(ids[1], ""))
	var th: String = TankDialogue.fish_intent_line(sim, moss, "thinking")
	t.check(th != "", "a fish says what it's thinking (%s)" % th)
