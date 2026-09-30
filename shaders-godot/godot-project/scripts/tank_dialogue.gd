extends RefCounted

# Keeper ↔ tank conversation memory, promises, fish-to-fish follow-ups, and
# tank-initiated lines. Pure template logic (no LLM, no I/O) so it is safe on
# the main thread and deterministic enough to smoke-test.
#
# Persistence: the memory lives in tm["keeper_memory"] (tm = sim._tank_mind),
# which TankMind.to_dict/from_dict already carry through save_state/load_state.
# It is bounded (ENTRIES_MAX / PROMISES_MAX) and versioned (MEMORY_VERSION);
# migrate() upgrades old saves that lack it.
#
# Deliberately does NOT preload tank_mind.gd (tank_mind preloads this file);
# callers pass the tm dictionary and the TankMind.keeper_state() snapshot.
#
# Also: overheard fish-to-fish chatter while the keeper is silent, the tank's
# night dreams (recombined from the day's real events) and the grounded
# answers to "what are you thinking / dreaming / who is your friend /
# tell me about <fish>".

const FishSocial = preload("res://scripts/fish_social.gd")
const _Backstory = preload("res://scripts/fish_backstory.gd")
# Fish ask the keeper (questions + remembered answers). Preloads neither this
# file nor tank_mind.gd, so there is no cycle.
const TankQuestions = preload("res://scripts/tank_questions.gd")

const MEMORY_VERSION: int = 1
const ENTRIES_MAX: int = 16
const PROMISES_MAX: int = 6
const TEXT_MAX: int = 60
# An earlier line must be at least this old (seconds) before the tank calls
# back to it — otherwise "you asked about food earlier" fires on the next line.
const CALLBACK_MIN_AGE_S: float = 45.0
# Turns between topic callbacks (promise outcomes are exempt).
const CALLBACK_TURN_GAP: int = 2
const PROMISE_WINDOW_S: Dictionary = {"feed": 600.0, "water": 1200.0, "air": 900.0}

# Fish follow-ups (a second fish reacting to the first fish's reply).
const FOLLOWUPS_MAX: int = 2
const FOLLOWUP_CHANCE: Array = [0.55, 0.3]
const FOLLOWUP_MIN_GAP_MS: int = 2500
const FOLLOWUP_EXCHANGE_WINDOW_MS: int = 45000

# Tank-initiated lines.
const INIT_KEEPER_QUIET_S: float = 45.0
const INIT_MIN_GAP_S: float = 150.0
const INIT_KIND_COOLDOWN_S: float = 480.0
const INIT_PENDING_TTL_S: float = 180.0
const INIT_ABSENCE_S: float = 900.0
const INIT_RETURN_GAP_S: float = 6.0 * 3600.0
const INIT_PRIORITY: Array = ["o2_low", "death", "birth", "arrival", "promise", "dream", "absence"]

# One id per process: entries from another session read as "last time".
static var session_id: String = ""


static func _session() -> String:
	if session_id == "":
		session_id = "%d-%d" % [int(Time.get_unix_time_from_system()), randi() % 100000]
	return session_id


static func _unix() -> float:
	return float(Time.get_unix_time_from_system())


# Sim clock for promise deadlines (tank_age_s advances only while simulated).
static func _age(sim) -> float:
	var v: Variant = sim.get("tank_age_s") if sim != null else null
	if v == null or v is Callable:
		return _unix()
	return float(v)


static func default_memory() -> Dictionary:
	return {
		"v": MEMORY_VERSION,
		"entries": [],
		"promises": [],
		"topic_counts": {},
		"turns": 0,
		"last_callback_turn": -99,
		"last_keeper_unix": 0,
		"kept": 0,
		"broken": 0,
	}


# Upgrade tm in place so it always carries a valid, bounded keeper_memory.
# Old saves (pre-memory) get a fresh ledger, seeded with the last keeper line
# the tank remembers if there was one.
static func migrate(tm: Dictionary) -> Dictionary:
	var raw: Variant = tm.get("keeper_memory", null)
	var mem: Dictionary
	if not (raw is Dictionary):
		mem = default_memory()
		var last_text: String = str(tm.get("last_keeper_text", "")).strip_edges()
		if last_text != "":
			(mem["entries"] as Array).append({"t": 0.0, "s": "legacy", "text": last_text.substr(0, TEXT_MAX),
					"topics": [], "feel": "calm", "valence": 0.0, "said": ""})
	else:
		mem = raw as Dictionary
		var dm: Dictionary = default_memory()
		for k in dm:
			if not mem.has(k):
				mem[k] = dm[k]
		for k in ["entries", "promises"]:
			if not (mem[k] is Array):
				mem[k] = []
		if not (mem["topic_counts"] is Dictionary):
			mem["topic_counts"] = {}
		mem["v"] = MEMORY_VERSION
	var entries: Array = mem["entries"]
	while entries.size() > ENTRIES_MAX:
		entries.pop_front()
	var promises: Array = mem["promises"]
	while promises.size() > PROMISES_MAX:
		promises.pop_front()
	tm["keeper_memory"] = mem
	# The questions ledger rides along (versioned + bounded the same way).
	TankQuestions.migrate(tm)
	return mem


static func memory(tm: Dictionary) -> Dictionary:
	var raw: Variant = tm.get("keeper_memory", null)
	if raw is Dictionary and int((raw as Dictionary).get("v", 0)) == MEMORY_VERSION:
		return raw as Dictionary
	return migrate(tm)


# How the tank feels right now, as one word (stored per ledger entry).
static func feel_word(st: Dictionary) -> String:
	if float(st.get("o2", 1.0)) < 0.45:
		return "breathless"
	if float(st.get("ammonia", 0.0)) >= 0.18 or float(st.get("nitrite", 0.0)) >= 0.18:
		return "stung"
	if float(st.get("avg_hunger", 0.0)) > 0.55:
		return "hungry"
	if float(st.get("max_stress", 0.0)) > 0.55 or float(st.get("avg_stress", 0.0)) > 0.35:
		return "uneasy"
	if float(st.get("daylight", 1.0)) < 0.28:
		return "sleepy"
	return "calm"


static func _bad_feel(w: String) -> bool:
	return w in ["breathless", "stung", "hungry", "uneasy"]


# --- Promises -------------------------------------------------------------

static var _promise_res: Dictionary = {}


static func _re(key: String, pattern: String) -> RegEx:
	if not _promise_res.has(key):
		var r := RegEx.new()
		r.compile(pattern)
		_promise_res[key] = r
	return _promise_res[key]


# "i'll feed you soon" → "feed". "" when the line holds no keeper promise.
static func detect_promise(text: String) -> String:
	var t: String = " %s " % text.to_lower().replace("’", "'")
	if "?" in t and not (" i'll " in t or " i will " in t):
		return ""
	var first_person: String = "(i'll|i will|i'm going to|im going to|i'm gonna|im gonna|gonna|going to|let me|i'm about to|ill)"
	if _re("feed", "\\b%s\\b.*\\b(feed|food|flakes|pellets|dinner|snack|breakfast)" % first_person).search(t) != null \
			or _re("feed_soon", "\\b(food|feeding|dinner|flakes|pellets)\\b.*\\b(soon|coming|on the way|in a (bit|minute|sec|moment))\\b").search(t) != null:
		return "feed"
	if _re("air", "\\b%s\\b.*\\b(air|oxygen|aerat\\w*|bubbl\\w*|pump|airstone)" % first_person).search(t) != null:
		return "air"
	if _re("water", "\\b%s\\b.*\\b(water|clean|ammonia|nitrate|nitrite|filter)" % first_person).search(t) != null:
		return "water"
	return ""


