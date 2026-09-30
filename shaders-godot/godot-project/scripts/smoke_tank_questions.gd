extends SceneTree

# Fish ask the keeper (TankQuestions): questions are grounded in real state
# (a death → "where did X go?"), rate-limited, the keeper's answer is stored
# (episodic memory + per-fish answers map), persisted through a JSON save,
# migrated from old / malformed saves, referenced later, fades when ignored,
# and freed fish never crash it.

const TankMind = preload("res://scripts/tank_mind.gd")
const TankQuestions = preload("res://scripts/tank_questions.gd")
const TankDialogue = preload("res://scripts/tank_dialogue.gd")
const StubScript = preload("res://scripts/tank_conversation_test_stub.gd")

const T0: float = 1_000_000.0
const FISH_ROLL: float = 0.3
const TANK_ROLL: float = 0.05

var t := TestSupport.Suite.new("smoke_tank_questions")
var _stubs: Array = []
var _all_fish: Array = []


func _initialize() -> void:
	_test_death_question_and_answer()
	_test_rate_limits()
	_test_persist_and_migrate()
	_test_fade_when_ignored()
	_test_collective_question()
	_test_freed_fish_safe()
	for f in _all_fish:
		if is_instance_valid(f):
			(f as Fish).free()
	for s in _stubs:
		(s as Node).free()
	quit(t.finish())


func _make_fish(id: String, nm: String) -> Fish:
	var f: Fish = Fish.new()
	f.id = id
	f.fish_name = nm
	f.hunger = 0.2
	f.stress = 0.05
	f.familiarity = 0.5
	f.personality = {"boldness": 0.5, "curiosity": 0.5, "sociability": 0.5,
			"gluttony": 0.5, "calm": 0.5}
	_all_fish.append(f)
	return f


func _new_sim() -> Node:
	var sim: Node = StubScript.new()
	var n: int = _stubs.size()
	sim.fish = [_make_fish("q-%d-1" % n, "Pip"), _make_fish("q-%d-2" % n, "Moss"),
			_make_fish("q-%d-3" % n, "Reed")]
	_stubs.append(sim)
	return sim


func _ask(sim: Node, rt: Dictionary, now: float, roll: float = FISH_ROLL, present: bool = true,
		busy: bool = false, enabled: bool = true, quiet: float = 600.0) -> Dictionary:
	var tm: Dictionary = TankMind.ensure(sim)
	return TankQuestions.maybe_ask(sim, tm, rt, TankMind.keeper_state(sim), quiet, present, busy,
			enabled, now, roll)


func _teach(f: Fish, words: Array) -> void:
	var lex: Dictionary = _lexicon(f)
	for w in words:
		lex[str(w)] = {"pairings": 5, "strength": 0.8}


func _lexicon(f: Fish) -> Dictionary:
	if not (f._learned_words is Dictionary):
		f._learned_words = {}
	return f._learned_words


# Pip dies → someone asks where Pip went; the answer is stored and recalled.
func _test_death_question_and_answer() -> void:
	var sim: Node = _new_sim()
	var rt: Dictionary = {}
	var tm: Dictionary = TankMind.ensure(sim)
	# First poll only observes the roster (keeper absent).
	t.check(_ask(sim, rt, T0, FISH_ROLL, false).is_empty(), "absent keeper: no question")
	var pip: Fish = sim.fish[0]
	sim.fish.erase(pip)
	var q: Dictionary = _ask(sim, rt, T0 + 5.0)
	t.equals(str(q.get("kind", "")), "gone", "death grounds the question")
	t.check(str(q.get("line", "")).contains("where did Pip go"), "asks where Pip went: %s" % q.get("line", ""))
	t.check(str(q.get("fish_id", "")) != str(pip.id), "the dead fish does not ask")
	t.check(TankQuestions.has_pending(tm, T0 + 6.0), "question is pending")
	var asker: Fish = TankQuestions.fish_by_id(sim, str(q.get("fish_id", "")))
	t.check(asker != null, "asker is a living fish")
	if asker == null:
		return
	_teach(asker, ["big", "water"])
	var fam0: float = asker.familiarity
	var eps0: int = asker._episodic_store.size()
	var res: Dictionary = TankQuestions.answer(sim, tm, "Pip went to the big water, it's ok", T0 + 20.0)
	t.check(bool(res.get("ok", false)), "keeper line read as the answer")
	t.check(not TankQuestions.has_pending(tm, T0 + 21.0), "answer clears the pending question")
	t.check((res.get("understood", PackedStringArray()) as PackedStringArray).has("big"),
			"MindLexicon: understood 'big'")
	t.in_range(float(res.get("comprehension", 0.0)), 0.3, 0.8, "partial comprehension")
	t.check(str(res.get("line", "")) != "", "asker acknowledges: %s" % res.get("line", ""))
	t.check(asker.familiarity > fam0, "kind answer raises familiarity")
	t.check(asker._episodic_store.size() > eps0, "answer encoded as an episode")
	var found: bool = false
	for e in asker._episodic_store:
		if e is Dictionary and str((e as Dictionary).get("kind", "")) == "keeper_answer":
			found = str((e as Dictionary).get("text", "")).contains("big water")
	t.check(found, "episode holds the keeper's words")
	var ans: Array = TankQuestions.answers_for(tm, str(asker.id))
	t.equals(ans.size(), 1, "answer stored in the per-fish map")
	var recall: String = TankQuestions.recall_line(tm, str(asker.id), T0 + 4000.0)
	t.check(recall.contains("you told me") and recall.contains("big water"),
			"later reference to the answer: %s" % recall)
	# A later ask never repeats the answered question.
	var again: Dictionary = _ask(sim, rt, T0 + 5000.0)
	t.check(str(again.get("kind", "")) != "gone" or str(again.get("fish_id", "")) != str(asker.id),
			"answered question is not asked again by the same fish")
	pip.free()


