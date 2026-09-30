extends SceneTree

# Tank conversation memory (TankDialogue): keeper ledger persists through a
# save round-trip, old saves migrate, replies call back to earlier topics,
# promises resolve against real state, fish-to-fish follow-ups stay bounded,
# and tank-initiated lines are rate-limited.

const TankMind = preload("res://scripts/tank_mind.gd")
const TankDialogue = preload("res://scripts/tank_dialogue.gd")
const StubScript = preload("res://scripts/tank_conversation_test_stub.gd")

var t := TestSupport.Suite.new("smoke_tank_conversation_memory")
var _stubs: Array = []
var _all_fish: Array = []


func _initialize() -> void:
	_test_record_and_round_trip()
	_test_migration()
	_test_topic_callback()
	_test_safe_callback()
	_test_session_return()
	_test_promises()
	_test_followups()
	_test_initiation()
	for f in _all_fish:
		if is_instance_valid(f):
			(f as Fish).free()
	for s in _stubs:
		(s as Node).free()
	quit(t.finish())


func _make_fish(id: String, nm: String, hunger: float, stress: float) -> Fish:
	var f: Fish = Fish.new()
	f.id = id
	f.fish_name = nm
	f.hunger = hunger
	f.stress = stress
	f.familiarity = 0.5
	f.personality = {"boldness": 0.5, "curiosity": 0.5, "sociability": 0.5,
			"gluttony": 0.5, "calm": 0.5}
	_all_fish.append(f)
	return f


func _new_sim() -> Node:
	var sim: Node = StubScript.new()
	sim.fish = [
		_make_fish("m-%d-1" % _stubs.size(), "Pip", 0.2, 0.05),
		_make_fish("m-%d-2" % _stubs.size(), "Moss", 0.3, 0.1),
		_make_fish("m-%d-3" % _stubs.size(), "Reed", 0.2, 0.1),
	]
	_stubs.append(sim)
	return sim


func _age_entries(sim: Node, secs: float) -> void:
	for e in TankDialogue.memory(TankMind.ensure(sim))["entries"]:
		e["t"] = float(e["t"]) - secs


func _test_record_and_round_trip() -> void:
	var sim: Node = _new_sim()
	TankMind.keeper_reply(sim, "hello tank")
	TankMind.keeper_reply(sim, "are you hungry?")
	var r: Dictionary = TankMind.keeper_reply(sim, "I'll feed you soon")
	t.equals(str(r.get("promise", "")), "feed", "promise detected in keeper line")
	var mem: Dictionary = TankDialogue.memory(TankMind.ensure(sim))
	t.equals((mem["entries"] as Array).size(), 3, "three keeper lines in the ledger")
	t.has_keys((mem["entries"] as Array)[0], ["t", "text", "topics", "feel", "said"], "entry shape")
	t.check(str((mem["entries"] as Array)[1]["feel"]) != "", "entry records how the tank felt")
	# Real saves go through JSON (ints come back as floats).
	var json: String = JSON.stringify(TankMind.to_dict(sim))
	var parsed: Variant = JSON.parse_string(json)
	t.check(parsed is Dictionary, "tank mind serialises to JSON")
	var sim2: Node = _new_sim()
	TankMind.from_dict(sim2, parsed)
	var mem2: Dictionary = TankDialogue.memory(TankMind.ensure(sim2))
	t.equals((mem2["entries"] as Array).size(), 3, "ledger survives save round-trip")
	t.equals(str((mem2["entries"] as Array)[1]["text"]), "are you hungry?", "entry text survives")
	t.equals(int(mem2["v"]), TankDialogue.MEMORY_VERSION, "memory version survives")
	t.check(not TankDialogue.open_promise(TankMind.ensure(sim2), "feed").is_empty(),
			"open feed promise survives round-trip")
	# Bounded.
	for i in 40:
		TankMind.keeper_reply(sim, "line %d" % i)
	t.equals((TankDialogue.memory(TankMind.ensure(sim))["entries"] as Array).size(),
			TankDialogue.ENTRIES_MAX, "ledger bounded at ENTRIES_MAX")


