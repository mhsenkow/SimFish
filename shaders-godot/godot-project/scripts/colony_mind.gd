extends RefCounted

# Collective minds for the invertebrates — "do the arthropods need brains too?"
#
# Fish get one mind each (fish_mind*, global_workspace, mind_*); the tank has a
# slow macro mind (tank_mind.gd). Shrimp, snails and the substrate crowd are
# modelled as COLLECTIVES instead: one small mood/needs/memory record per group,
# ticked every 1.5–3 s (staggered), O(n) over that group's members. That is both
# cheap and biologically apt — a shrimp colony reads the water as a crowd
# (synchronised moults, shared alarm cues, swarming a food drop), and snails
# answer water quality as a population (the "snails at the waterline" tell).
#
# Groups:
#   "shrimp"    — the shrimp colony
#   "snails"    — the snail congregation (glass/substrate crawlers, snail.gd)
#   "substrate" — trumpet snails + detrital/bristle worms + microfauna swarm
#
# State lives on the SimDriver as metadata (META_KEY) so no field has to be
# added to sim_driver.gd. Persisted via to_dict()/from_dict() (schema-versioned,
# bounded). Behaviour hooks in shrimp.gd / snail.gd / trumpet_snail.gd read the
# cached per-group bias through the tiny helpers near the bottom — each is a
# couple of dictionary lookups, safe to call per creature per tick.
#
# Voice: voice_line(group, sim, topic) — template-only, grounded in the group's
# real state and memory, never repeats a recent line. relevance()/chorus() let
# the tank-conversation code include a colony as a responder.
#
# No class_name on purpose (callers preload) so headless runs need no rescan.

const SCHEMA_VERSION: int = 1
const META_KEY: StringName = &"colony_mind"
const GROUPS: Array[String] = ["shrimp", "snails", "substrate"]
const MEMORY_MAX: int = 12
const RECENT_LINES_MAX: int = 8
const DETAIL_MAX_LEN: int = 40
const COALESCE_S: float = 45.0
const SWARM_TTL_S: float = 25.0
const ALARM_DECAY_PER_S: float = 0.045
const PRED_RADIUS: float = 4.5

# Base tick interval and initial stagger per group — never all on one frame.
const INTERVAL: Dictionary = {"shrimp": 1.5, "snails": 2.5, "substrate": 3.0}
const STAGGER: Dictionary = {"shrimp": 0.0, "snails": 0.8, "substrate": 1.7}

const SPEAKER: Dictionary = {
	"shrimp": "the shrimp colony",
	"snails": "the snails",
	"substrate": "the substrate",
}

# Words that name a group directly (keeper addressing it).
const NAME_WORDS: Dictionary = {
	"shrimp": ["shrimp", "shrimps", "shrimplet", "shrimplets", "cherry", "cherries",
			"neocaridina", "caridina", "amano", "prawn", "prawns", "moult", "molt",
			"molting", "moulting", "colony", "crustacean", "crustaceans"],
	"snails": ["snail", "snails", "nerite", "nerites", "ramshorn", "ramshorns",
			"shell", "shells", "slime", "bladder", "mystery", "apple"],
	"substrate": ["substrate", "gravel", "soil", "sand", "dirt", "worm", "worms",
			"bottom", "floor", "bacteria", "microfauna", "copepod", "copepods",
			"critters", "bugs", "detritus", "trumpet", "trumpets", "mts", "mulm"],
}

# Minimal topic table so this module works standalone; the conversation code
# may pass TankMind.parse_keeper_words() topics instead.
const TOPIC_WORDS: Dictionary = {
	"greeting": ["hello", "hi", "hey", "morning", "evening", "greetings"],
	"food": ["food", "hungry", "eat", "eating", "feed", "fed", "feeding", "snack",
			"flakes", "pellets", "meal", "algae", "biofilm", "wafer"],
	"water": ["water", "clean", "dirty", "ammonia", "nitrate", "nitrite", "cloudy",
			"murky", "filter", "chemistry", "toxic", "quality", "parameters", "ph"],
	"air": ["air", "oxygen", "o2", "breath", "breathing", "bubbles", "gasp", "gasping"],
	"calm": ["safe", "calm", "ok", "okay", "shh", "quiet", "relax", "gentle", "sorry",
			"scared", "afraid", "danger", "hide", "hiding"],
	"light": ["light", "dark", "night", "sleep", "day", "lamp", "dawn", "dusk"],
	"wellbeing": ["how", "feel", "feeling", "doing", "happy", "sad", "well", "healthy"],
	"who": ["who", "many", "count", "everyone", "everybody", "all", "family"],
}


# --- state -----------------------------------------------------------------

static func default_group(g: String) -> Dictionary:
	return {
		"valence": 0.1,
		"arousal": 0.2,
		"need_food": 0.3,
		"need_cover": 0.3,
		"water_stress": 0.0,
		"population": 0,
		"juveniles": 0,
		"alarm": 0.0,
		"habituation": 0.0,
		"last_predator": "",
		"feast": 0.0,
		"feast_name": "",
		"feast_id": 0,
		"swarm_ttl": 0.0,
		"moult_night": false,
		"moults_tonight": 0,
		"moults_total": 0,
		"births_total": 0,
		"losses_total": 0,
		"memory": [],
		"recent_lines": [],
		"accum": float(STAGGER.get(g, 0.0)),
		"_last_n": -1,
		"_last_juv": -1,
		"_kills_since": 0,
		"_was_night": false,
		"_pos": Vector3.INF,        # colony centroid (runtime only)
		"_swarm_pos": Vector3.INF,  # runtime only
		"_feast_pos": Vector3.INF,  # runtime only
		"bias": {},
	}


static func ensure(sim: Object) -> Dictionary:
	if sim == null:
		return {}
	if sim.has_meta(META_KEY):
		var d: Variant = sim.get_meta(META_KEY)
		if d is Dictionary:
			return d
	var fresh: Dictionary = {"schema_version": SCHEMA_VERSION, "clock": 0.0, "groups": {}}
	for g in GROUPS:
		fresh["groups"][g] = default_group(g)
		_refresh_bias(fresh["groups"][g], g)
	sim.set_meta(META_KEY, fresh)
	return fresh