static func _promise_baseline(sim, st: Dictionary) -> Dictionary:
	var feed_unix: Variant = sim.get("_last_feed_unix") if sim != null else null
	return {
		"feed_unix": int(feed_unix) if feed_unix != null else 0,
		"nitrate": float(st.get("nitrate", 0.0)),
		"toxic": float(st.get("ammonia", 0.0)) + float(st.get("nitrite", 0.0)),
		"o2": float(st.get("o2", 1.0)),
	}


static func add_promise(sim, mem: Dictionary, kind: String, text: String, st: Dictionary) -> void:
	var promises: Array = mem["promises"]
	for p in promises:
		if p is Dictionary and str(p.get("kind", "")) == kind and str(p.get("status", "")) == "open":
			# Repeating a promise just extends it.
			p["age"] = _age(sim)
			return
	promises.append({
		"kind": kind,
		"status": "open",
		"t": _unix(),
		"age": _age(sim),
		"text": text.strip_edges().substr(0, TEXT_MAX),
		"base": _promise_baseline(sim, st),
		"told": false,
	})
	while promises.size() > PROMISES_MAX:
		promises.pop_front()


static func _water_changed_since(sim, age: float) -> bool:
	var ev: Variant = sim.get("story_events") if sim != null else null
	if not (ev is Array):
		return false
	for i in range((ev as Array).size() - 1, maxi(-1, (ev as Array).size() - 12), -1):
		var e: Variant = (ev as Array)[i]
		if e is Dictionary and str((e as Dictionary).get("text", "")).begins_with("Water change") \
				and float((e as Dictionary).get("tank_age_s", -1.0)) >= age:
			return true
	return false


static func _promise_kept(sim, p: Dictionary, st: Dictionary) -> bool:
	var base: Dictionary = {}
	var base_v: Variant = p.get("base", null)
	if base_v is Dictionary:
		base = base_v as Dictionary
	match str(p.get("kind", "")):
		"feed":
			var fu: Variant = sim.get("_last_feed_unix") if sim != null else null
			return fu != null and int(fu) > int(base.get("feed_unix", 0)) \
					and float(fu) >= float(p.get("t", 0.0)) - 1.0
		"water":
			if _water_changed_since(sim, float(p.get("age", 0.0))):
				return true
			var n0: float = float(base.get("nitrate", 0.0))
			if n0 > 0.05 and float(st.get("nitrate", 0.0)) <= n0 * 0.8:
				return true
			var tox0: float = float(base.get("toxic", 0.0))
			var tox: float = float(st.get("ammonia", 0.0)) + float(st.get("nitrite", 0.0))
			return tox0 >= 0.15 and tox < 0.08
		"air":
			var o0: float = float(base.get("o2", 1.0))
			return float(st.get("o2", 0.0)) >= maxf(o0 + 0.1, 0.6)
	return false


# Resolve open promises (kept / broken). Returns the promises that changed
# status this call. Mood nudges are applied to tm.
static func update_promises(sim, tm: Dictionary, st: Dictionary) -> Array:
	var mem: Dictionary = memory(tm)
	var changed: Array = []
	var now_age: float = _age(sim)
	for p in mem["promises"]:
		if not (p is Dictionary) or str(p.get("status", "")) != "open":
			continue
		if _promise_kept(sim, p, st):
			p["status"] = "kept"
			mem["kept"] = int(mem.get("kept", 0)) + 1
			tm["mood_valence"] = clampf(float(tm.get("mood_valence", 0.0)) + 0.05, -1.0, 1.0)
			note_dream_seed(tm, "promise_kept", "", str(p.get("kind", "")), 0.6)
			changed.append(p)
		elif now_age - float(p.get("age", now_age)) > float(PROMISE_WINDOW_S.get(str(p.get("kind", "")), 900.0)):
			p["status"] = "broken"
			mem["broken"] = int(mem.get("broken", 0)) + 1
			tm["mood_valence"] = clampf(float(tm.get("mood_valence", 0.0)) - 0.04, -1.0, 1.0)
			note_dream_seed(tm, "promise_broken", "", str(p.get("kind", "")), 0.6)
			changed.append(p)
	return changed


static func _promise_phrase(kind: String) -> String:
	match kind:
		"feed":
			return "feed us"
		"air":
			return "help us breathe"
		_:
			return "fix the water"


static func promise_outcome_line(p: Dictionary) -> String:
	var what: String = _promise_phrase(str(p.get("kind", "")))
	if str(p.get("status", "")) == "kept":
		return ["you said you'd %s — and you did" % what,
				"you promised to %s. you kept it" % what][randi() % 2]
	return ["you said you'd %s. we waited" % what,
			"you promised to %s. it didn't come" % what][randi() % 2]


# First resolved promise the tank has not mentioned yet (marks it told).
static func take_untold_outcome(tm: Dictionary) -> String:
	var mem: Dictionary = memory(tm)
	for p in mem["promises"]:
		if p is Dictionary and str(p.get("status", "")) in ["kept", "broken"] and not bool(p.get("told", false)):
			p["told"] = true
			return promise_outcome_line(p)
	return ""


static func open_promise(tm: Dictionary, kind: String) -> Dictionary:
	for p in memory(tm)["promises"]:
		if p is Dictionary and str(p.get("kind", "")) == kind and str(p.get("status", "")) == "open":
			return p
	return {}


# --- Recording + callbacks -----------------------------------------------

# Record one keeper line (+ the tank's reply and how it felt) in the ledger.
# Returns the promise kind detected ("" if none).
static func record_keeper_line(sim, tm: Dictionary, text: String, topics: PackedStringArray,
		st: Dictionary, said: String) -> String:
	var mem: Dictionary = memory(tm)
	var entries: Array = mem["entries"]
	var tlist: Array = []
	for tp in topics:
		tlist.append(str(tp))
		var tc: Dictionary = mem["topic_counts"]
		tc[str(tp)] = int(tc.get(str(tp), 0)) + 1
	var low: String = text.to_lower()
	if ("safe" in low or "you're ok" in low or "youre ok" in low or "it's ok" in low) and not tlist.has("safe"):
		tlist.append("safe")
	entries.append({
		"t": _unix(),
		"s": _session(),
		"text": text.strip_edges().substr(0, TEXT_MAX),
		"topics": tlist,
		"feel": feel_word(st),
		"valence": snappedf(float(tm.get("mood_valence", 0.0)), 0.01),
		"said": said.strip_edges().substr(0, TEXT_MAX + 4),
	})
	while entries.size() > ENTRIES_MAX:
		entries.pop_front()
	mem["turns"] = int(mem.get("turns", 0)) + 1
	mem["last_keeper_unix"] = int(_unix())
	var kind: String = detect_promise(text)
	if kind != "":
		add_promise(sim, mem, kind, text, st)
	return kind