func _test_rate_limits() -> void:
	var sim: Node = _new_sim()
	var rt: Dictionary = {}
	var tm: Dictionary = TankMind.ensure(sim)
	t.check(_ask(sim, rt, T0, FISH_ROLL, true, false, false).is_empty(), "voice off: silent")
	t.check(_ask(sim, rt, T0, FISH_ROLL, true, true).is_empty(), "keeper mid-exchange: silent")
	t.check(_ask(sim, rt, T0, FISH_ROLL, true, false, true, 5.0).is_empty(), "keeper just spoke: silent")
	t.check(_ask(sim, rt, T0, 0.9).is_empty(), "failed chance roll: silent")
	var q1: Dictionary = _ask(sim, rt, T0)
	t.check(not q1.is_empty(), "a curious fish asks: %s" % q1.get("line", ""))
	t.check(_ask(sim, rt, T0 + 10.0).is_empty(), "one question at a time")
	TankQuestions.answer(sim, tm, "hello little one", T0 + 12.0)
	t.check(_ask(sim, rt, T0 + 60.0).is_empty(), "ASK_MIN_GAP_S holds after an answer")
	var q2: Dictionary = _ask(sim, rt, T0 + TankQuestions.ASK_MIN_GAP_S + 20.0)
	t.check(not q2.is_empty(), "asks again after the gap")
	t.check(str(q2.get("fish_id", "")) != str(q1.get("fish_id", "")), "per-fish gap: a different fish asks")
	t.equals(int(TankQuestions.state(tm)["asked_n"]), 2, "two questions counted")


func _test_persist_and_migrate() -> void:
	var sim: Node = _new_sim()
	var rt: Dictionary = {}
	var tm: Dictionary = TankMind.ensure(sim)
	var q: Dictionary = _ask(sim, rt, T0)
	var fid: String = str(q.get("fish_id", ""))
	TankQuestions.answer(sim, tm, "the world beyond is big", T0 + 5.0)
	var parsed: Variant = JSON.parse_string(JSON.stringify(TankMind.to_dict(sim)))
	t.check(parsed is Dictionary, "tank mind with answers serialises to JSON")
	var sim2: Node = _new_sim()
	TankMind.from_dict(sim2, parsed)
	var tm2: Dictionary = TankMind.ensure(sim2)
	var ans: Array = TankQuestions.answers_for(tm2, fid)
	t.equals(ans.size(), 1, "answer survives save round-trip")
	t.equals(str((ans[0] as Dictionary).get("a", "")), "the world beyond is big", "answer text survives")
	t.equals(int(TankQuestions.state(tm2)["v"]), TankQuestions.QUESTIONS_VERSION, "version survives")
	t.check(TankQuestions.recall_line(tm2, fid).contains("world"), "recall works after load")
	# Old save without the ledger.
	var sim3: Node = _new_sim()
	TankMind.from_dict(sim3, {"schema_version": 1, "mood_valence": 0.1})
	t.has_keys(TankMind.ensure(sim3).get("keeper_questions", {}), ["v", "answers", "asked", "pending"],
			"old save gains a questions ledger")
	# Malformed / oversized ledger is repaired and bounded.
	var many: Array = []
	for i in 10:
		many.append({"k": "beyond", "a": "answer %d" % i, "t": float(i), "w": ["a", "b", "c", "d", "e", "f"]})
	many.append("junk")
	var bad: Dictionary = {"keeper_questions": {"v": 0, "answers": {"x": many, "y": "junk"},
			"asked": [], "pending": {"fish_id": "x"}}}
	var qs: Dictionary = TankQuestions.migrate(bad)
	t.equals((qs["answers"]["x"] as Array).size(), TankQuestions.ANSWERS_PER_FISH, "answers bounded per fish")
	t.check(not (qs["answers"] as Dictionary).has("y"), "malformed answer list dropped")
	t.check(qs["asked"] is Dictionary, "asked map repaired")
	t.check((qs["pending"] as Dictionary).is_empty(), "malformed pending dropped")
	t.equals(((qs["answers"]["x"] as Array)[0]["w"] as Array).size(), TankQuestions.WORDS_MAX, "words bounded")
	var big: Dictionary = {}
	for i in 40:
		big["f%d" % i] = [{"k": "beyond", "t": float(i)}]
	var qs2: Dictionary = TankQuestions.migrate({"keeper_questions": {"v": 1, "answers": big}})
	t.equals((qs2["answers"] as Dictionary).size(), TankQuestions.ANSWER_FISH_MAX, "fish map bounded")
	t.check((qs2["answers"] as Dictionary).has("f39") and not (qs2["answers"] as Dictionary).has("f0"),
			"stalest fish evicted first")


