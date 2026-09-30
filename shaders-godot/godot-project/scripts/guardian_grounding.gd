extends RefCounted

# SENTIENCE_EMBEDDED #72 — grounded prompts + post-generation validation for the
# small in-process model (SmolLM2-360M) and the Ollama tiers.
#
# Two halves:
#   1. build_prompt(): a COMPACT completion-style prompt. The old path fed the
#      whole context dict as JSON (40+ keys, often >1024 tokens), which the
#      native context silently truncated from the FRONT — dropping the rules.
#      Here the model gets a handful of plain facts, a few-shot drawn from the
#      fish's real state (the template line IS a grounded example of its voice),
#      and a speaker tag to complete. Stop sequences end it at the first line.
#   2. validate()/finalize(): every model line passes through here before it
#      can reach the UI. Rejects assistant-speak, emojis, meta talk, markup,
#      over-long / truncated lines, and claims that contradict sim state
#      ("the water is clean" while ammonia is high). A rejected line becomes
#      the template fallback — it is never shown.
#
# Deliberately no class_name (preload it): a new global needs an editor rescan
# before headless --script runs resolve it (AGENTS.md).

const MindNarrator = preload("res://scripts/mind_narrator.gd")

const KIND_GUARDIAN: String = "guardian"
const KIND_THOUGHT: String = "thought"
const KIND_REPLY: String = "reply"
const KIND_CHRONICLE: String = "chronicle"

const RECAP_MAX_WORDS: int = 36
const CHRONICLE_MAX_WORDS: int = 22
const MIN_WORDS: int = 2
# Stop at the first line / next speaker — the few-shot format makes the model
# want to continue the transcript otherwise.
const STOP_SEQUENCES: Array = ["\n", "<|im_end|>", "<|endoftext|>", "<|im_start|>", "Keeper:"]

const HUNGRY_AT: float = 0.62
const FED_BELOW: float = 0.22
const STRESSED_AT: float = 0.6

# Lowercase substrings. Assistant register, refusals, and fourth-wall talk.
const ASSISTANT_SPEAK: Array = [
	"as an ai", "an ai ", "ai model", "language model", "assistant", "chatbot",
	"chatgpt", "openai", "i'm here to help", "i am here to help", "here to help",
	"happy to help", "glad to help", "how can i help", "how may i", "i can help",
	"can i help", "let me know", "feel free", "i cannot", "i can't help",
	"i'm sorry, but", "i am sorry, but", "sorry, but i", "i apologize",
	"certainly!", "of course!", "sure!", "great question",
	"i hope this", "hope this helps", "in summary", "in conclusion", "disclaimer",
	"as a fish", "as your guardian", "as the guardian",
]
const META_TALK: Array = [
	"prompt", "context", "instruction", "the user", "user:",
	"sentence", "word count", "words max", "max words", "roleplay", "role-play",
	"in character", "character", "moniker", "json", "the facts", "facts:",
	"situation:", "example", "simulation", "video game", "the game", "the player",
	"npc", "http", "www.", "```",
]
const MARKUP_CHARS: Array = ["{", "}", "<", ">", "[", "]", "#", "*", "|", "_", "`", "\\", "@"]

# Contradiction patterns, checked against derived facts. (?i) regexes.
const RX_CLAIM_WATER_CLEAN: String = (
	"(?i)\\b(clean|clear|fresh|pure|perfect|healthy|sweet|crisp)\\s+(water|tank)\\b"
	+ "|\\b(water|tank)\\b[^.!?]{0,24}\\b(is|feels|looks|seems|tastes|stays)\\s+"
	+ "(so\\s+|very\\s+|nice\\s+and\\s+)?(clean|clear|fresh|pure|perfect|healthy|fine|great|good|safe)\\b"
	+ "|\\b(all is well|everything is fine|everything's fine|all is fine|nothing is wrong)\\b")
