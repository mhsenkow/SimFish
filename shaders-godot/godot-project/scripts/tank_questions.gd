extends RefCounted

# Fish ask the keeper. The other half of the tank-talk channel: a curious,
# familiar fish occasionally asks a question grounded in its own world ("where
# did Pip go?" after a death, "will you feed us when the gold light comes?"
# from the keeper's real feeding times, "what is beyond the glass?"), and the
# keeper's next line is read as the ANSWER. The fish keeps it (episodic memory
# + a small per-fish answers map) and can bring it up later ("you told me
# about beyond the glass — \"it's a big world\"").
#
# Comprehension goes through MindLexicon: a fish only understands words it has
# actually paired. Partial understanding is normal ("\"big\" — I caught that
# part"). Answering kindly raises familiarity / trust a little; an unanswered
# question fades ("…never mind").
#
# Pure template logic, main-thread safe, deterministic under a fixed roll.
#
# Persistence: tm["keeper_questions"] (tm = sim._tank_mind), carried by
# TankMind.to_dict/from_dict. Versioned (QUESTIONS_VERSION) and bounded
# (ANSWERS_PER_FISH / ANSWER_FISH_MAX / ASKED_KINDS_MAX); migrate() repairs old
# or malformed saves. TankDialogue.migrate() calls it.
#
# Deliberately preloads neither tank_dialogue.gd nor tank_mind.gd nor
# keeper_input.gd (they preload this file); callers pass tm and the
# TankMind.keeper_state() snapshot.

const FishSocial = preload("res://scripts/fish_social.gd")
const _Backstory = preload("res://scripts/fish_backstory.gd")
const MindLexicon = preload("res://scripts/mind_lexicon.gd")
const EpisodicMemory = preload("res://scripts/episodic_memory.gd")

const QUESTIONS_VERSION: int = 1
const ANSWERS_PER_FISH: int = 4
const ANSWER_FISH_MAX: int = 24
const ASKED_KINDS_MAX: int = 10
const TEXT_MAX: int = 56
const WORDS_MAX: int = 4
# The tank-wide ("we") answers live under this pseudo fish id.
const TANK_ID: String = "tank"

# Rate limits (unix seconds — persisted, so a relaunch does not re-ask).
const ASK_MIN_GAP_S: float = 300.0
const ASK_FISH_GAP_S: float = 1200.0
const ASK_REPEAT_S: float = 6.0 * 3600.0
const ASK_KEEPER_QUIET_S: float = 25.0
const ASK_CHANCE: float = 0.5
const COLLECTIVE_SHARE: float = 0.15
const COLLECTIVE_GAP_S: float = 2400.0
const RECALL_GAP_S: float = 3600.0
const PENDING_TTL_S: float = 90.0
const GONE_WINDOW_S: float = 900.0
const GONE_MAX: int = 4
const ASK_MIN_SCORE: float = 0.3

const STOPWORDS: Array = ["the", "a", "an", "is", "it", "its", "it's", "and", "or", "of", "to", "in",
		"on", "at", "you", "your", "i", "im", "i'm", "me", "my", "we", "us", "our", "they", "them",
		"that", "this", "there", "are", "was", "be", "just", "so", "very", "yes", "no", "oh", "well",
		"do", "does", "did", "will", "would", "can", "not", "don't", "dont", "for", "with", "all",
		"what", "why", "where", "when", "who", "how", "because", "about", "some", "go", "goes", "went"]
const KIND_WORDS: Array = ["yes", "yeah", "yep", "sure", "of course", "always", "good", "love", "safe",
		"don't worry", "dont worry", "it's ok", "its ok", "okay", "gentle", "soon", "promise", "friend",
		"beautiful", "sweet", "little one", "sleep", "rest", "home"]
const HARSH_WORDS: Array = ["shut up", "stupid", "go away", "whatever", "stop asking", "leave me",
		"dumb", "idiot", "hate", "be quiet"]


static func _unix() -> float:
	return float(Time.get_unix_time_from_system())


static func _now(now: float) -> float:
	return now if now >= 0.0 else _unix()


