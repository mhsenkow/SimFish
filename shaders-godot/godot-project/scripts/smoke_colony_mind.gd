extends SceneTree

# ColonyMind (colony_mind.gd): invertebrate collective minds. Headless — no
# World; a small stand-in sim carries only the fields ColonyMind reads.
#
# Covers: mood reacts to predation (named fish) and food rain; snails bias
# surfaceward in bad water (API + the real snail.gd heading choice); voice is
# grounded and does not repeat; relevance for a "shrimp" keeper topic; save
# round-trip + legacy/garbage migration; tick cost bounded for 200 shrimp.

const ColonyMind = preload("res://scripts/colony_mind.gd")
const SnailScript = preload("res://scripts/snail.gd")


class FakeChem:
	extends RefCounted
	var ammonia: float = 0.0
	var nitrite: float = 0.0


class FakeFish:
	extends Node3D
	var fish_name: String = "Ember"
	var species: String = "betta"
	var shrimp_predator: bool = true
	@warning_ignore("unused_private_class_variable")
	var _asleep: bool = false


class FakeSnail:
	extends Node3D
	var hunger: float = 0.3
	var is_baby: bool = false

	func _init() -> void:
		add_to_group("snails")


class FakeSim:
	extends Node
	var shrimp: Array = []
	var fish: Array = []
	var plants: Array = []
	var algae: Array = []
	var waste: Array = []
	var _live_snails: Array = []
	var _feed_memory: Array = []
	var dissolved_o2: float = 0.85
	var total_plant_biomass: int = 120
	var water_chemistry: FakeChem = FakeChem.new()
	var substrate_census: Dictionary = {"trumpets": 6, "worms": 3, "micro": 40}
	var dl: float = 0.8

	func daylight() -> float:
		return dl

	func sim_day() -> float:
		return 3.0


func _make_sim(n_shrimp: int, n_snails: int) -> FakeSim:
	var sim := FakeSim.new()
	root.add_child(sim)
	for i in n_shrimp:
		var s: Shrimp = Shrimp.new()
		s.hunger = 0.3
		s.maturity = Shrimp.MATURITY_ADULT
		s.position = Vector3(float(i % 10) * 0.3, 1.7, float(i / 10.0) * 0.3)
		sim.shrimp.append(s)
	for i in n_snails:
		var sn := FakeSnail.new()
		sn.position = Vector3(float(i), 2.0, 0.0)
		sim.add_child(sn)
		sim._live_snails.append(sn)
	return sim


func _free_sim(sim: FakeSim) -> void:
	for s in sim.shrimp:
		(s as Node).free()
	sim.shrimp.clear()
	for f in sim.fish:
		(f as Node).free()
	sim.fish.clear()
	sim.free()


func _initialize() -> void:
	# One frame so root is inside the tree (snail.gd reads global_position).
	await process_frame
	var t := TestSupport.Suite.new("smoke_colony_mind")
	_test_mood(t)
	_test_snail_surface(t)
	_test_voice(t)
	_test_relevance(t)
	_test_save(t)
	_test_cost(t)
	quit(t.finish())