const RX_CLAIM_WATER_BAD: String = (
	"(?i)\\b(dirty|foul|toxic|poison(ed|ous)?|murky|sour|burning|stinging)\\s+(water|tank)\\b"
	+ "|\\b(water|tank)\\b[^.!?]{0,24}\\b(is|feels|tastes|seems)\\s+(so\\s+|very\\s+)?"
	+ "(dirty|foul|toxic|poison(ed|ous)?|wrong|bad|sour|burning)\\b")
const RX_CLAIM_AIR_EASY: String = (
	"(?i)\\b(breath(e|ing)?\\s+(is\\s+)?(easy|easily|freely|deep)|plenty of (air|oxygen))\\b")
const RX_CLAIM_NOT_HUNGRY: String = (
	"(?i)\\b(not|never|no longer)\\s+hungry\\b|\\bwell[- ]fed\\b|\\bso full\\b|\\bbelly is full\\b"
	+ "|\\bjust ate\\b|\\bate (so )?much\\b|\\bno need (for|of) food\\b")
const RX_CLAIM_STARVING: String = (
	"(?i)\\bstarv(ing|e|ed)\\b|\\bso hungry\\b|\\bhaven'?t eaten\\b|\\bno food (for|in) days\\b")
const RX_CLAIM_HAPPY: String = (
	"(?i)\\b(so |very |truly )?(happy|joyful|joyous|delighted|ecstatic|carefree|blissful|thrilled)\\b")
# Assistant-style openers ("Sure, ...", "Certainly. ...") only at the start —
# "I'm not sure, but" mid-line is fine fish talk.
const RX_ASSISTANT_OPENER: String = "(?i)^(sure|certainly|of course|absolutely|okay|ok|well)[,.!]\\s"
const RX_CLAIM_SUN: String = "(?i)\\b(sunshine|sunny|the sun|bright morning|broad daylight)\\b"

static var _rx_cache: Dictionary = {}

# Health counters local to this module (the narrator's counters are bumped too).
static var rejects: int = 0
static var accepts: int = 0
static var last_reason: String = ""
static var reject_reasons: Dictionary = {}


static func reset_stats_for_test() -> void:
	rejects = 0
	accepts = 0
	last_reason = ""
	reject_reasons.clear()


# ---- Kind / limits ---------------------------------------------------------

static func kind_for(cache_key: String, ctx: Dictionary) -> String:
	var sit: String = str(ctx.get("situation", ""))
	if sit == "keeper_reply":
		return KIND_REPLY
	if cache_key.begins_with("thought|") or cache_key.begins_with("cog|"):
		return KIND_THOUGHT
	if sit.begins_with("keeper_") or sit in ["inspect", "follow", "idle"]:
		return KIND_THOUGHT
	return KIND_GUARDIAN


static func max_words(kind: String, situation: String = "") -> int:
	match kind:
		KIND_REPLY:
			return MindNarrator.FISH_REPLY_MAX_WORDS
		KIND_THOUGHT:
			return MindNarrator.FISH_THOUGHT_MAX_WORDS
		KIND_CHRONICLE:
			return CHRONICLE_MAX_WORDS
		_:
			if situation == "away_recap":
				return RECAP_MAX_WORDS
			return MindNarrator.GUARDIAN_MAX_WORDS


# ---- World facts -----------------------------------------------------------

# Adds plain grounding fields read straight from the sim, so the prompt and the
# validator agree on what is true. Safe with a null sim.
static func annotate_world(ctx: Dictionary, sim: Node) -> Dictionary:
	if sim == null:
		return ctx
	var chem: Variant = sim.get("water_chemistry")
	if chem != null and chem is Object:
		var nh3: float = float((chem as Object).get("ammonia") if (chem as Object).get("ammonia") != null else 0.0)
		var no2: float = float((chem as Object).get("nitrite") if (chem as Object).get("nitrite") != null else 0.0)
		ctx["ammonia"] = snappedf(nh3, 0.01)
		ctx["nitrite"] = snappedf(no2, 0.01)
	var o2_v: Variant = sim.get("dissolved_o2")
	if o2_v != null:
		ctx["dissolved_o2"] = snappedf(float(o2_v), 0.01)
	if sim.has_method("daylight"):
		ctx["daylight"] = snappedf(float(sim.call("daylight")), 0.01)
	ctx["water_state"] = water_state(ctx)
	return ctx