static func group(sim: Object, g: String) -> Dictionary:
	var cm: Dictionary = ensure(sim)
	if cm.is_empty():
		return {}
	var groups: Dictionary = cm["groups"]
	if not groups.has(g):
		groups[g] = default_group(g)
		_refresh_bias(groups[g], g)
	return groups[g]


static func clock(sim: Object) -> float:
	var cm: Dictionary = ensure(sim)
	return float(cm.get("clock", 0.0))


# --- tick ------------------------------------------------------------------

# Call once per sim tick with sim dt. Each group updates on its own staggered
# interval; between updates this is three float adds.
static func tick(sim: Object, dt: float) -> void:
	if sim == null or dt <= 0.0:
		return
	var cm: Dictionary = ensure(sim)
	cm["clock"] = float(cm.get("clock", 0.0)) + dt
	var groups: Dictionary = cm["groups"]
	var ws: float = -1.0
	for g in GROUPS:
		var gd: Dictionary = groups.get(g, {})
		if gd.is_empty():
			gd = default_group(g)
			groups[g] = gd
		gd["accum"] = float(gd.get("accum", 0.0)) + dt
		var interval: float = float(INTERVAL.get(g, 2.0))
		if float(gd["accum"]) < interval:
			continue
		var elapsed: float = float(gd["accum"])
		gd["accum"] = 0.0
		if ws < 0.0:
			ws = water_stress(sim)
		match g:
			"shrimp":
				_update_shrimp(sim, gd, elapsed, ws)
			"snails":
				_update_snails(sim, gd, elapsed, ws)
			"substrate":
				_update_substrate(sim, gd, elapsed, ws)
		_refresh_bias(gd, g)


# Force every group to update now (tests, load, away catch-up).
static func tick_all_now(sim: Object) -> void:
	if sim == null:
		return
	for g in GROUPS:
		var gd: Dictionary = group(sim, g)
		gd["accum"] = float(INTERVAL.get(g, 2.0))
	tick(sim, 0.0001)


# 0..1: how hard the water is on soft bodies. Low O2 weighs heaviest (a snail
# at the waterline is first of all a breathing problem), then NH3/NO2.
static func water_stress(sim: Object) -> float:
	var o2: float = _f(sim, "dissolved_o2", 0.85)
	var nh3: float = 0.0
	var no2: float = 0.0
	var wc: Variant = sim.get("water_chemistry") if sim != null else null
	if wc is Object and wc != null:
		var a: Variant = (wc as Object).get("ammonia")
		var n: Variant = (wc as Object).get("nitrite")
		nh3 = float(a) if a != null else 0.0
		no2 = float(n) if n != null else 0.0
	var o2_s: float = clampf((0.55 - o2) / 0.35, 0.0, 1.0)
	var tox_s: float = clampf((nh3 + no2 - 0.10) / 0.50, 0.0, 1.0)
	return clampf(maxf(o2_s, tox_s) + minf(o2_s, tox_s) * 0.3, 0.0, 1.0)


static func _update_shrimp(sim: Object, gd: Dictionary, el: float, ws: float) -> void:
	var list: Variant = sim.get("shrimp")
	var n: int = 0
	var juv: int = 0
	var sum_h: float = 0.0
	var c: Vector3 = Vector3.ZERO
	if list is Array:
		for s in list:
			if not is_instance_valid(s):
				continue
			if bool(s.get("_dying")):
				continue
			n += 1
			sum_h += float(s.get("hunger"))
			c += (s as Node3D).position
			if int(s.get("maturity")) == 0:
				juv += 1
	gd["population"] = n
	gd["juveniles"] = juv
	gd["_pos"] = c / float(n) if n > 0 else Vector3.INF
	var avg_h: float = sum_h / float(n) if n > 0 else 0.0
	# Food availability: algae + detritus per head.
	var algae_n: int = _arr_size(sim, "algae")
	var waste_n: int = _arr_size(sim, "waste")
	var avail: float = clampf((float(algae_n) + float(waste_n) * 0.5) / maxf(1.0, float(n) * 0.8), 0.0, 1.0)
	gd["need_food"] = clampf(avg_h * 0.7 + (1.0 - avail) * 0.3, 0.0, 1.0)
	var cover: float = clampf(_f(sim, "total_plant_biomass", 0.0) / (40.0 + float(n) * 20.0), 0.0, 1.0)
	gd["need_cover"] = 1.0 - cover
	gd["water_stress"] = ws
	# Births / losses from census deltas.
	var last_juv: int = int(gd.get("_last_juv", -1))
	if last_juv >= 0 and juv > last_juv:
		note(sim, "shrimp", "birth", "", float(juv - last_juv))
	var last_n: int = int(gd.get("_last_n", -1))
	if last_n >= 0 and n < last_n and int(gd.get("_kills_since", 0)) == 0:
		note(sim, "shrimp", "loss", "", float(last_n - n))
	gd["_last_juv"] = juv
	gd["_last_n"] = n
	gd["_kills_since"] = 0
	# Predator presence near the colony centroid (O(fish), not O(fish*shrimp)).
	var presence: float = 0.0
	var nearest_name: String = ""
	if n > 0:
		var fl: Variant = sim.get("fish")
		if fl is Array:
			for f in fl:
				if not is_instance_valid(f) or not _is_shrimp_predator(f):
					continue
				var d: float = (f as Node3D).position.distance_to(gd["_pos"])
				var p: float = clampf(1.0 - d / PRED_RADIUS, 0.0, 1.0)
				if p > presence:
					presence = p
					nearest_name = _fish_name(f)
	var hab: float = float(gd.get("habituation", 0.0))
	if presence > 0.2:
		hab = minf(0.8, hab + 0.03)
	else:
		hab = maxf(0.0, hab - 0.01)
	gd["habituation"] = hab
	var alarm: float = maxf(0.0, float(gd.get("alarm", 0.0)) - ALARM_DECAY_PER_S * el)
	alarm = maxf(alarm, presence * 0.35 * (1.0 - hab))
	gd["alarm"] = alarm
	if presence > 0.2 and nearest_name != "":
		gd["near_predator"] = nearest_name
	else:
		gd.erase("near_predator")
	_detect_food_rain(sim, gd, el, "shrimp")
	gd["swarm_ttl"] = maxf(0.0, float(gd.get("swarm_ttl", 0.0)) - el)
	# Moult nights: at dusk the colony rolls whether tonight is a moult night.
	var dl: float = SimGate.daylight(sim, 0.6)
	var night: bool = dl < 0.28
	if night and not bool(gd.get("_was_night", false)):
		var p_moult: float = 0.25 + clampf(float(gd["valence"]), 0.0, 0.5) * 0.5
		gd["moult_night"] = randf() < p_moult
		gd["moults_tonight"] = 0
	elif not night and bool(gd.get("_was_night", false)):
		gd["moult_night"] = false
	gd["_was_night"] = night
	var swarm: float = 1.0 if float(gd["swarm_ttl"]) > 0.0 else 0.0
	var tv: float = 0.35 - float(gd["need_food"]) * 0.5 - ws * 0.6 - alarm * 0.7 \
		+ cover * 0.2 + swarm * 0.2
	var ta: float = 0.15 + alarm * 0.7 + ws * 0.4 + swarm * 0.4 + float(gd["need_food"]) * 0.15
	_ease_mood(gd, tv, ta, el)


