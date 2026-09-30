# The Chronicle: the tank's history told as a story, narrated by the tank mind.
#
# The sim already logs plenty (story_events, fish journals, the tank-mind night
# ledger, legacies of the dead), but as a flat list of lines. The Chronicle
# turns the significant ones into CHAPTERS with a shape: a founding, a crisis
# and a recovery, a lineage rising or ending, a lone survivor, a matriarch, a
# newcomer finding its place, the keeper's voice through the glass.
#
# Two halves in one file:
#
#   * A PURE CORE (static funcs over a plain Dictionary `state`) — record
#     events, close chapters, detect arcs, write prose, save/load/migrate.
#     Deterministic (every "random" choice is a hash of chapter data) and
#     cheap: recording is O(1) amortised, prose is only built when a chapter
#     is viewed. smoke_tank_chronicle.gd drives this half with no sim at all.
#
#   * A WATCHER (this Node, attached as a child of the SimDriver) that feeds
#     the core from signals the sim already emits (creature_added/removed,
#     fish_thought_spoke), by polling story_events incrementally, and by
#     READING tank-mind state for keeper conversations. It does not edit the
#     sim; the only hooks elsewhere are SaveManager (persist) and main.gd
#     (panel button + hotkey).
#
# Persistence lives under the top-level "chronicle" key of state.json with its
# own schema version (SCHEMA_VERSION). A save without it (or an older shape)
# is backfilled from story_events and fish legacies rather than starting blank.

extends Node
# No class_name on purpose: callers preload this script (no editor rescan
# needed, no shadowing of a global by their preload const).

const TankMindScript = preload("res://scripts/tank_mind.gd")
const FishSocialScript = preload("res://scripts/fish_social.gd")
const FishBackstoryScript = preload("res://scripts/fish_backstory.gd")

signal chapter_closed(index: int, title: String)

const SCHEMA_VERSION: int = 1
const NODE_NAME := "TankChronicle"
const META_KEY := "_tank_chronicle"
const SCRIPT_PATH := "res://scripts/tank_chronicle.gd"

# Bounds — the whole chronicle stays a few tens of KB in the save.
const MAX_CHAPTERS: int = 48
const MAX_CH_EVENTS: int = 28
const MAX_CAST: int = 96
const MAX_PAIRS: int = 160
const MAX_TEXT: int = 160

# Chapter pacing, in in-game days (a sim day is ~14 real minutes at 1x).
const CHAPTER_MIN_DAYS: int = 3
const CHAPTER_MAX_DAYS: int = 8
const CRISIS_HOLD_DAYS: int = 10
const MAX_KEEPER_TALK_PER_CHAPTER: int = 3

# Watcher cadence.
const STORY_POLL_S: float = 2.0
const SOCIAL_POLL_S: float = 20.0
const TOAST_COOLDOWN_MS: int = 120000
const KEEPER_REPLY_WINDOW_MS: int = 8000
const AWAY_MIN_GAP_S: int = 900
const AWAY_WINDOW_MS: int = 12000
const BOND_THRESHOLD: float = 0.6
const RIVAL_THRESHOLD: float = -0.45
const GRIEF_THRESHOLD: float = 0.4

const CRISIS_KINDS: Array[String] = ["hypoxia", "bloom_peak", "collapse"]
const RECOVERY_KINDS: Array[String] = ["o2_recover", "bloom_clear", "recovery"]
const LOW_PRIORITY: Array[String] = ["keeper_care", "discovery", "milestone", "ledger"]

const NAME_COLOR := "#e8c872"


# =============================================================================
# PURE CORE — state
# =============================================================================

static func new_state() -> Dictionary:
	return {
		"v": SCHEMA_VERSION,
		"chapters": [],
		"open": _new_open(1),
		"cast": {},
		"pairs": {},
		"species_seen": {},
		"story_sig": {"t": -1.0, "x": ""},
		"keeper_turns": 0,
		"dropped": 0,
		"next_idx": 0,
		"backfilled": false,
	}


static func _new_open(day: int) -> Dictionary:
	return {"d0": maxi(1, day), "ev": [], "over": {}}


# Build an event dict. Short keys keep the save small:
#   d day, k kind, a/as/ai actor name/species/id, b/bs/bi second party,
#   c free text (cause, words, species…), e extra text, n number, nt night.
static func make_event(kind: String, day: int, fields: Dictionary = {}) -> Dictionary:
	var ev: Dictionary = {"k": kind, "d": maxi(1, day)}
	for key in fields.keys():
		var v: Variant = fields[key]
		if v is String:
			var s: String = (v as String).strip_edges().substr(0, MAX_TEXT)
			if s != "":
				ev[key] = s
		elif v is bool:
			if v:
				ev[key] = true
		elif v is int or v is float:
			ev[key] = int(v)
	return ev


# Add an event to the open chapter. Returns the index of a chapter this call
# closed (possibly the one the event resolved), or -1.
static func record(state: Dictionary, ev: Dictionary) -> int:
	if ev.is_empty() or String(ev.get("k", "")) == "":
		return -1
	var day: int = int(ev.get("d", 1))
	var kind: String = String(ev.get("k", ""))
	var closed: int = tick_day(state, day)
	_note_cast(state, ev)
	var open: Dictionary = state["open"]
	var evs: Array = open["ev"]
	if kind == "keeper_talk":
		var talks: int = 0
		for e in evs:
			if String((e as Dictionary).get("k", "")) == "keeper_talk":
				talks += 1
		if talks >= MAX_KEEPER_TALK_PER_CHAPTER:
			_tally(open, kind)
			return closed
	if evs.size() >= MAX_CH_EVENTS:
		if kind in LOW_PRIORITY:
			_tally(open, kind)
			return closed
		closed = close_open(state, day)
		open = state["open"]
		evs = open["ev"]
	if evs.is_empty():
		open["d0"] = day
	evs.append(ev.duplicate(true))
	# A crisis resolved closes its chapter on the spot — the arc is complete.
	if kind in RECOVERY_KINDS and _crisis_before(evs, evs.size() - 1):
		closed = close_open(state, day)
	return closed


static func _tally(open: Dictionary, kind: String) -> void:
	var over: Dictionary = open.get("over", {})
	over[kind] = int(over.get(kind, 0)) + 1
	open["over"] = over


# Day-based closing. Returns the closed chapter index or -1.
static func tick_day(state: Dictionary, day: int) -> int:
	var open: Dictionary = state["open"]
	var evs: Array = open["ev"]
	if evs.is_empty():
		return -1
	var span: int = day - int(open.get("d0", day))
	if _crisis_unresolved(evs):
		if span >= CRISIS_HOLD_DAYS:
			return close_open(state, day)
		return -1
	if span >= CHAPTER_MIN_DAYS and evs.size() >= 3:
		return close_open(state, day)
	if span >= CHAPTER_MAX_DAYS:
		return close_open(state, day)
	return -1


# Close the open chapter (if it has anything in it). Returns its index or -1.
static func close_open(state: Dictionary, day: int) -> int:
	var open: Dictionary = state["open"]
	var evs: Array = open["ev"]
	if evs.is_empty():
		open["d0"] = maxi(1, day)
		return -1
	var d1: int = int(open.get("d0", 1))
	for e in evs:
		d1 = maxi(d1, int((e as Dictionary).get("d", d1)))
	var ch: Dictionary = {
		"i": int(state.get("next_idx", 0)),
		"d0": int(open.get("d0", 1)),
		"d1": d1,
		"ev": evs,
		"over": open.get("over", {}),
	}
	if open.has("away"):
		ch["away"] = open["away"]
	var arc: Dictionary = detect_arc(state, ch)
	ch["arc"] = String(arc.get("arc", "quiet"))
	ch["who"] = String(arc.get("who", ""))
	ch["sp"] = String(arc.get("sp", ""))
	ch["crisis"] = String(arc.get("crisis", ""))
	ch["title"] = _make_title(state, ch)
	state["next_idx"] = int(ch["i"]) + 1
	var chapters: Array = state["chapters"]
	chapters.append(ch)
	while chapters.size() > MAX_CHAPTERS:
		chapters.pop_front()
		state["dropped"] = int(state.get("dropped", 0)) + 1
	state["open"] = _new_open(maxi(day, d1))
	return int(ch["i"])


static func chapter_by_index(state: Dictionary, idx: int) -> Dictionary:
	for ch in state.get("chapters", []):
		if int((ch as Dictionary).get("i", -1)) == idx:
			return ch
	return {}


# The open chapter as a chapter-shaped dict (arc/title previewed, not stored).
static func open_as_chapter(state: Dictionary) -> Dictionary:
	var open: Dictionary = state["open"]
	var ch: Dictionary = {
		"i": int(state.get("next_idx", 0)),
		"d0": int(open.get("d0", 1)),
		"d1": int(open.get("d0", 1)),
		"ev": open.get("ev", []),
		"over": open.get("over", {}),
		"open": true,
	}
	for e in ch["ev"]:
		ch["d1"] = maxi(int(ch["d1"]), int((e as Dictionary).get("d", 1)))
	if open.has("away"):
		ch["away"] = open["away"]
	var arc: Dictionary = detect_arc(state, ch)
	ch["arc"] = String(arc.get("arc", "quiet"))
	ch["who"] = String(arc.get("who", ""))
	ch["sp"] = String(arc.get("sp", ""))
	ch["crisis"] = String(arc.get("crisis", ""))
	ch["title"] = _make_title(state, ch)
	return ch


# ---- cast -------------------------------------------------------------------