# A short phrase tying this reply to something the keeper said before, or ""
# when there is nothing worth recalling. Call BEFORE record_keeper_line so the
# current line is not its own "earlier".
static func callback_phrase(sim, tm: Dictionary, topics: PackedStringArray, st: Dictionary,
		now_unix: float = -1.0) -> String:
	var mem: Dictionary = memory(tm)
	var outcome: String = take_untold_outcome(tm)
	if outcome != "":
		mem["last_callback_turn"] = int(mem.get("turns", 0))
		return outcome
	var entries: Array = mem["entries"]
	if entries.is_empty():
		return ""
	if int(mem.get("turns", 0)) - int(mem.get("last_callback_turn", -99)) < CALLBACK_TURN_GAP:
		return ""
	var now: float = now_unix if now_unix >= 0.0 else _unix()
	var feel_now: String = feel_word(st)
	var out: String = ""
	# Back from another session: recall how we were last time.
	var last_e: Variant = entries[-1]
	if last_e is Dictionary and str((last_e as Dictionary).get("s", "")) != _session():
		var then: String = str((last_e as Dictionary).get("feel", "calm"))
		if then == feel_now:
			out = "you're back. last time we were %s too" % then
		else:
			out = "you're back. last time we were %s; now %s" % [then, feel_now]
	if out == "":
		var want: Array = []
		for tp in topics:
			want.append(str(tp))
		if "safe" in want or topics.has("calm"):
			want.append("safe")
		for i in range(entries.size() - 1, -1, -1):
			var e: Variant = entries[i]
			if not (e is Dictionary):
				continue
			var ed: Dictionary = e as Dictionary
			if now - float(ed.get("t", now)) < CALLBACK_MIN_AGE_S:
				continue
			var etopics: Array = []
			var et_v: Variant = ed.get("topics", null)
			if et_v is Array:
				etopics = et_v as Array
			# "you said we were safe" also answers a tank that is now in trouble.
			if etopics.has("safe") and (_bad_feel(feel_now) or want.has("safe")):
				out = "you said we were safe. we believed you" if _bad_feel(feel_now) \
						else "you said we were safe — it held"
				break
			var hit: String = ""
			for tp in etopics:
				if want.has(str(tp)) and not (str(tp) in ["greeting", "who", "safe"]):
					hit = str(tp)
					break
			if hit != "":
				out = _topic_callback(sim, hit, ed, st, now)
				if out != "":
					break
	if out != "":
		mem["last_callback_turn"] = int(mem.get("turns", 0))
	return out


static func _ago(secs: float) -> String:
	if secs < 90.0:
		return "just now"
	if secs < 3600.0:
		return "%d min ago" % int(round(secs / 60.0))
	if secs < 86400.0:
		return "%d h ago" % int(round(secs / 3600.0))
	return "days ago"


static func _topic_callback(sim, topic: String, e: Dictionary, st: Dictionary, now: float) -> String:
	var then_feel: String = str(e.get("feel", "calm"))
	match topic:
		"food":
			var fu: Variant = sim.get("_last_feed_unix") if sim != null else null
			if fu != null and float(fu) > float(e.get("t", 0.0)):
				return "you asked about food earlier — we ate %s" % _ago(now - float(fu))
			if float(st.get("avg_hunger", 0.0)) > 0.5:
				return "you asked about food earlier; we're still waiting"
			return "you asked about food earlier; we're fine for now"
		"calm":
			return "you told us to be calm before; we tried" if _bad_feel(feel_word(st)) \
					else "you told us to be calm before. we are"
		"air":
			return "you asked about the air before — o2 is %d%% now" % int(round(float(st.get("o2", 0.0)) * 100.0))
		"water":
			if float(st.get("ammonia", 0.0)) >= 0.18 or float(st.get("nitrite", 0.0)) >= 0.18:
				return "you asked about the water earlier. it still stings"
			return "you asked about the water earlier — it's clean now"
		"light":
			return "you spoke of the light before; we keep the day's rhythm"
		"love":
			return "you said something kind earlier; we kept it"
		"wellbeing":
			var now_feel: String = feel_word(st)
			if now_feel != then_feel:
				return "you asked how we were before — %s then, %s now" % [then_feel, now_feel]
			return "you asked how we were before. still %s" % now_feel
	return ""


# Most recent keeper line mentioning "safe" in this session ({} if none).
static func last_safe_claim(tm: Dictionary) -> Dictionary:
	var entries: Array = memory(tm)["entries"]
	for i in range(entries.size() - 1, -1, -1):
		var e: Variant = entries[i]
		if e is Dictionary and (e.get("topics", []) as Array).has("safe") and str(e.get("s", "")) == _session():
			return e
	return {}


# --- Fish follow-ups -------------------------------------------------------

static func begin_exchange(rt: Dictionary, responder_ids: PackedStringArray, topics: PackedStringArray,
		now_ms: int) -> void:
	rt["started_ms"] = now_ms
	rt["followups"] = 0
	rt["responders"] = responder_ids
	rt["topics"] = topics
	rt["spoken"] = []
	rt["last_ms"] = int(rt.get("last_ms", -FOLLOWUP_MIN_GAP_MS))


static func _fish_state(f: Fish) -> Dictionary:
	return {
		"hungry": f.hunger > 0.55,
		"tense": maxf(f.stress, f.spooked) > 0.45,
		"calm": maxf(f.stress, f.spooked) < 0.25,
		"bold": float(f.personality.get("boldness", 0.5)) > 0.62 if not f.personality.is_empty() else false,
		"social": float(f.personality.get("sociability", 0.5)) > 0.62 if not f.personality.is_empty() else false,
	}


static func _moniker(f: Fish) -> String:
	if f.fish_name.strip_edges() != "":
		return f.fish_name.strip_edges()
	return "the %s" % str(f.species).replace("_", " ")


static func _alive(node: Variant) -> bool:
	if node == null or not is_instance_valid(node) or not (node is Fish):
		return false
	var fn: Fish = node as Fish
	return not fn.is_queued_for_deletion() and fn.get("_dying") != true


# Which kind of reaction `b` has to `a`'s line, from their real states.
static func followup_kind(a: Fish, b: Fish, a_line: String, topics: PackedStringArray) -> String:
	var sa: Dictionary = _fish_state(a)
	var sb: Dictionary = _fish_state(b)
	var al: String = a_line.to_lower()
	var about_food: bool = topics.has("food") or al.contains("food") or al.contains("hungry") \
			or al.contains("belly") or al.contains("flakes")
	var about_fear: bool = topics.has("calm") or topics.has("air") or topics.has("water") \
			or al.contains("safe") or al.contains("tight") or al.contains("settle") or al.contains("heavy")
	if about_food or bool(sa["hungry"]):
		if bool(sa["hungry"]) == bool(sb["hungry"]):
			return "agree_hungry" if bool(sb["hungry"]) else "agree_fed"
		return "contradict_fed" if bool(sa["hungry"]) else "contradict_hungry"
	if about_fear or bool(sa["tense"]):
		if bool(sa["tense"]) and bool(sb["calm"]):
			return "contradict_calm"
		if not bool(sa["tense"]) and bool(sb["tense"]):
			return "contradict_tense"
		if bool(sb["tense"]):
			return "agree_tense"
	if bool(sb["bold"]) or bool(sb["social"]):
		return "tease"
	return "agree"