static func default_state() -> Dictionary:
	return {
		"v": QUESTIONS_VERSION,
		"answers": {},
		"asked": {},
		"pending": {},
		"asked_n": 0,
		"answered_n": 0,
		"faded_n": 0,
		"last_ask_unix": 0.0,
		"last_collective_unix": 0.0,
	}


# Repair tm["keeper_questions"] in place: fill missing keys, drop malformed
# entries, re-bound every map. Safe on JSON round-trips (ints → floats).
static func migrate(tm: Dictionary) -> Dictionary:
	var raw: Variant = tm.get("keeper_questions", null)
	var qs: Dictionary = raw as Dictionary if raw is Dictionary else default_state()
	var dflt: Dictionary = default_state()
	for k in dflt:
		if not qs.has(k):
			qs[k] = dflt[k]
	for k in ["answers", "asked", "pending"]:
		if not (qs[k] is Dictionary):
			qs[k] = {}
	var answers: Dictionary = qs["answers"]
	for fid in answers.keys():
		var list_v: Variant = answers[fid]
		if not (list_v is Array):
			answers.erase(fid)
			continue
		var clean: Array = []
		for e in list_v as Array:
			if e is Dictionary and str((e as Dictionary).get("k", "")) != "":
				var ed: Dictionary = e as Dictionary
				var words: Array = []
				var w_v: Variant = ed.get("w", [])
				if w_v is Array:
					for w in w_v as Array:
						if words.size() < WORDS_MAX:
							words.append(str(w))
				clean.append({
					"k": str(ed.get("k", "")),
					"q": str(ed.get("q", "")).substr(0, 96),
					"a": str(ed.get("a", "")).substr(0, TEXT_MAX),
					"w": words,
					"c": clampf(float(ed.get("c", 0.0)), 0.0, 1.0),
					"about": str(ed.get("about", "")).substr(0, 32),
					"t": float(ed.get("t", 0.0)),
					"told": float(ed.get("told", 0.0)),
				})
		while clean.size() > ANSWERS_PER_FISH:
			clean.pop_front()
		if clean.is_empty():
			answers.erase(fid)
		else:
			answers[fid] = clean
	_bound_fish_map(answers, ANSWER_FISH_MAX)
	var asked: Dictionary = qs["asked"]
	for fid in asked.keys():
		if not (asked[fid] is Dictionary):
			asked.erase(fid)
			continue
		var kinds: Dictionary = asked[fid]
		while kinds.size() > ASKED_KINDS_MAX:
			kinds.erase(_oldest_key(kinds))
	while asked.size() > ANSWER_FISH_MAX:
		asked.erase(asked.keys()[0])
	var pend: Dictionary = qs["pending"]
	if not pend.is_empty() and (str(pend.get("line", "")) == "" or str(pend.get("kind", "")) == ""):
		qs["pending"] = {}
	for k in ["asked_n", "answered_n", "faded_n"]:
		qs[k] = int(qs.get(k, 0))
	for k in ["last_ask_unix", "last_collective_unix"]:
		qs[k] = float(qs.get(k, 0.0))
	qs["v"] = QUESTIONS_VERSION
	tm["keeper_questions"] = qs
	return qs


static func state(tm: Dictionary) -> Dictionary:
	var raw: Variant = tm.get("keeper_questions", null)
	if raw is Dictionary and int((raw as Dictionary).get("v", 0)) == QUESTIONS_VERSION:
		return raw as Dictionary
	return migrate(tm)


static func _oldest_key(d: Dictionary) -> Variant:
	var best: Variant = null
	var best_t: float = INF
	for k in d:
		var tv: float = float(d[k]) if (d[k] is float or d[k] is int) else 0.0
		if tv < best_t:
			best_t = tv
			best = k
	return best


# Keep at most `cap` fish in an answers map, evicting the stalest.
static func _bound_fish_map(answers: Dictionary, cap: int) -> void:
	while answers.size() > cap:
		var worst: Variant = null
		var worst_t: float = INF
		for fid in answers:
			if str(fid) == TANK_ID:
				continue
			var list: Array = answers[fid] as Array
			var t_last: float = float((list[-1] as Dictionary).get("t", 0.0)) if not list.is_empty() else 0.0
			if t_last < worst_t:
				worst_t = t_last
				worst = fid
		if worst == null:
			return
		answers.erase(worst)