func _test_migration() -> void:
	var sim: Node = _new_sim()
	TankMind.from_dict(sim, {"schema_version": 1, "focus": "daylight", "last_keeper_text": "hello fish",
			"night_ledger": []})
	var tm: Dictionary = TankMind.ensure(sim)
	t.check(tm.get("keeper_memory") is Dictionary, "old save gains keeper_memory on load")
	var mem: Dictionary = TankDialogue.memory(tm)
	t.equals(int(mem["v"]), TankDialogue.MEMORY_VERSION, "migrated memory is versioned")
	t.equals((mem["entries"] as Array).size(), 1, "last keeper line seeds migrated ledger")
	t.equals(str(tm.get("focus", "")), "daylight", "migration keeps the rest of the tank mind")
	var r: Dictionary = TankMind.keeper_reply(sim, "hi again")
	t.check(str(r["line"]) != "", "migrated tank still answers")
	# Corrupt / oversized memory is repaired and trimmed.
	var big: Array = []
	for i in 30:
		big.append({"t": 0.0, "s": "x", "text": "x%d" % i, "topics": [], "feel": "calm"})
	var sim2: Node = _new_sim()
	TankMind.from_dict(sim2, {"schema_version": 1, "keeper_memory": {"v": 0, "entries": big, "promises": "bad"}})
	var mem2: Dictionary = TankDialogue.memory(TankMind.ensure(sim2))
	t.equals((mem2["entries"] as Array).size(), TankDialogue.ENTRIES_MAX, "oversized ledger trimmed on migrate")
	t.check(mem2["promises"] is Array and (mem2["promises"] as Array).is_empty(), "bad promises field repaired")
	t.check(mem2.has("topic_counts") and mem2.has("turns"), "missing memory keys filled")


func _test_topic_callback() -> void:
	var sim: Node = _new_sim()
	TankMind.keeper_reply(sim, "are you hungry? food?")
	var r0: Dictionary = TankMind.keeper_reply(sim, "food?")
	t.equals(str(r0.get("callback", "")), "", "no callback to a line said seconds ago")
	_age_entries(sim, 300.0)
	sim._last_feed_unix = int(Time.get_unix_time_from_system()) - 240
	var r: Dictionary = TankMind.keeper_reply(sim, "hungry again?")
	var line: String = str(r["line"]).to_lower()
	t.check(str(r.get("callback", "")).contains("food earlier"), "callback names the earlier topic (got '%s')" % r.get("callback", ""))
	t.check(line.contains("earlier") and line.contains("we ate"),
			"reply references earlier food talk and the real feeding (got '%s')" % line)
	var r2: Dictionary = TankMind.keeper_reply(sim, "food?")
	t.equals(str(r2.get("callback", "")), "", "callbacks are spaced out (no callback next turn)")


func _test_safe_callback() -> void:
	var sim: Node = _new_sim()
	TankMind.keeper_reply(sim, "you're safe now")
	_age_entries(sim, 200.0)
	for f in sim.fish:
		(f as Fish).stress = 0.9
	var r: Dictionary = TankMind.keeper_reply(sim, "hello")
	t.check(str(r["line"]).to_lower().contains("you said we were safe"),
			"stressed tank recalls 'you said we were safe' (got '%s')" % r["line"])


func _test_session_return() -> void:
	var prev: String = TankDialogue.session_id
	TankDialogue.session_id = "session-a"
	var sim: Node = _new_sim()
	TankMind.keeper_reply(sim, "goodnight")
	var saved: Variant = JSON.parse_string(JSON.stringify(TankMind.to_dict(sim)))
	TankDialogue.session_id = "session-b"
	var sim2: Node = _new_sim()
	TankMind.from_dict(sim2, saved)
	var r: Dictionary = TankMind.keeper_reply(sim2, "hello")
	t.check(str(r["line"]).contains("you're back"), "new session recalls last time (got '%s')" % r["line"])
	TankDialogue.session_id = prev