static func water_state(ctx: Dictionary) -> String:
	var explicit: String = str(ctx.get("water_state", ""))
	if explicit in ["fouled", "thin_air", "steady"]:
		return explicit
	if ctx.has("ammonia") or ctx.has("nitrite"):
		if float(ctx.get("ammonia", 0.0)) > 0.3 or float(ctx.get("nitrite", 0.0)) > 0.4:
			return "fouled"
	if ctx.has("dissolved_o2") and float(ctx.get("dissolved_o2", 1.0)) < 0.5:
		return "thin_air"
	var wr: String = str(ctx.get("world_read", "")).to_lower()
	if "wrong" in wr:
		return "fouled"
	if "thin" in wr:
		return "thin_air"
	if _list_has(ctx.get("wants", null), "cleaner water"):
		return "fouled"
	if ctx.has("ammonia") or "steady" in wr:
		return "steady"
	return ""


static func facts(ctx: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var ws: String = water_state(ctx)
	out["water"] = ws
	var hungry: bool = false
	var fed: bool = false
	if ctx.has("hunger"):
		var h: float = float(ctx.get("hunger", 0.0))
		hungry = h > HUNGRY_AT
		fed = h < FED_BELOW
	if _list_has(ctx.get("wants", null), "eat soon"):
		hungry = true
		fed = false
	out["hungry"] = hungry
	out["fed"] = fed
	var feel: String = str(ctx.get("feel", "")).to_lower()
	out["stressed"] = float(ctx.get("stress", 0.0)) > STRESSED_AT \
			or feel in ["anxious", "scared", "afraid", "panicked", "sulking"]
	var night: bool = false
	var day: bool = false
	var phase: String = str(ctx.get("day_phase", "")).to_lower()
	if ctx.has("daylight"):
		night = float(ctx.get("daylight", 0.5)) < 0.2
		day = float(ctx.get("daylight", 0.5)) > 0.6
	elif phase != "":
		night = "night" in phase
		day = phase in ["day", "midday", "noon", "afternoon"]
	out["night"] = night
	out["day"] = day
	return out


# ---- Prompt ----------------------------------------------------------------

static func _speaker(ctx: Dictionary) -> String:
	var nm: String = str(ctx.get("fish_name", "")).strip_edges()
	if nm == "":
		nm = str(ctx.get("species", "")).strip_edges().capitalize()
	if nm == "":
		nm = "Fish"
	return _plain(nm, 24)


static func _plain(s: String, cap: int) -> String:
	var out: String = s.replace("\n", " ").replace("\r", " ").replace("\"", "'")
	for ch in ["<", ">", "{", "}", "|", "`"]:
		out = out.replace(ch, "")
	out = out.strip_edges()
	if out.length() > cap:
		out = out.substr(0, cap).strip_edges()
	return out


static func _facts_lines(ctx: Dictionary, kind: String) -> PackedStringArray:
	var f: Dictionary = facts(ctx)
	var lines: PackedStringArray = PackedStringArray()
	var species: String = _plain(str(ctx.get("species", "")), 24)
	if species != "":
		lines.append("Species: %s." % species.replace("_", " "))
	var feel: String = _plain(str(ctx.get("feel", ctx.get("mood", ""))), 20)
	if feel != "":
		lines.append("Feeling: %s." % feel)
	if bool(f.get("hungry", false)):
		lines.append("Belly: hungry.")
	elif bool(f.get("fed", false)):
		lines.append("Belly: recently fed.")
	match str(f.get("water", "")):
		"fouled":
			lines.append("Water: fouled, it stings.")
		"thin_air":
			lines.append("Water: breathing is hard.")
		"steady":
			lines.append("Water: steady.")
	if bool(f.get("night", false)):
		lines.append("Light: night, dark.")
	elif bool(f.get("day", false)):
		lines.append("Light: bright.")
	if bool(f.get("stressed", false)):
		lines.append("Body: tense, uneasy.")
	if kind == KIND_GUARDIAN:
		var mon: String = _plain(str(ctx.get("player_moniker", "")), 28)
		if mon != "":
			lines.append("The keeper is called: %s." % mon)
		var sit: String = str(ctx.get("situation", ""))
		var moment: String = situation_meaning(sit, ctx)
		if moment != "":
			lines.append("Now: %s." % _plain(moment, 90))
	var mems: PackedStringArray = _memory_snippets(ctx, 2)
	if not mems.is_empty():
		lines.append("Remembers: %s." % "; ".join(mems))
	return lines


static func situation_meaning(sit: String, ctx: Dictionary) -> String:
	match sit:
		"arrival":
			return "the keeper came back to the glass"
		"departure":
			return "the keeper is leaving"
		"feed_nudge":
			return "everyone is hungry, hoping for food"
		"autofeed_on":
			return "the tank is feeding itself until the keeper returns"
		"water_stress":
			return "the water feels wrong"
		"tank_care":
			return "the tank needs a little care"
		"morning":
			return "morning light is coming"
		"away_recap":
			var gap: String = _plain(str(ctx.get("away_gap", ctx.get("gap_human", ""))), 30)
			return "the keeper is back after being away" + (" %s" % gap if gap != "" else "")
		"daily":
			return "first visit of the day"
		"observe":
			var on: String = _plain(str(ctx.get("observed_fish", "")), 20)
			var of: String = _plain(str(ctx.get("observed_feel", "")), 16)
			if on != "":
				return "watching %s, who seems %s" % [on, of if of != "" else "quiet"]
			return "watching the others"
		"newcomer":
			return "someone new joined the tank"
		"loss", "witnessed_death", "obituary":
			return "someone in the tank has died"
		"goodnight", "goodnight_hard":
			return "the keeper is saying goodnight"
		"recovery":
			return "the tank has steadied again"
		"":
			return ""
		_:
			return sit.replace("_", " ")


static func _memory_snippets(ctx: Dictionary, n: int) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for key in ["salient_memories", "memories_of_you"]:
		var v: Variant = ctx.get(key, null)
		var items: Array = []
		if v is PackedStringArray:
			for s in (v as PackedStringArray):
				items.append(s)
		elif v is Array:
			items = v as Array
		# Most recent last — walk backwards.
		for i in range(items.size() - 1, -1, -1):
			if out.size() >= n:
				break
			var it: Variant = items[i]
			var text: String = ""
			if it is Dictionary:
				text = str((it as Dictionary).get("text", (it as Dictionary).get("summary", "")))
			else:
				text = str(it)
			text = _plain(text, 60)
			if text != "" and not out.has(text):
				out.append(text)
		if out.size() >= n:
			break
	return out


static func _examples(ctx: Dictionary, fallback: String, kind: String) -> PackedStringArray:
	var ex: PackedStringArray = PackedStringArray()
	var fb: String = _plain(fallback, 140)
	# Template lines can carry a "[Chapter]" prefix — never teach brackets.
	if fb.begins_with("[") and "]" in fb:
		fb = fb.substr(fb.find("]") + 1).strip_edges()
	var recent: Variant = ctx.get("recent_lines", null)
	if recent is PackedStringArray:
		var rl: PackedStringArray = recent as PackedStringArray
		for i in range(maxi(0, rl.size() - 2), rl.size()):
			var r: String = _plain(String(rl[i]), 140)
			if r != "" and r != fb and validate(kind, ctx, r).get("ok", false):
				ex.append(r)
	if fb != "" and fb != "..." and fb != "…":
		ex.append(fb)
	return ex


# Compact completion prompt for tiny models. Deterministic for a given ctx.
static func build_prompt(kind: String, ctx: Dictionary, fallback: String = "") -> String:
	var who: String = _speaker(ctx)
	var limit: int = max_words(kind, str(ctx.get("situation", "")))
	var rules: String = ""
	match kind:
		KIND_REPLY:
			rules = ("%s is a small aquarium fish. It hears the keeper and answers in first person, "
				+ "at most %d words, simple sensory words, fragments are fine. "
				+ "It does not understand every word.") % [who, limit]
		KIND_THOUGHT:
			rules = ("%s is a small aquarium fish. Write its next private thought: first person, "
				+ "present tense, one sentence, at most %d words, about what it senses.") % [who, limit]
		_:
			rules = ("%s is the tank's guardian fish. It speaks to the keeper in one or two short "
				+ "sentences, first person, at most %d words, warm and observant.") % [who, limit]
	rules += (" Use only the facts below. No questions, no emojis, no lists."
		+ " Never mention AI, help, stories or games.")
	var parts: PackedStringArray = PackedStringArray()
	parts.append(rules)
	parts.append("")
	for line in _facts_lines(ctx, kind):
		parts.append(line)
	var tag: String = "%s says" % who if kind != KIND_THOUGHT else "%s thinks" % who
	var keeper: String = ""
	if kind == KIND_REPLY:
		keeper = MindNarrator.prompt_safe_keeper_text(str(ctx.get("keeper_text", "")))
		keeper = _plain(keeper, 100)
	parts.append("")
	for e in _examples(ctx, fallback, kind):
		if kind == KIND_REPLY:
			parts.append("Keeper: (a sound at the glass)")
		parts.append("%s: %s" % [tag, e])
	if kind == KIND_REPLY:
		parts.append("Keeper: %s" % (keeper if keeper != "" else "(a sound at the glass)"))
	parts.append("%s:" % tag)
	return "\n".join(parts)


static func generation_params(cache_key: String, n_predict: int) -> Dictionary:
	return {
		"temperature": 0.35,
		"top_p": 0.9,
		"top_k": 40,
		"repeat_penalty": 1.12,
		"seed": seed_from_key(cache_key),
		"stop": STOP_SEQUENCES.duplicate(),
		"max_tokens": n_predict,
	}


static func seed_from_key(key: String) -> int:
	var h: int = 0
	for i in key.length():
		h = (h * 31 + key.unicode_at(i)) & 0x7fffffff
	return h if h > 0 else 1


# ---- Validation ------------------------------------------------------------

static func _rx(pattern: String) -> RegEx:
	if _rx_cache.has(pattern):
		return _rx_cache[pattern] as RegEx
	var r := RegEx.new()
	if r.compile(pattern) != OK:
		push_warning("[GuardianGrounding] bad regex: %s" % pattern)
		r = null
	_rx_cache[pattern] = r
	return r


static func _matches(pattern: String, s: String) -> bool:
	var r: RegEx = _rx(pattern)
	return r != null and r.search(s) != null


static func _list_has(v: Variant, needle: String) -> bool:
	if v is PackedStringArray:
		return (v as PackedStringArray).has(needle)
	if v is Array:
		return (v as Array).has(needle)
	return false


static func has_emoji(s: String) -> bool:
	for i in s.length():
		var c: int = s.unicode_at(i)
		if (c >= 0x1F000 and c <= 0x1FAFF) or (c >= 0x2600 and c <= 0x27BF) \
				or (c >= 0x2B00 and c <= 0x2BFF) or c == 0xFE0F or c == 0x200D \
				or (c >= 0x1F1E6 and c <= 0x1F1FF) or (c >= 0xE000 and c <= 0xF8FF):
			return true
	return false


# Cheap cleanup that never changes meaning: special tokens, a leading speaker
# tag the model echoed, wrapping quotes, first line only.
static func repair(ctx: Dictionary, raw: String) -> String:
	var s: String = raw
	# Ollama reply prompts ask for {"line": ...} — unwrap before markup checks.
	var trimmed: String = s.strip_edges()
	if trimmed.begins_with("{"):
		var json := JSON.new()
		var parsed: Variant = json.get_data() if json.parse(trimmed) == OK else null
		if parsed is Dictionary:
			var d: Dictionary = parsed as Dictionary
			s = str(d.get("line", d.get("text", d.get("response", ""))))
	for tag in ["<|im_end|>", "<|endoftext|>", "<|im_start|>", "</s>", "<s>"]:
		s = s.replace(tag, "\n" if tag == "<|im_start|>" else "")
	s = s.strip_edges()
	if "\n" in s:
		s = s.split("\n", false)[0].strip_edges() if s.split("\n", false).size() > 0 else ""
	var who: String = _speaker(ctx).to_lower()
	for _i in 2:
		var colon: int = s.find(":")
		if colon > 0 and colon <= 32:
			var head: String = s.substr(0, colon).strip_edges().to_lower()
			var tagged: bool = head in ["guardian", "assistant", "fish", "me", "answer", "reply",
					"thought", "line", "response"] \
					or head == who or head == "%s says" % who or head == "%s thinks" % who \
					or head.ends_with(" says") or head.ends_with(" thinks")
			if tagged:
				s = s.substr(colon + 1).strip_edges()
				continue
		break
	while s.length() >= 2 and ((s.begins_with("\"") and s.ends_with("\""))
			or (s.begins_with("'") and s.ends_with("'"))
			or (s.begins_with("“") and s.ends_with("”"))):
		s = s.substr(1, s.length() - 2).strip_edges()
	if s.begins_with("\"") and s.count("\"") == 1:
		s = s.substr(1).strip_edges()
	while "  " in s:
		s = s.replace("  ", " ")
	return s


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "line": "", "reason": reason}


