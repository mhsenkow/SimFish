extends RefCounted

# SENTIENCE_THE_CONVERSATION §D — per-fish model of the keeper (speech + care).

const KeeperInput = preload("res://scripts/keeper_input.gd")
const MindSelfModel = preload("res://scripts/mind_self_model.gd")
const MindWriteback = preload("res://scripts/mind_writeback.gd")
const CognitiveSchema = preload("res://scripts/cognitive_schema.gd")

const SCHEMA_VERSION: int = 1
const TONE_RING_MAX: int = 12
const THEME_MAX: int = 5
const SPEECH_RING_MAX: int = 8


static func ensure(f) -> Dictionary:
	var existing: Variant = f.get("_keeper_model")
	if existing is Dictionary:
		return existing as Dictionary
	var fresh: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"speech_themes": PackedStringArray(),
		"speech_ring": [],
		"tone_history": [],
		"keeper_mood_valence": 0.0,
		"keeper_mood_arousal": 0.22,
		"player_moniker": "the big shape",
		"care_trust": 0.3,
		"speech_read": "still learning your sounds",
		"conversation_count": 0,
		"greeting_ritual": "",
		"prosody_baseline": {"valence": 0.0, "arousal": 0.22},
		"last_absence_s": 0,
	}
	if f is Object:
		(f as Object).set("_keeper_model", fresh)
	return fresh


static func on_keeper_line(f, text: String, result: Dictionary, sim: Node) -> void:
	var km: Dictionary = ensure(f)
	km["conversation_count"] = int(km.get("conversation_count", 0)) + 1
	var ring: Array = km.get("speech_ring", [])
	ring.append(text.strip_edges().substr(0, 80))
	while ring.size() > SPEECH_RING_MAX:
		ring.pop_front()
	km["speech_ring"] = ring
	var val: float = float(result.get("keeper_valence", 0.0)) if result.has("keeper_valence") \
			else float(f._keeper_pending.get("keeper_valence", 0.0))
	var ar: float = float(result.get("keeper_arousal", 0.0)) if result.has("keeper_arousal") \
			else float(f._keeper_pending.get("keeper_arousal", 0.0))
	var tones: Array = km.get("tone_history", [])
	tones.append({"v": val, "a": ar, "t": Time.get_ticks_msec()})
	while tones.size() > TONE_RING_MAX:
		tones.pop_front()
	km["tone_history"] = tones
	var sum_v: float = 0.0
	var sum_a: float = 0.0
	for t in tones:
		sum_v += float((t as Dictionary).get("v", 0.0))
		sum_a += float((t as Dictionary).get("a", 0.0))
	if tones.size() > 0:
		km["keeper_mood_valence"] = sum_v / float(tones.size())
		km["keeper_mood_arousal"] = sum_a / float(tones.size())
	var base: Dictionary = km.get("prosody_baseline", {})
	var bv: float = float(base.get("valence", 0.0))
	var ba: float = float(base.get("arousal", 0.22))
	if tones.size() >= 4:
		km["prosody_baseline"] = {
			"valence": lerpf(bv, km["keeper_mood_valence"], 0.08),
			"arousal": lerpf(ba, km["keeper_mood_arousal"], 0.08),
		}
	_extract_themes(f, km, text)
	_update_moniker(f, km, sim)
	_update_speech_read(km)
	_propose_belief_from_line(f, text, result)
	f._keeper_model = km
	if int(km.get("conversation_count", 0)) == 3:
		MindSelfModel.update_self_summary(f, "the soft-sound shape teaches me words")


static func prosody_delta(f, valence: float, arousal: float) -> Dictionary:
	var km: Dictionary = ensure(f)
	var base: Dictionary = km.get("prosody_baseline", {})
	return {
		"valence_delta": valence - float(base.get("valence", 0.0)),
		"arousal_delta": arousal - float(base.get("arousal", 0.22)),
	}


static func note_absence(f, gap_s: int) -> void:
	var km: Dictionary = ensure(f)
	km["last_absence_s"] = gap_s
	if gap_s >= 86400 * 3:
		km["player_moniker"] = "the long-absent shape"
	elif gap_s >= 86400:
		km["player_moniker"] = "the returning shape"
	f._keeper_model = km


static func note_care_event(f, kind: String) -> void:
	var km: Dictionary = ensure(f)
	var trust: float = float(km.get("care_trust", 0.3))
	match kind:
		"feed":
			trust = clampf(trust + 0.04, 0.0, 1.0)
		"water_change", "prune":
			trust = clampf(trust + 0.03, 0.0, 1.0)
		"neglect":
			trust = clampf(trust - 0.06, 0.0, 1.0)
	km["care_trust"] = trust
	f._keeper_model = km


static func record_greeting_ritual(f, keeper_line: String, fish_line: String) -> void:
	var km: Dictionary = ensure(f)
	if keeper_line.strip_edges() == "":
		return
	var ritual: String = str(km.get("greeting_ritual", ""))
	if ritual == "":
		km["greeting_ritual"] = keeper_line.strip_edges().substr(0, 40)
	elif ritual == keeper_line.strip_edges().substr(0, 40) and fish_line != "":
		km["greeting_ritual"] = ritual  # reinforced
	f._keeper_model = km