# --- small fish helpers (copies — tank_dialogue.gd preloads this file) -------

static func _alive(node: Variant) -> bool:
	if node == null or not is_instance_valid(node) or not (node is Fish):
		return false
	var fn: Fish = node as Fish
	return not fn.is_queued_for_deletion() and fn.get("_dying") != true


static func moniker(f: Fish) -> String:
	if f.fish_name.strip_edges() != "":
		return f.fish_name.strip_edges()
	return "the %s" % str(f.species).replace("_", " ")


static func _living(sim) -> Array:
	var out: Array = []
	var fish_v: Variant = sim.get("fish") if sim != null else null
	if fish_v is Array:
		for c in fish_v as Array:
			if _alive(c):
				out.append(c)
	return out


static func fish_by_id(sim, fid: String) -> Fish:
	if fid == "":
		return null
	for c in _living(sim):
		if str((c as Fish).id) == fid:
			return c as Fish
	return null


# --- observation ---------------------------------------------------------------

# Track who disappeared (runtime only; `rt` is caller-owned, not saved).
static func observe(sim, rt: Dictionary, now: float) -> void:
	var snap: Dictionary = {}
	for c in _living(sim):
		snap[str((c as Fish).id)] = moniker(c as Fish)
	var gone: Array = rt.get("gone", []) as Array
	if rt.has("ids"):
		var prev: Dictionary = rt["ids"]
		for id in prev:
			if not snap.has(id):
				gone.append({"name": str(prev[id]), "t": now})
	var keep: Array = []
	for g in gone:
		if g is Dictionary and now - float((g as Dictionary).get("t", now)) <= GONE_WINDOW_S:
			keep.append(g)
	while keep.size() > GONE_MAX:
		keep.pop_front()
	rt["gone"] = keep
	rt["ids"] = snap


# "the gold light" etc. from the minutes-of-day the keeper really fed at, or
# "" when there is no learned rhythm yet.
static func feed_time_phrase(sim) -> String:
	var hist_v: Variant = sim.get("_feed_time_history") if sim != null else null
	if not (hist_v is Array) or (hist_v as Array).size() < 3:
		return ""
	var buckets: Dictionary = {}
	for m_v in hist_v as Array:
		var m: int = int(m_v)
		var b: String = "dark"
		if m >= 300 and m < 660:
			b = "gold"
		elif m >= 660 and m < 1020:
			b = "high"
		elif m >= 1020 and m < 1320:
			b = "soft"
		buckets[b] = int(buckets.get(b, 0)) + 1
	var top: String = ""
	for b in buckets:
		if top == "" or int(buckets[b]) > int(buckets[top]):
			top = str(b)
	if int(buckets.get(top, 0)) < 2:
		return ""
	match top:
		"gold":
			return "when the gold light comes"
		"high":
			return "when the light is high"
		"soft":
			return "when the light goes soft"
	return "in the dark time"


static func _keeper_moniker(f: Fish) -> String:
	var km: Variant = f.get("_keeper_model")
	if km is Dictionary:
		var m: String = str((km as Dictionary).get("player_moniker", "")).strip_edges()
		if m != "":
			return m
	return "the big shape"


static func ask_score(f: Fish) -> float:
	var cur: float = float(f.personality.get("curiosity", 0.5)) if not f.personality.is_empty() else 0.5
	return f.familiarity * 0.5 + clampf(f._curiosity_about_keeper, 0.0, 1.0) * 0.5 + cur * 0.25


static func _answered_kinds(qs: Dictionary, fid: String) -> Dictionary:
	var out: Dictionary = {}
	var list_v: Variant = (qs["answers"] as Dictionary).get(fid, null)
	if list_v is Array:
		for e in list_v as Array:
			if e is Dictionary:
				out["%s|%s" % [str(e.get("k", "")), str(e.get("about", ""))]] = true
	return out


