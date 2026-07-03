extends RefCounted

# CONSCIOUSNESS_ENGINEERING §F + DARING §B — structured cognitive operations + validation.

const MindNarrator = preload("res://scripts/mind_narrator.gd")
const KeeperInput = preload("res://scripts/keeper_input.gd")
const MindLexicon = preload("res://scripts/mind_lexicon.gd")

const SCHEMA_VERSION: int = 2

const MOOD_NUDGE_MAX: float = 0.1
const ALLOWED_APPRAISALS: Array = [
	"safe", "uncertain", "threatened", "hopeful", "sad", "content", "curious",
]
const ALLOWED_INTENTIONS: Array = [
	"seek_food", "seek_safety", "explore", "rest", "social", "watch", "none",
]
const ALLOWED_KEEPER_FELT: Array = [
	"greeting", "comfort", "scold", "question", "name", "neutral", "silence",
]
const ALLOWED_KEEPER_INTENTS: Array = [
	"greeting", "comfort", "scold", "question", "name", "neutral", "silence",
	"unknown_sound", "misheard", "food", "presence",
]
const ALLOWED_CHOICES: Array = ["approach", "avoid"]
const ALLOWED_PLAN_VERBS: Array = [
	"go_to_nook", "wait_for_feed", "shadow_mate", "watch", "rest",
]


static func template_op(ctx: Dictionary) -> Dictionary:
	var feel: String = str(ctx.get("feel", "calm"))
	var appraisal: String = "content" if feel in ["content", "cozy", "calm"] else "uncertain"
	if feel in ["anxious", "sulking"]:
		appraisal = "threatened"
	var op: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"appraisal": appraisal,
		"intention": "none",
		"mood_nudge": 0.0,
		"memory_keep": false,
		"certainty": 0.72,
		"line": MindNarrator.template_fish_thought(ctx),
	}
	if ctx.has("keeper_text") and str(ctx.get("keeper_text", "")) != "":
		op["keeper_felt"] = str(ctx.get("keeper_felt", "neutral"))
	return op


static func parse_line(raw: String) -> Dictionary:
	var s: String = raw.strip_edges()
	if s.begins_with("{"):
		var parsed: Variant = JSON.parse_string(s)
		if parsed is Dictionary:
			return parsed as Dictionary
	return {
		"schema_version": SCHEMA_VERSION,
		"line": s,
		"appraisal": "uncertain",
		"intention": "none",
	}


static func validate_op(op: Dictionary, ctx: Dictionary) -> bool:
	if op.is_empty():
		return false
	var appraisal: String = str(op.get("appraisal", ""))
	if appraisal != "" and not ALLOWED_APPRAISALS.has(appraisal):
		return false
	var intent: String = str(op.get("intention", ""))
	if intent != "" and intent != "none" and not ALLOWED_INTENTIONS.has(intent):
		return false
	if absf(float(op.get("mood_nudge", 0.0))) > MOOD_NUDGE_MAX + 0.001:
		return false
	if op.has("feel_token") and str(op.get("feel_token", "")) != str(ctx.get("feel", "")):
		return false
	if op.has("keeper_felt"):
		if not ALLOWED_KEEPER_FELT.has(str(op.get("keeper_felt", ""))):
			return false
	if op.has("keeper_intent"):
		if not ALLOWED_KEEPER_INTENTS.has(str(op.get("keeper_intent", ""))):
			return false
	if op.has("choice"):
		if not ALLOWED_CHOICES.has(str(op.get("choice", ""))):
			return false
	if op.has("certainty"):
		var c: float = float(op.get("certainty", 1.0))
		if c < 0.0 or c > 1.0:
			return false
	if op.has("plan") and op.get("plan") is Array:
		for step in op["plan"]:
			if not ALLOWED_PLAN_VERBS.has(str(step)):
				return false
	if op.has("bid_weight") and op.get("bid_weight") is Dictionary:
		for k in op["bid_weight"]:
			var v: float = float((op["bid_weight"] as Dictionary)[k])
			if v < -0.25 or v > 0.35:
				return false
	if op.has("new_belief"):
		var nb: String = str(op.get("new_belief", ""))
		if nb.length() > 48 or nb.length() < 3:
			return false
	return true


static func gbnf_grammar(_allowed_names: PackedStringArray) -> String:
	return (
		"root ::= op\n"
		+ "op ::= \"{\" ws \"\\\"appraisal\\\"\" ws \":\" ws appraisal ws \",\" ws "
		+ "\"\\\"intention\\\"\" ws \":\" ws intention ws \",\" ws "
		+ "\"\\\"mood_nudge\\\"\" ws \":\" ws number ws \",\" ws "
		+ "\"\\\"line\\\"\" ws \":\" ws string ws \"}\"\n"
		+ "appraisal ::= \"\\\"safe\\\"\" | \"\\\"uncertain\\\"\" | \"\\\"threatened\\\"\" | "
		+ "\"\\\"hopeful\\\"\" | \"\\\"sad\\\"\" | \"\\\"content\\\"\" | \"\\\"curious\\\"\"\n"
		+ "intention ::= \"\\\"none\\\"\" | \"\\\"seek_food\\\"\" | \"\\\"seek_safety\\\"\" | "
		+ "\"\\\"explore\\\"\" | \"\\\"rest\\\"\" | \"\\\"social\\\"\" | \"\\\"watch\\\"\"\n"
		+ "number ::= \"-0.\" [0-9] | \"0.\" [0-9] | \"0\"\n"
		+ "string ::= \"\\\"\" [^\"]* \"\\\"\"\n"
		+ "ws ::= [ \\t\\n]*\n"
	)