# Prefix-safe checks, usable on a partial stream: anything that fails here will
# fail the final validation too, so streaming can stop early.
static func check_content(kind: String, ctx: Dictionary, s: String) -> String:
	var low: String = s.to_lower()
	if has_emoji(s):
		return "emoji"
	for bad in ASSISTANT_SPEAK:
		if bad in low:
			return "assistant_speak"
	if _matches(RX_ASSISTANT_OPENER, s):
		return "assistant_speak"
	for bad in META_TALK:
		if bad in low:
			return "meta_talk"
	for ch in MARKUP_CHARS:
		if ch in s:
			return "markup"
	if ":" in s:
		return "meta_format"
	if _matches("(?i)\\b(fuck|shit|damn|bitch|crap)\\b", s):
		return "profanity"
	var f: Dictionary = facts(ctx)
	var water: String = str(f.get("water", ""))
	if water in ["fouled", "thin_air"] and _matches(RX_CLAIM_WATER_CLEAN, s):
		return "contradiction:water_clean"
	if water == "steady" and _matches(RX_CLAIM_WATER_BAD, s):
		return "contradiction:water_bad"
	if water == "thin_air" and _matches(RX_CLAIM_AIR_EASY, s):
		return "contradiction:air_easy"
	if bool(f.get("hungry", false)) and _matches(RX_CLAIM_NOT_HUNGRY, s):
		return "contradiction:not_hungry"
	if bool(f.get("fed", false)) and _matches(RX_CLAIM_STARVING, s):
		return "contradiction:starving"
	if bool(f.get("stressed", false)) and _matches(RX_CLAIM_HAPPY, s):
		return "contradiction:happy_under_stress"
	if bool(f.get("night", false)) and _matches(RX_CLAIM_SUN, s):
		return "contradiction:sun_at_night"
	if kind == KIND_REPLY or kind == KIND_THOUGHT:
		# Fish don't narrate the UI or the keeper's device.
		if _matches("(?i)\\b(screen|button|click|keyboard|computer|phone|app)\\b", s):
			return "meta_talk"
	return ""


