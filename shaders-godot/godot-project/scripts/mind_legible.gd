class_name MindLegible
extends RefCounted

# Plain-language translation of mind state (BROAD_DIRECTIONS #17).
#
# THE GAP. 48 `mind_*.gd` modules — active inference, a global workspace,
# felt-self layers, self-models, episodic memory, prediction error — and no
# UI surfaced any of it. Grepping every `*panel*.gd` found zero references to
# mind state. The project's largest single investment was something the
# player could only infer from swimming.
#
# WHY TRANSLATION, NOT A READOUT. The tempting fix is a debug panel:
# "dopamine 0.45 · serotonin 0.50 · cortisol 0.20". That is not legibility,
# it is telemetry — it tells the player what the *simulation* holds, not what
# the *fish* is doing. Legibility is "Wary — keeping the driftwood between
# herself and the big danio. Hungry, but not enough to risk it."
#
# So this module is pure: MindState/Fish in, sentences out. No Nodes, no
# panel, no side effects — which means the panel, the fish journal, the
# guardian's diary, the inbox and a hover tooltip can all read the same
# phrasing, and it is unit-testable without booting the game
# (smoke_mind_legible.gd).
#
# PHRASING RULES, in priority order:
#   1. **Name the behaviour, not the number.** Never print a raw scalar.
#   2. **One dominant thing.** A fish is doing one thing most; lead with it.
#   3. **Say why when we know why.** attention_focus/goal_kind carry the
#      cause; a state without a cause is half a sentence.
#   4. **Never invent.** Grounded in MindContext/vitals per ENGINEERING_CREED;
#      if a field is absent, say less rather than guessing.

# Emotional states, as the player should read them. Keys match
# FishMind.emotional_state(); an unknown key falls through to itself so a new
# state degrades to its bare name instead of vanishing.
const MOOD_WORDS: Dictionary = {
	"dreaming": "Dreaming",
	"cozy": "Asleep",
	"anxious": "Uneasy",
	"content": "Content",
	"excited": "Excited",
	"playful": "Playful",
	"bored": "Restless",
	"sulking": "Withdrawn",
	"calm": "Calm",
}

# What a dominant need looks like from outside the fish.
const NEED_PHRASES: Dictionary = {
	"safety": "looking for somewhere to hide",
	"food": "searching for food",
	"social": "staying close to their mate",
	"rest": "settled in the plants",
	"explore": "investigating the tank",
	"play": "darting about for the sake of it",
	"calm": "cruising with nothing much to do",
}

# Attention targets, rendered as a place or thing rather than an enum.
const FOCUS_PHRASES: Dictionary = {
	"food": "a scrap of food",
	"predator": "something bigger",
	"mate": "a potential mate",
	"plant": "the planting",
	"rival": "a rival",
	"surface": "the surface",
	"substrate": "the substrate",
	"glass": "their reflection",
	"keeper": "you",
	"shrimp": "the shrimp",
	"novelty": "something new",
}

# Thresholds for "is this worth mentioning at all". Deliberately high: a
# panel that lists every faint drive reads as noise, and the point is to
# surface what is actually driving behaviour.
const DRIVE_NOTABLE: float = 0.45
const STRESS_NOTABLE: float = 0.5
const SURPRISE_NOTABLE: float = 0.4


# --- Headline --------------------------------------------------------------

# Two or three words: the mood, capitalised. Used as a card title.
static func mood_label(state: Object) -> String:
	var key: String = _str(state, "emotional_state")
	if key.is_empty():
		key = _derive_mood_key(state)
	return String(MOOD_WORDS.get(key, key.capitalize()))


