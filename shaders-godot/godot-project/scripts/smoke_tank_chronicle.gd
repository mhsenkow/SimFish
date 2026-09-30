# Smoke: the Chronicle's pure core (tank_chronicle.gd) — events become
# chapters, arcs are detected, prose is grounded in real names and never
# repeats a sentence within a chapter, saves round-trip (and old saves
# backfill), and the whole thing stays bounded. No SimDriver / World.
extends SceneTree

const Chron = preload("res://scripts/tank_chronicle.gd")


func _init() -> void:
	var t := TestSupport.Suite.new("smoke_tank_chronicle")
	_test_founding(t)
	_test_crisis_recovery(t)
	_test_arcs(t)
	_test_no_duplicate_sentences(t)
	_test_save_roundtrip(t)
	_test_migration(t)
	_test_bounds(t)
	_test_classifier(t)
	_test_predation_and_intros(t)
	quit(t.finish())


func _ev(kind: String, day: int, fields: Dictionary = {}) -> Dictionary:
	return Chron.make_event(kind, day, fields)


func _all_text(prose: Dictionary) -> String:
	return " ".join(prose.get("paragraphs", PackedStringArray()) as PackedStringArray)


func _sentences(prose: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile("(?<=[.!?”])\\s+")
	for p in prose.get("paragraphs", PackedStringArray()):
		var s: String = re.sub(String(p), "\n", true)
		for line in s.split("\n", false):
			out.append(line.strip_edges())
	return out


func _test_founding(t: TestSupport.Suite) -> void:
	var st: Dictionary = Chron.new_state()
	Chron.record(st, _ev("arrive", 1, {"a": "Pip", "as": "neon_tetra", "ai": "f1"}))
	Chron.record(st, _ev("arrive", 1, {"a": "Moss", "as": "cory", "ai": "f2"}))
	Chron.record(st, _ev("arrive", 1, {"a": "Juniper", "as": "neon_tetra", "ai": "f3"}))
	t.equals((st["chapters"] as Array).size(), 0, "nothing closes on day 1")
	t.equals(Chron.tick_day(st, 2), -1, "chapter held open before CHAPTER_MIN_DAYS")
	var closed: int = Chron.tick_day(st, 1 + Chron.CHAPTER_MIN_DAYS)
	t.equals(closed, 0, "day tick closes the first chapter")
	var ch: Dictionary = Chron.chapter_by_index(st, 0)
	t.equals(String(ch.get("arc", "")), "founding", "first chapter reads as a founding")
	t.check(String(ch.get("title", "")).begins_with("Day 1 — "), "title is 'Day N — Name' (%s)" % ch.get("title", ""))
	var prose: Dictionary = Chron.chapter_prose(st, ch)
	var text: String = _all_text(prose)
	for nm in ["Pip", "Moss", "Juniper"]:
		t.check(text.contains(nm), "founding prose names %s" % nm)
		t.check((prose["cast"] as PackedStringArray).has(nm), "%s is in the cast" % nm)
	t.check(text.contains("neon tetra"), "species rendered readably")
	var bb: String = Chron.prose_bbcode(prose)
	t.check(bb.contains("[color=%s]Pip[/color]" % Chron.NAME_COLOR), "cast names highlighted in bbcode")
	t.equals(Chron.chapter_prose(st, ch), prose, "prose is deterministic")


func _test_crisis_recovery(t: TestSupport.Suite) -> void:
	var st: Dictionary = Chron.new_state()
	Chron.record(st, _ev("arrive", 1, {"a": "Pip", "as": "neon_tetra", "ai": "f1"}))
	Chron.close_open(st, 2)
	Chron.record(st, _ev("hypoxia", 5, {"nt": true}))
	Chron.record(st, _ev("death", 5, {"a": "Wren", "as": "guppy", "ai": "f9", "c": "breath"}))
	t.check(Chron.tick_day(st, 5 + Chron.CHAPTER_MAX_DAYS - 1) == -1,
			"an unresolved crisis holds its chapter open")
	var closed: int = Chron.record(st, _ev("o2_recover", 7))
	t.check(closed >= 0, "recovery closes the crisis chapter on the spot")
	var ch: Dictionary = Chron.chapter_by_index(st, closed)
	t.equals(String(ch.get("arc", "")), "crisis_recovery", "crisis + recovery arc detected")
	t.equals(String(ch.get("crisis", "")), "hypoxia", "crisis kind remembered")
	var title: String = String(ch.get("title", ""))
	t.check(title.begins_with("Day 5 — ") and (title.contains("Long Dark") or title.contains("Thin Water")
			or title.contains("Breath Returns")), "hypoxia chapter titled for the dark (%s)" % title)
	var text: String = _all_text(Chron.chapter_prose(st, ch))
	t.check(text.contains("Wren"), "the lost fish is named")
	t.check(text.contains("night of Day 5") or text.contains("Night on Day 5") or text.contains("dark of Day 5"),
			"night hypoxia is told as a night")
	t.check(text.contains(" we ") or text.begins_with("We") or text.contains(" us"), "tank-mind 'we' voice")


func _test_arcs(t: TestSupport.Suite) -> void:
	# Matriarch: one mother, four fry, one chapter.
	var st: Dictionary = Chron.new_state()
	Chron.close_open(st, 1)
	Chron.record(st, _ev("arrive", 1, {"a": "Seed", "as": "guppy", "ai": "x0"}))
	Chron.close_open(st, 2)
	for i in range(4):
		Chron.record(st, _ev("birth", 10, {"a": "Fry%d" % i, "as": "guppy", "ai": "k%d" % i,
				"b": "Mira", "bs": "guppy", "bi": "m1", "c": "Tov", "g": 1}))
	var ci: int = Chron.close_open(st, 11)
	var ch: Dictionary = Chron.chapter_by_index(st, ci)
	t.equals(String(ch.get("arc", "")), "matriarch", "four fry from one mother = matriarch")
	t.equals(String(ch.get("who", "")), "Mira", "matriarch named")
	var text: String = _all_text(Chron.chapter_prose(st, ch))
	t.check(text.contains("Mira") and text.contains("Tov") and text.contains("Fry2"),
			"births name mother, father and fry")
	t.equals(int((st["cast"]["m1"] as Dictionary).get("k", 0)), 4, "cast counts the mother's children")

	# Lineage fall.
	var ci2: int = -1
	Chron.record(st, _ev("death", 20, {"a": "Old Bo", "as": "betta", "ai": "b1", "c": "age"}))
	Chron.record(st, _ev("extinct", 20, {"a": "Old Bo", "as": "betta"}))
	ci2 = Chron.close_open(st, 21)
	var ch2: Dictionary = Chron.chapter_by_index(st, ci2)
	t.equals(String(ch2.get("arc", "")), "lineage_fall", "last of a species = lineage fall")
	t.check(String(ch2.get("title", "")).contains("Betta") or String(ch2.get("title", "")).contains("Line"),
			"lineage-fall title (%s)" % ch2.get("title", ""))

	# Lone survivor.
	Chron.record(st, _ev("death", 30, {"a": "Ana", "as": "cory", "ai": "c1", "c": "hunger"}))
	Chron.record(st, _ev("death", 30, {"a": "Ben", "as": "cory", "ai": "c2", "c": "hunger"}))
	Chron.record(st, _ev("lone", 30, {"a": "Cal", "as": "cory", "ai": "c3"}))
	var ch3: Dictionary = Chron.chapter_by_index(st, Chron.close_open(st, 31))
	t.equals(String(ch3.get("arc", "")), "lone_survivor", "lone survivor arc")
	t.equals(String(ch3.get("who", "")), "Cal", "survivor named")

	# Newcomer finding its place: arrives (not a founder), later pairs.
	Chron.record(st, _ev("arrive", 40, {"a": "Nova", "as": "guppy", "ai": "n1"}))
	Chron.close_open(st, 41)
	Chron.record(st, _ev("pair", 44, {"a": "Nova", "as": "guppy", "ai": "n1",
			"b": "Mira", "bs": "guppy", "bi": "m1"}))
	var ch4: Dictionary = Chron.chapter_by_index(st, Chron.close_open(st, 45))
	t.equals(String(ch4.get("arc", "")), "newcomer", "newcomer who pairs = finding a place")
	t.equals(String(ch4.get("who", "")), "Nova", "newcomer named")

	# Keeper conversation: the fish answer back.
	Chron.record(st, _ev("keeper_talk", 50, {"c": "hello little ones", "r": "we hear you",
			"a": "Pip", "as": "neon_tetra", "e": "you came back"}))
	var ch5: Dictionary = Chron.chapter_by_index(st, Chron.close_open(st, 51))
	t.equals(String(ch5.get("arc", "")), "keeper", "keeper talk arc")
	var t5: String = _all_text(Chron.chapter_prose(st, ch5))
	t.check(t5.contains("hello little ones") and t5.contains("we hear you") and t5.contains("you came back")
			and t5.contains("Pip"), "keeper words, tank reply and fish reply all in the prose")

	# Titles never repeat across chapters.
	var titles: Dictionary = {}
	var dup: bool = false
	for c in st["chapters"]:
		var nm: String = String((c as Dictionary).get("title", "")).get_slice(" — ", 1)
		if titles.has(nm):
			dup = true
		titles[nm] = true
	t.check(not dup, "chapter titles are unique")


func _test_no_duplicate_sentences(t: TestSupport.Suite) -> void:
	var st: Dictionary = Chron.new_state()
	Chron.close_open(st, 1)
	Chron.record(st, _ev("arrive", 1, {"a": "Seed", "as": "guppy"}))
	Chron.close_open(st, 2)
	# A busy chapter: the same kinds, over and over.
	var causes: Array[String] = ["age", "illness", "predation"]
	for i in range(6):
		Chron.record(st, _ev("death", 3, {"a": "D%d" % i, "as": "guppy", "c": causes[i % 3]}))
	for i in range(4):
		Chron.record(st, _ev("bond", 3, {"a": "A%d" % i, "b": "B%d" % i}))
	for i in range(4):
		Chron.record(st, _ev("rival", 3, {"a": "R%d" % i, "b": "S%d" % i}))
	for i in range(5):
		Chron.record(st, _ev("keeper_care", 3, {"c": "water"}))
	for i in range(3):
		Chron.record(st, _ev("lexicon", 3, {"a": "L%d" % i, "c": "food"}))
	var ch: Dictionary = Chron.chapter_by_index(st, Chron.close_open(st, 4))
	var prose: Dictionary = Chron.chapter_prose(st, ch)
	var sents: Array[String] = _sentences(prose)
	t.check(sents.size() >= 6, "busy chapter produced prose (%d sentences)" % sents.size())
	var seen: Dictionary = {}
	var dups: Array[String] = []
	for s in sents:
		if seen.has(s):
			dups.append(s)
		seen[s] = true
	t.check(dups.is_empty(), "no duplicate sentences in a chapter %s" % str(dups))
	var text: String = _all_text(prose)
	t.check(text.contains("5 water changes"), "repeated care folds into one sentence")
	for nm in ["D0", "A3", "S2"]:
		t.check(text.contains(nm), "busy chapter still names %s" % nm)


func _test_save_roundtrip(t: TestSupport.Suite) -> void:
	var st: Dictionary = Chron.new_state()
	Chron.record(st, _ev("arrive", 1, {"a": "Pip", "as": "neon_tetra", "ai": "f1"}))
	Chron.record(st, _ev("arrive", 1, {"a": "Moss", "as": "cory", "ai": "f2"}))
	Chron.close_open(st, 4)
	Chron.record(st, _ev("bloom_peak", 6))
	Chron.record(st, _ev("bloom_clear", 8))
	Chron.record(st, _ev("birth", 9, {"a": "Dot", "as": "neon_tetra", "b": "Pip", "bi": "f1"}))
	var before: Array = []
	for c in st["chapters"]:
		before.append(Chron.chapter_prose(st, c))
	# Through JSON, exactly as state.json stores it (ints come back as floats).
	var json: String = JSON.stringify(Chron.to_save(st))
	var parsed: Variant = JSON.parse_string(json)
	t.check(parsed is Dictionary, "chronicle serialises to JSON")
	var back: Dictionary = Chron.from_save(parsed)
	t.equals(int(back.get("v", 0)), Chron.SCHEMA_VERSION, "schema version stamped")
	t.equals((back["chapters"] as Array).size(), (st["chapters"] as Array).size(), "chapters survive")
	var after: Array = []
	for c in back["chapters"]:
		after.append(Chron.chapter_prose(back, c))
	t.check(before.size() == after.size() and before.size() >= 2, "same chapter count after load")
	var same: bool = true
	for i in range(mini(before.size(), after.size())):
		if _all_text(before[i]) != _all_text(after[i]) or before[i]["title"] != after[i]["title"]:
			same = false
	t.check(same, "prose identical after a save round-trip")
	t.equals((back["open"]["ev"] as Array).size(), 1, "open chapter survives")
	t.equals(int(back.get("next_idx", 0)), int(st.get("next_idx", 0)), "chapter numbering survives")
	# Recording continues cleanly on loaded (float-typed) data.
	var ci: int = Chron.close_open(back, 12)
	t.check(ci == int(st["next_idx"]), "next chapter index continues after load")


func _test_migration(t: TestSupport.Suite) -> void:
	var story: Array = [
		{"t": 10.0, "sim_day": "Day 2", "day_phase": 0.3, "text": "First eggs laid — a guppy pair spawned 12 eggs."},
		{"t": 20.0, "sim_day": "Day 3", "day_phase": 0.8, "text": "Dissolved O₂ dipping — surface gas exchange struggling (31%)."},
		{"t": 30.0, "sim_day": "Day 4", "day_phase": 0.3, "text": "O₂ recovering — photosynthesis catching up with respiration."},
		{"t": 40.0, "sim_day": "Day 5", "day_phase": 0.3, "text": "Discovered: Java fern (Microsorum pteropus) growing in your tank."},
		{"t": 50.0, "sim_day": "Day 6", "day_phase": 0.3, "text": "Some ambient line the chronicle ignores."},
	]
	var legacies: Array = [{"id": "e_7", "name": "Kestrel", "species": "guppy", "sim_day": "Day 3"}]
	var st: Dictionary = Chron.from_save(null, story, legacies)
	t.check(bool(st.get("backfilled", false)), "old save (no chronicle key) is backfilled")
	var kinds: Array = []
	var names: Array = []
	for c in st["chapters"]:
		for e in (c as Dictionary)["ev"]:
			kinds.append(String(e.get("k", "")))
			names.append(String(e.get("a", "")))
	for e in st["open"]["ev"]:
		kinds.append(String(e.get("k", "")))
		names.append(String(e.get("a", "")))
	for k in ["first_spawn", "hypoxia", "o2_recover", "discovery", "death"]:
		t.check(kinds.has(k), "backfill recovered %s" % k)
	t.check(names.has("Kestrel"), "backfill recovered a named death from legacies")
	t.equals(String(st["story_sig"]["x"]), String(story[-1]["text"]), "live polling resumes after the backfill")
	var first: Dictionary = Chron.open_as_chapter(st)
	if not (st["chapters"] as Array).is_empty():
		first = (st["chapters"] as Array)[0]
	var text: String = _all_text(Chron.chapter_prose(st, first))
	t.check(text.contains("fragments") or text.contains("no chronicle") or text.contains("blurred"),
			"backfilled first chapter admits it is reconstructed")
	var empty: Dictionary = Chron.from_save(null, [], [])
	t.check((empty["chapters"] as Array).is_empty() and (empty["open"]["ev"] as Array).is_empty(),
			"save with no history migrates to an empty chronicle")
	var future: Dictionary = Chron.from_save({"v": Chron.SCHEMA_VERSION + 5, "chapters": [1, 2]})
	t.check(future.has("future") and (future["chapters"] as Array).is_empty(),
			"newer-schema chronicle is kept aside, not misread")
	var junk: Dictionary = Chron.from_save({"v": Chron.SCHEMA_VERSION, "chapters": "nope", "open": 3})
	t.check(junk["chapters"] is Array and junk["open"] is Dictionary, "garbage fields repaired")


func _test_bounds(t: TestSupport.Suite) -> void:
	var st: Dictionary = Chron.new_state()
	var kinds: Array[String] = ["birth", "death", "arrive", "bond", "hypoxia", "o2_recover",
			"keeper_care", "discovery", "bloom_peak", "bloom_clear"]
	for i in range(3000):
		var day: int = 1 + int(i / 3.0)
		var k: String = kinds[i % kinds.size()]
		Chron.record(st, _ev(k, day, {"a": "Fish%d" % i, "as": "guppy", "ai": "id%d" % i,
				"b": "Mom%d" % (i % 7), "bi": "mom%d" % (i % 7), "c": "water"}))
	var chapters: Array = st["chapters"]
	t.check(chapters.size() <= Chron.MAX_CHAPTERS, "chapters bounded (%d)" % chapters.size())
	t.check(int(st.get("dropped", 0)) > 0, "oldest chapters dropped and counted")
	var ev_ok: bool = true
	for c in chapters:
		if ((c as Dictionary)["ev"] as Array).size() > Chron.MAX_CH_EVENTS:
			ev_ok = false
	t.check(ev_ok, "events per chapter bounded")
	t.check((st["cast"] as Dictionary).size() <= Chron.MAX_CAST, "cast bounded")
	var size: int = JSON.stringify(Chron.to_save(st)).length()
	t.check(size < 400000, "serialised chronicle stays small (%d bytes)" % size)
	var t0: int = Time.get_ticks_usec()
	for c in chapters:
		Chron.chapter_prose(st, c)
	var per_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, float(chapters.size()))
	t.check(per_ms < 20.0, "prose build is cheap (%.2f ms/chapter)" % per_ms)


