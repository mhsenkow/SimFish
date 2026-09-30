extends SceneTree

# Fish social graph (fish_social.gd): affinity from shared schooling, loss from
# chases, decay toward neutral, bounded maps, save round-trip + migration of
# pre-social saves, and grief when a close friend dies.

const FishSocial = preload("res://scripts/fish_social.gd")


var _host: Node3D = null


func _mk(fid: String, pos: Vector3, nm: String = "") -> Fish:
	var f := Fish.new()
	_host.add_child(f)
	f.id = fid
	f.species = "glassdart"
	f.fish_name = nm
	f.maturity = Fish.MATURITY_ADULT
	f.age = 600.0
	f.position = pos
	f.heading = Vector3.FORWARD
	return f


func _initialize() -> void:
	await process_frame
	_host = Node3D.new()
	root.add_child(_host)
	var t := TestSupport.Suite.new("smoke_fish_social")
	var made: Array = []

	# --- 1. Shared schooling grows friendship -------------------------------
	var a := _mk("fa", Vector3(0, 1, 0), "Mira")
	var b := _mk("fb", Vector3(1, 1, 0), "Kip")
	var far := _mk("fc", Vector3(20, 1, 0), "Bo")
	made.append_array([a, b, far])
	var roster: Array = [a, b, far]
	var now: float = 1000.0
	for i in 20:
		now += 5.0
		FishSocial.tick_among(a, 5.0, roster, now, 1_700_000_000 + i * 5)
		FishSocial.tick_among(b, 5.0, roster, now, 1_700_000_000 + i * 5)
	var ab: float = FishSocial.affinity(a, "fb")
	t.check(ab >= FishSocial.FRIEND_AFF,
		"schooling together makes friends (aff %.3f)" % ab)
	t.approx(FishSocial.affinity(a, "fc"), 0.0, "a fish far away gains no affinity")
	t.check(FishSocial.has_tag(a, "fb", "shoal"), "shoal-mate tag recorded")
	t.equals(String(FishSocial.best_friend(a).get("id", "")), "fb", "best_friend is the shoal-mate")
	t.equals(String(FishSocial.best_friend(a).get("name", "")), "Kip", "best_friend carries the name")
	t.check(FishSocial.describe_relation(a, b).contains("Kip"), "describe_relation names the other fish")
	t.check(FishSocial.summary_line(a).begins_with("Friends: Kip"),
		"summary line lists the friend (%s)" % FishSocial.summary_line(a))
	var befriended: bool = false
	for e in a._episodic_store:
		if String((e as Dictionary).get("kind", "")) == "befriended":
			befriended = true
	t.check(befriended, "friendship recorded as an episodic memory")

	# Misaligned fish nearby don't count as schooling.
	var c := _mk("fd", Vector3(0, 1, 1))
	var d := _mk("fe", Vector3(0.5, 1, 1))
	d.heading = Vector3.BACK
	made.append_array([c, d])
	for i in 10:
		FishSocial.tick_among(c, 5.0, [c, d], 2000.0 + i * 5.0, 1_700_000_000)
	t.check(FishSocial.affinity(c, "fe") < 0.01, "opposite headings are not schooling")

	# --- 2. Chases lower affinity on both sides -----------------------------
	var bully := _mk("fx", Vector3(1.5, 1, 0), "Brute")
	bully.heading = Vector3.BACK  # passing through, not schooling with b
	made.append(bully)
	var roster2: Array = [a, b, bully]
	FishSocial.tick_among(b, 5.0, roster2, 3000.0, 1_700_001_000)  # seed gseen
	b.grudges["fx"] = 600.0
	FishSocial.tick_among(b, 5.0, roster2, 3005.0, 1_700_001_005)
	t.check(FishSocial.affinity(b, "fx") < 0.0, "being chased lowers affinity for the chaser")
	t.check(FishSocial.has_tag(b, "fx", "chased_me"), "'that one chased me' remembered")
	t.check(FishSocial.affinity(bully, "fb") < 0.0, "chaser's opinion of the victim drops too")
	var before_repeat: float = FishSocial.affinity(b, "fx")
	FishSocial.tick_among(b, 5.0, roster2, 3010.0, 1_700_001_010)
	t.approx(FishSocial.affinity(b, "fx"), before_repeat, "a standing grudge is one chase, not one per tick",
		0.01)
	# Two more distinct chases make a rival.
	for n in 2:
		b.grudges.erase("fx")
		FishSocial.tick_among(b, 0.1, roster2, 3020.0 + n, 1_700_001_020)
		b.grudges["fx"] = 600.0
		FishSocial.tick_among(b, 0.1, roster2, 3025.0 + n, 1_700_001_025)
	t.check(FishSocial.affinity(b, "fx") <= FishSocial.RIVAL_AFF,
		"repeated chases make a rival (aff %.3f)" % FishSocial.affinity(b, "fx"))
	t.equals(String(FishSocial.rival(b).get("id", "")), "fx", "rival() returns the bully")
	t.check(FishSocial.describe_relation(b, "fx").contains("chased me"),
		"describe_relation mentions the chase (%s)" % FishSocial.describe_relation(b, "fx"))
	t.check(float(b.grudges.get("fx", 0.0)) >= FishSocial.RIVAL_GRUDGE_S,
		"a rival keeps a grudge alive so avoidance steering applies")

	# --- 3. Decay relaxes toward neutral (never past it) ---------------------
	var lone := _mk("fl", Vector3.ZERO)
	made.append(lone)
	lone.bonds["p"] = 0.8
	lone.bonds["q"] = -0.8
	FishSocial.tick_among(lone, 200.0, [], 5000.0, 1_700_002_000)
	var pa: float = FishSocial.affinity(lone, "p")
	var qa: float = FishSocial.affinity(lone, "q")
	t.check(pa < 0.8 and pa > 0.0, "positive affinity decays toward 0 (%.3f)" % pa)
	t.check(qa > -0.8 and qa < 0.0, "rival affinity decays toward 0, not toward -1 (%.3f)" % qa)
	for i in 20:
		FishSocial.tick_among(lone, 100.0, [], 5100.0 + i, 1_700_002_100)
	t.check(not lone.bonds.has("p") and not lone.bonds.has("q"), "fully decayed strangers are forgotten")

	# --- 4. Bounded size -----------------------------------------------------
	var busy := _mk("fbusy", Vector3.ZERO)
	made.append(busy)
	for i in 40:
		FishSocial.record_event(busy, "other_%d" % i, "met", 0.05 + 0.01 * i)
	t.check(busy.bonds.size() <= FishSocial.MAX_REL,
		"bonds bounded (%d)" % busy.bonds.size())
	t.check((busy.social["rel"] as Dictionary).size() <= FishSocial.MAX_REL,
		"relationship map bounded (%d)" % (busy.social["rel"] as Dictionary).size())
	t.check(busy.bonds.has("other_39"), "strongest relationships are the ones kept")

	# --- 5. Save round-trip + migration --------------------------------------
	var saved: Dictionary = FishSocial.to_save(b)
	var json_back: Variant = JSON.parse_string(JSON.stringify(saved))
	var b2 := _mk("fb", Vector3.ZERO)
	made.append(b2)
	b2.bonds = b.bonds.duplicate()
	FishSocial.from_save(b2, json_back)
	t.check(FishSocial.has_tag(b2, "fx", "chased_me"), "tags survive a JSON round-trip")
	t.equals(String(FishSocial.rival(b2).get("id", "")), "fx", "rival survives a round-trip")
	t.equals(FishSocial.describe_relation(b2, "fa"), FishSocial.describe_relation(b, "fa"),
		"describe_relation identical after round-trip")
	var old := _mk("fold", Vector3.ZERO)
	made.append(old)
	old.grudges["someone"] = 300.0
	FishSocial.from_save(old, null)
	t.check((old.social["rel"] as Dictionary).is_empty(), "pre-social save migrates to an empty graph")
	FishSocial.tick_among(old, 5.0, [], 6000.0, 1_700_003_000)
	t.check(not FishSocial.has_tag(old, "someone", "chased_me"),
		"old grudges are adopted silently, not replayed as new chases")
	var junk := _mk("fjunk", Vector3.ZERO)
	made.append(junk)
	FishSocial.from_save(junk, {"rel": {"x": "garbage", "y": {"fam": "NaN", "tags": 5}}, "grief": 7})
	t.check(not (junk.social["rel"] as Dictionary).has("x"), "malformed relationship entries dropped")
	t.check(FishSocial.grieving_for(junk).is_empty(), "malformed grief ignored")
	var src: String = FileAccess.get_file_as_string("res://scripts/fish.gd")
	t.check(src.contains("\"social\": FishSocial.to_save(self)"), "fish save dict persists the social graph")
	t.check(src.contains("FishSocial.from_save(self, d.get(\"social\""), "fish load restores the social graph")

	# --- 6. Grief when a close friend dies -----------------------------------
	a.bonds["fb"] = 0.8
	var mood_before: float = a.mood
	a.position = Vector3(6, 1, 0)
	FishSocial.on_death_among(b, [a, b, far])
	var g: Dictionary = FishSocial.grieving_for(a)
	t.equals(String(g.get("id", "")), "fb", "friend's death starts grief")
	t.check(float(g.get("level", 0.0)) > 0.5, "close friend -> strong grief")
	t.check(a.mood < mood_before, "grief lowers mood")
	t.check(FishSocial.grief_pull(a).length() > 0.9, "grieving fish is drawn to where the friend died")
	t.check(FishSocial.best_friend(a).is_empty(), "a dead friend is no longer best_friend")
	t.check(FishSocial.describe_relation(a, "fb").contains("gone"), "describe_relation knows they are gone")
	t.check(FishSocial.summary_line(a).contains("Missing Kip"), "panel line shows the loss")
	var loss_ep: bool = false
	for e in a._episodic_store:
		if String((e as Dictionary).get("kind", "")) == "loss":
			loss_ep = true
	t.check(loss_ep, "loss recorded as an episodic memory")
	t.approx(FishSocial.grief_level(far), 0.0, "a stranger does not grieve")
	var lvl0: float = FishSocial.grief_level(a)
	FishSocial.tick_among(a, 30.0, [a, far], 7000.0, 1_700_004_000)
	t.check(FishSocial.grief_level(a) < lvl0, "grief fades over time")
	for i in 40:
		FishSocial.tick_among(a, 30.0, [a, far], 7100.0 + i, 1_700_004_100)
	t.check(FishSocial.grieving_for(a).is_empty(), "grief ends eventually")

	# Mates grieve even at moderate affinity.
	var m1 := _mk("m1", Vector3.ZERO)
	var m2 := _mk("m2", Vector3.ONE)
	made.append_array([m1, m2])
	FishSocial.record_event(m1, m2, "spawned together", 0.25, "mate")
	FishSocial.on_death_among(m2, [m1, m2])
	t.check(FishSocial.grief_level(m1) >= 0.5, "a mate's death is grieved")

	_host.free()
	quit(t.finish())