# Every question this fish could ask right now, from its real world:
# [{k, q, about, w}], strongest first.
static func question_candidates(sim, f: Fish, qs: Dictionary, rt: Dictionary, st: Dictionary,
		now: float) -> Array:
	var out: Array = []
	var fid: String = str(f.id)
	var answered: Dictionary = _answered_kinds(qs, fid)
	var asked_v: Variant = (qs["asked"] as Dictionary).get(fid, {})
	var asked: Dictionary = asked_v as Dictionary if asked_v is Dictionary else {}
	var push := func(k: String, q: String, about: String, w: float) -> void:
		if answered.has("%s|%s" % [k, about]):
			return
		var key: String = "%s|%s" % [k, about]
		if now - float(asked.get(key, -INF)) < ASK_REPEAT_S:
			return
		out.append({"k": k, "q": q, "about": about, "w": w})
	# A loss: the grieving fish asks about its friend; anyone asks about a
	# recent disappearance.
	var g: Dictionary = FishSocial.grieving_for(f)
	if not g.is_empty() and float(g.get("level", 0.0)) > 0.1 and str(g.get("name", "")) != "":
		push.call("gone", "where did %s go? I keep looking" % str(g["name"]), str(g["name"]), 3.0)
	for gv in rt.get("gone", []) as Array:
		var nm: String = str((gv as Dictionary).get("name", ""))
		if nm != "" and nm != moniker(f):
			push.call("gone", "where did %s go?" % nm, nm, 2.0)
	if float(st.get("ammonia", 0.0)) >= 0.18 or float(st.get("nitrite", 0.0)) >= 0.18:
		push.call("sting", "why does the water sting?", "", 0.9)
	var ft: String = feed_time_phrase(sim)
	if ft != "" and f.hunger > 0.3:
		push.call("feed", "will you feed us %s?" % ft, "", 0.6 + f.hunger * 0.3)
	var dl: float = float(st.get("daylight", 0.6))
	if dl < 0.45 and dl > 0.03:
		push.call("light", "why does the light go away?", "", 0.55)
	if f.familiarity >= 0.3:
		push.call("beyond", "what is beyond the glass?", "", 0.4)
	if f._curiosity_about_keeper > 0.3 or f.familiarity > 0.4:
		push.call("shape", "are you %s?" % _keeper_moniker(f), "", 0.35)
	var fear: String = _Backstory.fear_phrase(f)
	if fear != "":
		push.call("fear", "should I be afraid of %s?" % fear, fear, 0.4)
	var like: String = _Backstory.like_phrase(f)
	if like != "":
		push.call("like", "do you like %s too?" % like, like, 0.3)
	out.sort_custom(func(a, b): return float(a["w"]) > float(b["w"]))
	return out


static func collective_candidates(rt: Dictionary, st: Dictionary, qs: Dictionary, now: float) -> Array:
	var out: Array = []
	var answered: Dictionary = _answered_kinds(qs, TANK_ID)
	var asked_v: Variant = (qs["asked"] as Dictionary).get(TANK_ID, {})
	var asked: Dictionary = asked_v as Dictionary if asked_v is Dictionary else {}
	var push := func(k: String, q: String, w: float) -> void:
		var key: String = "%s|" % k
		if answered.has(key) or now - float(asked.get(key, -INF)) < ASK_REPEAT_S:
			return
		out.append({"k": k, "q": q, "about": "", "w": w})
	if not (rt.get("gone", []) as Array).is_empty():
		push.call("stop", "keeper, why do some of us stop?", 2.0)
	if float(st.get("o2", 1.0)) < 0.5:
		push.call("thin", "keeper, why does the water get thin?", 1.2)
	if int(st.get("n", 0)) > 0:
		push.call("other_water", "keeper, is there other water, beyond ours?", 0.4)
		push.call("who", "keeper, what are you, when you're not at the glass?", 0.3)
	out.sort_custom(func(a, b): return float(a["w"]) > float(b["w"]))
	return out