static func partial_ok(kind: String, ctx: Dictionary, partial: String) -> bool:
	var s: String = repair(ctx, partial)
	if s == "":
		return true
	return check_content(kind, ctx, s) == ""


# Full validation. Returns {ok, line (repaired), reason}.
static func validate(kind: String, ctx: Dictionary, raw: String) -> Dictionary:
	var s: String = repair(ctx, raw)
	if s == "":
		return _fail("empty")
	var reason: String = check_content(kind, ctx, s)
	if reason != "":
		return _fail(reason)
	var words: PackedStringArray = s.split(" ", false)
	if words.size() < MIN_WORDS:
		return _fail("too_short")
	var limit: int = max_words(kind, str(ctx.get("situation", "")))
	if words.size() > limit:
		# Repair: keep whole leading sentences that fit; never cut mid-sentence.
		var kept: String = _leading_sentences(s, limit)
		if kept == "":
			return _fail("too_long")
		s = kept
		words = s.split(" ", false)
	# Repetition loops are the classic small-model failure.
	var counts: Dictionary = {}
	for w in words:
		var k: String = w.to_lower().strip_edges().trim_suffix(".").trim_suffix(",")
		if k.length() < 3:
			continue
		counts[k] = int(counts.get(k, 0)) + 1
		if int(counts[k]) >= 4:
			return _fail("repetitive")
	var ends_ok: bool = s.ends_with(".") or s.ends_with("!") or s.ends_with("…") \
			or s.ends_with("?") or s.ends_with("...")
	if not ends_ok:
		# A token-capped line that stopped near the limit is almost surely cut off.
		if words.size() >= int(ceil(float(limit) * 0.8)):
			return _fail("truncated")
		s = s.trim_suffix(",").trim_suffix(";").trim_suffix(" -").strip_edges() + "."
	# Copying the rules back is a telltale of a confused model.
	var low: String = s.to_lower()
	if "first person" in low or "at most" in low or "the keeper is called" in low:
		return _fail("prompt_echo")
	return {"ok": true, "line": s, "reason": ""}