# One sentence: what this creature is doing and, where known, why.
# The thing a player should be able to read at a glance.
static func headline(state: Object) -> String:
	var mood: String = mood_label(state)
	var need: String = _str(state, "dominant_need")
	var phrase: String = String(NEED_PHRASES.get(need, ""))
	var focus: String = _focus_phrase(state)

	# Asleep overrides everything — a sleeping fish is not "searching for food".
	if _num(state, "sleep_depth", 0.0) > 0.15 or need == "rest":
		var wisp: String = _str(state, "dream_wisp")
		if not wisp.is_empty():
			return "%s — dreaming of %s." % [mood, wisp]
		return "%s — settled in for the night." % mood

	if phrase.is_empty() and focus.is_empty():
		return "%s." % mood
	if focus.is_empty():
		return "%s — %s." % [mood, phrase]
	if phrase.is_empty():
		return "%s — watching %s." % [mood, focus]
	return "%s — %s, with an eye on %s." % [mood, phrase, focus]


# --- Detail lines ----------------------------------------------------------

# Zero to four short lines expanding the headline. Only things that are
# actually notable appear, so an unremarkable fish reads as unremarkable
# rather than padded out with near-zero values.
static func detail_lines(state: Object) -> Array[String]:
	var out: Array[String] = []

	var stress: float = _num(state, "stress", 0.0)
	var hunger: float = _num(state, "hunger", 0.0)
	var curiosity: float = _num(state, "curiosity_drive", 0.0)
	var surprise: float = _num(state, "surprise", 0.0)
	var vigilance: float = _num(state, "vigilance", 0.0)

	if stress > 0.75:
		out.append("Badly stressed — this one needs the water checked.")
	elif stress > STRESS_NOTABLE:
		out.append("Carrying some stress.")

	if hunger > 0.75:
		out.append("Very hungry.")
	elif hunger > DRIVE_NOTABLE:
		out.append("Getting hungry.")

	if vigilance > 0.6:
		out.append("On alert, checking over their shoulder.")
	elif curiosity > 0.6:
		out.append("Curious — keeps going back for another look.")

	if surprise > SURPRISE_NOTABLE:
		out.append("Something just caught them off guard.")

	# A thought, when the mind has produced one. This is the felt-self /
	# narrator output, and it is the single most humanising line available,
	# so it goes last where the eye lands.
	var thought: String = _str(state, "current_thought")
	if thought.is_empty():
		thought = _str(state, "thought_stream")
	if not thought.is_empty():
		out.append("“%s”" % thought.strip_edges())

	return out


# --- Inner workings, made honest ------------------------------------------

# The deliberately un-mystical view: what the mind is actually doing right
# now, for players who want to see the machinery. Still phrased, not dumped.
# Returns label -> value pairs, ordered, ready for a two-column layout.
static func workings(state: Object) -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	var intention: String = _str(state, "current_intention")
	if intention.is_empty():
		intention = _str(state, "goal_kind")
	if not intention.is_empty():
		out.append({"label": "Trying to", "value": _humanise(intention)})

	var focus: String = _focus_phrase(state)
	if not focus.is_empty():
		out.append({"label": "Attending to", "value": focus})

	# Workspace ignition is the global-workspace module's headline event:
	# several bids resolved into one conscious focus.
	if _flag(state, "workspace_ignited"):
		out.append({"label": "Mind", "value": "one thing has taken over"})
	else:
		var ws: Variant = _field(state, "workspace")
		if ws is Array and (ws as Array).size() > 1:
			out.append({"label": "Mind", "value":
				"%d impulses competing" % (ws as Array).size()})

	# Prediction error is active inference's core quantity — "the tank is not
	# behaving as expected" is the honest plain-language reading.
	var pe: float = _num(state, "prediction_error", 0.0)
	if pe > 0.5:
		out.append({"label": "Expectations", "value": "the tank keeps surprising them"})
	elif pe > 0.25:
		out.append({"label": "Expectations", "value": "mostly as expected"})
	elif pe > 0.0:
		out.append({"label": "Expectations", "value": "the tank feels predictable"})

	var stance: String = _str(state, "life_stance")
	if not stance.is_empty():
		out.append({"label": "Outlook", "value": _humanise(stance)})

	var summary: String = _str(state, "self_summary")
	if not summary.is_empty():
		out.append({"label": "Sense of self", "value": summary})

	# Meta-states are the "thinking about thinking" flags; name them plainly.
	var meta: Variant = _field(state, "meta_states")
	if meta != null:
		var names: Array[String] = []
		for m in meta:
			names.append(_humanise(String(m)))
		if not names.is_empty():
			out.append({"label": "Also", "value": ", ".join(names)})

	return out