# Best asker among living, awake, settled fish ({} when nobody qualifies).
static func pick_asker(sim, qs: Dictionary, rt: Dictionary, st: Dictionary, now: float) -> Dictionary:
	var best: Dictionary = {}
	var best_s: float = -INF
	for c in _living(sim):
		var f: Fish = c as Fish
		if f._asleep or maxf(f.stress, f.spooked) > 0.6:
			continue
		var score: float = ask_score(f)
		if score < ASK_MIN_SCORE:
			continue
		var asked_v: Variant = (qs["asked"] as Dictionary).get(str(f.id), {})
		if asked_v is Dictionary:
			var last: float = -INF
			for k in asked_v as Dictionary:
				last = maxf(last, float((asked_v as Dictionary)[k]))
			if now - last < ASK_FISH_GAP_S:
				continue
		var cands: Array = question_candidates(sim, f, qs, rt, st, now)
		if cands.is_empty():
			continue
		var top: Dictionary = cands[0]
		var s: float = score + float(top["w"])
		if s > best_s:
			best_s = s
			best = {"fish": f, "q": top}
	return best


# --- asking ----------------------------------------------------------------------

static func pending(tm: Dictionary) -> Dictionary:
	return state(tm)["pending"] as Dictionary


static func has_pending(tm: Dictionary, now: float = -1.0) -> bool:
	var p: Dictionary = pending(tm)
	return not p.is_empty() and _now(now) - float(p.get("t", 0.0)) <= PENDING_TTL_S


# Maybe a fish (or, rarely, the whole tank) asks the keeper something.
# Returns one of:
#   {}                                              nothing this poll
#   {kind, fish_id, name, line, about, collective}  a new question (now pending)
#   {fade: true, fish_id, name, line, kind}         an ignored question fading
#   {recall: true, fish_id, name, line}             a fish bringing up an answer
# Gates: `enabled` (voice on, not immersive/timelapse), keeper present, not
# busy mid-exchange, quiet ASK_KEEPER_QUIET_S, ASK_MIN_GAP_S between questions,
# ASK_FISH_GAP_S per fish, ASK_REPEAT_S per question, an ASK_CHANCE roll.
static func maybe_ask(sim, tm: Dictionary, rt: Dictionary, st: Dictionary, keeper_quiet_s: float,
		keeper_present: bool, keeper_busy: bool, enabled: bool = true, now: float = -1.0,
		roll: float = -1.0) -> Dictionary:
	if sim == null:
		return {}
	var t: float = _now(now)
	observe(sim, rt, t)
	var qs: Dictionary = state(tm)
	var p: Dictionary = qs["pending"]
	if not p.is_empty():
		var asker_gone: bool = not bool(p.get("collective", false)) \
				and fish_by_id(sim, str(p.get("fish_id", ""))) == null
		if asker_gone:
			qs["pending"] = {}
			return {}
		if t - float(p.get("t", t)) > PENDING_TTL_S:
			return fade_pending(sim, tm, t)
		return {}
	if not enabled or not keeper_present or keeper_busy or keeper_quiet_s < ASK_KEEPER_QUIET_S:
		return {}
	if t - float(qs.get("last_ask_unix", 0.0)) < ASK_MIN_GAP_S:
		return {}
	var r: float = roll if roll >= 0.0 else randf()
	if r >= ASK_CHANCE:
		return {}
	if r < COLLECTIVE_SHARE and t - float(qs.get("last_collective_unix", 0.0)) >= COLLECTIVE_GAP_S:
		var cc: Array = collective_candidates(rt, st, qs, t)
		if not cc.is_empty():
			var cq: Dictionary = cc[0]
			qs["last_collective_unix"] = t
			return _set_pending(qs, TANK_ID, "the tank", cq, t, true)
	var pick: Dictionary = pick_asker(sim, qs, rt, st, t)
	if pick.is_empty():
		return _maybe_recall(sim, qs, t)
	var f: Fish = pick["fish"]
	return _set_pending(qs, str(f.id), moniker(f), pick["q"], t, false)