func _test_mood(t: TestSupport.Suite) -> void:
	var sim := _make_sim(12, 4)
	ColonyMind.tick_all_now(sim)
	var gd: Dictionary = ColonyMind.group(sim, "shrimp")
	t.equals(int(gd.get("population", 0)), 12, "shrimp census")
	t.check(sim.has_meta(ColonyMind.META_KEY), "state lives on sim meta")
	var v0: float = float(gd.get("valence", 0.0))

	# Predation by a named fish: mood drops, colony alarm rises, memory names it.
	var ember := FakeFish.new()
	ember.position = Vector3(20, 3, 0)   # far from the colony
	sim.fish.append(ember)
	var victim: Shrimp = sim.shrimp.pop_back()
	ColonyMind.note_predation(sim, ember, victim)
	victim.free()
	t.check(float(gd["valence"]) < v0 - 0.2, "predation drops valence (%.2f -> %.2f)" % [v0, float(gd["valence"])])
	t.check(ColonyMind.shrimp_alarm(sim) > 0.8, "predation raises colony alarm")
	var mem: Array = gd.get("memory", [])
	t.check(not mem.is_empty() and str(mem[-1].get("d", "")) == "Ember",
		"memory names the predator fish")
	# The kill must not also read as an unexplained loss on the next census.
	ColonyMind.tick_all_now(sim)
	t.equals(int(gd.get("losses_total", 0)), 0, "a noted kill is not double-counted as a loss")
	# Alarm decays over time.
	for _i in 40:
		ColonyMind.tick(sim, 1.0)
	t.check(ColonyMind.shrimp_alarm(sim) < 0.2, "alarm decays when nothing else happens")

	# Food rain: a fresh feed drop lifts mood and pulls idle shrimp to it.
	var v1: float = float(gd["valence"])
	var drop := Vector3(4.0, 5.0, 2.0)
	sim._feed_memory.append({"pos": drop, "t": 0.0})
	ColonyMind.tick_all_now(sim)
	t.check(float(gd["valence"]) > v1 + 0.1, "food rain lifts valence (%.2f -> %.2f)" % [v1, float(gd["valence"])])
	var pull: Vector3 = ColonyMind.shrimp_swarm_pull(sim, Vector3(0, 1.7, 0), 0.5)
	t.check(pull.length() > 0.1 and pull.x > 0.0 and pull.z > 0.0, "swarm pull points at the drop")
	t.equals(ColonyMind.shrimp_swarm_pull(sim, Vector3(0, 1.7, 0), 0.0), Vector3.ZERO,
		"sated shrimp ignore the swarm")

	# Predator loitering near the colony raises a (habituating) alarm.
	ember.position = Vector3(1.0, 1.7, 0.6)
	ColonyMind.tick_all_now(sim)
	t.check(ColonyMind.shrimp_alarm(sim) > 0.1, "predator near colony -> collective hide cue")
	t.check(str(gd.get("near_predator", "")) == "Ember", "near predator is named")

	# Moult nights multiply the moult clock; normal nights do not.
	gd["moult_night"] = true
	ColonyMind.note(sim, "shrimp", "moult")
	t.check(ColonyMind.shrimp_moult_mult(sim) > 1.5, "moult night speeds moults")
	ColonyMind.note(sim, "shrimp", "moult")
	t.equals(int((gd["memory"] as Array)[-1].get("n", 0)), 2, "moults coalesce into one memory")
	_free_sim(sim)


func _test_snail_surface(t: TestSupport.Suite) -> void:
	var sim := _make_sim(0, 6)
	ColonyMind.tick_all_now(sim)
	t.check(ColonyMind.snail_surface_bias(sim) < 0.05, "good water: no surface bias")
	t.check(not ColonyMind.substrate_emerge(sim), "good water: trumpets stay buried by day")
	var good_up: int = _count_up_headings(sim)

	sim.dissolved_o2 = 0.30
	sim.water_chemistry.ammonia = 0.25
	ColonyMind.tick_all_now(sim)
	var sb: float = ColonyMind.snail_surface_bias(sim)
	t.check(sb > 0.6, "bad water: snails bias surfaceward (%.2f)" % sb)
	t.check(ColonyMind.substrate_emerge(sim), "bad water: trumpet snails surface by day")
	var bad_up: int = _count_up_headings(sim)
	t.check(bad_up > good_up * 3 and bad_up > 60,
		"real snail.gd heads up far more often in bad water (good=%d bad=%d)" % [good_up, bad_up])

	# Melting plant = feast; snails congregate.
	var melt := FakeMeltPlant.new()
	melt.position = Vector3(3.0, 1.6, 1.0)
	sim.add_child(melt)
	sim.plants.append(melt)
	ColonyMind.tick_all_now(sim)
	var gd: Dictionary = ColonyMind.group(sim, "snails")
	t.check(float(gd.get("feast", 0.0)) > 0.25, "melting plant registers as a feast")
	var fp: Vector3 = ColonyMind.snail_feast_pull(sim, Vector3(0.0, 1.6, 0.0))
	t.check(fp.x > 2.0, "snails pulled toward the melting plant")
	var mem: Array = gd.get("memory", [])
	t.check(not mem.is_empty() and str(mem[-1].get("k", "")) == "melt", "melt remembered")
	_free_sim(sim)


class FakeMeltPlant:
	extends Node3D
	var _melt_active: bool = true
	var species_name: String = "crypt wendtii"

	func biomass() -> int:
		return 30