static func _update_snails(sim: Object, gd: Dictionary, el: float, ws: float) -> void:
	var list: Variant = sim.get("_live_snails")
	if not (list is Array) or (list as Array).is_empty():
		var root: Variant = sim.get("snails_root")
		if root is Node:
			list = (root as Node).get_children()
	var n: int = 0
	var babies: int = 0
	var sum_h: float = 0.0
	var c: Vector3 = Vector3.ZERO
	if list is Array:
		for sn in list:
			if not is_instance_valid(sn) or not (sn as Node).is_in_group("snails"):
				continue
			n += 1
			var h: Variant = sn.get("hunger")
			sum_h += float(h) if h != null else 0.3
			c += (sn as Node3D).position
			if sn.get("is_baby") == true:
				babies += 1
	gd["population"] = n
	gd["juveniles"] = babies
	gd["_pos"] = c / float(n) if n > 0 else Vector3.INF
	gd["water_stress"] = ws
	var last_juv: int = int(gd.get("_last_juv", -1))
	if last_juv >= 0 and babies > last_juv:
		note(sim, "snails", "birth", "", float(babies - last_juv))
	var last_n: int = int(gd.get("_last_n", -1))
	if last_n >= 0 and n < last_n and int(gd.get("_kills_since", 0)) == 0:
		note(sim, "snails", "loss", "", float(last_n - n))
	gd["_last_juv"] = babies
	gd["_last_n"] = n
	gd["_kills_since"] = 0
	var avg_h: float = sum_h / float(n) if n > 0 else 0.0
	var algae_n: int = _arr_size(sim, "algae")
	var avail: float = clampf(float(algae_n) / maxf(1.0, float(n) * 0.6), 0.0, 1.0)
	gd["need_food"] = clampf(avg_h * 0.6 + (1.0 - avail) * 0.4, 0.0, 1.0)
	gd["need_cover"] = 0.1
	# Feast: a melting / dying plant is a snail banquet. O(plants) every 2.5 s.
	var best: Node3D = null
	var best_bm: int = 4
	var pl: Variant = sim.get("plants")
	if pl is Array:
		for p in pl:
			if not is_instance_valid(p):
				continue
			var melting: bool = p.get("_melt_active") == true or p.get("is_dying") == true
			var hv: Variant = p.get("health")
			if not melting and not (hv != null and float(hv) < 0.3):
				continue
			var bm: int = int(p.biomass()) if p.has_method("biomass") else 10
			if bm > best_bm:
				best_bm = bm
				best = p
	if best != null:
		gd["_feast_pos"] = best.position
		gd["feast"] = clampf(float(best_bm) / 40.0, 0.3, 1.0)
		var pid: int = best.get_instance_id()
		if pid != int(gd.get("feast_id", 0)):
			gd["feast_id"] = pid
			var nm: String = _plant_name(best)
			gd["feast_name"] = nm
			note(sim, "snails", "melt", nm)
			note(sim, "substrate", "melt", nm, 0.5)
	else:
		gd["_feast_pos"] = Vector3.INF
		gd["feast"] = maxf(0.0, float(gd.get("feast", 0.0)) - 0.02 * el)
		gd["feast_id"] = 0
	var alarm: float = maxf(0.0, float(gd.get("alarm", 0.0)) - ALARM_DECAY_PER_S * 0.6 * el)
	gd["alarm"] = alarm
	_detect_food_rain(sim, gd, el, "snails")
	gd["swarm_ttl"] = maxf(0.0, float(gd.get("swarm_ttl", 0.0)) - el)
	var tv: float = 0.3 - float(gd["need_food"]) * 0.4 - ws * 0.7 - alarm * 0.5 \
		+ float(gd["feast"]) * 0.3
	var ta: float = 0.08 + ws * 0.5 + alarm * 0.5 + float(gd["feast"]) * 0.2
	_ease_mood(gd, tv, ta, el)


static func _update_substrate(sim: Object, gd: Dictionary, el: float, ws: float) -> void:
	var n: int = 0
	var trumpets: int = 0
	var tree: SceneTree = null
	if sim is Node and (sim as Node).is_inside_tree():
		tree = (sim as Node).get_tree()
	if tree != null:
		trumpets = tree.get_nodes_in_group("trumpet_snails").size()
	var worms: int = 0
	var micro: int = 0
	var w: Variant = (sim as Node).get_parent() if sim is Node else null
	if w is Object and w != null:
		var wr: Variant = (w as Object).get("wriggle_root")
		if wr is Node:
			worms = (wr as Node).get_child_count()
		if (w as Object).has_method("live_microfauna_count"):
			micro = int((w as Object).call("live_microfauna_count"))
	# Stub / test override.
	var ov: Variant = sim.get("substrate_census")
	if ov is Dictionary:
		trumpets = int((ov as Dictionary).get("trumpets", trumpets))
		worms = int((ov as Dictionary).get("worms", worms))
		micro = int((ov as Dictionary).get("micro", micro))
	n = trumpets + worms + micro
	gd["population"] = n
	gd["trumpets"] = trumpets
	gd["worms"] = worms
	gd["micro"] = micro
	gd["water_stress"] = ws
	var waste_n: int = _arr_size(sim, "waste")
	var fall: float = clampf(float(waste_n) / 30.0, 0.0, 1.0)
	gd["need_food"] = 1.0 - fall
	gd["need_cover"] = 0.0
	gd["alarm"] = maxf(0.0, float(gd.get("alarm", 0.0)) - ALARM_DECAY_PER_S * el)
	gd["feast"] = maxf(0.0, float(gd.get("feast", 0.0)) - 0.01 * el)
	var tv: float = 0.25 + fall * 0.3 - ws * 0.5 + float(gd["feast"]) * 0.2
	var ta: float = 0.05 + ws * 0.4 + fall * 0.1
	_ease_mood(gd, tv, ta, el)