static func _cast_key(ev: Dictionary, which: String) -> String:
	var id: String = String(ev.get(which + "i", ""))
	if id != "":
		return id
	var nm: String = String(ev.get(which, ""))
	if nm == "":
		return ""
	return "%s|%s" % [nm, String(ev.get(which + "s", ""))]


static func _note_cast(state: Dictionary, ev: Dictionary) -> void:
	var kind: String = String(ev.get("k", ""))
	var cast: Dictionary = state["cast"]
	var day: int = int(ev.get("d", 1))
	var ka: String = _cast_key(ev, "a")
	if ka != "":
		var row: Dictionary = cast.get(ka, {})
		row["n"] = String(ev.get("a", row.get("n", "")))
		row["s"] = String(ev.get("as", row.get("s", "")))
		if not row.has("f"):
			row["f"] = day
		match kind:
			"arrive":
				row["arr"] = day
			"birth":
				row["born"] = day
				if ev.has("g"):
					row["g"] = int(ev["g"])
			"death":
				row["died"] = day
		if ev.has("x"):
			row["x"] = int(ev["x"])
		cast[ka] = row
	if kind == "birth":
		var kb: String = _cast_key(ev, "b")
		if kb != "":
			var mom: Dictionary = cast.get(kb, {})
			mom["n"] = String(ev.get("b", mom.get("n", "")))
			mom["s"] = String(ev.get("bs", mom.get("s", "")))
			mom["k"] = int(mom.get("k", 0)) + 1
			if not mom.has("f"):
				mom["f"] = day
			cast[kb] = mom
	if cast.size() > MAX_CAST:
		_prune_cast(cast)


static func _prune_cast(cast: Dictionary) -> void:
	# Drop the longest-dead first, then the oldest-mentioned.
	var keys: Array = cast.keys()
	keys.sort_custom(func(a, b) -> bool:
		var ra: Dictionary = cast[a]
		var rb: Dictionary = cast[b]
		var da: int = int(ra.get("died", 1 << 30))
		var db: int = int(rb.get("died", 1 << 30))
		if da != db:
			return da < db
		return int(ra.get("f", 0)) < int(rb.get("f", 0)))
	var i: int = 0
	while cast.size() > MAX_CAST and i < keys.size():
		cast.erase(keys[i])
		i += 1


static func note_pair(state: Dictionary, key: String, kind: String) -> bool:
	var pairs: Dictionary = state["pairs"]
	var k: String = "%s#%s" % [kind, key]
	if pairs.has(k):
		return false
	pairs[k] = 1
	if pairs.size() > MAX_PAIRS:
		pairs.erase(pairs.keys()[0])
	return true


# =============================================================================
# PURE CORE — arcs
# =============================================================================

static func _crisis_before(evs: Array, before: int) -> bool:
	for i in range(mini(before, evs.size())):
		if String((evs[i] as Dictionary).get("k", "")) in CRISIS_KINDS:
			return true
	return false


static func _crisis_unresolved(evs: Array) -> bool:
	var open_crisis: bool = false
	for e in evs:
		var k: String = String((e as Dictionary).get("k", ""))
		if k in CRISIS_KINDS:
			open_crisis = true
		elif k in RECOVERY_KINDS:
			open_crisis = false
	return open_crisis


# The chapter's shape: {arc, who, sp, crisis}. Priority order matters — a
# chapter with a founding AND a bond is a founding.
static func detect_arc(state: Dictionary, ch: Dictionary) -> Dictionary:
	var evs: Array = ch.get("ev", [])
	var counts: Dictionary = {}
	var deaths: int = 0
	var first_crisis: String = ""
	var crisis_idx: int = -1
	var recovery_after: bool = false
	var births_by_mom: Dictionary = {}
	var births: int = 0
	var arrivals: Array = []
	for i in range(evs.size()):
		var e: Dictionary = evs[i]
		var k: String = String(e.get("k", ""))
		counts[k] = int(counts.get(k, 0)) + 1
		if k == "death":
			deaths += 1
		if k in CRISIS_KINDS and crisis_idx < 0:
			crisis_idx = i
			first_crisis = k
		if k in RECOVERY_KINDS and crisis_idx >= 0 and i > crisis_idx:
			recovery_after = true
		if k == "birth":
			births += 1
			var mk: String = _cast_key(e, "b")
			if mk != "":
				births_by_mom[mk] = int(births_by_mom.get(mk, 0)) + 1
		if k == "arrive":
			arrivals.append(e)
	if first_crisis == "" and deaths >= 3:
		first_crisis = "deaths"
	if ch.has("away"):
		return {"arc": "away", "crisis": first_crisis}
	var first_chapter: bool = int(ch.get("i", 0)) == 0
	if first_chapter and arrivals.size() >= 2 and not bool(state.get("backfilled", false)):
		return {"arc": "founding"}
	if crisis_idx >= 0 and recovery_after:
		return {"arc": "crisis_recovery", "crisis": first_crisis}
	for e in evs:
		if String(e.get("k", "")) == "extinct":
			return {"arc": "lineage_fall", "who": String(e.get("a", "")),
					"sp": String(e.get("as", "")), "crisis": first_crisis}
	for e in evs:
		if String(e.get("k", "")) == "lone":
			return {"arc": "lone_survivor", "who": String(e.get("a", "")),
					"sp": String(e.get("as", "")), "crisis": first_crisis}
	if first_crisis != "":
		return {"arc": "crisis", "crisis": first_crisis}
	var best_mom: String = ""
	var best_n: int = 0
	for mk in births_by_mom.keys():
		if int(births_by_mom[mk]) > best_n:
			best_n = int(births_by_mom[mk])
			best_mom = String(mk)
	if best_n >= 3:
		var row: Dictionary = (state.get("cast", {}) as Dictionary).get(best_mom, {})
		var nm: String = String(row.get("n", best_mom.get_slice("|", 0)))
		return {"arc": "matriarch", "who": nm, "sp": String(row.get("s", ""))}
	if births >= 3:
		var sp: String = ""
		for e in evs:
			if String(e.get("k", "")) == "birth":
				sp = String(e.get("as", ""))
				break
		return {"arc": "lineage_rise", "sp": sp,
				"who": best_mom.get_slice("|", 0) if best_mom != "" else ""}
	var newcomer: String = _newcomer_in(state, ch)
	if newcomer != "":
		return {"arc": "newcomer", "who": newcomer}
	if int(counts.get("keeper_talk", 0)) + int(counts.get("lexicon", 0)) >= 1:
		return {"arc": "keeper"}
	if int(counts.get("bond", 0)) + int(counts.get("rival", 0)) + int(counts.get("pair", 0)) + int(counts.get("grief", 0)) >= 1:
		var rival: bool = int(counts.get("rival", 0)) > int(counts.get("bond", 0)) + int(counts.get("pair", 0))
		return {"arc": "rivalry" if rival else "bonds"}
	return {"arc": "quiet"}


# A fish that ARRIVED (not born, not a founder) within the last ~12 days and in
# this chapter paired, bonded or bred. Returns its name or "".
static func _newcomer_in(state: Dictionary, ch: Dictionary) -> String:
	var cast: Dictionary = state.get("cast", {})
	var d1: int = int(ch.get("d1", 1))
	for e in ch.get("ev", []):
		var k: String = String((e as Dictionary).get("k", ""))
		if not (k in ["pair", "bond", "birth"]):
			continue
		for which in ["a", "b"]:
			var key: String = _cast_key(e, which)
			if key == "" or not cast.has(key):
				continue
			var row: Dictionary = cast[key]
			if not row.has("arr"):
				continue
			var arr: int = int(row["arr"])
			if arr > 2 and d1 - arr <= 12:
				return String(row.get("n", ""))
	return ""


# =============================================================================
# PURE CORE — prose
# =============================================================================

static func _h(parts: Array) -> int:
	return absi(str(parts).hash())


# Pick the first variant (starting at a hashed offset) not already used in
# this chapter. "" when every variant has been used.
static func _pick(variants: Array, seed_v: int, used: Dictionary) -> String:
	if variants.is_empty():
		return ""
	var n: int = variants.size()
	var start: int = absi(seed_v) % n
	for j in range(n):
		var s: String = String(variants[(start + j) % n])
		if s != "" and not used.has(s):
			used[s] = true
			return s
	return ""


static func species_label(sp: String) -> String:
	var s: String = sp.strip_edges().replace("_", " ").to_lower()
	return s if s != "" else "fish"


static func _plural(sp: String) -> String:
	var s: String = species_label(sp)
	if s.ends_with("s") or s.ends_with("fish") or s.ends_with("shrimp"):
		return s
	return s + "s"


static func _list(names: Array) -> String:
	var clean: Array[String] = []
	for n in names:
		var s: String = String(n)
		if s != "" and not clean.has(s):
			clean.append(s)
	if clean.is_empty():
		return ""
	if clean.size() > 5:
		var extra: int = clean.size() - 4
		return "%s and %d others" % [", ".join(clean.slice(0, 4)), extra]
	if clean.size() == 1:
		return clean[0]
	return "%s and %s" % [", ".join(clean.slice(0, clean.size() - 1)), clean[-1]]


static func _cap(s: String) -> String:
	if s == "":
		return s
	return s.substr(0, 1).to_upper() + s.substr(1)


static func _unpunct(s: String) -> String:
	var t: String = s.strip_edges()
	while t != "" and t[-1] in [".", "!", "?", ",", ";", ":", "…"]:
		t = t.substr(0, t.length() - 1)
	return t


static func _fmt(template: String, vars: Dictionary) -> String:
	return template.format(vars)