static func _set_pending(qs: Dictionary, fid: String, nm: String, q: Dictionary, t: float,
		collective: bool) -> Dictionary:
	var kind: String = str(q.get("k", ""))
	var about: String = str(q.get("about", ""))
	var line: String = str(q.get("q", "")).substr(0, 96)
	qs["pending"] = {"fish_id": fid, "name": nm, "kind": kind, "about": about, "line": line,
			"t": t, "collective": collective}
	var asked: Dictionary = qs["asked"]
	var kinds: Dictionary = asked.get(fid, {}) as Dictionary if asked.get(fid, {}) is Dictionary else {}
	kinds["%s|%s" % [kind, about]] = t
	while kinds.size() > ASKED_KINDS_MAX:
		kinds.erase(_oldest_key(kinds))
	asked[fid] = kinds
	while asked.size() > ANSWER_FISH_MAX:
		asked.erase(asked.keys()[0])
	qs["last_ask_unix"] = t
	qs["asked_n"] = int(qs.get("asked_n", 0)) + 1
	return {"kind": kind, "fish_id": fid, "name": nm, "line": line, "about": about,
			"collective": collective}


# The unanswered question lets go. Curiosity dips a little (not trust).
static func fade_pending(sim, tm: Dictionary, now: float = -1.0) -> Dictionary:
	var qs: Dictionary = state(tm)
	var p: Dictionary = qs["pending"]
	if p.is_empty():
		return {}
	qs["pending"] = {}
	qs["faded_n"] = int(qs.get("faded_n", 0)) + 1
	qs["last_ask_unix"] = _now(now)
	var fid: String = str(p.get("fish_id", ""))
	var line: String = ["…never mind", "…it doesn't matter", "…never mind. I'll wonder on my own"][randi() % 3]
	if bool(p.get("collective", false)):
		line = ["…never mind, keeper", "…we'll wonder by ourselves"][randi() % 2]
	else:
		var f: Fish = fish_by_id(sim, fid)
		if f == null:
			return {}
		f._curiosity_about_keeper = clampf(f._curiosity_about_keeper - 0.05, 0.0, 1.0)
	return {"fade": true, "fish_id": fid, "name": str(p.get("name", "")), "line": line,
			"kind": str(p.get("kind", ""))}


# --- answering -------------------------------------------------------------------

static func _content_words(text: String) -> PackedStringArray:
	var clean: String = text.to_lower().replace("’", "'")
	for ch in [".", ",", "!", "?", ";", ":", "\"", "(", ")", "…", "—", "-"]:
		clean = clean.replace(ch, " ")
	var out: PackedStringArray = PackedStringArray()
	for tok in clean.split(" ", false):
		var w: String = tok.strip_edges().trim_prefix("'").trim_suffix("'")
		if w.length() >= 3 and not STOPWORDS.has(w) and not out.has(w):
			out.append(w)
	return out


static func tone_of(text: String) -> String:
	var low: String = " %s " % text.to_lower().replace("’", "'")
	for h in HARSH_WORDS:
		if low.contains(str(h)):
			return "harsh"
	if text.length() > 3 and text == text.to_upper() and text.to_lower() != text:
		return "harsh"
	for k in KIND_WORDS:
		if low.contains(" %s" % str(k)):
			return "kind"
	return "plain"


static func _clean_answer(text: String) -> String:
	var a: String = text.strip_edges().to_lower().replace("’", "'")
	while a != "" and a[-1] in [".", "!", "?", ",", ";"]:
		a = a.substr(0, a.length() - 1)
	return a.substr(0, TEXT_MAX)


# Which words of `text` this listener really understands (MindLexicon), plus
# the content words it heard. `listeners` = the asking fish, or every living
# fish for a collective question.
static func comprehension(listeners: Array, text: String) -> Dictionary:
	var words: PackedStringArray = _content_words(text)
	var understood: PackedStringArray = PackedStringArray()
	for w in words:
		for c in listeners:
			if _alive(c) and MindLexicon.comprehend(c as Fish, w):
				understood.append(w)
				break
	var c_frac: float = float(understood.size()) / float(maxi(1, words.size())) if not words.is_empty() else 0.0
	return {"words": words, "understood": understood, "c": c_frac}


static func _subject(kind: String, about: String) -> String:
	match kind:
		"gone":
			return "where %s went" % about
		"sting":
			return "the stinging water"
		"feed":
			return "the feeding"
		"light":
			return "why the light goes away"
		"beyond":
			return "what's beyond the glass"
		"shape":
			return "the big shape"
		"fear", "like":
			return about
		"stop":
			return "why some of us stop"
		"thin":
			return "the thin water"
		"other_water":
			return "the other water"
		"who":
			return "what you are away from the glass"
	return "what I asked"


