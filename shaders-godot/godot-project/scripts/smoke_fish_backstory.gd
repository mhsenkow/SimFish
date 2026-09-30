extends SceneTree

# FishBackstory + FishEnvironment: every fish has a deterministic history,
# bred fry reference their real parents, the story survives save/load (and old
# saves without it get one), and the environment module steers toward valid
# targets while respecting the fish's fear.

const Backstory := preload("res://scripts/fish_backstory.gd")
const Env := preload("res://scripts/fish_environment.gd")

const CANDS: Array = [
	{"kind": "driftwood", "label": "driftwood", "key": "driftwood"},
	{"kind": "filter", "label": "filter current", "key": "filter"},
	{"kind": "lamp", "label": "lamp", "key": "lamp"},
	{"kind": "plant", "label": "Java Fern", "key": "plant:java_fern"},
	{"kind": "surface", "label": "surface", "key": "surface"},
	{"kind": "substrate", "label": "sand", "key": "substrate"},
]


func _make_fish(parent: Node, fid: String, fname: String, pers: Dictionary) -> Fish:
	var f := Fish.new()
	parent.add_child(f)
	f.init_genome({"species": "glassdart", "_display_name": fname, "personality": pers})
	f.id = fid
	f.fish_name = fname
	f.personality = pers.duplicate()
	return f


