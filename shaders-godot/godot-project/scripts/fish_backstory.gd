class_name FishBackstory
extends RefCounted

# Fish backstories: every fish arrives with a history.
#
# Offline, template-generated, deterministic. The seed is derived from the
# fish's stable id + species + name through SimRng.stream_seed, so the same
# fish always tells the same story; personality and genome traits WEIGHT the
# choices (a shy fish is more likely to love the driftwood and fear the lamp;
# an herbivore is more likely to love a plant).
#
# A story holds:
#   origin      bred / adopted / founder (+ origin_text)
#   parents     REAL lineage for fry bred in this tank: names (and ids when
#               the parent is alive at generation time), clutch size, how it
#               was born (live, guarded clutch, scattered eggs), sim day
#   formative   one formative memory (tied to origin or to its fear)
#   quirk       a small habit
#   like / fear subjects that exist IN THIS TANK: a specific plant species,
#               driftwood, stones, cave, lily pads, the lamp, the filter
#               current, the surface, the substrate, a corner, or a tankmate.
#               FishEnvironment turns these into behavior.
#
# Persistence: Fish.backstory (Dictionary) rides in to_save_dict under
# "backstory". Old saves without it get one generated on load (ensure()).
# The template story is always present; an LLM bio (AIDirector
# fish_bio_ready -> character_bio) is a separate, optional enrichment.
#
# Getter API for speech / UI (all safe on any fish, never null):
#   FishBackstory.summary(f)        -> String, 1-3 short sentences
#   FishBackstory.tagline(f)        -> String, a few words for bio lines
#   FishBackstory.bio_lines(f)      -> Array[String] for panels
#   FishBackstory.likes(f) / fears(f) -> Dictionary {kind,label,key[,id]}
#   FishBackstory.like_phrase(f) / fear_phrase(f) -> "the Java Fern"
#   FishBackstory.quirk(f), formative_memory(f), origin_text(f), parents(f)
#   FishBackstory.speech_line(f, topic) -> first-person line; topic in
#       "origin", "parents", "memory", "like", "fear", "quirk", "home"

const SimRngScript = preload("res://scripts/sim_rng.gd")
const EpisodicMemoryScript = preload("res://scripts/episodic_memory.gd")

const SCHEMA_V: int = 1
const SEED_MASTER: int = 0x0B105701

const FOUNDER_ORIGINS: Array[String] = [
	"came from a friend's overgrown tank",
	"was rehomed from a hobbyist's fish room",
	"was rescued from a crowded shop tank",
	"came from a classroom tank that closed for the summer",
	"was a hand-me-down when a neighbour's tank was broken down",
	"descends from wild-caught stock from a slow, leafy stream",
	"grew up in a breeder's bare grow-out tub",
]
const ADOPTED_ORIGINS: Array[String] = [
	"arrived as a stranger and was adopted in",
	"drifted in from another keeper's tank and stayed",
	"turned up with a bag of plant cuttings and was taken in",
	"was an unexpected arrival the keeper chose to keep",
]
const ORIGIN_MEMORIES: Dictionary = {
	"founder": [
		"the long, dark ride here in a bag",
		"being the smallest in a crowded tank",
		"the first morning the lamp came on over this water",
		"watching older fish eat first, and learning to be quick",
		"hiding for days before daring to swim in the open",
	],
	"adopted": [
		"the strange water the day it arrived",
		"being the only one of its kind for a long while",
		"the first fish that let it school alongside",
	],
	"bred": [
		"the first light through the water the morning it was born",
		"hiding with its siblings while the adults cruised overhead",
		"the first meal it ever caught",
	],
}
const FEAR_MEMORIES: Dictionary = {
	"lamp": "the lamp snapping on in the dark during its first week",
	"filter": "being pulled against the filter intake when it was small",
	"surface": "a net coming down through the surface",
	"substrate": "being pinned in the %s by a bigger fish",
	"driftwood": "something lunging out from behind the driftwood",
	"stones": "getting wedged between the stones",
	"cave": "a bad scare in the dark of the cave",
	"lily": "a shadow passing over the lily pads",
	"plant": "getting tangled in the %s as a youngster",
	"corner": "being cornered once, with nowhere to go",
	"tankmate": "%s chasing it on its first day",
	"ornament": "the %s falling in with a splash",
}
const QUIRKS: Array[Dictionary] = [
	{"text": "always turns left around obstacles", "trait": "", "w": 1.0},
	{"text": "inspects every bubble that drifts past", "trait": "curiosity", "w": 1.0},
	{"text": "sleeps nose-down, like it is reading the substrate", "trait": "calm", "w": 1.0},
	{"text": "flares at its own reflection in the glass", "trait": "boldness", "w": 1.0},
	{"text": "follows the keeper's finger along the glass", "trait": "sociability", "w": 1.0},
	{"text": "swims one slow lap of the tank at dawn", "trait": "calm", "w": 1.0},
	{"text": "nudges loose grains of substrate around", "trait": "curiosity", "w": 1.0},
	{"text": "is first to the surface whenever food might appear", "trait": "gluttony", "w": 1.0},
	{"text": "freezes for a heartbeat before every turn", "trait": "", "w": 0.8},
	{"text": "likes to hover just behind a bigger fish", "trait": "sociability", "w": 0.8},
]


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