static func _ack_line(kind: String, tone: String, comp: Dictionary, collective: bool) -> String:
	var understood: PackedStringArray = comp["understood"]
	var c_frac: float = float(comp["c"])
	if tone == "harsh":
		return "…oh. ok" if not collective else "…we hear the sharpness. ok"
	var we: bool = collective
	if c_frac >= 0.5:
		var lines: Array = ["\"%s\"… I'll remember that" % " ".join(understood.slice(0, 3)),
				"so that's it. \"%s\"" % " ".join(understood.slice(0, 3))]
		if we:
			lines = ["\"%s\"… we'll keep that, all of us" % " ".join(understood.slice(0, 3))]
		if kind == "gone":
			lines.append("\"%s\". then I'll stop looking so hard" % " ".join(understood.slice(0, 2)))
		return str(lines[randi() % lines.size()])
	if not understood.is_empty():
		return ("\"%s\" — we caught that part. we'll keep it" if we
				else "\"%s\" — I caught that part. I'll keep it") % understood[0]
	if tone == "kind":
		return "we don't know those sounds… but you answered us" if we \
				else "I don't know those sounds… but you answered me"
	return "the sounds are too big for us. we'll keep them anyway" if we \
			else "I don't know those sounds yet. I'll keep them anyway"


# The keeper's line answers the pending question. Returns {} when nothing is
# pending (or it expired / the asker is gone) — the caller then routes the
# line as ordinary talk. Otherwise {ok, fish_id, name, kind, line (the
# asker's acknowledgement), understood, comprehension, tone, collective}.
static func answer(sim, tm: Dictionary, text: String, now: float = -1.0) -> Dictionary:
	var t: float = _now(now)
	var qs: Dictionary = state(tm)
	var p: Dictionary = qs["pending"]
	var said: String = text.strip_edges()
	if p.is_empty() or said == "":
		return {}
	if t - float(p.get("t", t)) > PENDING_TTL_S:
		return {}
	var collective: bool = bool(p.get("collective", false))
	var fid: String = str(p.get("fish_id", ""))
	var listeners: Array = []
	if collective:
		listeners = _living(sim)
	else:
		var asker: Fish = fish_by_id(sim, fid)
		if asker == null:
			qs["pending"] = {}
			return {}
		listeners = [asker]
	var kind: String = str(p.get("kind", ""))
	var about: String = str(p.get("about", ""))
	var comp: Dictionary = comprehension(listeners, said)
	var tone: String = tone_of(said)
	var understood: PackedStringArray = comp["understood"]
	var heard: PackedStringArray = comp["words"]
	var keep_words: Array = []
	for w in (understood if not understood.is_empty() else heard):
		if keep_words.size() < WORDS_MAX:
			keep_words.append(str(w))
	var entry: Dictionary = {"k": kind, "q": str(p.get("line", "")), "a": _clean_answer(said),
			"w": keep_words, "c": snappedf(float(comp["c"]), 0.01), "about": about, "t": t, "told": 0.0}
	var answers: Dictionary = qs["answers"]
	var list: Array = answers.get(fid, []) as Array if answers.get(fid, []) is Array else []
	list.append(entry)
	while list.size() > ANSWERS_PER_FISH:
		list.pop_front()
	answers[fid] = list
	_bound_fish_map(answers, ANSWER_FISH_MAX)
	qs["pending"] = {}
	qs["answered_n"] = int(qs.get("answered_n", 0)) + 1
	var memory_text: String = "I asked the keeper %s. they said \"%s\"" % [_subject(kind, about),
			str(entry["a"])]
	var sal: float = clampf(0.5 + float(comp["c"]) * 0.3 + (0.1 if tone == "kind" else 0.0), 0.1, 0.95)
	# Collective: the most curious few carry the memory for the school.
	var carriers: Array = listeners.duplicate()
	if collective:
		carriers.sort_custom(func(a, b): return ask_score(a as Fish) > ask_score(b as Fish))
		carriers = carriers.slice(0, 3)
	for c in carriers:
		var f: Fish = c as Fish
		EpisodicMemory.encode_episode(f, "keeper_answer", memory_text.substr(0, 110), sal, f.position)
		_apply_answer_feel(f, tone)
	if collective:
		tm["mood_valence"] = clampf(float(tm.get("mood_valence", 0.0))
				+ (0.03 if tone != "harsh" else -0.03), -1.0, 1.0)
	return {"ok": true, "fish_id": fid, "name": str(p.get("name", "")), "kind": kind, "about": about,
			"line": _ack_line(kind, tone, comp, collective).substr(0, 110), "understood": understood,
			"comprehension": float(comp["c"]), "tone": tone, "collective": collective}