static func followup_line(kind: String, a: Fish, _b: Fish) -> String:
	var an: String = _moniker(a)
	var lines: Array = []
	match kind:
		"agree_hungry":
			lines = ["same. my belly's light too", "%s's right — food would be good" % an, "yes, what %s said. hungry" % an]
		"agree_fed":
			lines = ["we're full, %s's right" % an, "still heavy from the last meal, same as %s" % an]
		"contradict_fed":
			lines = ["%s is always hungry. I'm fine" % an, "speak for yourself, %s — I ate" % an, "not me. %s ate less, that's all" % an]
		"contradict_hungry":
			lines = ["full? not me. I'm hungry", "%s may be full. I'm not" % an]
		"contradict_calm":
			lines = ["%s worries too much. it's quiet" % an, "easy, %s. nothing's chasing us" % an]
		"contradict_tense":
			lines = ["easy for %s to say. I'm still twitchy" % an, "%s is calm. I'm not, yet" % an]
		"agree_tense":
			lines = ["I feel it too, %s" % an, "yes — the water feels wrong to me too"]
		"tease":
			lines = ["%s says that every time" % an, "listen to %s, showing off for the keeper" % an, "%s just wants the keeper's attention" % an]
		_:
			lines = ["mm, what %s said" % an, "yes — %s has it" % an, "I think so too"]
	return str(lines[randi() % lines.size()]).substr(0, 96)


# After `speaker` answered the keeper, maybe another fish reacts to it.
# Returns {} (nobody) or {fish_id, name, to, line, kind}. Bounded: at most
# FOLLOWUPS_MAX per keeper line, FOLLOWUP_MIN_GAP_MS apart, only inside the
# exchange window. `roll` < 0 draws randf(); tests pass a fixed roll.
static func maybe_followup(sim, rt: Dictionary, speaker: Fish, speaker_line: String, now_ms: int,
		roll: float = -1.0) -> Dictionary:
	if sim == null or not _alive(speaker) or rt.is_empty():
		return {}
	var n: int = int(rt.get("followups", FOLLOWUPS_MAX))
	if n >= FOLLOWUPS_MAX:
		return {}
	if now_ms - int(rt.get("started_ms", -FOLLOWUP_EXCHANGE_WINDOW_MS * 2)) > FOLLOWUP_EXCHANGE_WINDOW_MS:
		return {}
	if now_ms - int(rt.get("last_ms", -FOLLOWUP_MIN_GAP_MS)) < FOLLOWUP_MIN_GAP_MS:
		return {}
	var r: float = roll if roll >= 0.0 else randf()
	if r >= float(FOLLOWUP_CHANCE[mini(n, FOLLOWUP_CHANCE.size() - 1)]):
		return {}
	var spoken: Array = rt.get("spoken", []) as Array
	var best: Fish = null
	var best_s: float = -INF
	var fish_v: Variant = sim.get("fish")
	if not (fish_v is Array):
		return {}
	for c in fish_v as Array:
		if not _alive(c) or c == speaker:
			continue
		var b: Fish = c as Fish
		if b._asleep:
			continue
		var s: float = randf() * 0.25
		s -= b.position.distance_to(speaker.position) / 12.0
		if not b.personality.is_empty():
			s += float(b.personality.get("sociability", 0.5)) * 0.5 + float(b.personality.get("boldness", 0.5)) * 0.3
		if spoken.has(str(b.id)):
			s -= 0.6
		if s > best_s:
			best_s = s
			best = b
	if best == null:
		return {}
	var kind: String = followup_kind(speaker, best, speaker_line, rt.get("topics", PackedStringArray()))
	var line: String = followup_line(kind, speaker, best)
	rt["followups"] = n + 1
	rt["last_ms"] = now_ms
	spoken.append(str(best.id))
	rt["spoken"] = spoken
	return {"fish_id": str(best.id), "name": _moniker(best), "to": _moniker(speaker), "line": line, "kind": kind}


# --- Tank initiates ----------------------------------------------------------

static func _fish_snapshot(sim) -> Dictionary:
	var out: Dictionary = {}
	var fish_v: Variant = sim.get("fish")
	if not (fish_v is Array):
		return out
	for c in fish_v as Array:
		if not _alive(c):
			continue
		var f: Fish = c as Fish
		out[str(f.id)] = {"name": _moniker(f), "gen": f.generation, "age": f.age}
	return out


static func _push_pending(rt: Dictionary, kind: String, data: Dictionary, now_s: float) -> void:
	var pend: Array = rt.get("pending", []) as Array
	for p in pend:
		if str(p.get("kind", "")) == kind:
			var names: Array = p.get("names", []) as Array
			if data.has("name") and names.size() < 3:
				names.append(data["name"])
			p["names"] = names
			p["t"] = now_s
			rt["pending"] = pend
			return
	var entry: Dictionary = {"kind": kind, "t": now_s, "names": []}
	if data.has("name"):
		(entry["names"] as Array).append(data["name"])
	for k in data:
		if k != "name":
			entry[k] = data[k]
	pend.append(entry)
	rt["pending"] = pend


# Diff the tank since the last call and queue notable events.
static func observe(sim, tm: Dictionary, rt: Dictionary, st: Dictionary, now_s: float) -> void:
	var snap: Dictionary = _fish_snapshot(sim)
	if not rt.has("ids"):
		rt["ids"] = snap
		rt["o2_low"] = float(st.get("o2", 1.0)) < 0.45
		rt["started_s"] = now_s
		rt["pending"] = []
		var mem0: Dictionary = memory(tm)
		var last_k: int = int(mem0.get("last_keeper_unix", 0))
		if last_k > 0 and _unix() - float(last_k) > INIT_RETURN_GAP_S:
			_push_pending(rt, "absence", {"return": true}, now_s)
		return
	var prev: Dictionary = rt["ids"]
	for id in snap:
		if not prev.has(id):
			var d: Dictionary = snap[id]
			if int(d.get("gen", 0)) > 0 and float(d.get("age", 999.0)) < 120.0:
				_push_pending(rt, "birth", {"name": d["name"]}, now_s)
				note_dream_seed(tm, "birth", str(d["name"]), "", 0.8)
			else:
				_push_pending(rt, "arrival", {"name": d["name"]}, now_s)
				note_dream_seed(tm, "arrival", str(d["name"]), "", 0.5)
	for id in prev:
		if not snap.has(id):
			var gone: String = str((prev[id] as Dictionary).get("name", "someone"))
			_push_pending(rt, "death", {"name": gone}, now_s)
			note_dream_seed(tm, "death", gone, "", 0.9)
	rt["ids"] = snap
	var o2: float = float(st.get("o2", 1.0))
	if o2 < 0.45 and not bool(rt.get("o2_low", false)):
		rt["o2_low"] = true
		_push_pending(rt, "o2_low", {"o2": o2}, now_s)
	elif o2 > 0.55:
		rt["o2_low"] = false
	if not update_promises(sim, tm, st).is_empty():
		_push_pending(rt, "promise", {}, now_s)
	# Expire stale news — the tank only brings up what is still fresh.
	var keep: Array = []
	for p in rt.get("pending", []):
		if now_s - float(p.get("t", now_s)) <= INIT_PENDING_TTL_S or str(p.get("kind", "")) == "absence":
			keep.append(p)
	rt["pending"] = keep


static func _names(p: Dictionary) -> String:
	var names: Array = p.get("names", []) as Array
	if names.is_empty():
		return "someone"
	if names.size() == 1:
		return str(names[0])
	return "%s and %s" % [", ".join(PackedStringArray(names.slice(0, names.size() - 1))), str(names[-1])]