func _sig(s: Dictionary) -> String:
	return "%s|%s|%s|%s|%s" % [str(s.get("origin_text")), str(s.get("formative")),
		str(s.get("quirk")), str((s.get("like", {}) as Dictionary).get("key")),
		str((s.get("fear", {}) as Dictionary).get("key"))]


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("fish_backstory")
	Env.clear_for_test()
	var parent := Node3D.new()
	root.add_child(parent)
	var pers := {"boldness": 0.3, "curiosity": 0.7, "sociability": 0.5, "gluttony": 0.4, "calm": 0.6}

	# --- determinism -----------------------------------------------------
	var a := _make_fish(parent, "bs_a", "Pip", pers)
	var a2 := _make_fish(parent, "bs_a", "Pip", pers)
	var s1: Dictionary = Backstory.generate(a, CANDS)
	var s2: Dictionary = Backstory.generate(a2, CANDS)
	t.equals(_sig(s2), _sig(s1), "same fish seed -> same backstory")
	t.has_keys(s1, ["v", "origin", "origin_text", "formative", "quirk", "like", "fear"], "story shape")
	t.check(String((s1["like"] as Dictionary)["key"]) != String((s1["fear"] as Dictionary)["key"]),
		"like and fear are different subjects")

	# --- varies across fish -------------------------------------------
	var sigs: Dictionary = {}
	for i in 10:
		var fi := _make_fish(parent, "bs_v%d" % i, "Fish%d" % i, pers)
		var si: Dictionary = Backstory.generate(fi, CANDS)
		sigs[_sig(si)] = true
		t.check(String((si["like"] as Dictionary)["key"]) != String((si["fear"] as Dictionary)["key"]),
			"fish %d: like != fear" % i)
		fi.queue_free()
	t.check(sigs.size() >= 7, "backstories differ across fish (%d distinct of 10)" % sigs.size())

	# --- bred fry reference real parents --------------------------------
	var fry := _make_fish(parent, "bs_fry", "Nib", pers)
	fry.generation = 1
	fry.parent_lineage = "Mika & Juno"
	var mates: Array = [
		{"id": "m1", "name": "Mika", "species": "glassdart", "sex": 1, "size": 1.0, "lineage": "Founders"},
		{"id": "j1", "name": "Juno", "species": "glassdart", "sex": 0, "size": 1.0, "lineage": "Founders"},
		{"id": "sib", "name": "Tam", "species": "glassdart", "sex": 0, "size": 0.4, "lineage": "Mika & Juno"},
	]
	var fs: Dictionary = Backstory.generate(fry, CANDS, mates, "Day 12")
	t.equals(String(fs.get("origin")), "bred", "fry origin is bred")
	var par: Array = fs.get("parents", [])
	t.equals(par.size(), 2, "fry has two parents")
	if par.size() == 2:
		t.equals(String(par[0]["name"]), "Mika", "first parent name from lineage")
		t.equals(String(par[0]["id"]), "m1", "parent id resolved from living tankmate")
		t.equals(String(par[1]["id"]), "j1", "second parent id resolved")
	t.equals(int(fs.get("clutch", 0)), 2, "clutch counts the living sibling")
	t.check(String(fs.get("origin_text")).contains("Mika") and String(fs.get("origin_text")).contains("Day 12"),
		"origin text names the parents and the birth day: %s" % String(fs.get("origin_text")))
	fry.backstory = fs
	t.check(Backstory.speech_line(fry, "parents").contains("Juno"), "speech line names parents")

	# --- ensure + getters + episodic seeding ---------------------------
	var e := _make_fish(parent, "bs_e", "Oda", pers)
	e.backstory = {}
	var before: int = e._episodic_store.size()
	Backstory.ensure(e)
	t.check(Backstory.has_story(e), "ensure() generates a story")
	t.check(e._episodic_store.size() > before, "formative memory seeded into episodic memory")
	t.check(Backstory.summary(e) != "", "summary non-empty")
	t.check(Backstory.tagline(e) != "", "tagline non-empty")
	t.check(not Backstory.likes(e).is_empty() and not Backstory.fears(e).is_empty(), "likes/fears getters")
	t.check(Backstory.bio_lines(e).size() >= 4, "bio lines for panels")
	for topic in ["origin", "memory", "like", "fear", "quirk", "home"]:
		t.check(Backstory.speech_line(e, topic) != "", "speech line for %s" % topic)
	t.check(e.get_bio_summary().contains(Backstory.tagline(e)), "bio summary carries the tagline")

	# --- save round-trip (through JSON) + migration ---------------------
	var saved: Dictionary = e.to_save_dict()
	t.check(saved.has("backstory"), "save dict carries backstory")
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	t.check(parsed is Dictionary, "save dict survives JSON")
	var b := Fish.new()
	parent.add_child(b)
	b.apply_save_dict(parsed as Dictionary)
	t.equals(_sig(b.backstory), _sig(e.backstory), "backstory round-trips through save")
	var old: Dictionary = (parsed as Dictionary).duplicate(true)
	old.erase("backstory")
	var m := Fish.new()
	parent.add_child(m)
	m.apply_save_dict(old)
	t.check(Backstory.has_story(m), "old save without backstory gets one on load")
	t.equals(_sig(m.backstory), _sig(e.backstory), "migrated story is the same deterministic story")
	var junk: Dictionary = (parsed as Dictionary).duplicate(true)
	junk["backstory"] = {"v": 1, "like": "garbage"}
	var jf := Fish.new()
	parent.add_child(jf)
	jf.apply_save_dict(junk)
	t.check(Backstory.has_story(jf) and Backstory.likes(jf).has("key"), "malformed backstory is regenerated")

	# --- environment: valid targets, respects fear ----------------------
	var fern_pos := Vector3(3.0, 3.2, 0.0)
	var wood_pos := Vector3(-3.0, 2.2, 0.0)
	Env.set_landmarks_for_test([
		{"kind": "plant", "label": "Java Fern", "key": "plant:java_fern", "pos": fern_pos},
		{"kind": "driftwood", "label": "driftwood", "key": "driftwood", "pos": wood_pos},
	])
	var g := _make_fish(parent, "bs_env", "Ivo", pers)
	g.sim = null
	g.maturity = Fish.MATURITY_ADULT
	g.position = Vector3(0.0, 3.0, 0.0)
	g.home_x = 0.0
	g.home_z = 0.0
	g.stress = 0.0
	g.hunger = 0.2
	g.backstory = {"v": 1, "origin": "founder", "origin_text": "Test", "formative": "x", "quirk": "y",
		"like": {"kind": "plant", "label": "Java Fern", "key": "plant:java_fern"},
		"fear": {"kind": "driftwood", "label": "driftwood", "key": "driftwood"}, "fav_visits": 0}
	var lp: Vector3 = Env.resolve_pos(g, Backstory.likes(g))
	t.check(lp.is_finite() and lp.distance_to(fern_pos) < 0.01, "like resolves to the Java Fern")
	var bounds: AABB = Env.DEFAULT_BOUNDS.grow(0.01)
	var picked: Dictionary = {}
	for i in 60:
		var intent: String = Env.choose_intent(g)
		picked[intent] = true
		if intent == Env.INTENT_NONE:
			continue
		var tgt: Vector3 = g.env_state.get("target", Vector3.INF)
		t.check(tgt.is_finite() and bounds.has_point(tgt), "intent %s target valid %s" % [intent, str(tgt)])
		t.check(tgt.distance_to(wood_pos) > 1.0, "never targets the feared driftwood (%s)" % intent)
	t.check(picked.has(Env.INTENT_REST), "favourite-spot rest gets chosen")
	# Fear push: next to the driftwood the fish is pushed away from it.
	g.position = wood_pos + Vector3(0.8, 0.0, 0.0)
	Env.scan(g)
	var push: Vector3 = Env.fear_push(g, g.position, 1.0)
	t.check(push.length() > 0.1 and push.dot(g.position - wood_pos) > 0.0, "fear pushes away from driftwood")
	g.position = Vector3(3.0, 3.0, 3.0)
	t.approx(Env.fear_push(g, g.position, 1.0).length(), 0.0, "no fear push far away")
	var sv: Vector3 = Env.steer(g, 0.1, 1.0)
	t.check(sv.is_finite(), "steer returns a finite vector")
	# Arrival records an episode + counts the favourite-spot visit.
	var ep_before: int = g._episodic_store.size()
	Env._begin(g.env_state, Env.INTENT_REST, fern_pos, "the Java Fern", 10.0)
	g.position = fern_pos
	g.env_state["episode_t"] = -9999.0
	Env.steer(g, 0.1, 1.0)
	t.check(g._episodic_store.size() > ep_before, "arriving at favourite spot records an episode")
	t.equals(int(g.backstory.get("fav_visits", 0)), 1, "favourite-spot visit counted")
	t.check(Env.last_interaction(g).contains("Java Fern"), "last interaction readable: %s" % Env.last_interaction(g))
	# Newly placed object: a curious fish goes to inspect it.
	var c := _make_fish(parent, "bs_cur", "Kit", {"boldness": 0.8, "curiosity": 1.0, "sociability": 0.5, "calm": 0.5})
	c.sim = null
	c.maturity = Fish.MATURITY_ADULT
	c.position = Vector3(0.0, 3.0, 0.0)
	c.backstory = g.backstory.duplicate(true)
	Env.register_novel(Vector3(1.0, 2.5, 1.0), "new stone", "stones")
	var went: bool = false
	for i in 12:
		Env.scan(c)
		if Env.current_intent(c) == Env.INTENT_INVESTIGATE:
			went = true
			break
	t.check(went, "curious fish investigates a newly placed object")
	t.check(Env.current_activity(c).contains("new stone"), "activity text names the new object")
	Env.clear_for_test()
	quit(t.finish())