func _test_classifier(t: TestSupport.Suite) -> void:
	var e: Dictionary = Chron.classify_story({"sim_day": "Day 9", "text": "Day 9: Mira understood \"food\"."})
	t.equals(String(e.get("k", "")), "lexicon", "lexicon line classified")
	t.equals(String(e.get("a", "")), "Mira", "lexicon speaker parsed")
	t.equals(String(e.get("c", "")), "food", "lexicon word parsed")
	var g: Dictionary = Chron.classify_story({"sim_day": "Day 30", "text": "Lineages deepening — generation 4 reached in the tank."})
	t.equals(int(g.get("n", 0)), 4, "generation depth parsed")
	var col: Dictionary = Chron.classify_story({"text": "Shrimp colony collapsed — detritus loop thinning."})
	t.equals(String(col.get("c", "")), "shrimp", "collapse subject parsed")
	t.check(Chron.classify_story({"text": "Pip tucked into a nook for the night."}).is_empty(),
			"ambient lines are not chronicle events")
	t.check(Chron.classify_story({"text": "Kestrel, a guppy, has passed — 12 meals."}).is_empty(),
			"live deaths come from signals, not text")


class StubFish:
	extends RefCounted
	var fish_name: String = ""
	var id: String = ""
	var backstory: Dictionary = {}