static func consolidate_idle(f, _sim: Node) -> void:
	if not f._asleep and f.stress > 0.4:
		return
	var km: Dictionary = ensure(f)
	var themes: Variant = km.get("speech_themes", null)
	if themes is PackedStringArray and (themes as PackedStringArray).size() > 0:
		var t0: String = String((themes as PackedStringArray)[0])
		if t0 != "":
			MindSelfModel.update_self_summary(f, "keeper keeps saying %s" % t0)
	f._keeper_model = km


static func merge_context(ctx: Dictionary, f, sim: Node = null) -> Dictionary:
	var out: Dictionary = ctx.duplicate(true)
	var km: Dictionary = ensure(f)
	out["keeper_moniker"] = str(km.get("player_moniker", ""))
	out["keeper_speech_read"] = str(km.get("speech_read", ""))
	out["keeper_mood_valence"] = snappedf(float(km.get("keeper_mood_valence", 0.0)), 0.01)
	out["keeper_mood_arousal"] = snappedf(float(km.get("keeper_mood_arousal", 0.0)), 0.01)
	out["care_trust"] = snappedf(float(km.get("care_trust", 0.0)), 0.01)
	var themes: Variant = km.get("speech_themes", null)
	if themes is PackedStringArray and (themes as PackedStringArray).size() > 0:
		out["keeper_themes"] = themes
	out["greeting_ritual"] = str(km.get("greeting_ritual", ""))
	out["conversation_count"] = int(km.get("conversation_count", 0))
	var gap: int = int(km.get("last_absence_s", 0))
	if gap >= 86400:
		out["keeper_absence_days"] = snappedf(float(gap) / 86400.0, 0.1)
	if f._mate_grief > 0.35:
		out["mate_grief"] = snappedf(f._mate_grief, 0.01)
	if sim != null and sim.has_method("story_events"):
		var care_tags: PackedStringArray = _care_tags_from_story(sim.story_events)
		if not care_tags.is_empty():
			out["keeper_care_patterns"] = care_tags
	return out


static func to_dict(f) -> Dictionary:
	return ensure(f).duplicate(true)


static func from_dict(f, d: Variant) -> void:
	if d is Dictionary:
		f._keeper_model = (d as Dictionary).duplicate(true)


static func _extract_themes(_f, km: Dictionary, text: String) -> void:
	var counts: Dictionary = {}
	for tok in text.strip_edges().to_lower().split(" ", false):
		if tok.length() < 3:
			continue
		counts[tok] = int(counts.get(tok, 0)) + 1
	var themes: PackedStringArray = km.get("speech_themes", PackedStringArray())
	for k in counts:
		if int(counts[k]) >= 2 and not themes.has(k):
			themes.append(k)
	while themes.size() > THEME_MAX:
		themes.remove_at(0)
	km["speech_themes"] = themes


static func _update_moniker(_f, km: Dictionary, sim: Node) -> void:
	var trust: float = float(km.get("care_trust", 0.3))
	var conv: int = int(km.get("conversation_count", 0))
	var tones: Array = km.get("tone_history", [])
	var comfort_n: int = 0
	for t in tones:
		if float((t as Dictionary).get("v", 0.0)) > 0.15:
			comfort_n += 1
	if trust >= 0.75 and conv >= 8:
		km["player_moniker"] = "my keeper"
	elif comfort_n >= 4:
		km["player_moniker"] = "the gentle shape"
	elif conv >= 5:
		km["player_moniker"] = "the familiar shape"
	elif sim != null and sim.has_method("feed_anticipation_active") \
			and bool(sim.feed_anticipation_active()):
		km["player_moniker"] = "the flake-bringer"
	else:
		km["player_moniker"] = str(km.get("player_moniker", "the big shape"))


static func _update_speech_read(km: Dictionary) -> void:
	var themes: Variant = km.get("speech_themes", null)
	var val: float = float(km.get("keeper_mood_valence", 0.0))
	var conv: int = int(km.get("conversation_count", 0))
	if themes is PackedStringArray and (themes as PackedStringArray).size() > 0:
		km["speech_read"] = "you keep bringing up %s" % String((themes as PackedStringArray)[0])
	elif val < -0.25:
		km["speech_read"] = "your sounds feel sharp lately"
	elif val > 0.25:
		km["speech_read"] = "your sounds feel warm lately"
	elif conv >= 6:
		km["speech_read"] = "I know some of your patterns now"
	else:
		km["speech_read"] = "still learning your sounds"


static func _propose_belief_from_line(f, text: String, result: Dictionary) -> void:
	var lower: String = text.strip_edges().to_lower()
	var belief: String = ""
	if lower.contains("safe") or lower.contains("calm"):
		belief = "glass means calm"
	elif lower.contains("food") or lower.contains("dinner"):
		belief = "sound may mean food"
	elif lower.contains("hide") or lower.contains("scary"):
		belief = "something feels wrong"
	if belief == "":
		return
	var ctx: Dictionary = {"feel": "calm", "keeper_felt": str(result.get("felt", "neutral"))}
	var op: Dictionary = CognitiveSchema.template_op(ctx)
	op["new_belief"] = belief
	MindWriteback.apply_op(f, op, ctx, "keeper_speech")


static func _care_tags_from_story(events: Array) -> PackedStringArray:
	var tags: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	for e in events:
		var s: String = str(e).to_lower()
		for tag in ["feed", "water change", "prune", "filter"]:
			if tag in s and not seen.has(tag):
				seen[tag] = true
				tags.append(tag)
				if tags.size() >= 4:
					return tags
	return tags