# Real snail.gd heading choice on vertical glass, 400 rolls.
func _count_up_headings(sim: FakeSim) -> int:
	var sn: Node3D = SnailScript.new()
	sn.process_mode = Node.PROCESS_MODE_DISABLED
	sn.set("wall_normal", Vector3.RIGHT)
	sim.add_child(sn)
	sn.set("_sim_driver_ref", sim)
	sn.position = Vector3(-4.0, 3.0, 0.0)
	var up: int = 0
	for _i in 400:
		sn.set("_clamped", false)
		sn.call("_choose_new_direction")
		var d: Vector2 = sn.get("_direction")
		if d.is_equal_approx(Vector2(0.0, 1.0)):
			up += 1
	sim.remove_child(sn)
	sn.free()
	return up


func _test_voice(t: TestSupport.Suite) -> void:
	var sim := _make_sim(10, 5)
	ColonyMind.tick_all_now(sim)
	var ember := FakeFish.new()
	ember.fish_name = "Ember"
	sim.fish.append(ember)
	ColonyMind.note_predation(sim, ember, sim.shrimp[0])
	var calm: String = ColonyMind.voice_line("shrimp", sim, "calm")
	t.check(calm.contains("Ember"), "shrimp voice grounded in the kill: '%s'" % calm)
	var seen: Array = []
	var repeats: int = 0
	for _i in 8:
		var line: String = ColonyMind.voice_line("shrimp", sim, "")
		t.check(line != "", "shrimp voice non-empty")
		if seen.has(line):
			repeats += 1
		seen.append(line)
	t.equals(repeats, 0, "8 shrimp lines, none repeated")

	sim.dissolved_o2 = 0.3
	ColonyMind.tick_all_now(sim)
	var sl: String = ColonyMind.voice_line("snails", sim, "water")
	t.check(sl.contains("climb") or sl.contains("top") or sl.contains(" up") or sl.contains("the line"),
		"snail voice names the climb in bad water: '%s'" % sl)
	t.check(sl.contains("…"), "snail voice is slow (ellipses)")
	var sub: String = ColonyMind.voice_line("substrate", sim, "")
	t.check(sub != "", "substrate speaks")
	t.equals(ColonyMind.voice_line("nobody", sim, ""), "", "unknown group is silent")
	_free_sim(sim)
	var empty := _make_sim(0, 0)
	ColonyMind.tick_all_now(empty)
	t.equals(ColonyMind.voice_line("shrimp", empty, "food"), "", "no shrimp -> no shrimp voice")
	_free_sim(empty)


func _test_relevance(t: TestSupport.Suite) -> void:
	var sim := _make_sim(8, 4)
	ColonyMind.tick_all_now(sim)
	var r_named: float = ColonyMind.relevance("shrimp", sim, "how are the shrimp doing?")
	t.check(r_named >= 1.0, "naming shrimp -> addressed (%.2f)" % r_named)
	var r_off: float = ColonyMind.relevance("shrimp", sim, "nice lamp")
	t.check(r_off < 0.45, "unrelated line -> shrimp stay quiet (%.2f)" % r_off)
	t.check(ColonyMind.relevance("snails", sim, "how are the shrimp doing?") < 0.45,
		"shrimp question does not summon the snails")
	sim.dissolved_o2 = 0.3
	ColonyMind.tick_all_now(sim)
	var r_water: float = ColonyMind.relevance("snails", sim, "is the water ok?")
	t.check(r_water >= 0.45, "water question + snails climbing -> snails answer (%.2f)" % r_water)
	var ch: Array = ColonyMind.chorus(sim, "hello shrimp", PackedStringArray(["greeting"]), 1)
	t.check(ch.size() == 1 and str(ch[0].get("group", "")) == "shrimp", "chorus picks the named colony")
	if not ch.is_empty():
		t.equals(str(ch[0].get("speaker", "")), "the shrimp colony", "speaker label")
		t.check(str(ch[0].get("line", "")) != "", "chorus carries a line")
	_free_sim(sim)