static func _leading_sentences(s: String, limit: int) -> String:
	var out: String = ""
	var count: int = 0
	var start: int = 0
	var i: int = 0
	while i < s.length():
		var c: String = s[i]
		if c == "." or c == "!" or c == "?" or c == "…":
			var sentence: String = s.substr(start, i - start + 1).strip_edges()
			var n: int = sentence.split(" ", false).size()
			if count + n > limit:
				break
			out = (out + " " + sentence).strip_edges()
			count += n
			start = i + 1
		i += 1
	return out


static func _note_reject(reason: String) -> void:
	rejects += 1
	last_reason = reason
	reject_reasons[reason] = int(reject_reasons.get(reason, 0)) + 1


# The one gate every model line goes through (in-process AND Ollama tiers).
# Grounding validation first, then the narrator's entity/number/manipulation
# checks. Returns {line, source ("model"|"fallback"), reason}.
static func finalize(kind: String, ctx: Dictionary, raw: String, fallback: String) -> Dictionary:
	var v: Dictionary = validate(kind, ctx, raw)
	if not bool(v.get("ok", false)):
		var why: String = "grounding:%s" % str(v.get("reason", ""))
		_note_reject(why)
		MindNarrator.gen_attempts += 1
		MindNarrator.fallback_uses += 1
		MindNarrator.fact_check_rejects += 1
		MindNarrator.last_reject_reason = why
		return {"line": fallback, "source": "fallback", "reason": why}
	var cleaned: String = str(v.get("line", ""))
	var limit: int = max_words(kind, str(ctx.get("situation", "")))
	var fin: Dictionary
	if kind == KIND_REPLY:
		fin = MindNarrator.finalize_reply_line(ctx, cleaned, fallback, limit)
	elif kind == KIND_CHRONICLE:
		fin = {"line": cleaned, "source": "model", "reason": ""}
	else:
		fin = MindNarrator.finalize_line(ctx, cleaned, fallback, limit)
	var line: String = str(fin.get("line", fallback))
	if str(fin.get("source", "")) == "model" and line == fallback:
		# The model echoed its own few-shot template — harmless, not a reject.
		return {"line": fallback, "source": "fallback", "reason": "copied_template"}
	if str(fin.get("source", "")) != "model":
		_note_reject("narrator:%s" % str(fin.get("reason", "")))
		return {"line": fallback, "source": "fallback", "reason": str(fin.get("reason", ""))}
	# sanitize_prose may have re-punctuated — re-check content once.
	if check_content(kind, ctx, line) != "":
		_note_reject("post_polish")
		return {"line": fallback, "source": "fallback", "reason": "post_polish"}
	accepts += 1
	return {"line": line, "source": "model", "reason": ""}