static func initiation_line(tm: Dictionary, p: Dictionary, st: Dictionary) -> String:
	var who: String = _names(p)
	match str(p.get("kind", "")):
		"o2_low":
			return ["keeper — the water is getting thin. o2 at %d%%" % int(round(float(st.get("o2", 0.0)) * 100.0)),
					"we're breathing hard near the top. the air in the water is low"][randi() % 2]
		"death":
			var safe: Dictionary = last_safe_claim(tm)
			if not safe.is_empty():
				return "%s is gone. you said we were safe" % who
			return ["%s is gone. the water feels emptier" % who, "we lost %s. we are fewer now" % who][randi() % 2]
		"birth":
			return ["something new — %s, hatched among us" % who, "a new small one: %s. we make room" % who][randi() % 2]
		"arrival":
			return ["someone new in the water — %s. we are watching them" % who,
					"%s arrived. the school is still deciding" % who][randi() % 2]
		"promise":
			var o: String = take_untold_outcome(tm)
			return o
		"dream":
			return take_dream_share(tm, st)
		"absence":
			if bool(p.get("return", false)):
				return ["you were gone a long while. we kept the water", "you're back. the days went on without you"][randi() % 2]
			return ["it's been quiet a long time. are you still there?", "we haven't heard you in a while, keeper"][randi() % 2]
	return ""


# Maybe speak first. Returns {line, kind} or {}. Rate-limited: keeper must
# have been quiet INIT_KEEPER_QUIET_S, INIT_MIN_GAP_S between any two
# initiations, INIT_KIND_COOLDOWN_S per kind. `enabled` = voice not off.
static func maybe_initiate(sim, tm: Dictionary, rt: Dictionary, st: Dictionary, keeper_quiet_s: float,
		now_s: float, enabled: bool = true, keeper_present: bool = true) -> Dictionary:
	observe(sim, tm, rt, st, now_s)
	# Morning after a dream: tell it once, if someone is there to hear it.
	if keeper_present and dream_share_ready(tm, st):
		var did: String = str((tm.get("last_dream", {}) as Dictionary).get("id", ""))
		if did != "" and str(rt.get("dream_queued", "")) != did:
			rt["dream_queued"] = did
			_push_pending(rt, "dream", {}, now_s)
	if not enabled:
		rt["pending"] = []
		return {}
	if keeper_quiet_s < INIT_KEEPER_QUIET_S:
		rt["absence_fired"] = false
		return {}
	if keeper_quiet_s >= INIT_ABSENCE_S and not bool(rt.get("absence_fired", false)) \
			and now_s - float(rt.get("started_s", now_s)) >= INIT_ABSENCE_S:
		rt["absence_fired"] = true
		_push_pending(rt, "absence", {}, now_s)
	if now_s - float(rt.get("last_init_s", -INF)) < INIT_MIN_GAP_S:
		return {}
	var pend: Array = rt.get("pending", []) as Array
	if pend.is_empty():
		return {}
	var kind_last: Dictionary = rt.get("kind_last", {}) as Dictionary
	for kind in INIT_PRIORITY:
		for i in pend.size():
			var p: Dictionary = pend[i]
			if str(p.get("kind", "")) != kind:
				continue
			if now_s - float(kind_last.get(kind, -INF)) < INIT_KIND_COOLDOWN_S:
				continue
			var line: String = initiation_line(tm, p, st)
			pend.remove_at(i)
			rt["pending"] = pend
			if line == "":
				return {}
			kind_last[kind] = now_s
			rt["kind_last"] = kind_last
			rt["last_init_s"] = now_s
			rt["count"] = int(rt.get("count", 0)) + 1
			return {"line": line, "kind": kind}
	return {}


# True while a keeper ↔ tank exchange (and its fish follow-ups) is still live.
static func exchange_active(rt: Dictionary, now_ms: int) -> bool:
	if rt.is_empty():
		return false
	return now_ms - int(rt.get("started_ms", -FOLLOWUP_EXCHANGE_WINDOW_MS * 2)) <= FOLLOWUP_EXCHANGE_WINDOW_MS


# --- Overheard chatter (keeper silent) ------------------------------------------
#
# Two nearby, visible, awake fish trade 2–3 lines grounded in their real
# states and what they share (hunger, a chase, a newborn, a loss, a new plant,
# the light turning). `rt` is caller-owned runtime state (not saved). The
# caller decides visibility (camera frustum) and passes only those fish.

const CHATTER_MIN_GAP_S: float = 90.0
const CHATTER_KEEPER_QUIET_S: float = 60.0
const CHATTER_CHANCE: float = 0.3
const CHATTER_NEAR_DIST: float = 5.0
const CHATTER_NEWBORN_AGE_S: float = 300.0
const CHATTER_LIGHT_WINDOW_S: float = 120.0
const CHATTER_PLANT_WINDOW_S: float = 300.0


static func _tense(f: Fish) -> bool:
	return maxf(f.stress, f.spooked) > 0.45


# Track what changed around the tank (light trend, plant count) so chatter
# can notice it. Called on every poll, before the rate gates.
static func _chatter_observe(sim, rt: Dictionary, now_s: float) -> void:
	var dl: float = SimGate.daylight(sim, 0.6) if sim != null else 0.6
	if rt.has("dl_prev"):
		var prev: float = float(rt["dl_prev"])
		if prev >= 0.45 and dl < 0.45:
			rt["light_change"] = "dim"
			rt["light_change_s"] = now_s
		elif prev < 0.45 and dl >= 0.45:
			rt["light_change"] = "up"
			rt["light_change_s"] = now_s
	rt["dl_prev"] = dl
	var plants_v: Variant = sim.get("plants") if sim != null else null
	if plants_v is Array:
		var n: int = (plants_v as Array).size()
		if rt.has("plants_n") and n > int(rt["plants_n"]):
			rt["new_plant_s"] = now_s
		rt["plants_n"] = n


# Best pair of close, awake, living fish among `candidates` ([] if none).
static func pick_chatter_pair(candidates: Array) -> Array:
	var live: Array = []
	for c in candidates:
		if _alive(c) and not (c as Fish)._asleep:
			live.append(c)
	var best: Array = []
	var best_s: float = -INF
	for i in live.size():
		for j in range(i + 1, live.size()):
			var a: Fish = live[i] as Fish
			var b: Fish = live[j] as Fish
			var d: float = a.position.distance_to(b.position)
			if d > CHATTER_NEAR_DIST:
				continue
			var s: float = -d / CHATTER_NEAR_DIST + randf() * 0.2
			s += absf(FishSocial.affinity(a, str(b.id))) * 0.8
			if not a.personality.is_empty():
				s += float(a.personality.get("sociability", 0.5)) * 0.3
			if s > best_s:
				best_s = s
				best = [a, b]
	return best


static func _newborn_name(sim, a: Fish, b: Fish) -> String:
	var fish_v: Variant = sim.get("fish") if sim != null else null
	if not (fish_v is Array):
		return ""
	for c in fish_v as Array:
		if not _alive(c) or c == a or c == b:
			continue
		var f: Fish = c as Fish
		if f.generation > 0 and f.age < CHATTER_NEWBORN_AGE_S:
			return _moniker(f)
	return ""