func _test_save(t: TestSupport.Suite) -> void:
	var sim := _make_sim(6, 3)
	ColonyMind.tick_all_now(sim)
	var ember := FakeFish.new()
	sim.fish.append(ember)
	ColonyMind.note_predation(sim, ember, sim.shrimp[0])
	for i in 30:
		ColonyMind.note(sim, "shrimp", "birth" if i % 2 == 0 else "food_rain", "", 1.0)
		ColonyMind.group(sim, "shrimp")["memory"][-1]["c"] = -1000.0 * float(i)  # defeat coalescing
	var saved: Dictionary = ColonyMind.to_dict(sim)
	t.equals(int(saved.get("schema_version", 0)), ColonyMind.SCHEMA_VERSION, "save is schema-versioned")
	var mem_saved: Array = saved["groups"]["shrimp"]["memory"]
	t.check(mem_saved.size() <= ColonyMind.MEMORY_MAX, "saved memory bounded (%d)" % mem_saved.size())
	t.check(JSON.stringify(saved).length() < 8000, "save payload small")
	var round_trip: Variant = JSON.parse_string(JSON.stringify(saved))   # through JSON like the real save
	var sim2 := _make_sim(0, 0)
	ColonyMind.from_dict(sim2, round_trip)
	var g2: Dictionary = ColonyMind.group(sim2, "shrimp")
	var g1: Dictionary = ColonyMind.group(sim, "shrimp")
	t.approx(float(g2["valence"]), float(g1["valence"]), "valence survives", 0.002)
	t.equals(str(g2.get("last_predator", "")), "Ember", "last predator survives")
	t.equals(int(g2.get("births_total", 0)), int(g1.get("births_total", 0)), "births survive")
	t.equals((g2["memory"] as Array).size(), mem_saved.size(), "memory survives")

	# Migration: absent / garbage / legacy v0 flat layout.
	var sim3 := _make_sim(0, 0)
	ColonyMind.from_dict(sim3, null)
	t.approx(float(ColonyMind.group(sim3, "snails")["valence"]), 0.1, "null -> defaults")
	ColonyMind.from_dict(sim3, "garbage")
	t.has_keys(ColonyMind.group(sim3, "substrate"), ["valence", "memory", "bias"], "garbage -> defaults")
	ColonyMind.from_dict(sim3, {"shrimp": {"valence": 9.0, "moults_total": 4,
			"memory": ["bad", {"k": "moult", "n": 2}]}})
	var g3: Dictionary = ColonyMind.group(sim3, "shrimp")
	t.approx(float(g3["valence"]), 1.0, "v0 flat save migrated + clamped")
	t.equals(int(g3.get("moults_total", 0)), 4, "v0 counters kept")
	t.equals((g3["memory"] as Array).size(), 1, "v0 junk memory entries dropped")
	t.approx(float(ColonyMind.group(sim3, "snails")["valence"]), 0.1, "missing group -> defaults")
	_free_sim(sim)
	_free_sim(sim2)
	_free_sim(sim3)


func _test_cost(t: TestSupport.Suite) -> void:
	var sim := _make_sim(200, 40)
	for i in 12:
		var f := FakeFish.new()
		f.shrimp_predator = i % 3 == 0
		f.position = Vector3(float(i), 3.0, 0.0)
		sim.fish.append(f)
	for i in 80:
		var p := FakeMeltPlant.new()
		p._melt_active = i == 7
		sim.plants.append(p)
	ColonyMind.tick_all_now(sim)
	var t0: int = Time.get_ticks_usec()
	for _i in 20:
		ColonyMind.tick_all_now(sim)
	var full_us: float = float(Time.get_ticks_usec() - t0) / 20.0
	t.check(full_us < 2500.0, "full 3-group update for 200 shrimp < 2.5 ms (%.0f us)" % full_us)
	t0 = Time.get_ticks_usec()
	for _i in 600:
		ColonyMind.tick(sim, 1.0 / 60.0)
	var frame_us: float = float(Time.get_ticks_usec() - t0) / 600.0
	t.check(frame_us < 60.0, "amortised per-frame tick < 60 us (%.1f us)" % frame_us)
	t0 = Time.get_ticks_usec()
	var acc: float = 0.0
	for s in sim.shrimp:
		acc += ColonyMind.shrimp_alarm(sim) + ColonyMind.shrimp_moult_mult(sim)
		acc += ColonyMind.shrimp_swarm_pull(sim, (s as Node3D).position, 0.5).x
	var reads_us: float = float(Time.get_ticks_usec() - t0)
	t.check(reads_us < 1500.0 and is_finite(acc), "200 shrimp bias reads < 1.5 ms (%.0f us)" % reads_us)
	for p in sim.plants:
		(p as Node).free()
	sim.plants.clear()
	_free_sim(sim)