func _test_fade_when_ignored() -> void:
	var sim: Node = _new_sim()
	var rt: Dictionary = {}
	var tm: Dictionary = TankMind.ensure(sim)
	var q: Dictionary = _ask(sim, rt, T0)
	t.check(not q.is_empty(), "question asked")
	t.check(_ask(sim, rt, T0 + 30.0).is_empty(), "still waiting inside the TTL")
	var fade: Dictionary = _ask(sim, rt, T0 + TankQuestions.PENDING_TTL_S + 5.0)
	t.check(bool(fade.get("fade", false)), "ignored question fades")
	t.check(str(fade.get("line", "")).contains("never mind") or str(fade.get("line", "")).contains("doesn't matter"),
			"fade line: %s" % fade.get("line", ""))
	t.check(TankQuestions.pending(tm).is_empty(), "fade clears pending")
	t.equals(int(TankQuestions.state(tm)["faded_n"]), 1, "fade counted")
	t.check(TankQuestions.answer(sim, tm, "the glass", T0 + 200.0).is_empty(),
			"late line is ordinary talk, not an answer")


func _test_collective_question() -> void:
	var sim: Node = _new_sim()
	var rt: Dictionary = {}
	var tm: Dictionary = TankMind.ensure(sim)
	_ask(sim, rt, T0, FISH_ROLL, false)
	var gone: Fish = sim.fish[2]
	sim.fish.erase(gone)
	var q: Dictionary = _ask(sim, rt, T0 + 5.0, TANK_ROLL)
	t.check(bool(q.get("collective", false)), "the tank asks collectively")
	t.check(str(q.get("line", "")).contains("why do some of us stop"), "collective question grounded in a loss")
	var res: Dictionary = TankQuestions.answer(sim, tm, "everything that lives stops someday", T0 + 10.0)
	t.check(bool(res.get("collective", false)), "collective answer")
	t.check(not TankQuestions.answers_for(tm, TankQuestions.TANK_ID).is_empty(), "tank answer stored")
	t.check(TankQuestions.recall_line(tm, TankQuestions.TANK_ID).contains("you told us"), "tank recalls as 'us'")
	gone.free()


func _test_freed_fish_safe() -> void:
	var sim: Node = _new_sim()
	var rt: Dictionary = {}
	var tm: Dictionary = TankMind.ensure(sim)
	var q: Dictionary = _ask(sim, rt, T0)
	var asker: Fish = TankQuestions.fish_by_id(sim, str(q.get("fish_id", "")))
	t.check(asker != null, "asker found")
	if asker == null:
		return
	# Freed while still in the roster array (the worst case).
	_all_fish.erase(asker)
	asker.free()
	t.check(TankQuestions.answer(sim, tm, "hello", T0 + 5.0).is_empty(), "answer to a freed asker is ignored")
	t.check(TankQuestions.pending(tm).is_empty(), "freed asker's question dropped")
	_ask(sim, rt, T0 + 1000.0)
	t.check(true, "maybe_ask survives a freed fish in the roster")
	TankQuestions.observe(sim, rt, T0 + 1001.0)
	t.check(TankDialogue.fish_intent_line(sim, null, "thinking") == "", "intent line on null fish safe")