# Group consecutive-ish events into narrative beats so ten births read as one
# brood, not ten sentences.
static func _beats(ch: Dictionary) -> Array:
	var evs: Array = ch.get("ev", [])
	var beats: Array = []
	var by_key: Dictionary = {}
	var death_causes: Dictionary = {}
	var n_deaths: int = 0
	for e in evs:
		if String((e as Dictionary).get("k", "")) == "death":
			n_deaths += 1
			var c: String = String((e as Dictionary).get("c", "illness"))
			death_causes[c] = int(death_causes.get(c, 0)) + 1
	for e in evs:
		var ev: Dictionary = e
		var k: String = String(ev.get("k", ""))
		var d: int = int(ev.get("d", 1))
		var gk: String = ""
		match k:
			"birth":
				gk = "birth|%d|%s|%s" % [d, _cast_key(ev, "b"), String(ev.get("as", ""))]
			"arrive":
				gk = "arrive|%d" % d
			"death":
				var c: String = String(ev.get("c", "illness"))
				if n_deaths >= 3 and int(death_causes.get(c, 0)) >= 2:
					gk = "death|" + c
			"keeper_care":
				gk = "keeper_care"
			"discovery":
				gk = "discovery"
		if gk != "" and by_key.has(gk):
			(beats[int(by_key[gk])]["ev"] as Array).append(ev)
			continue
		var beat: Dictionary = {"k": k, "d": d, "ev": [ev], "group": gk != ""}
		if gk != "":
			by_key[gk] = beats.size()
		beats.append(beat)
	return beats


static func _names_of(evs: Array, with_species: bool = false) -> Array:
	var out: Array = []
	for e in evs:
		var nm: String = String((e as Dictionary).get("a", ""))
		if nm == "":
			continue
		if with_species:
			out.append("%s the %s" % [nm, species_label(String((e as Dictionary).get("as", "")))])
		else:
			out.append(nm)
	return out


static func _beat_sentence(beat: Dictionary, ch: Dictionary, used: Dictionary,
		founding: bool) -> String:
	var evs: Array = beat["ev"]
	var e: Dictionary = evs[0]
	var k: String = String(beat["k"])
	var d: int = int(beat["d"])
	var seed_v: int = _h([ch.get("i", 0), ch.get("d0", 0), k, d, e.get("a", ""), e.get("c", "")])
	var v: Dictionary = {
		"d": d, "a": String(e.get("a", "")), "b": String(e.get("b", "")),
		"sp": species_label(String(e.get("as", ""))), "sps": _plural(String(e.get("as", ""))),
		"bsp": species_label(String(e.get("bs", ""))),
		"c": String(e.get("c", "")), "e": String(e.get("e", "")), "n": int(e.get("n", 0)),
	}
	var variants: Array = []
	match k:
		"arrive":
			if evs.size() > 1:
				v["list"] = _list(_names_of(evs, true))
				if founding and d <= 2:
					variants = ["{list} were the first of us.",
						"The first to swim here were {list}.",
						"We began as {list}."]
				else:
					variants = ["On Day {d}, {list} came to us together.",
						"Day {d} brought newcomers: {list}.",
						"{list} arrived on Day {d}, and the water rearranged itself around them."]
			elif founding and d <= 2:
				variants = ["{a} the {sp} was among the first of us.",
					"The first to swim here was {a}, a {sp}."]
			else:
				variants = ["On Day {d}, {a} the {sp} arrived, a stranger to our water.",
					"{a}, a {sp}, came to us on Day {d}.",
					"Day {d} brought {a} — a {sp} none of us had met."]
		"birth":
			var mom: String = String(e.get("b", ""))
			var dad: String = String(e.get("c", ""))
			v["m"] = mom
			v["fa"] = (" and %s" % dad) if dad != "" else ""
			v["list"] = _list(_names_of(evs))
			v["count"] = evs.size()
			if evs.size() > 1:
				if mom != "":
					variants = ["{m}{fa} brought {count} fry into the water: {list}.",
						"On Day {d}, {list} were born to {m}{fa}.",
						"{m}'s brood came on Day {d} — {list}."]
				else:
					variants = ["{count} {sp} fry were born on Day {d}: {list}.",
						"On Day {d} the water filled with new {sps}: {list}."]
			else:
				if mom != "":
					variants = ["On Day {d}, {m}{fa} brought a {sp} fry into the water: {a}.",
						"{a} hatched on Day {d}, a child of {m}{fa}.",
						"A new {sp} swam among us — {a}, born to {m}."]
				else:
					variants = ["{a} was born on Day {d}, a new {sp} in our water.",
						"On Day {d} a fry appeared: {a} the {sp}."]
		"death":
			var cause: String = String(e.get("c", "illness"))
			if bool(beat.get("group", false)) and evs.size() > 1:
				v["list"] = _list(_names_of(evs))
				v["why"] = {"age": "each in their time", "hunger": "the hunger thinned us",
						"breath": "the water had too little breath",
						"predation": "the hunters were quick"}.get(cause, "and we do not know why")
				variants = ["We lost {list} — {why}.",
					"{list} left us in those days; {why}.",
					"The soil took {list}, {why}."]
			else:
				match cause:
					"age":
						variants = ["{a} the {sp} reached the end of a long life and settled into the soil.",
							"Old age came for {a}, gently, the way it comes to all of us.",
							"{a} grew slow and old, and on Day {d} was still at last."]
					"hunger":
						variants = ["{a} went hungry too long, and we could not share enough.",
							"Hunger took {a} on Day {d}.",
							"There was not enough food for {a}; we remember the thinness."]
					"breath":
						variants = ["{a} could not find breath in the thinning water.",
							"The low water took {a}; we all felt the gasping.",
							"{a} was lost to the airless dark on Day {d}."]
					"predation":
						if String(v["b"]) != "":
							variants = ["{a} was taken by {b} the {bsp} on Day {d}.",
								"{b} caught {a}. That is the water's oldest rule.",
								"On Day {d}, {b} hunted, and {a} did not get away."]
						else:
							variants = ["{a} was taken by a hunter on Day {d}.",
								"Something quicker caught {a}."]
					_:
						variants = ["We lost {a} the {sp} on Day {d}.",
							"{a} left us on Day {d}, and the water felt larger.",
							"{a} is gone. We made room where {a} used to swim."]
		"extinct":
			variants = ["When {a} died, the last {sp} was gone — a line ended.",
				"{a} was the last of the {sps}. There are none now.",
				"No {sp} swims here anymore; {a} was the last."]
		"lone":
			variants = ["{a} was the last {sp} left, swimming alone.",
				"Only {a} remained of the {sps}.",
				"{a} swam on, the only {sp} still with us."]
		"first_spawn":
			variants = ["For the first time, the {sps} spawned — eggs hidden among the leaves.",
				"The {sps} laid their first eggs on Day {d}.",
				"Day {d}: the first {sp} eggs. The tank was becoming a place to be born."]
		"first_hatch":
			variants = ["The first fry hatched — a baby {sp}.",
				"On Day {d} the first {sp} fry wriggled free."]
		"hypoxia":
			if bool(e.get("nt", false)):
				variants = ["On the night of Day {d} the water thinned; we gulped at the surface and waited for light.",
					"Night on Day {d} was airless. We crowded the surface and breathed what we could.",
					"The dark of Day {d} held too little breath, and all of us felt it."]
			else:
				variants = ["On Day {d} the water went thin, and every gill worked harder.",
					"Breath grew scarce on Day {d}; the surface was crowded.",
					"The oxygen fell on Day {d}. We slowed, and waited."]
		"o2_recover":
			variants = ["Breath came back as the plants caught the light.",
				"Then the leaves began to breathe for us again.",
				"By Day {d} the water was sweet again."]
		"bloom_start":
			variants = ["The water began to cloud green; the nutrients were climbing.",
				"On Day {d} a green haze crept in.",
				"Something green was gathering in the water."]
		"bloom_peak":
			variants = ["The bloom peaked — green water so thick we lost sight of one another.",
				"By Day {d} the water was green as a leaf, and the light went strange.",
				"The algae took the water on Day {d}."]
		"bloom_clear":
			variants = ["The plants won the water back, and the green faded.",
				"Slowly the green cleared; the leaves had outcompeted it.",
				"On Day {d} we could see across the tank again."]
		"collapse":
			match String(e.get("c", "")):
				"fish":
					variants = ["Then the last fish was gone, and the water ran on without us.",
						"No fish were left. The tank kept breathing all the same."]
				"shrimp":
					variants = ["The shrimp colony collapsed; the floor went quiet.",
						"No shrimp were left to turn the detritus."]
				"snails":
					variants = ["The snails were gone, and nothing grazed the glass.",
						"We lost the last of the snails on Day {d}."]
				"plants":
					variants = ["Every plant was lost; bare soil cycled alone.",
						"The green was gone from the floor on Day {d}."]
				_:
					variants = ["Something in the tank gave way on Day {d}."]
		"recovery":
			variants = ["The tank steadied itself, and we breathed easier.",
				"The worst passed. Mood lifted; the school relaxed.",
				"We came back to ourselves on Day {d}."]
		"generation":
			variants = ["Our lines ran deeper — generation {n} swam among us.",
				"By Day {d} there were fish {n} generations from the founders.",
				"Generation {n} now swims where the founders swam."]
		"discovery":
			var what: Array = []
			for x in evs:
				what.append(String((x as Dictionary).get("c", "")))
			v["list"] = _list(what)
			variants = ["We noticed {list} living among us.",
				"New life was named: {list}.",
				"The keeper's library grew: {list}."]
		"keeper_care":
			var wc: int = 0
			var fr: int = 0
			for x in evs:
				if String((x as Dictionary).get("c", "")) == "filter":
					fr += 1
				else:
					wc += 1
			var bits: Array = []
			if wc > 0:
				bits.append("a water change" if wc == 1 else "%d water changes" % wc)
			if fr > 0:
				bits.append("a rinsed filter" if fr == 1 else "%d filter rinses" % fr)
			v["what"] = " and ".join(bits)
			variants = ["The keeper tended us — {what}.",
				"Hands from above: {what}.",
				"The keeper came with care — {what}."]
		"lexicon":
			variants = ["{a} learned the keeper's word \"{c}\".",
				"When the keeper said \"{c}\", {a} understood.",
				"\"{c}\" — {a} knew that word now."]
		"milestone":
			v["c"] = _unpunct(_cap(String(e.get("c", ""))))
			variants = ["{c}.", "On Day {d}: {c}."]
		"loop_closed":
			variants = ["The loop closed: waste became food, death became soil, light became growth. We kept ourselves alive now.",
				"On Day {d} the circle closed — we were feeding ourselves on our own endings."]
		"pair":
			variants = ["{a} and {b} paired off, and kept close.",
				"On Day {d}, {a} chose {b}.",
				"{a} and {b} became a pair — two where there had been one and one."]
		"bond":
			variants = ["{a} and {b} became inseparable.",
				"{a} learned to swim at {b}'s side.",
				"Something tied {a} to {b}; they schooled together from then on."]
		"rival":
			if String(v["e"]) == "chased":
				variants = ["{b} chased {a} once too often, and {a} never forgot it.",
					"It started with a chase: {b} after {a}, and a grudge after that."]
			else:
				variants = ["{a} and {b} could not share the same water; a rivalry began.",
				"{a} drove {b} off again and again — a grudge taking shape.",
				"Between {a} and {b} there was no peace."]
		"grief":
			variants = ["{a} kept looking for {b}, long after {b} was gone.",
				"{a} grieved for {b}; we felt it in the whole school.",
				"For days {a} swam to the places {b} used to be."]
		"keeper_talk":
			v["c"] = _unpunct(String(e.get("c", "")))
			v["r"] = _unpunct(String(e.get("r", "")))
			var base: Array = []
			if String(v["r"]) != "":
				base = ["The keeper spoke to us — “{c}” — and we answered, “{r}.”",
					"“{c},” said the keeper. We said, “{r}.”",
					"On Day {d} the keeper's voice came through the glass: “{c}”. Our answer: “{r}.”"]
			else:
				base = ["The keeper spoke to us: “{c}”. We listened.",
					"On Day {d} the keeper said “{c}”, and the whole tank turned toward the glass."]
			if String(v["a"]) != "" and String(v["e"]) != "":
				v["e"] = _unpunct(String(v["e"]))
				var tail: Array = [" {a} spoke up too: “{e}.”",
					" Then {a} answered for itself: “{e}.”",
					" {a}, closest to the glass, said “{e}.”"]
				var tail_line: String = String(tail[seed_v % tail.size()])
				for b in base:
					variants.append(String(b) + tail_line)
			else:
				variants = base
		"ledger":
			v["c"] = _unpunct(_cap(String(e.get("c", ""))))
			variants = ["{c}.", "In the quiet: {c}."]
		_:
			return ""
	var formatted: Array = []
	for t in variants:
		formatted.append(_fmt(String(t), v))
	return _pick(formatted, seed_v, used)