func _stub(nm: String, fid: String, origin: String, origin_text: String) -> StubFish:
	var f := StubFish.new()
	f.fish_name = nm
	f.id = fid
	f.backstory = {"v": 1, "origin": origin, "origin_text": origin_text,
			"like": {"kind": "plant", "label": "Java Fern"},
			"fear": {"kind": "lamp", "label": "the lamp"},
			"quirk": "always turns left around obstacles", "parents": []}
	return f


func _test_predation_and_intros(t: TestSupport.Suite) -> void:
	# Predation names both predator and prey.
	var st: Dictionary = Chron.new_state()
	Chron.close_open(st, 1)
	Chron.record(st, _ev("arrive", 1, {"a": "Seed", "as": "guppy"}))
	Chron.close_open(st, 2)
	Chron.record(st, _ev("death", 6, {"a": "Minnow", "as": "guppy", "ai": "p1", "c": "predation",
			"b": "Fang", "bs": "pike_cichlid"}))
	var ch: Dictionary = Chron.chapter_by_index(st, Chron.close_open(st, 7))
	var prose: Dictionary = Chron.chapter_prose(st, ch)
	var text: String = _all_text(prose)
	t.check(text.contains("Minnow") and text.contains("Fang"), "predation prose names prey and predator: %s" % text)
	t.check((prose["cast"] as PackedStringArray).has("Fang"), "predator is in the cast")

	# Backstory introductions: grounded, and only on first appearance.
	var founder := _stub("Pip", "f1", "founder", "Came from a friend's overgrown tank")
	var line: String = Chron.intro_line(founder)
	t.check(line.begins_with("Pip ") or line.contains(" Pip "), "intro names the fish (%s)" % line)
	t.check(line.contains("friend's overgrown tank") or line.contains("Java Fern")
			or line.contains("turns left"), "intro is grounded in the backstory")
	t.equals(Chron.intro_line(founder), line, "intro is deterministic")
	var fry := _stub("Dot", "f2", "bred", "Born here to Mira and Tov (born live), one of 3 from its clutch")
	var fry_line: String = Chron.intro_line(fry)
	t.check(fry_line != "" and not fry_line.contains("Born here"),
			"bred fish are introduced by like/quirk, not a repeat of their parentage (%s)" % fry_line)
	t.equals(Chron.intro_line(StubFish.new()), "", "no backstory, no intro")

	var st2: Dictionary = Chron.new_state()
	Chron.record(st2, _ev("arrive", 1, {"a": "Pip", "as": "neon_tetra", "ai": "f1", "i": line}))
	Chron.record(st2, _ev("arrive", 1, {"a": "Moss", "as": "cory", "ai": "f3"}))
	Chron.record(st2, _ev("bond", 2, {"a": "Pip", "ai": "f1", "b": "Moss", "bi": "f3"}))
	var ch2: Dictionary = Chron.chapter_by_index(st2, Chron.close_open(st2, 5))
	var text2: String = _all_text(Chron.chapter_prose(st2, ch2))
	t.check(text2.contains(line), "first appearance carries the backstory clause")
	t.equals(text2.count(line), 1, "backstory clause appears once, not on every mention")