# CONVERSATION §A #84 — structurally short fish replies (≤8 words, no Q&A register).
static func gbnf_reply_grammar() -> String:
	return (
		"root ::= op\n"
		+ "op ::= \"{\" ws \"\\\"line\\\"\" ws \":\" ws short_string ws \",\" ws "
		+ "\"\\\"appraisal\\\"\" ws \":\" ws appraisal ws \",\" ws "
		+ "\"\\\"keeper_intent\\\"\" ws \":\" ws keeper_intent ws \",\" ws "
		+ "\"\\\"certainty\\\"\" ws \":\" ws number ws \"}\"\n"
		+ "appraisal ::= \"\\\"safe\\\"\" | \"\\\"uncertain\\\"\" | \"\\\"threatened\\\"\" | "
		+ "\"\\\"hopeful\\\"\" | \"\\\"sad\\\"\" | \"\\\"content\\\"\" | \"\\\"curious\\\"\"\n"
		+ "keeper_intent ::= \"\\\"greeting\\\"\" | \"\\\"comfort\\\"\" | \"\\\"scold\\\"\" | "
		+ "\"\\\"question\\\"\" | \"\\\"name\\\"\" | \"\\\"neutral\\\"\" | \"\\\"unknown_sound\\\"\" | "
		+ "\"\\\"misheard\\\"\" | \"\\\"food\\\"\" | \"\\\"presence\\\"\"\n"
		+ "number ::= \"-0.\" [0-9] | \"0.\" [0-9] | \"0\"\n"
		+ "short_string ::= \"\\\"\" short_chars \"\\\"\"\n"
		+ "short_chars ::= short_char | short_char short_chars\n"
		+ "short_char ::= [^\"]{1,64}\n"
		+ "ws ::= [ \\t\\n]*\n"
	)


static func template_reply_op(ctx: Dictionary) -> Dictionary:
	var line: String = MindNarrator.template_fish_reply(ctx)
	var appraisal: String = "uncertain"
	var feel: String = str(ctx.get("feel", ""))
	if feel in ["content", "cozy", "calm"]:
		appraisal = "content"
	elif feel in ["anxious", "sulking"]:
		appraisal = "threatened"
	elif feel in ["playful", "excited"]:
		appraisal = "curious"
	return {
		"schema_version": SCHEMA_VERSION,
		"line": line,
		"appraisal": appraisal,
		"keeper_intent": str(ctx.get("keeper_intent", ctx.get("keeper_felt", "neutral"))),
		"certainty": clampf(float(ctx.get("keeper_comprehension", 0.5)), 0.0, 1.0),
	}


static func interpret_keeper_heuristic(text: String, f: Fish) -> Dictionary:
	var tone: Dictionary = KeeperInput.score_tone(text)
	var intent: String = str(tone.get("felt", "neutral"))
	var lower: String = text.strip_edges().to_lower()
	if lower.contains("feed") or lower.contains("food") or lower.contains("dinner"):
		intent = "food"
	elif lower.contains("think") or lower.contains("attention") or lower.contains("mind"):
		intent = "introspection"
	elif lower.contains("how do you feel") or (lower.contains("why") \
			and (lower.contains("feel") or lower.contains("did"))):
		intent = "introspection"
	elif lower.contains("safe") or lower.contains("calm") or lower.contains("trust") \
			or lower.contains("okay") or lower.begins_with("ok"):
		intent = "comfort"
	elif MindLexicon.comprehend(f, text):
		intent = "presence"
	var tokens: PackedStringArray = lower.split(" ", false)
	var unknown: bool = tokens.size() > 0
	for tok in tokens:
		if MindLexicon.comprehend(f, tok):
			unknown = false
			break
	if unknown and tokens.size() > 0 and intent not in ["comfort", "food", "introspection"]:
		intent = "unknown_sound"
	if intent == "comfort" or str(tone.get("felt", "")) == "comfort":
		intent = "comfort"
	return {
		"keeper_intent": intent,
		"keeper_felt": str(tone.get("felt", "neutral")),
		"keeper_valence": tone.get("valence", 0.0),
		"keeper_arousal": tone.get("arousal", 0.0),
	}


static func validate_reply_op(op: Dictionary, ctx: Dictionary) -> bool:
	if not validate_op(op, ctx):
		return false
	var line: String = str(op.get("line", ""))
	if line.strip_edges() == "":
		return false
	var words: PackedStringArray = line.strip_edges().split(" ", false)
	if words.size() > MindNarrator.FISH_REPLY_MAX_WORDS:
		return false
	var check: Dictionary = MindNarrator.validate_reply_line(ctx, line)
	return bool(check.get("ok", false))