# What these two would actually talk about. Returns {kind, a, b, ...data};
# `a` speaks first (the pair may be swapped, e.g. the one chased speaks).
static func chatter_kind(sim, rt: Dictionary, a: Fish, b: Fish, now_s: float) -> Dictionary:
	for pair in [[a, b], [b, a]]:
		var g: Dictionary = FishSocial.grieving_for(pair[0])
		if not g.is_empty() and float(g.get("level", 0.0)) > 0.15 and str(g.get("name", "")) != "":
			return {"kind": "grief", "a": pair[0], "b": pair[1], "name": str(g["name"])}
	for pair in [[a, b], [b, a]]:
		var victim: Fish = pair[0]
		var chaser: Fish = pair[1]
		if FishSocial.has_tag(victim, str(chaser.id), "chased_me") \
				or float(victim.grudges.get(str(chaser.id), 0.0)) > 0.0:
			return {"kind": "chase", "a": victim, "b": chaser}
	var baby: String = _newborn_name(sim, a, b)
	if baby != "":
		return {"kind": "newborn", "a": a, "b": b, "name": baby}
	var ha: bool = a.hunger > 0.55
	var hb: bool = b.hunger > 0.55
	if ha and hb:
		return {"kind": "both_hungry", "a": a, "b": b}
	if ha or hb:
		return {"kind": "one_hungry", "a": a if ha else b, "b": b if ha else a}
	if _tense(a) != _tense(b):
		return {"kind": "tense", "a": a if _tense(a) else b, "b": b if _tense(a) else a}
	if rt.has("light_change") and now_s - float(rt.get("light_change_s", -INF)) <= CHATTER_LIGHT_WINDOW_S:
		return {"kind": "light_dim" if str(rt["light_change"]) == "dim" else "light_up", "a": a, "b": b}
	if now_s - float(rt.get("new_plant_s", -INF)) <= CHATTER_PLANT_WINDOW_S:
		return {"kind": "new_plant", "a": a, "b": b}
	if FishSocial.affinity(a, str(b.id)) >= FishSocial.FRIEND_AFF:
		return {"kind": "friends", "a": a, "b": b}
	if _Backstory.has_story(a) and _Backstory.like_phrase(a) != "":
		return {"kind": "like", "a": a, "b": b, "like": _Backstory.like_phrase(a)}
	return {"kind": "quiet", "a": a, "b": b}


static func _pick(options: Array) -> Array:
	return options[randi() % options.size()] as Array


# 2–3 lines, alternating a / b, for a chatter kind.
static func chatter_lines(k: Dictionary) -> Array:
	var a: Fish = k["a"]
	var b: Fish = k["b"]
	var an: String = _moniker(a)
	var bn: String = _moniker(b)
	var nm: String = str(k.get("name", ""))
	match str(k.get("kind", "")):
		"grief":
			return _pick([["I keep looking for %s" % nm, "me too. the plants feel emptier"],
					["%s used to swim right here" % nm, "I know. stay near me for a while", "…ok"]])
		"chase":
			return _pick([["you chased me earlier, %s" % bn, "you were in my spot", "it's everyone's spot"],
					["keep your distance, %s" % bn, "then keep out of my corner"]])
		"newborn":
			return _pick([["did you see %s? so small" % nm, "we were that small once"],
					["the little one, %s — it follows everyone" % nm, "it'll learn. we did", "slowly"]])
		"both_hungry":
			return _pick([["is it just me, or is there no food anywhere?", "not just you. my belly's light too",
					"watch the top. it comes from there"],
					["hungry, %s?" % bn, "starving. you?", "same"]])
		"one_hungry":
			return _pick([["have you eaten, %s?" % bn, "I have. you missed it, %s" % an],
					["I'm so hungry", "I'm not. try the gravel by the plants"]])
		"tense":
			return _pick([["something feels wrong in the water", "it's only the current, %s. stay close" % an],
					["did you feel that?", "feel what? it's quiet, %s" % an, "…maybe"]])
		"light_dim":
			return _pick([["the light's going", "then we sleep soon"],
					["getting dark, %s" % bn, "good. I'm tired"]])
		"light_up":
			return _pick([["the light's back", "good — I can see you again"],
					["morning, %s" % bn, "is it? oh. yes. morning"]])
		"new_plant":
			return _pick([["something green is new over there", "it smells of roots. I like it"],
					["did you see the new plant?", "I've been hiding in it already"]])
		"friends":
			return _pick([["stay near me tonight, %s?" % bn, "always. I like your wake"],
					["you again", "me again. who else, %s?" % an]])
		"like":
			return _pick([["I'm going over to %s" % str(k.get("like", "")), "you always go there, %s" % an],
					["come with me to %s" % str(k.get("like", "")), "again? fine"]])
	return _pick([["quiet today", "quiet is good"], ["mm", "mm. warm water"],
			["you're drifting, %s" % bn, "so are you"]])


# Maybe two visible fish talk. Returns {} or {kind, lines: [{fish_id, name,
# to, line}]}. Gates: voice enabled, keeper not mid-conversation and quiet for
# CHATTER_KEEPER_QUIET_S, CHATTER_MIN_GAP_S between exchanges, a CHATTER_CHANCE
# roll (`roll` < 0 draws randf(); tests pass a fixed roll).
static func maybe_chatter(sim, rt: Dictionary, candidates: Array, keeper_quiet_s: float,
		keeper_busy: bool, now_s: float, enabled: bool = true, roll: float = -1.0) -> Dictionary:
	if sim == null:
		return {}
	_chatter_observe(sim, rt, now_s)
	if not enabled or keeper_busy or keeper_quiet_s < CHATTER_KEEPER_QUIET_S:
		return {}
	if now_s - float(rt.get("chatter_last_s", -INF)) < CHATTER_MIN_GAP_S:
		return {}
	var r: float = roll if roll >= 0.0 else randf()
	if r >= CHATTER_CHANCE:
		return {}
	var pair: Array = pick_chatter_pair(candidates)
	if pair.size() < 2:
		return {}
	var k: Dictionary = chatter_kind(sim, rt, pair[0], pair[1], now_s)
	var raw: Array = chatter_lines(k)
	var a: Fish = k["a"]
	var b: Fish = k["b"]
	var out_lines: Array = []
	for i in raw.size():
		var sp: Fish = a if i % 2 == 0 else b
		var to: Fish = b if i % 2 == 0 else a
		out_lines.append({"fish_id": str(sp.id), "name": _moniker(sp), "to": _moniker(to),
				"line": str(raw[i]).substr(0, 96)})
	rt["chatter_last_s"] = now_s
	rt["chatter_count"] = int(rt.get("chatter_count", 0)) + 1
	return {"kind": str(k["kind"]), "lines": out_lines}


# --- Tank dreams ------------------------------------------------------------------
#
# At deep night the tank recombines the day's strongest real events (births,
# deaths, arrivals, kept/broken promises, the fish's most salient episodic
# memories, what the keeper talked about most, the last story beat) into one
# surreal but grounded line. Stored in tm["last_dream"] (saved with the tank
# mind); shared once the next morning. Dreams nudge tank mood a little.

const DREAM_SEEDS_MAX: int = 12
const DREAM_AFTER_DUSK_S: float = 90.0
const DREAM_SHARE_TTL_S: float = 3.0 * 3600.0
const DREAM_MOOD_GAIN: float = 0.04
const DREAM_VALENCE: Dictionary = {
	"birth": 0.4, "death": -0.5, "arrival": 0.1, "promise_kept": 0.3, "promise_broken": -0.3,
	"memory": 0.0, "keeper": 0.15, "story": 0.0, "light": 0.1,
}


static func note_dream_seed(tm: Dictionary, kind: String, who: String, text: String, weight: float) -> void:
	var seeds: Array = tm.get("dream_seeds", []) as Array
	seeds.append({"k": kind, "n": who.substr(0, 32), "x": text.substr(0, 48), "w": weight, "t": _unix()})
	while seeds.size() > DREAM_SEEDS_MAX:
		seeds.pop_front()
	tm["dream_seeds"] = seeds