# Being answered kindly: a little more familiar, a little more trusting, and
# the itch to ask eases. A sharp answer stings.
static func _apply_answer_feel(f: Fish, tone: String) -> void:
	var km_v: Variant = f.get("_keeper_model")
	var km: Dictionary = km_v as Dictionary if km_v is Dictionary else {}
	if tone == "harsh":
		f.mood = clampf(f.mood - 0.05, -1.0, 1.0)
		f.stress = clampf(f.stress + 0.03, 0.0, 1.0)
		if km.has("care_trust"):
			km["care_trust"] = clampf(float(km["care_trust"]) - 0.01, 0.0, 1.0)
		return
	var gain: float = 1.0 if tone == "kind" else 0.6
	f.familiarity = clampf(f.familiarity + 0.03 * gain, 0.0, 1.0)
	f.mood = clampf(f.mood + 0.04 * gain, -1.0, 1.0)
	f._curiosity_about_keeper = clampf(f._curiosity_about_keeper - 0.08, 0.0, 1.0)
	if km.has("care_trust"):
		km["care_trust"] = clampf(float(km["care_trust"]) + 0.02 * gain, 0.0, 1.0)


# --- remembering the answer later ----------------------------------------------

static func answers_for(tm: Dictionary, fid: String) -> Array:
	var v: Variant = (state(tm)["answers"] as Dictionary).get(fid, [])
	return v as Array if v is Array else []


# A line referencing the most recent answer this fish was given ("" if none).
# `mark` records that it was brought up (RECALL_GAP_S throttles _maybe_recall).
static func recall_line(tm: Dictionary, fid: String, now: float = -1.0, mark: bool = true) -> String:
	var list: Array = answers_for(tm, fid)
	if list.is_empty():
		return ""
	var e: Dictionary = list[-1]
	var subj: String = _subject(str(e.get("k", "")), str(e.get("about", "")))
	var a: String = str(e.get("a", ""))
	var words: Array = e.get("w", []) as Array
	var who: String = "us" if fid == TANK_ID else "me"
	var out: String = ""
	if float(e.get("c", 0.0)) >= 0.5 and a != "":
		out = "you told %s about %s — \"%s\"" % [who, subj, a]
	elif not words.is_empty():
		out = "you told %s something about %s. \"%s\", I think" % [who, subj, str(words[0])]
	else:
		out = "you answered %s about %s once. I didn't know the sounds, but I kept them" % [who, subj]
	if mark:
		e["told"] = _now(now)
	return out.substr(0, 130)


static func _maybe_recall(sim, qs: Dictionary, t: float) -> Dictionary:
	var answers: Dictionary = qs["answers"]
	for c in _living(sim):
		var f: Fish = c as Fish
		if f._asleep:
			continue
		var list_v: Variant = answers.get(str(f.id), null)
		if not (list_v is Array) or (list_v as Array).is_empty():
			continue
		var e: Dictionary = (list_v as Array)[-1]
		if t - float(e.get("told", 0.0)) < RECALL_GAP_S or t - float(e.get("t", t)) < 60.0:
			continue
		var tm_stub: Dictionary = {"keeper_questions": qs}
		var line: String = recall_line(tm_stub, str(f.id), t)
		if line == "":
			continue
		qs["last_ask_unix"] = t
		return {"recall": true, "fish_id": str(f.id), "name": moniker(f), "line": line}
	return {}