func _test_promises() -> void:
	t.equals(TankDialogue.detect_promise("I'll feed you soon"), "feed", "detect: I'll feed")
	t.equals(TankDialogue.detect_promise("food is coming"), "feed", "detect: food is coming")
	t.equals(TankDialogue.detect_promise("I'm going to add an airstone"), "air", "detect: airstone")
	t.equals(TankDialogue.detect_promise("let me clean the water"), "water", "detect: clean the water")
	t.equals(TankDialogue.detect_promise("are you hungry?"), "", "detect: question is not a promise")
	t.equals(TankDialogue.detect_promise("hello"), "", "detect: greeting is not a promise")
	# Kept.
	var sim: Node = _new_sim()
	TankMind.keeper_reply(sim, "I'll feed you soon")
	var tm: Dictionary = TankMind.ensure(sim)
	sim._last_feed_unix = int(Time.get_unix_time_from_system()) + 1
	var changed: Array = TankDialogue.update_promises(sim, tm, TankMind.keeper_state(sim))
	t.equals(changed.size(), 1, "feeding resolves the feed promise")
	t.equals(str((changed[0] as Dictionary).get("status", "")), "kept", "promise marked kept")
	var r: Dictionary = TankMind.keeper_reply(sim, "hello")
	t.check(str(r["line"]).contains("you did") or str(r["line"]).contains("kept it"),
			"tank acknowledges the kept promise (got '%s')" % r["line"])
	var r2: Dictionary = TankMind.keeper_reply(sim, "hello")
	t.check(not str(r2["line"]).contains("you did") and not str(r2["line"]).contains("kept it"),
			"kept promise mentioned once")
	# Broken.
	var sim2: Node = _new_sim()
	TankMind.keeper_reply(sim2, "I will fix the water")
	sim2.tank_age_s += 2000.0
	var changed2: Array = TankDialogue.update_promises(sim2, TankMind.ensure(sim2), TankMind.keeper_state(sim2))
	t.check(changed2.size() == 1 and str(changed2[0].get("status", "")) == "broken",
			"unkept promise expires as broken")
	t.equals(int(TankDialogue.memory(TankMind.ensure(sim2))["broken"]), 1, "broken count tracked")


func _test_followups() -> void:
	var sim: Node = _new_sim()
	var a: Fish = sim.fish[0]
	var b: Fish = sim.fish[1]
	a.hunger = 0.9
	b.hunger = 0.1
	t.equals(TankDialogue.followup_kind(a, b, "belly's light — food?", PackedStringArray(["food"])),
			"contradict_fed", "fed fish contradicts a hungry one")
	b.hunger = 0.8
	t.equals(TankDialogue.followup_kind(a, b, "hungry", PackedStringArray(["food"])),
			"agree_hungry", "hungry fish agrees with a hungry one")
	var rt: Dictionary = {}
	TankDialogue.begin_exchange(rt, PackedStringArray([str(a.id)]), PackedStringArray(["food"]), 100000)
	_empty(TankDialogue.maybe_followup(sim, rt, a, "food?", 100100, 0.99), "high roll → no follow-up")
	var got: int = 0
	var now: int = 100000
	var first: Dictionary = {}
	for _i in 12:
		now += 3000
		var fu: Dictionary = TankDialogue.maybe_followup(sim, rt, a, "food?", now, 0.0)
		if not fu.is_empty():
			got += 1
			if first.is_empty():
				first = fu
	t.equals(got, TankDialogue.FOLLOWUPS_MAX, "follow-ups capped per keeper line")
	t.check(not first.is_empty() and str(first["fish_id"]) != str(a.id), "follower is another fish")
	t.check(str(first.get("line", "")) != "", "follow-up line non-empty")
	var rt2: Dictionary = {}
	TankDialogue.begin_exchange(rt2, PackedStringArray(), PackedStringArray(), 500000)
	t.check(not TankDialogue.maybe_followup(sim, rt2, a, "hi", 500000 + 3000, 0.0).is_empty(), "first follow-up fires")
	_empty(TankDialogue.maybe_followup(sim, rt2, a, "hi", 500000 + 3200, 0.0), "min gap between follow-ups")
	var rt3: Dictionary = {}
	TankDialogue.begin_exchange(rt3, PackedStringArray(), PackedStringArray(), 0)
	_empty(TankDialogue.maybe_followup(sim, rt3, a, "hi", 60000, 0.0), "no follow-up after exchange window")
	_empty(TankDialogue.maybe_followup(sim, {}, a, "hi", 60000, 0.0), "no exchange → no follow-up")