# Everything the tank could dream about tonight, strongest first.
static func dream_candidates(sim, tm: Dictionary) -> Array:
	var out: Array = []
	for sd in tm.get("dream_seeds", []) as Array:
		if sd is Dictionary:
			out.append((sd as Dictionary).duplicate())
	# The fish's most salient memories.
	var mems: Array = []
	var fish_v: Variant = sim.get("fish") if sim != null else null
	if fish_v is Array:
		for c in fish_v as Array:
			if not _alive(c):
				continue
			var f: Fish = c as Fish
			for e in f._episodic_store:
				if not (e is Dictionary):
					continue
				var txt: String = str((e as Dictionary).get("text", "")).strip_edges()
				var sal: float = float((e as Dictionary).get("salience", (e as Dictionary).get("weight", 0.0)))
				if txt.length() > 3 and sal >= 0.45:
					mems.append({"k": "memory", "n": _moniker(f), "x": txt.substr(0, 40), "w": sal * 0.8})
	mems.sort_custom(func(p, q): return float(p["w"]) > float(q["w"]))
	out.append_array(mems.slice(0, 2))
	# What the keeper talked about most today.
	var tc: Dictionary = {}
	var day_ago: float = _unix() - 86400.0
	for e in memory(tm)["entries"]:
		if not (e is Dictionary) or float((e as Dictionary).get("t", 0.0)) < day_ago:
			continue
		for tp in (e as Dictionary).get("topics", []) as Array:
			if not (str(tp) in ["greeting", "who", "wellbeing"]):
				tc[str(tp)] = int(tc.get(str(tp), 0)) + 1
	var top_topic: String = ""
	for tp in tc:
		if top_topic == "" or int(tc[tp]) > int(tc[top_topic]):
			top_topic = str(tp)
	if top_topic != "":
		out.append({"k": "keeper", "n": "", "x": top_topic, "w": 0.45 + 0.05 * float(mini(int(tc[top_topic]), 4))})
	# The last story beat.
	var ev: Variant = sim.get("story_events") if sim != null else null
	if ev is Array and not (ev as Array).is_empty():
		var last: Variant = (ev as Array)[-1]
		var stxt: String = str((last as Dictionary).get("text", "")) if last is Dictionary else str(last)
		if stxt.strip_edges().length() > 8:
			out.append({"k": "story", "n": "", "x": stxt.strip_edges().to_lower().substr(0, 44), "w": 0.35})
	out.append({"k": "light", "n": "", "x": "", "w": 0.2})
	out.sort_custom(func(p, q): return float(p["w"]) > float(q["w"]))
	return out


static func _dream_fragment(sd: Dictionary) -> String:
	var n: String = str(sd.get("n", ""))
	var x: String = str(sd.get("x", ""))
	match str(sd.get("k", "")):
		"birth":
			return ["%s was hatching over and over, smaller each time" % n,
					"%s was already old, and we were the small ones" % n][randi() % 2]
		"death":
			return ["%s swam back through the glass as if nothing had happened" % n,
					"%s was there, but only as a shadow in the plants" % n][randi() % 2]
		"arrival":
			return "%s arrived again, and this time we knew them" % n
		"promise_kept":
			return "your promise to %s came true twice" % _promise_phrase(x)
		"promise_broken":
			return "you promised to %s, and it hung above us and never fell" % _promise_phrase(x)
		"memory":
			return "%s remembered \"%s\", and the whole tank felt it" % [n, x]
		"keeper":
			match x:
				"food":
					return "your voice fell like flakes"
				"calm", "safe":
					return "you said safe, and the water believed it"
				"love":
					return "your warmth came through the glass like a second sun"
				"light":
					return "you asked for the light and it came twice"
				"air":
					return "your words rose like bubbles and we breathed them"
			return "your words drifted down like slow bubbles"
		"story":
			return "the day's news — %s — was written in the gravel" % x
	return "the gold light came twice"


# Build (not store) a dream. {} never: an empty day still dreams of the light.
static func build_dream(sim, tm: Dictionary) -> Dictionary:
	var cands: Array = dream_candidates(sim, tm)
	var picked: Array = []
	var kinds: Array = []
	for sd in cands:
		if picked.size() >= 2:
			break
		var k: String = str(sd.get("k", ""))
		# Two different kinds — a dream is a recombination, not a repeat.
		if kinds.has(k):
			continue
		picked.append(sd)
		kinds.append(k)
	var names: Array = []
	var frags: PackedStringArray = PackedStringArray()
	var valence: float = 0.0
	for sd in picked:
		frags.append(_dream_fragment(sd))
		valence += float(DREAM_VALENCE.get(str(sd.get("k", "")), 0.0))
		var n: String = str(sd.get("n", ""))
		if n != "" and not names.has(n):
			names.append(n)
	var line: String = "we dreamed " + ", and ".join(frags)
	if names.is_empty():
		var snap: Dictionary = _fish_snapshot(sim)
		if not snap.is_empty():
			var extra: String = str((snap[snap.keys()[randi() % snap.size()]] as Dictionary).get("name", ""))
			if extra != "":
				names.append(extra)
				line += ", and %s was there" % extra
	return {"line": line.substr(0, 150), "names": names, "kinds": kinds,
			"valence": clampf(valence, -1.0, 1.0)}


# Deep night: dream once per night. Returns the new dream or {}.
static func maybe_dream(sim, tm: Dictionary, dl: float) -> Dictionary:
	if dl >= 0.12 or float(tm.get("duration_since_dusk", 0.0)) < DREAM_AFTER_DUSK_S:
		return {}
	var night: int = int(tm.get("nights_tended", 0))
	if int(tm.get("dream_night", -1)) == night:
		return {}
	tm["dream_night"] = night
	var d: Dictionary = build_dream(sim, tm)
	d["id"] = "%d-%d" % [night, int(_unix())]
	d["t"] = _unix()
	d["told"] = false
	tm["last_dream"] = d
	tm["dream_seeds"] = []
	var v: float = float(d.get("valence", 0.0))
	tm["mood_valence"] = clampf(float(tm.get("mood_valence", 0.0)) + v * DREAM_MOOD_GAIN, -1.0, 1.0)
	return d


# Morning, an untold dream, not stale.
static func dream_share_ready(tm: Dictionary, st: Dictionary) -> bool:
	var d: Variant = tm.get("last_dream", null)
	if not (d is Dictionary) or (d as Dictionary).is_empty() or bool((d as Dictionary).get("told", false)):
		return false
	if float(st.get("daylight", 1.0)) < 0.35:
		return false
	return _unix() - float((d as Dictionary).get("t", 0.0)) <= DREAM_SHARE_TTL_S


# The dream as a morning line (marks it told), or "".
static func take_dream_share(tm: Dictionary, st: Dictionary) -> String:
	if not dream_share_ready(tm, st):
		return ""
	var d: Dictionary = tm["last_dream"]
	d["told"] = true
	return "last night %s" % str(d.get("line", "we dreamed"))


# --- "what are you thinking / dreaming / who is your friend / tell me about X" ---

static var _intent_res: Dictionary = {}


static func _ire(key: String, pattern: String) -> RegEx:
	if not _intent_res.has(key):
		var r := RegEx.new()
		r.compile(pattern)
		_intent_res[key] = r
	return _intent_res[key]


static func _fish_named(sim, nm: String) -> Fish:
	var want: String = nm.strip_edges().to_lower()
	if want == "":
		return null
	var fish_v: Variant = sim.get("fish") if sim != null else null
	if not (fish_v is Array):
		return null
	for c in fish_v as Array:
		if _alive(c) and (c as Fish).fish_name.strip_edges().to_lower() == want:
			return c as Fish
	return null