static func story(f: Object) -> Dictionary:
	if f == null:
		return {}
	var b: Variant = f.get("backstory")
	return b as Dictionary if b is Dictionary else {}


static func has_story(f: Object) -> bool:
	var s: Dictionary = story(f)
	return int(s.get("v", 0)) >= 1 and s.has("like")


# Generate once (spawn/adopt/old-save migration); idempotent afterwards.
# Seeds the formative memory into episodic memory the first time.
static func ensure(f: Object) -> Dictionary:
	if f == null:
		return {}
	if has_story(f):
		return story(f)
	var fid: String = String(f.get("id")) if f.get("id") != null else ""
	var fname: String = String(f.get("fish_name")) if f.get("fish_name") != null else ""
	if fid == "" and fname == "":
		return {}
	var sim: Variant = f.get("sim")
	# load() (not preload) — fish_environment.gd preloads this script.
	var env: GDScript = load("res://scripts/fish_environment.gd") as GDScript
	var cands: Array = env.call("candidates", sim) if env != null else []
	var mates: Array = mates_from_sim(sim, f)
	var s: Dictionary = generate(f, cands, mates, _sim_day(sim))
	f.set("backstory", s)
	_seed_memory(f, s)
	return s


static func _seed_memory(f: Object, s: Dictionary) -> void:
	if bool(s.get("seeded", false)) or not is_instance_valid(f) or not (f is Node):
		return
	var mem: String = String(s.get("formative", ""))
	if mem == "":
		return
	s["seeded"] = true
	EpisodicMemoryScript.encode_episode(f, "memory", "I remember " + mem, 0.72)


static func _sim_day(sim: Variant) -> String:
	if sim != null and is_instance_valid(sim) and (sim as Object).has_method("sim_day_label"):
		return String(sim.sim_day_label())
	return ""


# Tankmate facts for generation (plain data so tests need no scene).
static func mates_from_sim(sim: Variant, self_f: Object) -> Array:
	var out: Array = []
	if sim == null or not is_instance_valid(sim):
		return out
	var fish_v: Variant = (sim as Object).get("fish")
	if not (fish_v is Array):
		return out
	for o in fish_v:
		if o == null or not is_instance_valid(o) or o == self_f:
			continue
		if o.get("_dying") == true:
			continue
		out.append({
			"id": String(o.get("id")),
			"name": String(o.get("fish_name")),
			"species": String(o.get("species")),
			"sex": int(o.get("sex")) if o.get("sex") != null else 0,
			"size": float(o.get("adult_voxel_scale")) if o.get("adult_voxel_scale") != null else 1.0,
			"lineage": String(o.get("parent_lineage")) if o.get("parent_lineage") != null else "",
		})
	return out


static func seed_for(f: Object) -> int:
	var fid: String = String(f.get("id")) if f.get("id") != null else ""
	var sp: String = String(f.get("species")) if f.get("species") != null else ""
	var nm: String = String(f.get("fish_name")) if f.get("fish_name") != null else ""
	return SimRngScript.stream_seed(SEED_MASTER, "backstory|%s|%s|%s" % [fid, sp, nm])


static func _p(f: Object, key: String) -> float:
	var pv: Variant = f.get("personality")
	if pv is Dictionary:
		return clampf(float((pv as Dictionary).get(key, 0.5)), 0.0, 1.0)
	return 0.5


static func _weighted(rng: RandomNumberGenerator, items: Array, weights: Array) -> int:
	var total: float = 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0 or items.is_empty():
		return -1
	var roll: float = rng.randf() * total
	for i in items.size():
		roll -= maxf(0.0, float(weights[i]))
		if roll <= 0.0:
			return i
	return items.size() - 1