static func _ease_mood(gd: Dictionary, tv: float, ta: float, el: float) -> void:
	var kv: float = 1.0 - exp(-el / 20.0)
	var ka: float = 1.0 - exp(-el / 10.0)
	gd["valence"] = clampf(lerpf(float(gd.get("valence", 0.0)), clampf(tv, -1.0, 1.0), kv), -1.0, 1.0)
	gd["arousal"] = clampf(lerpf(float(gd.get("arousal", 0.2)), clampf(ta, 0.0, 1.0), ka), 0.0, 1.0)


# A fresh keeper feed drop (sim._feed_memory newest entry younger than the time
# since our last update) = food rain. Shrimp swarm to it.
static func _detect_food_rain(sim: Object, _gd: Dictionary, el: float, g: String) -> void:
	var fm: Variant = sim.get("_feed_memory")
	if not (fm is Array) or (fm as Array).is_empty():
		return
	var last: Variant = (fm as Array)[-1]
	if not (last is Dictionary):
		return
	var age: float = float((last as Dictionary).get("t", 999.0))
	if age > el + 0.05:
		return
	var pos: Vector3 = Vector3.INF
	var pv: Variant = (last as Dictionary).get("pos", null)
	if pv is Vector3:
		pos = pv
	note(sim, g, "food_rain", "", 1.0, pos)


# --- events ----------------------------------------------------------------

# Record a colony event. kind: moult, birth, loss, predation, food_rain, melt.
# Coalesces with the previous same-kind entry inside COALESCE_S so a moult
# night is one memory ("7 moults"), not seven.
static func note(sim: Object, g: String, kind: String, detail: String = "",
		weight: float = 1.0, pos: Vector3 = Vector3.INF) -> void:
	if sim == null:
		return
	var gd: Dictionary = group(sim, g)
	if gd.is_empty():
		return
	var now: float = clock(sim)
	var mem: Array = gd.get("memory", [])
	var cnt: int = maxi(1, int(round(weight)))
	var merged: bool = false
	if not mem.is_empty():
		var top: Dictionary = mem[-1]
		if str(top.get("k", "")) == kind and str(top.get("d", "")) == detail \
				and now - float(top.get("c", -999.0)) < COALESCE_S:
			top["n"] = int(top.get("n", 1)) + cnt
			top["c"] = now
			merged = true
	if not merged:
		mem.append({"k": kind, "d": detail.substr(0, DETAIL_MAX_LEN), "n": cnt, "c": now,
				"day": int(_sim_day(sim))})
		while mem.size() > MEMORY_MAX:
			mem.pop_front()
	gd["memory"] = mem
	var v: float = float(gd.get("valence", 0.0))
	var a: float = float(gd.get("arousal", 0.2))
	match kind:
		"predation":
			v -= 0.4
			a += 0.5
			gd["alarm"] = 1.0
			gd["habituation"] = 0.0
			gd["_kills_since"] = int(gd.get("_kills_since", 0)) + 1
			if detail != "":
				gd["last_predator"] = detail.substr(0, DETAIL_MAX_LEN)
		"food_rain":
			v += 0.25
			a += 0.3
			gd["swarm_ttl"] = SWARM_TTL_S
			gd["_swarm_pos"] = pos
		"birth":
			v += 0.12 * minf(3.0, weight)
			gd["births_total"] = int(gd.get("births_total", 0)) + cnt
		"loss":
			v -= 0.08
			gd["losses_total"] = int(gd.get("losses_total", 0)) + cnt
		"moult":
			v += 0.01
			gd["moults_total"] = int(gd.get("moults_total", 0)) + cnt
			gd["moults_tonight"] = int(gd.get("moults_tonight", 0)) + cnt
		"melt":
			v += 0.15 * weight
			a += 0.1 * weight
			gd["feast"] = maxf(float(gd.get("feast", 0.0)), 0.5 * weight)
	gd["valence"] = clampf(v, -1.0, 1.0)
	gd["arousal"] = clampf(a, 0.0, 1.0)
	_refresh_bias(gd, g)


# One-line hook for SimDriver's kill_prey / kill_snail handling.
static func note_predation(sim: Object, predator: Object, prey: Object) -> void:
	if sim == null or prey == null or not is_instance_valid(prey):
		return
	var g: String = ""
	if prey is Shrimp:
		g = "shrimp"
	elif prey is Node and (prey as Node).is_in_group("snails"):
		g = "snails"
	else:
		return
	var who: String = "something"
	if predator != null and is_instance_valid(predator):
		if predator is Shrimp:
			who = "one of us" if g == "shrimp" else "the shrimp"
		else:
			who = _fish_name(predator)
	note(sim, g, "predation", who)


# --- behaviour bias (cached per group update; cheap per-creature reads) ----

static func _refresh_bias(gd: Dictionary, g: String) -> void:
	var b: Dictionary = {}
	var ws: float = float(gd.get("water_stress", 0.0))
	var alarm: float = float(gd.get("alarm", 0.0))
	match g:
		"shrimp":
			b["alarm"] = alarm
			b["moult"] = 1.5 if bool(gd.get("moult_night", false)) else 0.0
			var sp: Variant = Vector3.INF
			if float(gd.get("swarm_ttl", 0.0)) > 0.0:
				sp = gd.get("_swarm_pos", Vector3.INF)
			b["swarm_pos"] = sp
		"snails":
			b["surface"] = clampf((ws - 0.15) / 0.6, 0.0, 1.0) * (1.0 - alarm * 0.5)
			b["withdraw"] = maxf(alarm * 0.8, clampf((ws - 0.75) * 2.5, 0.0, 1.0))
			b["feast_pos"] = gd.get("_feast_pos", Vector3.INF)
		"substrate":
			b["emerge"] = ws > 0.45
	gd["bias"] = b