# {intent: "about"|"dream"|"friend"|"thinking"|"", about_id}.
static func detect_intent(sim, text: String) -> Dictionary:
	var t: String = text.to_lower().replace("’", "'")
	var m: RegExMatch = _ire("about", "\\b(?:tell me about|what about|how is|how's|who is|who's|talk about)\\s+([a-z0-9_\\-]+)").search(t)
	if m != null:
		var f: Fish = _fish_named(sim, m.get_string(1))
		if f != null:
			return {"intent": "about", "about_id": str(f.id)}
	if _ire("dream", "\\bdream(?:s|ed|t|ing)?\\b").search(t) != null:
		return {"intent": "dream", "about_id": ""}
	if _ire("friend", "\\b(?:friends?|rivals?|enem(?:y|ies)|get along)\\b").search(t) != null \
			and ("?" in t or _ire("friend_q", "\\b(?:who|your|any)\\b").search(t) != null):
		return {"intent": "friend", "about_id": ""}
	if _ire("thinking", "\\b(?:thinking|thoughts?|on your minds?|what do you think|wondering)\\b").search(t) != null:
		return {"intent": "thinking", "about_id": ""}
	return {"intent": "", "about_id": ""}


static func fish_by_id(sim, fid: String) -> Fish:
	var fish_v: Variant = sim.get("fish") if sim != null else null
	if fid == "" or not (fish_v is Array):
		return null
	for c in fish_v as Array:
		if _alive(c) and str((c as Fish).id) == fid:
			return c as Fish
	return null


static func _state_word(f: Fish) -> String:
	if f._asleep:
		return "asleep"
	if f.hunger > 0.55:
		return "hungry"
	if _tense(f):
		return "uneasy"
	return "calm"


static func _top_memory(f: Fish) -> String:
	var best: String = ""
	var best_s: float = -1.0
	for e in f._episodic_store:
		if e is Dictionary:
			var txt: String = str((e as Dictionary).get("text", "")).strip_edges()
			var sal: float = float((e as Dictionary).get("salience", (e as Dictionary).get("weight", 0.0)))
			if txt.length() > 3 and sal > best_s:
				best_s = sal
				best = txt
	return best.substr(0, 48)


# Strongest friendship in the tank: [a, b, affinity] or [].
static func _closest_pair(sim, want_friend: bool) -> Array:
	var out: Array = []
	var best: float = 0.0
	var fish_v: Variant = sim.get("fish") if sim != null else null
	if not (fish_v is Array):
		return out
	for c in fish_v as Array:
		if not _alive(c):
			continue
		var f: Fish = c as Fish
		var rel: Dictionary = FishSocial.best_friend(f) if want_friend else FishSocial.rival(f)
		if rel.is_empty():
			continue
		var aff: float = absf(float(rel.get("affinity", 0.0)))
		if aff > best:
			best = aff
			out = [_moniker(f), str(rel.get("name", "another fish")), aff]
	return out


# The collective's answer to an intent, from real state ("" = no intent).
static func tank_intent_line(sim, tm: Dictionary, st: Dictionary, intent: String, about_id: String = "") -> String:
	match intent:
		"dream":
			var d: Variant = tm.get("last_dream", null)
			if d is Dictionary and str((d as Dictionary).get("line", "")) != "":
				(d as Dictionary)["told"] = true
				return str((d as Dictionary)["line"])
			if float(st.get("daylight", 1.0)) < 0.28:
				return "not yet — we're only just drifting down"
			return "no dream stayed with us. the night was too shallow"
		"thinking":
			var focus: String = str(st.get("focus", "")).replace("_", " ")
			var parts: PackedStringArray = PackedStringArray()
			parts.append("we're thinking of %s" % focus if focus != "" else "we're thinking of the water")
			if str(st.get("summary", "")) != "":
				parts.append(str(st["summary"]))
			var fish_v: Variant = sim.get("fish") if sim != null else null
			if fish_v is Array:
				for c in fish_v as Array:
					if _alive(c) and not (c as Fish)._asleep and (c as Fish).attention_focus != "":
						parts.append("%s keeps turning toward %s" % [_moniker(c as Fish),
								(c as Fish).attention_focus.replace("_", " ")])
						break
			return ". ".join(parts)
		"friend":
			var fr: Array = _closest_pair(sim, true)
			var rv: Array = _closest_pair(sim, false)
			var out: String = ""
			if not fr.is_empty():
				out = "%s and %s — they keep within a fin of each other" % [fr[0], fr[1]]
			else:
				out = "no one has chosen a friend yet; we school loosely"
			if not rv.is_empty():
				out += ". %s keeps away from %s" % [rv[0], rv[1]]
			return out
		"about":
			var f: Fish = fish_by_id(sim, about_id)
			if f == null:
				return ""
			var bits: PackedStringArray = PackedStringArray()
			var tag: String = _Backstory.tagline(f)
			bits.append("%s — %s" % [_moniker(f), tag] if tag != "" else _moniker(f))
			var soc: String = FishSocial.summary_line(f)
			if soc != "":
				bits.append(soc.to_lower())
			bits.append("right now %s" % _state_word(f))
			var mem: String = _top_memory(f)
			if mem != "":
				bits.append("it remembers \"%s\"" % mem)
			return ". ".join(bits)
	return ""


# One fish's own answer to an intent (the responder lines), from its state.
static func fish_intent_line(sim, f: Fish, intent: String, about_id: String = "") -> String:
	if not _alive(f):
		return ""
	var out: String = ""
	match intent:
		"thinking":
			var tm_v: Variant = sim.get("_tank_mind") if sim != null else null
			var recalled: String = TankQuestions.recall_line(tm_v as Dictionary, str(f.id)) \
					if tm_v is Dictionary and not TankQuestions.answers_for(tm_v as Dictionary, str(f.id)).is_empty() \
					and randf() < 0.5 else ""
			if f._asleep:
				out = "…dreaming, mostly"
			elif recalled != "":
				out = "about what you told me. %s" % recalled
			elif f.hunger > 0.6:
				out = "food. I'm thinking about food"
			elif _tense(f):
				out = "about whatever made the water tight"
			elif f.attention_focus != "":
				out = "about %s" % f.attention_focus.replace("_", " ")
			elif _Backstory.like_phrase(f) != "":
				out = "about %s" % _Backstory.like_phrase(f)
			else:
				out = "nothing much. the water, the light"
		"dream":
			var mem: String = _top_memory(f)
			out = "I dreamed of \"%s\"" % mem if mem != "" else "I don't remember dreaming"
		"friend":
			var bf: Dictionary = FishSocial.best_friend(f)
			if not bf.is_empty():
				out = "%s. always near" % FishSocial.describe_relation(f, str(bf.get("id", "")))
			else:
				out = "no one yet. I swim with whoever's close"
			var rv: Dictionary = FishSocial.rival(f)
			if not rv.is_empty():
				out += " — not %s" % str(rv.get("name", "that one"))
		"about":
			var other: Fish = fish_by_id(sim, about_id)
			if other == null:
				return ""
			if other == f:
				var own: String = _Backstory.speech_line(f, "like")
				out = "me? %s I'm %s" % [own, _state_word(f)] if own != "" else "me? I'm %s" % _state_word(f)
			else:
				out = "%s? %s. %s today" % [_moniker(other), FishSocial.describe_relation(f, other),
						_state_word(other)]
	return out.substr(0, 110)