# --- Drives, for a bar display --------------------------------------------

# Named drives with 0..1 magnitudes, strongest first, weak ones dropped.
# A UI can render these as bars; the caller does not need to know which
# MindState fields are drives.
static func drives(state: Object) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = [
		{"label": "Hunger", "value": _num(state, "hunger", 0.0)},
		{"label": "Stress", "value": _num(state, "stress", 0.0)},
		{"label": "Curiosity", "value": _num(state, "curiosity_drive", 0.0)},
		{"label": "Alertness", "value": _num(state, "vigilance", 0.0)},
		{"label": "Energy", "value": _num(state, "arousal", 0.0)},
	]
	var out: Array[Dictionary] = []
	for c in candidates:
		if float(c["value"]) >= 0.05:
			out.append(c)
	out.sort_custom(func(a, b): return float(a["value"]) > float(b["value"]))
	return out


# --- Helpers ---------------------------------------------------------------

static func _focus_phrase(state: Object) -> String:
	var focus: String = _str(state, "attention_focus")
	if focus.is_empty():
		return ""
	return String(FOCUS_PHRASES.get(focus, _humanise(focus)))


# snake_case / internal tokens -> readable words.
static func _humanise(token: String) -> String:
	return token.replace("_", " ").strip_edges()


# Mood key when the provider has no emotional_state() — mirrors
# FishMind.emotional_state()'s thresholds closely enough to phrase a
# MindState snapshot that was serialised without it.
static func _derive_mood_key(state: Object) -> String:
	if _num(state, "sleep_depth", 0.0) > 0.15:
		return "cozy"
	if _num(state, "vigilance", 0.0) > 0.55:
		return "anxious"
	var mood: float = _num(state, "mood", 0.0)
	var arousal: float = _num(state, "arousal", 0.0)
	if arousal > 0.65 and mood > 0.2:
		return "excited"
	if arousal > 0.55 and mood < 0.0:
		return "anxious"
	if _num(state, "curiosity_drive", 0.0) > 0.55 and arousal > 0.4:
		return "playful"
	if mood < -0.35 and arousal < 0.4:
		return "sulking"
	if mood > 0.15 and arousal < 0.45:
		return "content"
	return "calm"


# Read a property OR a zero-arg method of the same name, so this works
# against a MindState snapshot, a live Fish, or a test stub without the
# caller adapting. Never throws on a missing field.
# NB: named _field, not _get — `_get` collides with Object's virtual
# `_get(StringName) -> Variant` and fails to parse.
static func _field(state: Object, key: String) -> Variant:
	if state == null:
		return null
	# NOT `state is Node and not is_instance_valid(state)`: `is` throws
	# "Left operand of 'is' is a previously freed instance" on exactly the
	# input this check exists to catch. `state` is already typed Object, so
	# the validity test alone is both correct and stricter - it also catches
	# freed non-Node Objects.
	if not is_instance_valid(state):
		return null
	var v: Variant = state.get(key)
	if v != null:
		return v
	if state.has_method(key):
		return state.call(key)
	return null


static func _str(state: Object, key: String) -> String:
	var v: Variant = _field(state, key)
	if v == null:
		return ""
	return String(v).strip_edges()


static func _num(state: Object, key: String, fallback: float) -> float:
	var v: Variant = _field(state, key)
	if v == null:
		return fallback
	match typeof(v):
		TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
			return float(v)
		_:
			return fallback


static func _flag(state: Object, key: String) -> bool:
	var v: Variant = _field(state, key)
	return v != null and typeof(v) == TYPE_BOOL and bool(v)