static func _bias(sim: Object, g: String) -> Dictionary:
	if sim == null or not sim.has_meta(META_KEY):
		return {}
	var cm: Variant = sim.get_meta(META_KEY)
	if not (cm is Dictionary):
		return {}
	var gd: Variant = ((cm as Dictionary).get("groups", {}) as Dictionary).get(g, null)
	if not (gd is Dictionary):
		return {}
	return (gd as Dictionary).get("bias", {})


static func bias(sim: Object, g: String) -> Dictionary:
	return _bias(sim, g).duplicate()


# 0..1 colony alarm — shrimp hide collectively even out of a predator's reach.
static func shrimp_alarm(sim: Object) -> float:
	return float(_bias(sim, "shrimp").get("alarm", 0.0))


# Extra moult-timer drain multiplier (0 = normal; moult nights synchronise).
static func shrimp_moult_mult(sim: Object) -> float:
	return 1.0 + float(_bias(sim, "shrimp").get("moult", 0.0))


# Unit-ish steering pull toward a fresh food drop (Vector3.ZERO when none).
static func shrimp_swarm_pull(sim: Object, pos: Vector3, hunger: float) -> Vector3:
	var sp: Variant = _bias(sim, "shrimp").get("swarm_pos", Vector3.INF)
	if not (sp is Vector3) or (sp as Vector3) == Vector3.INF or hunger < 0.12:
		return Vector3.ZERO
	var to: Vector3 = (sp as Vector3) - pos
	to.y = 0.0
	var d: float = to.length()
	if d < 0.35 or d > 9.0:
		return Vector3.ZERO
	return to / d * clampf(0.5 + hunger, 0.5, 1.2)


# 0..1 pull toward the waterline — bad water (low O2 / NH3) sends snails up.
static func snail_surface_bias(sim: Object) -> float:
	return float(_bias(sim, "snails").get("surface", 0.0))


# 0..1 chance weight of a snail retreating into its shell.
static func snail_withdraw(sim: Object) -> float:
	return float(_bias(sim, "snails").get("withdraw", 0.0))


# World-space offset toward a melting-plant feast within reach, else ZERO.
static func snail_feast_pull(sim: Object, pos: Vector3, reach: float = 7.0) -> Vector3:
	var fp: Variant = _bias(sim, "snails").get("feast_pos", Vector3.INF)
	if not (fp is Vector3) or (fp as Vector3) == Vector3.INF:
		return Vector3.ZERO
	var to: Vector3 = (fp as Vector3) - pos
	if to.length_squared() > reach * reach or to.length_squared() < 0.09:
		return Vector3.ZERO
	return to


# Trumpet snails surface by day when the bed/water goes bad (a real tell).
static func substrate_emerge(sim: Object) -> bool:
	return bool(_bias(sim, "substrate").get("emerge", false))


# --- voice -----------------------------------------------------------------

static func _mem_recent(gd: Dictionary, now: float, window: float = 900.0) -> Dictionary:
	var mem: Array = gd.get("memory", [])
	for i in range(mem.size() - 1, -1, -1):
		var e: Dictionary = mem[i]
		if now - float(e.get("c", -1e9)) <= window:
			return e
	return {}


static func _memory_tails(g: String, e: Dictionary) -> Array:
	if e.is_empty():
		return []
	var k: String = str(e.get("k", ""))
	var d: String = str(e.get("d", ""))
	var n: int = int(e.get("n", 1))
	match g:
		"shrimp":
			match k:
				"predation":
					return ["%s took one of us. we remember the shape of its mouth" % d,
							"we felt %s strike. one of us is gone" % d,
							"%s. the shadow with fins. we keep low" % d]
				"food_rain":
					return ["food fell from the sky and we ran to it, all of us",
							"sweet rain from above. we swarmed it"]
				"moult":
					return ["%d old skins lie in the moss; we are soft and new" % n,
							"moult night. %d of us slipped out of our shells" % n]
				"birth":
					return ["%d tiny ones let go of the mothers' legs" % n,
							"new small we: %d of them, clear as water" % n]
				"loss":
					return ["one of us went still and we ate the silence",
							"we are fewer by %d" % n]
		"snails":
			match k:
				"predation":
					return ["%s… cracked one of us… we heard it" % d,
							"one shell… emptied… by %s" % d]
				"melt":
					return ["the %s… is softening… we go to it" % (d if d != "" else "green one"),
							"a feast… the %s melts… slowly… we gather" % (d if d != "" else "plant")]
				"food_rain":
					return ["something… sank… it smells of food",
							"food… on the glass floor… we are coming… slowly"]
				"birth":
					return ["small shells… %d… new on the glass" % n,
							"%d… of us… hatched" % n]
				"loss":
					return ["one shell… lies empty now",
							"we are… %d fewer" % n]
		"substrate":
			match k:
				"melt":
					return ["the green above is falling to us. it will be soil",
							"what melts above, we turn below"]
				"food_rain":
					return ["what the fish miss drifts down. we take it",
							"crumbs reach the dark between the grains"]
				_:
					return ["something shifted above; the grains felt it"]
	return []