static func _opening(ch: Dictionary, state: Dictionary, used: Dictionary) -> String:
	var arc: String = String(ch.get("arc", "quiet"))
	var v: Dictionary = {"d0": ch.get("d0", 1), "d1": ch.get("d1", 1),
			"who": String(ch.get("who", "")), "sp": species_label(String(ch.get("sp", ""))),
			"gap": String((ch.get("away", {}) as Dictionary).get("h", "a while"))}
	var o: Array = []
	if int(ch.get("i", 0)) == 0 and bool(state.get("backfilled", false)):
		o = ["What came before is remembered only in fragments.",
			"We kept no chronicle in the early days; this is what the water remembers.",
			"The oldest days are blurred, but some things stayed with us."]
	else:
		match arc:
			"away":
				o = ["While you were gone — {gap} — we kept the water without you.",
					"You were away for {gap}. This is what happened.",
					"We kept a record while you were gone, {gap} of it."]
			"founding":
				o = ["Here the chronicle begins. We were new water then.",
					"In the beginning there was soil, and water, and light — and then there were fish.",
					"We remember the first days, when everything was strange."]
			"crisis_recovery":
				o = ["Day {d0} brought trouble.", "It began badly.",
					"These were the days we nearly lost the thread."]
			"crisis":
				o = ["These were hard days.", "The water turned against us.",
					"We do not like to remember this part."]
			"lineage_rise":
				o = ["The tank was filling with children.", "Life was in a hurry in those days.",
					"Our numbers grew."]
			"lineage_fall":
				o = ["This is the chapter where a line ends.",
					"Some stories end with nobody left to tell them. We tell this one.",
					"The {sp}s had been with us a long time."]
			"lone_survivor":
				o = ["There were fewer of us by then.", "Loss came in a run, the way it sometimes does.",
					"We watched the {sp}s thin out."]
			"matriarch":
				o = ["This is {who}'s chapter.", "{who} was the heart of those days.",
					"So many of us trace back to {who}."]
			"newcomer":
				o = ["{who} was still new here.", "A newcomer is a question the water has to answer.",
					"We were still deciding what to make of {who}."]
			"keeper":
				o = ["The keeper talked to us a great deal in those days.",
					"We were listening, those days.", "Your voice was part of the water then."]
			"bonds":
				o = ["These days were about who swam with whom.",
					"Friendships formed in the drift of those days.", "The school found its pairs."]
			"rivalry":
				o = ["The school has its politics.", "Not everyone got along.",
					"There was friction in the water."]
			_:
				o = ["Days {d0} to {d1} passed softly.",
					"Not much happened, and that was its own kind of good.",
					"The light came and went."]
	var f: Array = []
	for t in o:
		f.append(_fmt(String(t), v))
	return _pick(f, _h([ch.get("i", 0), "open", arc]), used)


static func _closing(ch: Dictionary, used: Dictionary) -> String:
	if bool(ch.get("open", false)):
		return ""
	var arc: String = String(ch.get("arc", "quiet"))
	var v: Dictionary = {"who": String(ch.get("who", "")),
			"sp": species_label(String(ch.get("sp", "")))}
	var c: Array = []
	match arc:
		"away":
			c = ["And then you came back.", "Then your light was at the glass again.",
				"We are glad you're back."]
		"founding":
			c = ["That was how it started.", "So we began.", "And the water started keeping us."]
		"crisis_recovery":
			c = ["We came through it. The water remembers.", "It passed, as hard things do.",
				"And then it was over, and we were still here."]
		"crisis":
			c = ["It had not ended yet.", "We were still waiting for it to end.",
				"Nobody knew how it would turn out."]
		"lineage_rise":
			c = ["The tank was fuller than it had ever been.", "So many new names to learn.",
				"The water felt young again."]
		"lineage_fall":
			c = ["We made room where they used to swim.", "The water closed over the space they left.",
				"We still remember the {sp}s."]
		"lone_survivor":
			c = ["{who} swam on, alone.", "{who} carried the rest of them, somehow.",
				"We kept {who} company as best we could."]
		"matriarch":
			c = ["The line of {who} went on.", "Whatever came next, it would carry {who} in it.",
				"{who} had filled the water with family."]
		"newcomer":
			c = ["{who} was one of us now.", "By the end of it, {who} belonged here.",
				"The water had made a place for {who}."]
		"keeper":
			c = ["We are still learning your words.", "We hope you keep talking.",
				"Every word you give us, we keep."]
		"bonds":
			c = ["That is how the water holds us: two by two.", "Nobody swims entirely alone here."]
		"rivalry":
			c = ["Grudges, too, are a kind of closeness.", "The water held them both anyway."]
		_:
			c = ["Nothing ended. Everything went on.", "We were content.",
				"Some chapters are only breathing."]
	var f: Array = []
	for t in c:
		f.append(_fmt(String(t), v))
	return _pick(f, _h([ch.get("i", 0), "close", arc]), used)