func _test_initiation() -> void:
	var sim: Node = _new_sim()
	var tm: Dictionary = TankMind.ensure(sim)
	var rt: Dictionary = {}
	var st: Dictionary = TankMind.keeper_state(sim)
	_empty(TankDialogue.maybe_initiate(sim, tm, rt, st, 999.0, 0.0), "first poll only snapshots")
	var baby: Fish = _make_fish("m-baby", "Tiny", 0.2, 0.0)
	baby.generation = 1
	baby.age = 5.0
	sim.fish.append(baby)
	_empty(TankDialogue.maybe_initiate(sim, tm, rt, st, 10.0, 2.0),
			"keeper spoke recently → tank waits")
	var out: Dictionary = TankDialogue.maybe_initiate(sim, tm, rt, st, 100.0, 4.0)
	t.equals(str(out.get("kind", "")), "birth", "birth → tank speaks first")
	t.check(str(out.get("line", "")).contains("Tiny"), "birth line names the fry (got '%s')" % out.get("line", ""))
	var gone: Fish = sim.fish[0]
	sim.fish.erase(gone)
	_empty(TankDialogue.maybe_initiate(sim, tm, rt, st, 100.0, 20.0), "min gap between initiations")
	var out2: Dictionary = TankDialogue.maybe_initiate(sim, tm, rt, st, 100.0, 4.0 + TankDialogue.INIT_MIN_GAP_S + 1.0)
	t.equals(str(out2.get("kind", "")), "death", "death announced after the gap")
	_empty(TankDialogue.maybe_initiate(sim, tm, rt, st, 100.0, 1000.0, false),
			"voice off → silent")
	t.is_empty_arr(rt.get("pending", []) as Array, "voice off drops queued news")
	# Soak: O2 flapping every poll for an hour must not spam.
	var rt2: Dictionary = {}
	var count: int = 0
	var o2_count: int = 0
	var now: float = 0.0
	while now < 3600.0:
		sim.dissolved_o2 = 0.3 if int(now / 2.0) % 2 == 0 else 0.8
		var o: Dictionary = TankDialogue.maybe_initiate(sim, tm, rt2, TankMind.keeper_state(sim), 999.0, now)
		if not o.is_empty():
			count += 1
			if str(o.get("kind", "")) == "o2_low":
				o2_count += 1
		now += 2.0
	t.in_range(float(count), 1.0, 3600.0 / TankDialogue.INIT_MIN_GAP_S + 1.0, "initiations rate-limited (got %d/h)" % count)
	t.in_range(float(o2_count), 1.0, 3600.0 / TankDialogue.INIT_KIND_COOLDOWN_S + 1.0,
			"per-kind cooldown holds (got %d o2 lines/h)" % o2_count)
	sim.dissolved_o2 = 0.9
	# Facade runs end to end.
	var rt3: Dictionary = {}
	TankMind.maybe_initiate(sim, rt3, 999.0, 0.0)
	t.check(rt3.has("ids"), "TankMind.maybe_initiate drives TankDialogue")


func _empty(d: Dictionary, message: String) -> void:
	t.check(d.is_empty(), "%s (got %s)" % [message, str(d)])