# Pure + deterministic: same fish fields + same candidates -> same story.
static func generate(f: Object, cands: Array, mates: Array = [], sim_day: String = "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_for(f)
	var bold: float = _p(f, "boldness")
	var cur: float = _p(f, "curiosity")
	var soc: float = _p(f, "sociability")
	var calm: float = _p(f, "calm")
	var glut: float = _p(f, "gluttony")
	var herb: float = float(f.get("herbivory")) if f.get("herbivory") != null else 0.0
	if f.get("algae_grazer") == true or f.get("wood_grazer") == true:
		herb = maxf(herb, 0.6)
	var species: String = String(f.get("species")) if f.get("species") != null else ""
	var gen: int = int(f.get("generation")) if f.get("generation") != null else 0
	var lineage: String = String(f.get("parent_lineage")) if f.get("parent_lineage") != null else ""
	var s: Dictionary = {"v": SCHEMA_V, "fav_visits": 0, "seeded": false}

	# --- origin ---------------------------------------------------------
	var par_list: Array = []
	if gen > 0 and lineage.contains(" & "):
		s["origin"] = "bred"
		for pn in lineage.split(" & ", false):
			var pe: Dictionary = {"name": String(pn).strip_edges(), "id": ""}
			for m in mates:
				if String(m.get("name", "")) == pe["name"]:
					pe["id"] = String(m.get("id", ""))
					pe["sex"] = int(m.get("sex", 0))
					break
			par_list.append(pe)
		var siblings: int = 0
		for m in mates:
			if String(m.get("lineage", "")) == lineage:
				siblings += 1
		s["clutch"] = siblings + 1
		s["birth_day"] = sim_day
		var born: String
		if f.get("is_livebearer") == true:
			born = "born live"
		elif f.get("guards_clutch") == true:
			born = "hatched from a clutch its parents guarded"
		else:
			born = "hatched from an egg scattered among the plants"
		s["birth"] = born
		var names: String = _join_names(par_list)
		var clutch_txt: String = ("the only one of its clutch still here" if siblings == 0
			else "one of %d from its clutch" % (siblings + 1))
		s["origin_text"] = "Born here to %s (%s), %s%s" % [names, born, clutch_txt,
			(", %s" % sim_day) if sim_day != "" else ""]
	elif species.begins_with("stranger_"):
		s["origin"] = "adopted"
		var ao: String = ADOPTED_ORIGINS[rng.randi() % ADOPTED_ORIGINS.size()]
		s["origin_text"] = ao.left(1).to_upper() + ao.substr(1)
	else:
		s["origin"] = "founder"
		var fo: String = FOUNDER_ORIGINS[rng.randi() % FOUNDER_ORIGINS.size()]
		s["origin_text"] = fo.left(1).to_upper() + fo.substr(1)
	s["parents"] = par_list

	# --- like -----------------------------------------------------------
	var pool: Array = cands.duplicate()
	# Tankmates: a bred fish often adores a living parent; anyone may fear a
	# much bigger fish of another species.
	var my_size: float = float(f.get("adult_voxel_scale")) if f.get("adult_voxel_scale") != null else 1.0
	var parent_mate: Dictionary = {}
	for pe in par_list:
		if String(pe.get("id", "")) != "":
			parent_mate = {"kind": "tankmate", "label": String(pe["name"]), "key": "mate:" + String(pe["id"]),
				"id": String(pe["id"])}
			break
	var big_mate: Dictionary = {}
	var sorted_mates: Array = mates.duplicate()
	sorted_mates.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	for m in sorted_mates:
		if String(m.get("species", "")) != species and float(m.get("size", 1.0)) > my_size * 1.5 \
				and String(m.get("id", "")) != "":
			big_mate = {"kind": "tankmate", "label": String(m.get("name", "a big fish")),
				"key": "mate:" + String(m["id"]), "id": String(m["id"])}
			break
	var like_items: Array = []
	var like_w: Array = []
	for c in pool:
		like_items.append(c)
		like_w.append(_like_weight(String(c.get("kind", "")), bold, cur, soc, calm, herb))
	if not parent_mate.is_empty():
		like_items.append(parent_mate)
		like_w.append(1.2 + soc * 1.5)
	var li: int = _weighted(rng, like_items, like_w)
	var like: Dictionary = (like_items[li] as Dictionary).duplicate() if li >= 0 else \
		{"kind": "corner", "label": "quiet corner", "key": "corner"}
	s["like"] = like

	# --- fear (never the same subject as the like) ----------------------
	var fear_items: Array = []
	var fear_w: Array = []
	for c in pool:
		if String(c.get("key", "")) == String(like.get("key", "")):
			continue
		fear_items.append(c)
		fear_w.append(_fear_weight(String(c.get("kind", "")), bold, calm))
	if not big_mate.is_empty() and String(big_mate["key"]) != String(like.get("key", "")):
		fear_items.append(big_mate)
		fear_w.append(0.6 + (1.0 - bold) * 1.4)
	var fi: int = _weighted(rng, fear_items, fear_w)
	var fear: Dictionary = (fear_items[fi] as Dictionary).duplicate() if fi >= 0 else \
		({"kind": "surface", "label": "surface", "key": "surface"} if String(like.get("key", "")) != "surface"
			else {"kind": "substrate", "label": "substrate", "key": "substrate"})
	s["fear"] = fear

	# --- formative memory: origin-flavoured or tied to the fear ---------
	var origin: String = String(s["origin"])
	if rng.randf() < 0.5:
		var fk: String = String(fear.get("kind", ""))
		var tmpl: String = String(FEAR_MEMORIES.get(fk, "a bad scare it never forgot"))
		s["formative"] = tmpl % String(fear.get("label", "")) if tmpl.contains("%s") else tmpl
		s["formative_kind"] = "fear"
	else:
		var om: Array = ORIGIN_MEMORIES.get(origin, ORIGIN_MEMORIES["founder"])
		var mem: String = String(om[rng.randi() % om.size()])
		if origin == "bred" and not par_list.is_empty() and rng.randf() < 0.5:
			var par: Dictionary = par_list[rng.randi() % par_list.size()]
			mem = "%s hovering over the clutch, keeping the others away" % String(par["name"]) \
				if f.get("guards_clutch") == true else "following %s through the plants as a fry" % String(par["name"])
		s["formative"] = mem
		s["formative_kind"] = "origin"

	# --- quirk ----------------------------------------------------------
	var q_w: Array = []
	var traits: Dictionary = {"curiosity": cur, "calm": calm, "boldness": bold, "sociability": soc, "gluttony": glut}
	for q in QUIRKS:
		var t: String = String(q["trait"])
		q_w.append(float(q["w"]) * (0.5 + float(traits.get(t, 0.5)) * 1.5 if t != "" else float(q["w"])))
	var qi: int = _weighted(rng, QUIRKS, q_w)
	s["quirk"] = String(QUIRKS[maxi(qi, 0)]["text"])
	return s


static func _like_weight(kind: String, bold: float, cur: float, soc: float, calm: float, herb: float) -> float:
	var shy: float = 1.0 - bold
	match kind:
		"plant":
			return 0.6 + herb * 1.2 + calm * 0.4 + shy * 0.3
		"driftwood", "cave", "stones":
			return 0.5 + shy * 1.2
		"lily":
			return 0.5 + calm * 0.6 + shy * 0.4
		"lamp":
			return 0.2 + bold * 0.9
		"filter":
			return 0.15 + bold * 0.6 + cur * 0.6
		"surface":
			return 0.2 + bold * 0.5
		"substrate":
			return 0.25 + calm * 0.3
		"corner":
			return 0.2 + shy * 0.4
		"ornament":
			return 0.3 + cur * 0.9
	return 0.3 + soc * 0.1


static func _fear_weight(kind: String, bold: float, calm: float) -> float:
	var shy: float = 1.0 - bold
	match kind:
		"lamp":
			return 0.4 + shy * 1.0
		"filter":
			return 0.4 + shy * 0.8 + (1.0 - calm) * 0.4
		"surface":
			return 0.5 + shy * 0.9
		"substrate":
			return 0.2
		"driftwood", "cave", "stones":
			return 0.15 + (1.0 - calm) * 0.3
		"plant":
			return 0.12
		"lily":
			return 0.2
		"corner":
			return 0.25 + (1.0 - calm) * 0.3
		"ornament":
			return 0.3 + shy * 0.4
	return 0.2


# ---------------------------------------------------------------------------
# Save / load
# ---------------------------------------------------------------------------

static func to_save(f: Object) -> Dictionary:
	var s: Dictionary = story(f)
	return s.duplicate(true) if not s.is_empty() else {}


# Schema-safe: anything malformed is dropped and ensure() regenerates.
static func load_into(f: Object, v: Variant) -> void:
	if f == null:
		return
	if not (v is Dictionary):
		return
	var d: Dictionary = (v as Dictionary).duplicate(true)
	if int(d.get("v", 0)) < 1 or not (d.get("like") is Dictionary) or not (d.get("fear") is Dictionary):
		return
	f.set("backstory", d)


# ---------------------------------------------------------------------------
# Getters (speech + UI)
# ---------------------------------------------------------------------------

static func likes(f: Object) -> Dictionary:
	var v: Variant = story(f).get("like")
	return v as Dictionary if v is Dictionary else {}


static func fears(f: Object) -> Dictionary:
	var v: Variant = story(f).get("fear")
	return v as Dictionary if v is Dictionary else {}


# "the Java Fern", "the filter current", "Mika".
static func phrase(subject: Dictionary) -> String:
	if subject.is_empty():
		return ""
	var label: String = String(subject.get("label", ""))
	if String(subject.get("kind", "")) == "tankmate" or label.begins_with("the "):
		return label
	return "the " + label


static func like_phrase(f: Object) -> String:
	return phrase(likes(f))


static func fear_phrase(f: Object) -> String:
	return phrase(fears(f))


static func quirk(f: Object) -> String:
	return String(story(f).get("quirk", ""))


static func formative_memory(f: Object) -> String:
	return String(story(f).get("formative", ""))


static func origin_text(f: Object) -> String:
	return String(story(f).get("origin_text", ""))


static func _join_names(list: Array) -> String:
	var names := PackedStringArray()
	for e in list:
		if e is Dictionary and String((e as Dictionary).get("name", "")) != "":
			names.append(String((e as Dictionary)["name"]))
	return " and ".join(names)


static func parents(f: Object) -> Array:
	var v: Variant = story(f).get("parents")
	return v as Array if v is Array else []


static func summary(f: Object) -> String:
	if not has_story(f):
		return ""
	var s: Dictionary = story(f)
	var parts: PackedStringArray = PackedStringArray()
	parts.append(String(s.get("origin_text", "")) + ".")
	parts.append("Loves %s; wary of %s." % [like_phrase(f), fear_phrase(f)])
	var q: String = quirk(f)
	if q != "":
		parts.append("It %s." % q)
	return " ".join(parts)


static func tagline(f: Object) -> String:
	if not has_story(f):
		return ""
	var s: Dictionary = story(f)
	var o: String
	match String(s.get("origin", "")):
		"bred":
			o = "bred here"
		"adopted":
			o = "adopted"
		_:
			o = "founder"
	return "%s · loves %s" % [o, like_phrase(f)]


static func bio_lines(f: Object) -> Array[String]:
	var out: Array[String] = []
	if not has_story(f):
		return out
	out.append(origin_text(f) + ".")
	var mem: String = formative_memory(f)
	if mem != "":
		out.append("Remembers %s." % mem)
	out.append("Loves %s." % like_phrase(f))
	out.append("Wary of %s." % fear_phrase(f))
	var q: String = quirk(f)
	if q != "":
		out.append("Quirk: %s." % q)
	var visits: int = int(story(f).get("fav_visits", 0))
	if visits > 1:
		out.append("Has returned to its favourite spot %d times." % visits)
	return out


# First-person lines for the tank-mind conversation / fish replies.
static func speech_line(f: Object, topic: String) -> String:
	if not has_story(f):
		return ""
	var s: Dictionary = story(f)
	match topic:
		"origin", "parents":
			if String(s.get("origin", "")) == "bred":
				return "I was born here. %s are my parents." % _join_names(parents(f))
			var o: String = String(s.get("origin_text", ""))
			return "I %s." % (o.left(1).to_lower() + o.substr(1)) if o != "" else ""
		"memory":
			var m: String = formative_memory(f)
			return "I still remember %s." % m if m != "" else ""
		"like", "home":
			var lk: Dictionary = likes(f)
			if String(lk.get("kind", "")) == "tankmate":
				return "I like being near %s." % phrase(lk)
			return "My place is by %s." % phrase(lk)
		"fear":
			return "I keep away from %s." % fear_phrase(f)
		"quirk":
			var q: String = quirk(f)
			return "They say I %s." % q if q != "" else ""
	return ""