static func _topic_lines(g: String, topic: String, gd: Dictionary, sim: Object) -> Array:
	var n: int = int(gd.get("population", 0))
	var ws: float = float(gd.get("water_stress", 0.0))
	var alarm: float = float(gd.get("alarm", 0.0))
	var food: float = float(gd.get("need_food", 0.3))
	var val: float = float(gd.get("valence", 0.0))
	var dark: bool = SimGate.daylight(sim, 0.6) < 0.28
	var near_pred: String = str(gd.get("near_predator", ""))
	var last_pred: String = str(gd.get("last_predator", ""))
	var lines: Array = []
	match g:
		"shrimp":
			var we: String = "many small we" if n > 6 else "few small we"
			if alarm > 0.35 or topic == "calm" and alarm > 0.15:
				var who: String = near_pred if near_pred != "" else (last_pred if last_pred != "" else "the finned shadow")
				lines = ["%s… hiding. %s is near. legs tucked, antennae still" % [we, who],
						"shh. %s. we are under the leaves, all of us, waiting" % who,
						"we taste fear in the water. %s. we keep to the moss" % who]
			elif topic == "food" or float(gd.get("swarm_ttl", 0.0)) > 0.0:
				if float(gd.get("swarm_ttl", 0.0)) > 0.0:
					lines = ["food! food fell. %s run, many legs, one hunger" % we,
							"the sky rained sweet. we are all on it at once",
							"sweet. sweet. %d of us picking at the fall" % n]
				elif food > 0.55:
					lines = ["hungry, %s. the film on the leaves is thin" % we,
							"we pick and pick and the stones give little",
							"%d mouths, little film. we are light in the belly" % n]
				else:
					lines = ["sweet film on the leaf. we pick, we pick",
							"plenty. the moss is furred with good things",
							"full enough, %s. the leaves taste of green" % we]
			elif topic == "water" or topic == "air":
				if ws > 0.4:
					lines = ["the water stings our gills. we climb the stems to breathe",
							"sharp water. %s cling high and wait" % we,
							"thin water. our legs fan fast and it is not enough"]
				else:
					lines = ["soft water. our gills are easy",
							"the water is kind to shells like ours",
							"good water, %s. we would moult in it" % we]
			elif topic == "light" or dark:
				if bool(gd.get("moult_night", false)):
					lines = ["dark, and a moult night. we split our old skins together",
							"night. %d of us already soft and new" % int(gd.get("moults_tonight", 0)),
							"moult night. we feel it in every shell at once"]
				else:
					lines = ["dark. we walk the stones by feel",
							"night. the fish sleep and the floor is ours",
							"in the dark we are braver, %s" % we]
			elif topic == "who":
				lines = ["%d of us, %d still small. one colony, many legs" % [n, int(gd.get("juveniles", 0))],
						"we are %d. we do not count one by one" % n,
						"%s: %d bodies, one hunger" % [we, n]]
			else:
				if val > 0.2:
					lines = ["%s, picking, picking. the leaf is sweet" % we,
							"we are well. shells hard, bellies green",
							"many small we. we tick along the moss, content"]
				elif val < -0.2:
					lines = ["we are uneasy. antennae up, all of us",
							"something is wrong in the water or the shadows. we keep low",
							"%s, pressed together, not happy" % we]
				else:
					lines = ["many small we, going about the floor",
							"we pick at the world. the world is mostly film",
							"we are here, under the leaves, %d of us" % n]
		"snails":
			var surf: float = clampf((ws - 0.15) / 0.6, 0.0, 1.0)
			if topic == "water" or topic == "air" or surf > 0.45:
				if surf > 0.3:
					lines = ["the water… is thin below… we are climbing… to the top",
							"we… go up… the glass… to breathe where the air touches",
							"bad water… we gather… at the line… where it is kinder"]
				else:
					lines = ["the water… is soft… we stay low… and graze",
							"good water… no need… to climb",
							"clean… glass… slow… and easy"]
			elif alarm > 0.3 or topic == "calm":
				if alarm > 0.3:
					var who2: String = last_pred if last_pred != "" else "something"
					lines = ["in our shells… doors shut… %s is out there" % who2,
							"we… withdraw… and wait… for %s… to pass" % who2]
				else:
					lines = ["calm… we are always… calm",
							"we heard you… slowly… we were not worried"]
			elif topic == "food" or float(gd.get("feast", 0.0)) > 0.3:
				if float(gd.get("feast", 0.0)) > 0.3:
					var fname: String = str(gd.get("feast_name", "plant"))
					lines = ["the %s… melts… we are gathering… on it" % fname,
							"a feast… soft leaves… %d of us… converge" % n,
							"slow… slow… to the %s… it is falling apart… sweetly" % fname]
				elif food > 0.55:
					lines = ["the glass… is bare… we rasp… and find little",
							"hungry… slowly… hungry"]
				else:
					lines = ["green film… on the glass… we rasp… it is good",
							"we eat… the dust of light… on every surface"]
			elif topic == "who":
				lines = ["we… are %d… shells on every wall" % n,
						"%d… slow ones… one long patience" % n]
			else:
				if val > 0.15:
					lines = ["slow… good… the glass is green",
							"we… wander… content… leaving trails",
							"all is… slow… and well"]
				else:
					lines = ["we are… uneasy… slow to say why",
							"something… in the water… we feel it… in the foot",
							"not… well… we keep… our doors half shut"]
		"substrate":
			if ws > 0.45 or topic == "water" or topic == "air":
				if ws > 0.45:
					lines = ["the dark between the grains goes sour. we rise, even by day",
							"down here the breath is gone. we come up to the light",
							"the bed chokes. the trumpets leave the gravel"]
				else:
					lines = ["deep down, the water moves. the roots drink",
							"we keep the bed breathing, grain by grain"]
			elif topic == "food":
				if food < 0.5:
					lines = ["much falls to us. we are busy in the dark",
							"what dies above, we eat below. there is plenty"]
				else:
					lines = ["little falls. we are patient; we were here first",
							"lean times in the grains. we wait, we always wait"]
			elif topic == "who":
				lines = ["we are uncounted: %d that you can see, more that you cannot" % n,
						"worms, trumpets, the small drifting ones. we are the floor",
						"we are the ones beneath. %d, and the bacteria beyond number" % n]
			else:
				lines = ["we are old. older than the first leaf. we turn what falls",
						"deep and slow: the grains, the roots, us",
						"what the tank forgets, we remember as soil",
						"%s the floor turns in its sleep" % ("in the dark," if dark else "under the light,")]
	return lines