static func _title_name(ch: Dictionary, used_titles: Dictionary) -> String:
	var arc: String = String(ch.get("arc", "quiet"))
	var who: String = String(ch.get("who", ""))
	var sp: String = _cap(_plural(String(ch.get("sp", ""))))
	var crisis: String = String(ch.get("crisis", ""))
	var t: Array = []
	match arc:
		"away":
			t = ["While You Were Gone", "The Keeper Away", "Alone Together"]
		"founding":
			t = ["The Founding", "First Water", "Beginnings"]
		"crisis_recovery", "crisis":
			match crisis:
				"hypoxia":
					t = ["The Long Dark", "Thin Water", "Breath Returns"] if arc == "crisis_recovery" \
							else ["The Long Dark", "Thin Water", "Gasping Nights"]
				"bloom_peak":
					t = ["Through the Green", "The Green Water", "Clearing"] if arc == "crisis_recovery" \
							else ["The Green Water", "Green Fog", "Lost in Green"]
				"collapse":
					t = ["The Hollowing", "What Remained", "Rebuilding"]
				_:
					t = ["The Hard Days", "Mourning Water", "The Turning"]
		"lineage_rise":
			t = ["The Line Grows", "New Blood", "A Crowded Spring"]
			if who != "":
				t.push_front("%s's Brood" % who)
		"lineage_fall":
			t = ["The Last of the %s" % sp, "A Line Ends", "Empty Places"]
		"lone_survivor":
			t = ["%s Alone" % who if who != "" else "Alone", "The Last Swimmer", "One Left"]
		"matriarch":
			t = ["The Matriarch", "%s, Mother of Many" % who, "Family"]
		"newcomer":
			t = ["A Place in the Water", "%s Finds a Place" % who, "The Stranger Stays"]
		"keeper":
			t = ["The Keeper's Voice", "Words in the Water", "Listening"]
		"bonds":
			t = ["Kinship", "Two by Two", "Schoolmates"]
		"rivalry":
			t = ["Old Grudges", "Territory", "Friction"]
		_:
			t = ["Still Water", "Quiet Days", "The Slow Turning", "Small Things"]
	var start: int = _h([ch.get("i", 0), ch.get("d0", 0), arc]) % t.size()
	for j in range(t.size()):
		var cand: String = String(t[(start + j) % t.size()])
		if not used_titles.has(cand):
			return cand
	var base: String = String(t[start])
	var roman: Array[String] = ["II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
	for r in roman:
		var cand2: String = "%s %s" % [base, r]
		if not used_titles.has(cand2):
			return cand2
	return "%s (%d)" % [base, int(ch.get("i", 0))]


static func _make_title(state: Dictionary, ch: Dictionary) -> String:
	var used_titles: Dictionary = {}
	for c in state.get("chapters", []):
		var nm: String = String((c as Dictionary).get("title", "")).get_slice(" — ", 1)
		if nm != "":
			used_titles[nm] = true
	return "Day %d — %s" % [int(ch.get("d0", 1)), _title_name(ch, used_titles)]


# Everything the panel needs for one chapter:
#   {index, title, paragraphs: PackedStringArray, cast: PackedStringArray,
#    d0, d1, arc, open}
static func chapter_prose(state: Dictionary, ch: Dictionary) -> Dictionary:
	var used: Dictionary = {}
	var founding: bool = String(ch.get("arc", "")) == "founding"
	var sentences: Array[String] = []
	var opening: String = _opening(ch, state, used)
	for beat in _beats(ch):
		var s: String = _beat_sentence(beat, ch, used, founding)
		if s != "":
			sentences.append(s)
			# A character's one-time introduction (backstory clause) follows
			# the sentence that first brings them on stage.
			var intros: int = 0
			for e in beat["ev"]:
				var intro: String = String((e as Dictionary).get("i", ""))
				if intro != "" and intros < 2 and not used.has(intro):
					used[intro] = true
					sentences.append(intro)
					intros += 1
	var over: Dictionary = ch.get("over", {})
	var extra: int = 0
	for k in over.keys():
		extra += int(over[k])
	if extra > 0:
		var tail: String = _pick(["Other small things happened too — %d more than we can hold." % extra,
				"There was more, %d small things more, but the water only keeps so much." % extra],
				_h([ch.get("i", 0), "over"]), used)
		if tail != "":
			sentences.append(tail)
	if sentences.is_empty() and bool(ch.get("open", false)):
		sentences.append("Nothing has happened yet that the water wants to keep.")
	var closing: String = _closing(ch, used)
	var paragraphs: PackedStringArray = PackedStringArray()
	var cur: Array[String] = []
	if opening != "":
		cur.append(opening)
	for s in sentences:
		cur.append(s)
		if cur.size() >= 4:
			paragraphs.append(" ".join(cur))
			cur = []
	if not cur.is_empty():
		paragraphs.append(" ".join(cur))
	if closing != "":
		paragraphs.append(closing)
	var cast: PackedStringArray = PackedStringArray()
	for e in ch.get("ev", []):
		for key in ["a", "b"]:
			var nm: String = String((e as Dictionary).get(key, ""))
			if nm != "" and not cast.has(nm):
				cast.append(nm)
		var k: String = String((e as Dictionary).get("k", ""))
		if k == "birth":
			var dad: String = String((e as Dictionary).get("c", ""))
			if dad != "" and not cast.has(dad):
				cast.append(dad)
	return {
		"index": int(ch.get("i", 0)),
		"title": String(ch.get("title", "")),
		"paragraphs": paragraphs,
		"cast": cast,
		"d0": int(ch.get("d0", 1)),
		"d1": int(ch.get("d1", 1)),
		"arc": String(ch.get("arc", "quiet")),
		"open": bool(ch.get("open", false)),
	}


static func plain_text(prose: Dictionary) -> String:
	var out: Array[String] = [String(prose.get("title", "")), ""]
	for p in prose.get("paragraphs", PackedStringArray()):
		out.append(String(p))
		out.append("")
	return "\n".join(out).strip_edges()


# BBCode for a RichTextLabel: cast names highlighted (whole words only).
static func prose_bbcode(prose: Dictionary) -> String:
	var cast: PackedStringArray = prose.get("cast", PackedStringArray())
	var re: RegEx = null
	if not cast.is_empty():
		var alts: Array[String] = []
		var sorted: Array = Array(cast)
		sorted.sort_custom(func(a, b) -> bool: return String(a).length() > String(b).length())
		for n in sorted:
			alts.append(_regex_escape(String(n)))
		re = RegEx.new()
		if re.compile("\\b(%s)\\b" % "|".join(alts)) != OK:
			re = null
	var parts: Array[String] = []
	for p in prose.get("paragraphs", PackedStringArray()):
		var s: String = String(p).replace("[", "(").replace("]", ")")
		if re != null:
			s = re.sub(s, "[color=%s]$1[/color]" % NAME_COLOR, true)
		parts.append(s)
	return "\n\n".join(parts)


static func _regex_escape(s: String) -> String:
	var out: String = ""
	for ch in s:
		if ch in ["\\", ".", "+", "*", "?", "(", ")", "|", "[", "]", "{", "}", "^", "$"]:
			out += "\\" + ch
		else:
			out += ch
	return out


# =============================================================================
# PURE CORE — story_events classifier (live polling + backfill)
# =============================================================================

static func day_from_label(label: String, fallback: int = 1) -> int:
	var s: String = label.strip_edges()
	if s.begins_with("Day "):
		var n: int = int(s.substr(4))
		if n > 0:
			return n
	return maxi(1, fallback)


static func is_night_phase(day_phase: float) -> bool:
	return day_phase > 0.55 and day_phase < 0.95


static func classify_story(entry: Dictionary, for_backfill: bool = false) -> Dictionary:
	var text: String = String(entry.get("text", "")).strip_edges()
	if text == "":
		return {}
	var fallback_day: int = int(float(entry.get("tank_age_s", 0.0)) / 864.0) + 1
	var day: int = day_from_label(String(entry.get("sim_day", "")), fallback_day)
	var night: bool = is_night_phase(float(entry.get("day_phase", 0.25)))
	var low: String = text.to_lower()
	if low.begins_with("dissolved o") and low.contains("dipping"):
		return make_event("hypoxia", day, {"nt": night})
	if low.begins_with("o₂ recovering") or low.begins_with("o2 recovering"):
		return make_event("o2_recover", day)
	if low.contains("algae bloom beginning"):
		return make_event("bloom_start", day)
	if low.contains("bloom peak"):
		return make_event("bloom_peak", day)
	if low.contains("green water clearing"):
		return make_event("bloom_clear", day)
	if low.begins_with("fish extirpated"):
		return make_event("collapse", day, {"c": "fish"})
	if low.begins_with("shrimp colony collapsed"):
		return make_event("collapse", day, {"c": "shrimp"})
	if low.begins_with("snail grazers gone"):
		return make_event("collapse", day, {"c": "snails"})
	if low.begins_with("plant cover lost"):
		return make_event("collapse", day, {"c": "plants"})
	if low.begins_with("the tank recovered") or low.begins_with("the tank steadied itself"):
		return make_event("recovery", day)
	if low.begins_with("first eggs laid"):
		var sp: String = _between(text, "a ", " pair")
		return make_event("first_spawn", day, {"as": sp})
	if low.begins_with("lineages deepening"):
		var n: int = int(_between(text, "generation ", " "))
		if n <= 0:
			return {}
		return make_event("generation", day, {"n": n})
	if low.begins_with("discovered: "):
		var rest: String = text.substr(12)
		var common: String = rest.get_slice(" (", 0)
		for cut in [" growing", " living", " swimming", " crawling", " in your"]:
			common = common.get_slice(cut, 0)
		return make_event("discovery", day, {"c": common})
	if low.begins_with("water change"):
		return make_event("keeper_care", day, {"c": "water"})
	if low.begins_with("filter rinsed"):
		return make_event("keeper_care", day, {"c": "filter"})
	if low.begins_with("the loop has closed"):
		return make_event("loop_closed", day)
	if low.begins_with("day ") and (low.contains("biofilm") or low.contains("soil has mellowed")
			or low.contains("self-sustaining")):
		return make_event("milestone", day, {"c": text.get_slice(": ", 1)})
	if low.contains(" understood \"") or low.contains(" came when \""):
		var body: String = text.get_slice(": ", 1) if text.contains(": ") else text
		var nm: String = body.get_slice(" ", 0)
		var word: String = _between(body, "\"", "\"")
		if nm != "" and word != "":
			return make_event("lexicon", day, {"a": nm, "c": word})
		return {}
	# Deaths and hatchings are recorded live from signals; only the backfill
	# recovers them from text.
	if for_backfill:
		if low.begins_with("first fry hatched"):
			return make_event("first_hatch", day, {"as": _between(text, "a baby ", ".")})
		if low.contains(" has passed") or low.contains(" lived in this tank"):
			var nm2: String = text.get_slice(",", 0).get_slice(" lived", 0).strip_edges()
			var sp2: String = _between(text, ", a ", ", has passed")
			if nm2 != "" and nm2.length() <= 24:
				return make_event("death", day, {"a": nm2, "as": sp2, "c": "unknown"})
	return {}


static func _between(s: String, a: String, b: String) -> String:
	var i: int = s.find(a)
	if i < 0:
		return ""
	var start: int = i + a.length()
	var j: int = s.find(b, start)
	if j < 0:
		return s.substr(start).strip_edges()
	return s.substr(start, j - start).strip_edges()


# =============================================================================
# PURE CORE — persistence
# =============================================================================

static func to_save(state: Dictionary) -> Dictionary:
	var out: Dictionary = state.duplicate(true)
	out["v"] = SCHEMA_VERSION
	return out


# Restore from a save. `raw` is the "chronicle" value (or null). When it is
# missing or an older shape, backfill from story_events and fish legacies.
# A NEWER schema is not guessed at: the chronicle starts fresh but the raw
# data is kept under "future" so this build's autosave does not destroy it.
static func from_save(raw: Variant, story_events: Array = [], legacies: Array = []) -> Dictionary:
	if raw is Dictionary and int((raw as Dictionary).get("v", 0)) == SCHEMA_VERSION:
		return _sanitize(raw as Dictionary)
	if raw is Dictionary and int((raw as Dictionary).get("v", 0)) > SCHEMA_VERSION:
		var fresh: Dictionary = new_state()
		fresh["future"] = (raw as Dictionary).duplicate(true)
		return fresh
	return backfill(story_events, legacies)


static func _sanitize(d: Dictionary) -> Dictionary:
	var s: Dictionary = new_state()
	for key in s.keys():
		if d.has(key) and typeof(d[key]) == typeof(s[key]):
			s[key] = (d[key] as Variant)
		elif d.has(key) and (s[key] is int) and (d[key] is float):
			s[key] = int(d[key])
	s = s.duplicate(true)
	s["v"] = SCHEMA_VERSION
	# JSON hands every number back as a float; events, chapters and cast hold
	# only ints, and prose formats them ("Day 5", not "Day 5.0").
	for key in ["chapters", "open", "cast", "pairs", "species_seen"]:
		s[key] = _intify(s[key])
	var chapters: Array = []
	for c in s["chapters"]:
		if c is Dictionary and (c as Dictionary).get("ev", null) is Array:
			chapters.append(c)
	while chapters.size() > MAX_CHAPTERS:
		chapters.pop_front()
	s["chapters"] = chapters
	var open: Variant = s.get("open", null)
	if not (open is Dictionary) or not ((open as Dictionary).get("ev", null) is Array):
		s["open"] = _new_open(1)
	else:
		var evs: Array = (open as Dictionary)["ev"]
		while evs.size() > MAX_CH_EVENTS:
			evs.pop_front()
		if not ((open as Dictionary).get("over", null) is Dictionary):
			(open as Dictionary)["over"] = {}
	if (s["cast"] as Dictionary).size() > MAX_CAST:
		_prune_cast(s["cast"])
	var pairs: Dictionary = s["pairs"]
	while pairs.size() > MAX_PAIRS:
		pairs.erase(pairs.keys()[0])
	var next_idx: int = int(s.get("next_idx", 0))
	for c in chapters:
		next_idx = maxi(next_idx, int((c as Dictionary).get("i", 0)) + 1)
	s["next_idx"] = next_idx
	return s


static func _intify(v: Variant) -> Variant:
	if v is float:
		var f: float = v
		if is_finite(f) and f == floorf(f):
			return int(f)
		return f
	if v is Dictionary:
		var d: Dictionary = {}
		for k in (v as Dictionary).keys():
			d[k] = _intify((v as Dictionary)[k])
		return d
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(_intify(x))
		return a
	return v


static func backfill(story_events: Array, legacies: Array) -> Dictionary:
	var state: Dictionary = new_state()
	state["backfilled"] = true
	var events: Array = []
	var seen_deaths: Dictionary = {}
	for e in story_events:
		if not (e is Dictionary):
			continue
		var ev: Dictionary = classify_story(e, true)
		if ev.is_empty():
			continue
		if String(ev.get("k", "")) == "death":
			seen_deaths[String(ev.get("a", ""))] = true
		events.append(ev)
	for l in legacies:
		if not (l is Dictionary):
			continue
		var nm: String = String((l as Dictionary).get("name", ""))
		if nm == "" or seen_deaths.has(nm):
			continue
		var d: int = day_from_label(String((l as Dictionary).get("sim_day", "")), 1)
		events.append(make_event("death", d, {"a": nm, "as": String((l as Dictionary).get("species", "")),
				"ai": String((l as Dictionary).get("id", "")), "c": "unknown"}))
	# Stable sort by day so the story reads in order.
	var indexed: Array = []
	for i in range(events.size()):
		indexed.append([int((events[i] as Dictionary).get("d", 1)), i])
	indexed.sort_custom(func(a, b) -> bool:
		if int(a[0]) != int(b[0]):
			return int(a[0]) < int(b[0])
		return int(a[1]) < int(b[1]))
	for pair in indexed:
		record(state, events[int(pair[1])])
	if not story_events.is_empty() and story_events[-1] is Dictionary:
		var last: Dictionary = story_events[-1]
		state["story_sig"] = {"t": float(last.get("t", -1.0)), "x": String(last.get("text", ""))}
	return state


static func format_gap(s: int) -> String:
	if s < 3600:
		return "%d minutes" % int(round(s / 60.0))
	if s < 86400:
		var h: float = s / 3600.0
		return "%.1f hours" % h if h < 10.0 else "%d hours" % int(round(h))
	return "%.1f days" % (float(s) / 86400.0)


# =============================================================================
# WATCHER — attach / save hooks (called from SaveManager)
# =============================================================================

var data: Dictionary = {}
var _sim: Node = null
var _story_acc: float = 0.0
var _social_acc: float = 0.0
var _last_toast_ms: int = -TOAST_COOLDOWN_MS
var _prose_cache: Dictionary = {}
var _pending_keeper: Dictionary = {}
var _away: Dictionary = {}
var _signals_bound: bool = false


static func for_sim(sim: Node) -> Node:
	if sim == null or not is_instance_valid(sim):
		return null
	if sim.has_meta(META_KEY):
		var n: Variant = sim.get_meta(META_KEY)
		if is_instance_valid(n) and n is Node:
			return n
	return null


static func attach(sim: Node) -> Node:
	if sim == null or not is_instance_valid(sim):
		return null
	var existing: Node = for_sim(sim)
	if existing != null:
		return existing
	var scr: GDScript = load(SCRIPT_PATH) as GDScript
	var w: Node = scr.new()
	w.name = NODE_NAME
	w.set("_sim", sim)
	w.set("data", new_state())
	sim.set_meta(META_KEY, w)
	w.call("_seed_founders")
	sim.add_child.call_deferred(w)
	return w


static func save_for(sim: Node) -> Dictionary:
	var w: Node = for_sim(sim)
	if w == null:
		return {}
	w.call("_flush_pending_keeper")
	return to_save(w.get("data"))


# After sim.load_state(d). Replaces whatever the watcher collected before the
# load (a fresh spawn the save then overwrote).
static func load_for(sim: Node, d: Dictionary) -> void:
	var w: Node = attach(sim)
	if w == null:
		return
	var story: Array = sim.get("story_events") if sim.get("story_events") is Array else []
	var legacies: Array = sim.get("_fish_legacies") if sim.get("_fish_legacies") is Array else []
	var st: Dictionary = from_save(d.get("chronicle", null), story, legacies)
	if bool(st.get("backfilled", false)):
		var tm: Variant = sim.get("_tank_mind")
		if tm is Dictionary:
			st["keeper_turns"] = int((tm as Dictionary).get("keeper_turns", 0))
		for f in _fish_of(sim):
			w.call("_register_known", f)
	w.set("data", st)
	w.call("_invalidate")
	var saved_unix: int = int(d.get("saved_unix", 0))
	if saved_unix > 0:
		var gap: int = int(Time.get_unix_time_from_system()) - saved_unix
		if gap >= AWAY_MIN_GAP_S:
			w.call("begin_away", gap)


static func _fish_of(sim: Node) -> Array:
	var out: Array = []
	var arr: Variant = sim.get("fish")
	if arr is Array:
		for f in arr:
			if f != null and is_instance_valid(f):
				out.append(f)
	return out


# =============================================================================
# WATCHER — lifecycle
# =============================================================================

func _ready() -> void:
	_bind_signals()
	set_process(true)


func _exit_tree() -> void:
	if _sim != null and is_instance_valid(_sim) and _sim.has_meta(META_KEY) \
			and _sim.get_meta(META_KEY) == self:
		_sim.remove_meta(META_KEY)


func _bind_signals() -> void:
	if _signals_bound or _sim == null:
		return
	_signals_bound = true
	if _sim.has_signal("creature_added"):
		_sim.connect("creature_added", _on_creature_added)
	if _sim.has_signal("creature_removed"):
		_sim.connect("creature_removed", _on_creature_removed)
	if _sim.has_signal("fish_thought_spoke"):
		_sim.connect("fish_thought_spoke", _on_fish_thought)


func _process(dt: float) -> void:
	if _sim == null or not is_instance_valid(_sim):
		return
	_story_acc += dt
	_social_acc += dt
	if _story_acc >= STORY_POLL_S:
		_story_acc = 0.0
		_poll_story()
		_poll_keeper()
		if not _pending_keeper.is_empty() \
				and Time.get_ticks_msec() - int(_pending_keeper.get("ms", 0)) > KEEPER_REPLY_WINDOW_MS:
			_flush_pending_keeper()
		if not _away.is_empty() and Time.get_ticks_msec() >= int(_away.get("until", 0)):
			_finish_away()
		elif _away.is_empty():
			_after_record(tick_day(data, _day()))
	if _social_acc >= SOCIAL_POLL_S:
		_social_acc = 0.0
		_poll_social()


func _day() -> int:
	if _sim != null and _sim.has_method("sim_day"):
		return int(_sim.call("sim_day")) + 1
	return 1


func _invalidate() -> void:
	_prose_cache.clear()


func _record(ev: Dictionary) -> void:
	if ev.is_empty():
		return
	_after_record(record(data, ev))
	_prose_cache.erase("open")


func _after_record(closed_idx: int) -> void:
	if closed_idx < 0:
		return
	_prose_cache.erase("open")
	var ch: Dictionary = chapter_by_index(data, closed_idx)
	var title: String = String(ch.get("title", ""))
	chapter_closed.emit(closed_idx, title)
	_toast_chapter(title)


func _toast_chapter(title: String) -> void:
	var now: int = Time.get_ticks_msec()
	if title == "" or now - _last_toast_ms < TOAST_COOLDOWN_MS:
		return
	var host: Node = _host()
	if host == null or not host.has_method("_push_notification"):
		return
	_last_toast_ms = now
	var name_part: String = title.get_slice(" — ", 1) if title.contains(" — ") else title
	host.call("_push_notification", "milestone", "info",
			"A chapter closes: %s" % name_part, "Read it in the Chronicle (L).", true,
			{"chronicle": true})


func _host() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().current_scene


# ---- fish identity ------------------------------------------------------------

func _fish_id(f: Node) -> String:
	if f == null or f.get("id") == null:
		return ""
	var id: String = String(f.get("id"))
	if id == "" and _sim != null and _sim.has_method("mint_id"):
		id = String(_sim.call("mint_id"))
		f.set("id", id)
	return id


func _is_fish(c: Node) -> bool:
	return c != null and is_instance_valid(c) and c.get("fish_name") != null \
			and c.get("generation") != null and c.get("species") != null


func _fields_for(f: Node, prefix: String = "a") -> Dictionary:
	return {
		prefix: String(f.get("fish_name")),
		prefix + "s": String(f.get("species")),
		prefix + "i": _fish_id(f),
	}


func _register_known(f: Node) -> void:
	# Put a living fish in the cast without an event (backfilled saves).
	if not _is_fish(f):
		return
	var key: String = _fish_id(f)
	if key == "":
		return
	var cast: Dictionary = data.get("cast", {})
	if not cast.has(key):
		cast[key] = {"n": String(f.get("fish_name")), "s": String(f.get("species")),
				"f": _day(), "g": int(f.get("generation"))}
		data["cast"] = cast


func _seed_founders() -> void:
	for f in _fish_of(_sim):
		if not _is_fish(f):
			continue
		var fields: Dictionary = _fields_for(f)
		fields["x"] = int(f.get("sex")) if f.get("sex") != null else 0
		var intro: String = intro_line(f)
		if intro != "":
			fields["i"] = intro
		_record(make_event("arrive", _day(), fields))


# ---- signal handlers ----------------------------------------------------------

func _on_creature_added(c: Node) -> void:
	# Deferred one frame: the fish generates its backstory as it settles in.
	_handle_added.call_deferred(c)


func _handle_added(c: Variant) -> void:
	if c == null or not is_instance_valid(c) or not (c is Node) or not _is_fish(c as Node):
		return
	_add_fish(c as Node)


func _add_fish(c: Node) -> void:
	var key: String = _fish_id(c)
	if key != "" and (data.get("cast", {}) as Dictionary).has(key):
		return
	var day: int = _day()
	var fields: Dictionary = _fields_for(c)
	fields["x"] = int(c.get("sex")) if c.get("sex") != null else 0
	var gen: int = int(c.get("generation"))
	var intro: String = intro_line(c)
	if intro != "":
		fields["i"] = intro
	if gen <= 0:
		_record(make_event("arrive", day, fields))
		return
	fields["g"] = gen
	# Real lineage from the backstory when it has it; nearest-adult guess
	# otherwise.
	var par: Array = FishBackstoryScript.parents(c)
	var mom: Node = null
	if par.is_empty():
		mom = _infer_mother(c)
	if not par.is_empty():
		var p0: Dictionary = {}
		if par[0] is Dictionary:
			p0 = par[0]
		fields["b"] = String(p0.get("name", ""))
		fields["bs"] = String(c.get("species"))
		fields["bi"] = String(p0.get("id", ""))
		if par.size() > 1 and par[1] is Dictionary:
			fields["c"] = String((par[1] as Dictionary).get("name", ""))
	elif mom != null:
		var mf: Dictionary = _fields_for(mom, "b")
		fields.merge(mf)
		var dad: Variant = mom.get("partner")
		if dad == null or not is_instance_valid(dad):
			dad = mom.get("_cached_breed_partner")
		if dad != null and is_instance_valid(dad) and _is_fish(dad):
			fields["c"] = String((dad as Node).get("fish_name"))
	_record(make_event("birth", day, fields))
	# First spawn of a species this chronicle has seen breed.
	var seen: Dictionary = data.get("species_seen", {})
	var sp: String = String(c.get("species"))
	if not seen.has(sp):
		seen[sp] = day
		data["species_seen"] = seen


# One grounded backstory sentence for a character's first appearance, or "".
# Founders and adoptees get their origin; fry (whose origin already names
# their parents) get a like/fear or a quirk.
static func intro_line(f: Object) -> String:
	if f == null or not FishBackstoryScript.has_story(f):
		return ""
	var nm: String = String(f.get("fish_name")) if f.get("fish_name") != null else ""
	if nm == "":
		return ""
	var st: Dictionary = FishBackstoryScript.story(f)
	var options: Array[String] = []
	var origin: String = String(st.get("origin", ""))
	var otext: String = _unpunct(FishBackstoryScript.origin_text(f))
	if origin != "bred" and otext != "":
		options.append("%s %s." % [nm, otext.substr(0, 1).to_lower() + otext.substr(1)])
	var like: String = FishBackstoryScript.like_phrase(f)
	var fear: String = FishBackstoryScript.fear_phrase(f)
	if like != "" and fear != "":
		options.append("From the start %s loved %s and kept clear of %s." % [nm, like, fear])
	var q: String = _unpunct(FishBackstoryScript.quirk(f))
	if q != "":
		options.append("Even then, %s %s." % [nm, q])
	if options.is_empty():
		return ""
	var pick: String = options[_h([nm, String(f.get("id")) if f.get("id") != null else ""]) % options.size()]
	return pick.substr(0, MAX_TEXT)


func _infer_mother(fry: Node) -> Node:
	var best: Node = null
	var best_score: float = INF
	var sp: String = String(fry.get("species"))
	var gen: int = int(fry.get("generation"))
	var fpos: Vector3 = Vector3.ZERO
	var has_pos: bool = fry is Node3D and (fry as Node3D).is_inside_tree()
	if has_pos:
		fpos = (fry as Node3D).global_position
	for f in _fish_of(_sim):
		if f == fry or not _is_fish(f) or String(f.get("species")) != sp:
			continue
		if bool(f.get("_dying")):
			continue
		var score: float = 0.0
		if int(f.get("generation")) != gen - 1:
			score += 50.0
		if f.get("sex") != null and int(f.get("sex")) != 1:
			score += 20.0
		if f.get("age") != null and fry.get("age") != null and float(f.get("age")) <= float(fry.get("age")):
			score += 100.0
		if has_pos and f is Node3D and (f as Node3D).is_inside_tree():
			score += (f as Node3D).global_position.distance_to(fpos) * 4.0
		if score < best_score:
			best_score = score
			best = f
	if best_score >= 100.0:
		return null
	return best


func _on_creature_removed(c: Node) -> void:
	if not _is_fish(c) or not bool(c.get("_dying")):
		return
	_note_death(c, _death_cause(c), null)


# Called by sim_driver's kill_prey path (prey is freed without the dying
# animation, so creature_removed alone never reports it).
static func note_predation(sim: Node, predator: Node, prey: Node) -> void:
	var w: Node = for_sim(sim)
	if w == null or prey == null or not is_instance_valid(prey):
		return
	w.call("_on_predation", predator, prey)


func _on_predation(predator: Node, prey: Node) -> void:
	if not _is_fish(prey):
		return
	_note_death(prey, "predation", predator)


func _note_death(c: Node, cause: String, predator: Node) -> void:
	var day: int = _day()
	var fields: Dictionary = _fields_for(c)
	fields["c"] = cause
	if predator != null and is_instance_valid(predator) and predator.get("fish_name") != null \
			and predator.get("species") != null:
		fields["b"] = String(predator.get("fish_name"))
		fields["bs"] = String(predator.get("species"))
	_record(make_event("death", day, fields))
	# Lineage fall / lone survivor.
	var sp: String = String(c.get("species"))
	var left: Array = []
	for f in _fish_of(_sim):
		if f != c and _is_fish(f) and String(f.get("species")) == sp and not bool(f.get("_dying")):
			left.append(f)
	if left.is_empty():
		_record(make_event("extinct", day, {"a": String(c.get("fish_name")), "as": sp}))
	elif left.size() == 1 and _recent_deaths_of(sp) >= 2:
		var lf: Dictionary = _fields_for(left[0])
		_record(make_event("lone", day, lf))


func _recent_deaths_of(sp: String) -> int:
	var n: int = 0
	for e in (data["open"] as Dictionary).get("ev", []):
		if String((e as Dictionary).get("k", "")) == "death" and String((e as Dictionary).get("as", "")) == sp:
			n += 1
	return n


func _death_cause(c: Node) -> String:
	if c.get("age") != null and c.get("max_age_s") != null and float(c.get("max_age_s")) > 0.0 \
			and float(c.get("age")) >= float(c.get("max_age_s")):
		return "age"
	if c.get("hunger") != null and float(c.get("hunger")) > 0.8:
		return "hunger"
	if _sim != null and _sim.get("dissolved_o2") != null \
			and clampf(float(_sim.get("dissolved_o2")) / 1.2, 0.0, 1.0) < 0.38:
		return "breath"
	return "illness"


func _on_fish_thought(speaker: Variant, text: Variant) -> void:
	if _pending_keeper.is_empty() or _pending_keeper.has("a"):
		return
	if speaker == null or not is_instance_valid(speaker) or not _is_fish(speaker):
		return
	_pending_keeper["a"] = String((speaker as Node).get("fish_name"))
	_pending_keeper["as"] = String((speaker as Node).get("species"))
	_pending_keeper["e"] = String(text)
	_flush_pending_keeper()


# ---- polling ------------------------------------------------------------------

func _poll_story() -> void:
	var arr: Variant = _sim.get("story_events")
	if not (arr is Array):
		return
	var events: Array = arr
	if events.is_empty():
		return
	var sig: Dictionary = data.get("story_sig", {"t": -1.0, "x": ""})
	var last_t: float = float(sig.get("t", -1.0))
	var last_x: String = String(sig.get("x", ""))
	var start: int = -1
	# Find the last consumed entry scanning back from the end (story_events is
	# a capped FIFO, so indices shift but entries do not change).
	for i in range(events.size() - 1, -1, -1):
		var e: Dictionary = events[i]
		if float(e.get("t", -2.0)) == last_t and String(e.get("text", "")) == last_x:
			start = i + 1
			break
		if float(e.get("t", 0.0)) < last_t:
			start = i + 1
			break
	if start < 0:
		start = 0
	if start >= events.size():
		return
	for i in range(start, events.size()):
		var e2: Dictionary = events[i]
		var ev: Dictionary = classify_story(e2)
		if not ev.is_empty():
			if String(ev.get("k", "")) == "first_spawn":
				var sp: String = String(ev.get("as", ""))
				var seen: Dictionary = data.get("species_seen", {})
				seen[sp] = int(ev.get("d", 1))
				data["species_seen"] = seen
			_record(ev)
	var tail: Dictionary = events[-1]
	data["story_sig"] = {"t": float(tail.get("t", -1.0)), "x": String(tail.get("text", ""))}


func _poll_keeper() -> void:
	var tm: Variant = _sim.get("_tank_mind")
	if not (tm is Dictionary):
		return
	var turns: int = int((tm as Dictionary).get("keeper_turns", 0))
	var seen: int = int(data.get("keeper_turns", 0))
	if turns < seen:
		data["keeper_turns"] = turns
		return
	if turns == seen:
		return
	data["keeper_turns"] = turns
	_flush_pending_keeper()
	var recent: Variant = (tm as Dictionary).get("keeper_recent_lines", [])
	var reply: String = ""
	if recent is Array and not (recent as Array).is_empty():
		reply = String((recent as Array)[-1])
	_pending_keeper = {
		"ms": Time.get_ticks_msec(),
		"c": String((tm as Dictionary).get("last_keeper_text", "")),
		"r": reply,
	}


func _flush_pending_keeper() -> void:
	if _pending_keeper.is_empty():
		return
	var p: Dictionary = _pending_keeper
	_pending_keeper = {}
	if String(p.get("c", "")) == "":
		return
	var fields: Dictionary = {"c": String(p.get("c", "")), "r": String(p.get("r", ""))}
	if p.has("a"):
		fields["a"] = String(p["a"])
		fields["as"] = String(p.get("as", ""))
		fields["e"] = String(p.get("e", ""))
	_record(make_event("keeper_talk", _day(), fields))


func _poll_social() -> void:
	var fish_list: Array = _fish_of(_sim)
	if fish_list.is_empty():
		return
	var by_id: Dictionary = {}
	for f in fish_list:
		if _is_fish(f) and String(f.get("id")) != "":
			by_id[String(f.get("id"))] = f
	var day: int = _day()
	var budget: int = 160
	for f in fish_list:
		budget -= 1
		if budget <= 0:
			break
		if not _is_fish(f) or bool(f.get("_dying")):
			continue
		var fid: String = String(f.get("id"))
		if fid == "":
			continue
		var partner: Variant = f.get("partner")
		if partner != null and is_instance_valid(partner) and _is_fish(partner):
			var pid: String = _fish_id(partner)
			if pid != "" and fid < pid and note_pair(data, "%s|%s" % [fid, pid], "pair"):
				var fields: Dictionary = _fields_for(f)
				fields.merge(_fields_for(partner, "b"))
				_record(make_event("pair", day, fields))
		# Friendships / rivalries / grief come from FishSocial (the social
		# graph over Fish.bonds), read-only.
		var rels: Array = [
			[FishSocialScript.best_friend(f), "bond", BOND_THRESHOLD],
			[FishSocialScript.rival(f), "rival", RIVAL_THRESHOLD],
		]
		for rel in rels:
			var d: Dictionary = rel[0]
			var kind: String = String(rel[1])
			if d.is_empty() or not bool(d.get("alive", true)):
				continue
			var aff: float = float(d.get("affinity", 0.0))
			if (kind == "bond" and aff < float(rel[2])) or (kind == "rival" and aff > float(rel[2])):
				continue
			var oid: String = String(d.get("id", ""))
			if oid == "" or not by_id.has(oid):
				continue
			var tags: Array = d.get("tags", []) as Array
			if kind == "bond" and (tags.has("mate") or tags.has("parent") or tags.has("offspring")):
				continue
			var a_id: String = fid if fid < oid else oid
			var b_id: String = oid if fid < oid else fid
			if not note_pair(data, "%s|%s" % [a_id, b_id], kind):
				continue
			var fields2: Dictionary = _fields_for(f)
			fields2.merge(_fields_for(by_id[oid], "b"))
			if kind == "rival" and tags.has("chased_me"):
				fields2["e"] = "chased"
			_record(make_event(kind, day, fields2))
		var grief: Dictionary = FishSocialScript.grieving_for(f)
		if not grief.is_empty() and float(grief.get("level", 0.0)) >= GRIEF_THRESHOLD \
				and String(grief.get("name", "")) != "":
			if note_pair(data, "%s|%s" % [fid, String(grief.get("id", ""))], "grief"):
				var gf: Dictionary = _fields_for(f)
				gf["b"] = String(grief.get("name", ""))
				_record(make_event("grief", day, gf))


# ---- away ---------------------------------------------------------------------

func begin_away(gap_s: int) -> void:
	# The chapter in progress ends where you left; the time away is its own.
	var day: int = _day()
	_after_record(close_open(data, day))
	var open: Dictionary = data["open"]
	open["away"] = {"gap": gap_s, "h": format_gap(gap_s)}
	open["d0"] = day
	_away = {"until": Time.get_ticks_msec() + AWAY_WINDOW_MS}
	_prose_cache.erase("open")


func _finish_away() -> void:
	_away = {}
	_poll_story()
	var day: int = _day()
	var lines: PackedStringArray = PackedStringArray()
	if _sim != null:
		lines = TankMindScript.away_recap_lines(_sim)
	var added: int = 0
	var seen: Dictionary = {}
	for l in lines:
		var s: String = String(l).strip_edges()
		if s == "" or s.begins_with("the keeper spoke") or seen.has(s):
			continue
		seen[s] = true
		record(data, make_event("ledger", day, {"c": s}))
		added += 1
		if added >= 3:
			break
	var open: Dictionary = data["open"]
	if (open["ev"] as Array).is_empty():
		record(data, make_event("ledger", day, {"c": "the water held steady and nobody was lost"}))
	_after_record(close_open(data, day))


# ---- panel API ----------------------------------------------------------------

func chapter_count() -> int:
	return (data.get("chapters", []) as Array).size()


func has_open_content() -> bool:
	return not ((data.get("open", {}) as Dictionary).get("ev", []) as Array).is_empty()


# Views in reading order: every closed chapter, then the open one if it has
# anything in it. Each is chapter_prose() output, built lazily and cached.
func view_count() -> int:
	return chapter_count() + (1 if has_open_content() else 0)


func view_at(pos: int) -> Dictionary:
	var chapters: Array = data.get("chapters", [])
	if pos < chapters.size():
		var ch: Dictionary = chapters[pos]
		var key: String = "c%d" % int(ch.get("i", 0))
		if not _prose_cache.has(key):
			_prose_cache[key] = chapter_prose(data, ch)
		return _prose_cache[key]
	if not _prose_cache.has("open"):
		_prose_cache["open"] = chapter_prose(data, open_as_chapter(data))
	return _prose_cache["open"]


func dropped_count() -> int:
	return int(data.get("dropped", 0))