# Tiny, alien, plural voice grounded in the group's real state. `topic` is a
# keeper topic ("food", "water", "air", "calm", "light", "who", "greeting",
# "wellbeing", "") — empty means "say whatever is most pressing". Never repeats
# one of the group's last RECENT_LINES_MAX lines.
static func voice_line(g: String, sim: Object, topic: String = "") -> String:
	if sim == null or not (g in GROUPS):
		return ""
	var gd: Dictionary = group(sim, g)
	if int(gd.get("population", 0)) <= 0:
		return ""
	var t: String = topic
	if t == "greeting" or t == "love" or t == "wellbeing":
		t = ""
	var openers: Array = _topic_lines(g, t, gd, sim)
	if topic == "greeting":
		var hi: Array = {"shrimp": ["we feel you at the glass, big warm shape", "hello, sky-hand"],
				"snails": ["we… saw you… hello… slowly", "a shadow… that is you… hello"],
				"substrate": ["far above, a voice. we hear it in the grains",
						"the floor hears you, keeper"]}.get(g, [])
		var mixed: Array = []
		for h in hi:
			for o in openers:
				mixed.append("%s. %s" % [h, o])
		openers = mixed
	var tails: Array = _memory_tails(g, _mem_recent(gd, clock(sim)))
	var candidates: Array = []
	for o in openers:
		candidates.append(str(o))
		for tl in tails:
			var s: String = "%s… %s" % [str(o), str(tl)]
			if not candidates.has(s):
				candidates.append(s)
	for tl in tails:
		candidates.append(str(tl))
	if candidates.is_empty():
		return ""
	var recent: Array = gd.get("recent_lines", [])
	var fresh: Array = candidates.filter(func(c): return not recent.has(c))
	var chosen: String = ""
	if fresh.is_empty():
		var last: String = str(recent[-1]) if not recent.is_empty() else ""
		var alt: Array = candidates.filter(func(c): return c != last)
		chosen = str(alt[randi() % alt.size()]) if not alt.is_empty() else str(candidates[0])
	else:
		# Prefer the memory-grounded candidates a little when something happened.
		chosen = str(fresh[randi() % fresh.size()])
	recent.append(chosen)
	while recent.size() > RECENT_LINES_MAX:
		recent.pop_front()
	gd["recent_lines"] = recent
	return chosen


static func _tokens(text: String) -> PackedStringArray:
	var clean: String = text.to_lower()
	for ch in [".", ",", "!", "?", ";", ":", "\"", "(", ")", "…", "—", "-", "'"]:
		clean = clean.replace(ch, " ")
	return clean.split(" ", false)


static func topics_for(text: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for tok in _tokens(text):
		for topic in TOPIC_WORDS:
			if tok in (TOPIC_WORDS[topic] as Array) and not out.has(topic):
				out.append(topic)
	return out


# How much a keeper line concerns this group. ~0 = not at all; >=0.45 is a
# reasonable "include this colony in the chorus" threshold; >=1 = addressed.
# `topics` may come from TankMind.parse_keeper_words(); otherwise derived.
static func relevance(g: String, sim: Object, text: String,
		topics: PackedStringArray = PackedStringArray()) -> float:
	if sim == null or not (g in GROUPS):
		return 0.0
	var gd: Dictionary = group(sim, g)
	if int(gd.get("population", 0)) <= 0:
		return 0.0
	var toks: PackedStringArray = _tokens(text)
	var tps: PackedStringArray = topics if not topics.is_empty() else topics_for(text)
	var s: float = 0.0
	for tok in toks:
		if tok in (NAME_WORDS[g] as Array):
			s += 1.0
			break
	var ws: float = float(gd.get("water_stress", 0.0))
	var b: Dictionary = gd.get("bias", {})
	match g:
		"shrimp":
			if tps.has("food"):
				s += 0.2 + float(gd.get("need_food", 0.0)) * 0.3 \
					+ (0.3 if float(gd.get("swarm_ttl", 0.0)) > 0.0 else 0.0)
			if tps.has("water") or tps.has("air"):
				s += ws * 0.4
			if tps.has("calm"):
				s += float(gd.get("alarm", 0.0)) * 0.6
			if tps.has("light") and bool(gd.get("moult_night", false)):
				s += 0.3
		"snails":
			if tps.has("water") or tps.has("air"):
				s += 0.2 + float(b.get("surface", 0.0)) * 0.6
			if tps.has("food"):
				s += 0.1 + float(gd.get("feast", 0.0)) * 0.4
			if tps.has("calm"):
				s += float(b.get("withdraw", 0.0)) * 0.4
		"substrate":
			if tps.has("water") or tps.has("air"):
				s += 0.1 + ws * 0.4
			if tps.has("food"):
				s += 0.05
	if tps.has("who"):
		s += 0.3
	# Arousal makes a group more likely to pipe up.
	s += float(gd.get("arousal", 0.0)) * 0.1
	return s


# Convenience for the conversation code: up to max_n colonies that should
# answer, each with a ready line. [{group, speaker, score, line}]
static func chorus(sim: Object, text: String, topics: PackedStringArray = PackedStringArray(),
		max_n: int = 1, min_score: float = 0.45) -> Array:
	var tps: PackedStringArray = topics if not topics.is_empty() else topics_for(text)
	var scored: Array = []
	for g in GROUPS:
		var sc: float = relevance(g, sim, text, tps)
		if sc >= min_score:
			scored.append({"group": g, "score": sc})
	scored.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	var out: Array = []
	for e in scored:
		if out.size() >= max_n:
			break
		var g2: String = str(e["group"])
		var topic: String = _best_topic_for(g2, tps)
		var line: String = voice_line(g2, sim, topic)
		if line == "":
			continue
		out.append({"group": g2, "speaker": str(SPEAKER.get(g2, g2)),
				"score": float(e["score"]), "line": line})
	return out


static func _best_topic_for(g: String, tps: PackedStringArray) -> String:
	var pref: Array = ["water", "air", "food", "calm", "light", "who", "greeting"]
	if g == "shrimp":
		pref = ["calm", "food", "light", "water", "air", "who", "greeting"]
	for p in pref:
		if tps.has(p):
			return p
	return ""


# Compact read-only view for HUD / debug / other minds.
static func snapshot(sim: Object) -> Dictionary:
	var out: Dictionary = {}
	for g in GROUPS:
		var gd: Dictionary = group(sim, g)
		out[g] = {
			"population": int(gd.get("population", 0)),
			"valence": float(gd.get("valence", 0.0)),
			"arousal": float(gd.get("arousal", 0.0)),
			"need_food": float(gd.get("need_food", 0.0)),
			"water_stress": float(gd.get("water_stress", 0.0)),
			"alarm": float(gd.get("alarm", 0.0)),
			"bias": bias(sim, g),
		}
	return out


# --- persistence -----------------------------------------------------------

const _PERSIST_FLOATS: Array[String] = ["valence", "arousal", "need_food", "need_cover",
		"water_stress", "alarm", "habituation", "feast"]
const _PERSIST_INTS: Array[String] = ["moults_total", "births_total", "losses_total",
		"moults_tonight"]


static func to_dict(sim: Object) -> Dictionary:
	var out: Dictionary = {"schema_version": SCHEMA_VERSION, "groups": {}}
	if sim == null:
		return out
	for g in GROUPS:
		var gd: Dictionary = group(sim, g)
		var e: Dictionary = {}
		for k in _PERSIST_FLOATS:
			e[k] = snappedf(float(gd.get(k, 0.0)), 0.001)
		for k in _PERSIST_INTS:
			e[k] = int(gd.get(k, 0))
		e["moult_night"] = bool(gd.get("moult_night", false))
		e["last_predator"] = str(gd.get("last_predator", "")).substr(0, DETAIL_MAX_LEN)
		e["feast_name"] = str(gd.get("feast_name", "")).substr(0, DETAIL_MAX_LEN)
		var mem: Array = []
		for m in gd.get("memory", []):
			if m is Dictionary:
				mem.append({"k": str(m.get("k", "")), "d": str(m.get("d", "")).substr(0, DETAIL_MAX_LEN),
						"n": int(m.get("n", 1)), "day": int(m.get("day", 0))})
		e["memory"] = mem.slice(maxi(0, mem.size() - MEMORY_MAX))
		out["groups"][g] = e
	return out


# Accepts anything: null/garbage → defaults; schema 0 (legacy flat
# {"shrimp": {...}, ...} with no version) → migrated; newer schema → the known
# fields are read and the rest ignored.
static func from_dict(sim: Object, d: Variant) -> void:
	if sim == null:
		return
	var fresh: Dictionary = {"schema_version": SCHEMA_VERSION, "clock": 0.0, "groups": {}}
	for g in GROUPS:
		fresh["groups"][g] = default_group(g)
	sim.set_meta(META_KEY, fresh)
	if not (d is Dictionary):
		for g in GROUPS:
			_refresh_bias(fresh["groups"][g], g)
		return
	var src: Dictionary = migrate(d as Dictionary)
	var groups_in: Variant = src.get("groups", {})
	if not (groups_in is Dictionary):
		groups_in = {}
	for g in GROUPS:
		var gd: Dictionary = fresh["groups"][g]
		var e: Variant = (groups_in as Dictionary).get(g, null)
		if e is Dictionary:
			var ed: Dictionary = e
			for k in _PERSIST_FLOATS:
				if ed.has(k):
					var lo: float = -1.0 if k == "valence" else 0.0
					gd[k] = clampf(float(ed[k]), lo, 1.0)
			for k in _PERSIST_INTS:
				if ed.has(k):
					gd[k] = maxi(0, int(ed[k]))
			gd["moult_night"] = bool(ed.get("moult_night", false))
			gd["last_predator"] = str(ed.get("last_predator", "")).substr(0, DETAIL_MAX_LEN)
			gd["feast_name"] = str(ed.get("feast_name", "")).substr(0, DETAIL_MAX_LEN)
			var mem: Array = []
			var mem_in: Variant = ed.get("memory", [])
			if mem_in is Array:
				for m in mem_in:
					if m is Dictionary:
						# Restored memories are "old": clock far in the past so
						# they don't dominate voice lines right after a load.
						mem.append({"k": str(m.get("k", "")),
								"d": str(m.get("d", "")).substr(0, DETAIL_MAX_LEN),
								"n": maxi(1, int(m.get("n", 1))), "c": -1e6,
								"day": int(m.get("day", 0))})
			gd["memory"] = mem.slice(maxi(0, mem.size() - MEMORY_MAX))
		_refresh_bias(gd, g)


static func migrate(d: Dictionary) -> Dictionary:
	var cur: Dictionary = d
	if int(d.get("schema_version", 0)) <= 0:
		# v0: flat {group: {...}} without a "groups" wrapper.
		var groups: Dictionary = {}
		for g in GROUPS:
			if cur.get(g) is Dictionary:
				groups[g] = cur[g]
		if cur.get("groups") is Dictionary:
			groups = cur["groups"]
		cur = {"schema_version": 1, "groups": groups}
	return cur


# --- helpers ---------------------------------------------------------------

static func _f(obj: Object, key: String, fallback: float) -> float:
	if obj == null:
		return fallback
	var v: Variant = obj.get(key)
	if v == null:
		return fallback
	return float(v)


static func _arr_size(obj: Object, key: String) -> int:
	var v: Variant = obj.get(key) if obj != null else null
	return (v as Array).size() if v is Array else 0


static func _sim_day(sim: Object) -> float:
	if sim != null and sim.has_method("sim_day"):
		return float(sim.call("sim_day"))
	return 0.0


static func _is_shrimp_predator(f: Object) -> bool:
	if f.get("_asleep") == true:
		return false
	if f.get("shrimp_predator") == true:
		return true
	var sp: Variant = f.get("species")
	return sp != null and str(sp) == "betta"


static func _fish_name(f: Object) -> String:
	var nm: Variant = f.get("fish_name")
	if nm != null and str(nm).strip_edges() != "":
		return str(nm).strip_edges().substr(0, DETAIL_MAX_LEN)
	var sp: Variant = f.get("species")
	if sp != null and str(sp) != "":
		return ("a %s" % str(sp).replace("_", " ")).substr(0, DETAIL_MAX_LEN)
	return "a fish"


static func _plant_name(p: Object) -> String:
	for key in ["common_name", "species_name", "species", "display_name"]:
		var v: Variant = p.get(key)
		if v != null and str(v).strip_edges() != "":
			return str(v).replace("_", " ").to_lower().substr(0, DETAIL_MAX_LEN)
	return "plant"
