extends RefCounted

# class_name intentionally omitted — callers preload this script as
# `const KeeperInput = preload(...)`.

# SENTIENCE_THE_DARING_MIND §A — keeper as a percept (never a command).

const EpisodicMemory = preload("res://scripts/episodic_memory.gd")
const FishMind = preload("res://scripts/fish_mind.gd")
const MindLexicon = preload("res://scripts/mind_lexicon.gd")
const CognitiveSchema = preload("res://scripts/cognitive_schema.gd")
const MindNarrator = preload("res://scripts/mind_narrator.gd")
const MindKeeperModel = preload("res://scripts/mind_keeper_model.gd")
const KeeperCare = preload("res://scripts/keeper_care.gd")
const MindWorkerCfg = preload("res://scripts/mind_worker_cfg.gd")
const TankMind = preload("res://scripts/tank_mind.gd")
const TankDialogue = preload("res://scripts/tank_dialogue.gd")
const TankQuestions = preload("res://scripts/tank_questions.gd")

static var gaze_fish_id: String = ""
static var gaze_seconds: float = 0.0
static var cursor_near_fish_id: String = ""
static var cursor_speed: float = 0.0
static var mic_rms: float = 0.0


static func _tank_config() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return null
	var st: SceneTree = ml as SceneTree
	if st == null or st.root == null or not st.root.is_inside_tree():
		return null
	return st.root.get_node_or_null("/root/TankConfig")


static func _cfg_bool(key: String, default: bool) -> bool:
	if not Thread.is_main_thread():
		if MindWorkerCfg.active:
			return MindWorkerCfg.read_bool(key, default)
		return default
	var cfg: Node = _tank_config()
	if cfg == null:
		return default
	var v: Variant = cfg.get(key)
	if v is bool:
		return v
	if v == null:
		return default
	return default if v == false else true


static func ears_enabled() -> bool:
	if _cfg_bool("sentience_voice_off", false):
		return false
	return _cfg_bool("keeper_ears_enabled", true)


static func gaze_enabled() -> bool:
	return _cfg_bool("keeper_gaze_enabled", true)


static func mic_enabled() -> bool:
	return _cfg_bool("keeper_mic_enabled", false)


static func score_tone(text: String) -> Dictionary:
	var t: String = text.strip_edges()
	var arousal: float = 0.22
	var valence: float = 0.0
	if t.is_empty():
		return {"arousal": 0.0, "valence": 0.0, "felt": "silence"}
	var lower: String = t.to_lower()
	if "!!!" in t or t == t.to_upper() and t.length() > 3:
		arousal += 0.45
		valence -= 0.12
	if "?" in t:
		arousal += 0.12
	if lower.contains("shh") or lower.contains("quiet") or lower.contains("calm"):
		arousal -= 0.18
		valence += 0.28
	if lower.contains("safe") or lower.contains("okay") or lower.contains("ok ") \
			or lower.begins_with("ok") or lower.contains("trust"):
		valence += 0.32
		arousal -= 0.12
	if lower.contains("good") or lower.contains("love") or lower.contains("hello") \
			or lower.contains("hi ") or lower.begins_with("hi"):
		valence += 0.35
		arousal += 0.08
	if lower.contains("bad") or lower.contains("stop") or lower.contains("no "):
		valence -= 0.32
		arousal += 0.15
	arousal += clampf(float(t.length()) / 80.0, 0.0, 0.25)
	var felt: String = "neutral"
	if valence > 0.25:
		if lower.contains("safe") or lower.contains("trust") or lower.contains("calm"):
			felt = "comfort"
		else:
			felt = "greeting" if lower.contains("hello") or lower.begins_with("hi") else "comfort"
	elif valence < -0.2:
		felt = "scold"
	elif "?" in t:
		felt = "question"
	elif t.split(" ", false).size() == 1 and t.length() <= 16:
		felt = "name"
	return {
		"arousal": clampf(arousal, 0.0, 1.0),
		"valence": clampf(valence, -1.0, 1.0),
		"felt": felt,
	}


static func interpret_heuristic(text: String) -> Dictionary:
	var tone: Dictionary = score_tone(text)
	return {
		"keeper_felt": tone.get("felt", "neutral"),
		"keeper_valence": tone.get("valence", 0.0),
		"keeper_arousal": tone.get("arousal", 0.0),
		"keeper_text": text.strip_edges().substr(0, 120),
	}


static func submit_to_fish(f: Fish, text: String, sim: Node) -> Dictionary:
	if f == null or not is_instance_valid(f) or text.strip_edges() == "":
		return {"ok": false, "reason": "empty"}
	if not ears_enabled():
		return {"ok": false, "reason": "ears_off"}
	var clean: String = MindNarrator.sanitize_keeper_input(text)
	if clean == "":
		return {"ok": false, "reason": "empty"}
	var interp: Dictionary = _interpret_keeper(f, clean)
	f._keeper_pending = interp.duplicate(true)
	f._keeper_pending["t"] = Time.get_ticks_msec()
	var sal: float = clampf(0.35 + f.familiarity * 0.45 + float(interp.get("keeper_arousal", 0.0)) * 0.25, 0.0, 1.0)
	f._keeper_message_salience = sal
	MindLexicon.try_pair_on_keeper_word(f, text, sim)
	if sal > 0.42:
		EpisodicMemory.encode_episode(f, "keeper_word", str(interp.get("keeper_text", text)),
				sal, f.position)
		FishMind.record_salient(f, "keeper", "the keeper spoke", sal * 0.85, f.position)
	f.familiarity = clampf(f.familiarity + 0.04, 0.0, 1.0)
	f.arousal = clampf(f.arousal + float(interp.get("keeper_arousal", 0.0)) * 0.18, 0.0, 1.0)
	f.mood = clampf(f.mood + float(interp.get("keeper_valence", 0.0)) * 0.08, -1.0, 1.0)
	var comfort_fx: Dictionary = KeeperCare.apply_comfort_effects(f, interp, sim)
	var tier: int = KeeperCare.tier_from_sim(sim)
	var too_wary: bool = KeeperCare.compute_too_wary(f)
	var open: float = KeeperCare.conversation_openness(sim, f)
	var tank_blocks: bool = tier <= KeeperCare.Tier.STRESSED and open < 0.45
	var result: Dictionary = {
		"ok": true,
		"text": str(interp.get("keeper_text", text.strip_edges().substr(0, 120))),
		"felt": str(interp.get("keeper_felt", "neutral")),
		"intent": str(interp.get("keeper_intent", "neutral")),
		"comprehension": float(interp.get("keeper_comprehension", 0.0)),
		"salience": sal,
		"attending": f.attention_focus == "keeper_message",
		"too_wary": too_wary,
		"tank_tier": tier,
		"tank_blocks_words": tank_blocks,
		"conversation_open": open,
		"bond_stage": KeeperCare.bond_stage(f, sim),
		"comfort_applied": bool(comfort_fx.get("applied", false)),
		"attention_shift": bool(comfort_fx.get("attention_shift", false)),
		"care_hint": KeeperCare.primary_action_hint(sim),
		"is_guardian_advisor": f.is_guardian and tier <= KeeperCare.Tier.STRESSED,
	}
	return result


# "Speak to the tank" (no fish followed): the collective answers from real
# state, and picks 1–3 fish to answer back through submit_to_fish +
# sim.request_keeper_reply (the caller staggers those so they read as a
# conversation, not a burst). Template-only, main-thread safe.
static func submit_to_tank(sim: Node, text: String, focus_pos: Variant = null) -> Dictionary:
	if sim == null or text.strip_edges() == "":
		return {"ok": false, "reason": "empty"}
	if not ears_enabled():
		return {"ok": false, "reason": "ears_off"}
	var clean: String = MindNarrator.sanitize_keeper_input(text)
	if clean == "":
		return {"ok": false, "reason": "empty"}
	var reply: Dictionary = TankMind.keeper_reply(sim, clean)
	var responders: Array = TankMind.pick_keeper_responders(sim,
			reply.get("topics", PackedStringArray()), reply.get("tokens", PackedStringArray()),
			focus_pos)
	var intent: String = str(reply.get("intent", ""))
	var about_id: String = str(reply.get("about_id", ""))
	# "tell me about Pip": Pip answers first.
	if intent == "about" and about_id != "":
		var about_f: Fish = TankDialogue.fish_by_id(sim, about_id)
		if about_f != null:
			responders.erase(about_f)
			responders.push_front(about_f)
			if responders.size() > TankMind.RESPONDERS_MAX:
				responders.resize(TankMind.RESPONDERS_MAX)
	var ids: PackedStringArray = PackedStringArray()
	# Intent questions get grounded per-fish answers (thinking / dream /
	# friend / about) instead of the generic reply pipeline.
	var fish_answers: Dictionary = {}
	for f in responders:
		ids.append(str(f.id))
		if intent != "":
			var ans: String = TankDialogue.fish_intent_line(sim, f, intent, about_id)
			if ans != "":
				fish_answers[str(f.id)] = ans
	return {
		"ok": true,
		"text": clean,
		"line": str(reply.get("line", "")),
		"topics": reply.get("topics", PackedStringArray()),
		"understood": reply.get("understood", PackedStringArray()),
		"responder_ids": ids,
		"tank_tier": KeeperCare.tier_from_sim(sim),
		"callback": str(reply.get("callback", "")),
		"promise": str(reply.get("promise", "")),
		"intent": intent,
		"about_id": about_id,
		"fish_answers": fish_answers,
	}


# --- Fish ask the keeper (TankQuestions) ------------------------------------
#
# Main polls maybe_fish_question on a slow cadence; while a question is
# pending the keeper's next line goes to answer_fish_question first.

static func maybe_fish_question(sim: Node, rt: Dictionary, keeper_quiet_s: float, keeper_present: bool,
		keeper_busy: bool, voice_on: bool = true) -> Dictionary:
	if sim == null:
		return {}
	var tm: Dictionary = TankMind.ensure(sim)
	var st: Dictionary = TankMind.keeper_state(sim)
	var on: bool = voice_on and ears_enabled() and TankMind.enabled()
	var out: Dictionary = TankQuestions.maybe_ask(sim, tm, rt, st, keeper_quiet_s, keeper_present,
			keeper_busy, on)
	if not out.is_empty() and not bool(out.get("fade", false)) and not bool(out.get("recall", false)):
		TankMind.append_ledger_line(sim, tm, "%s asked the keeper: %s" % [str(out.get("name", "")),
				str(out.get("line", "")).substr(0, 56)])
	return out


# The open question ({} when none or expired).
static func pending_fish_question(sim: Node) -> Dictionary:
	if sim == null:
		return {}
	var tm: Dictionary = TankMind.ensure(sim)
	if not TankQuestions.has_pending(tm):
		return {}
	return TankQuestions.pending(tm)


# Read `text` as the answer to the pending question. {} → route as ordinary
# talk. On success the asking fish also hears the line as a keeper percept
# (lexicon pairing, familiarity) through submit_to_fish — after comprehension
# was measured, so the answer itself cannot teach the words it is judged by.
static func answer_fish_question(sim: Node, text: String) -> Dictionary:
	if sim == null or text.strip_edges() == "" or not ears_enabled():
		return {}
	var clean: String = MindNarrator.sanitize_keeper_input(text)
	if clean == "":
		return {}
	var res: Dictionary = TankQuestions.answer(sim, TankMind.ensure(sim), clean)
	if res.is_empty():
		return res
	res["text"] = clean
	if not bool(res.get("collective", false)):
		var f: Fish = TankQuestions.fish_by_id(sim, str(res.get("fish_id", "")))
		if f != null:
			submit_to_fish(f, clean, sim)
	TankMind.append_ledger_line(sim, TankMind.ensure(sim), "the keeper answered %s: \"%s\"" % [
			str(res.get("name", "")), clean.substr(0, 48)])
	return res


static func _interpret_keeper(f: Fish, text: String) -> Dictionary:
	var base: Dictionary = CognitiveSchema.interpret_keeper_heuristic(text, f)
	base["keeper_text"] = text.strip_edges().substr(0, 120)
	var tokens: PackedStringArray = text.strip_edges().to_lower().split(" ", false)
	var known: int = 0
	var total: int = maxi(1, tokens.size())
	for tok in tokens:
		if MindLexicon.comprehend(f, tok):
			known += 1
	base["keeper_comprehension"] = float(known) / float(total)
	if float(base["keeper_comprehension"]) < 0.34 and tokens.size() > 0:
		base["keeper_intent"] = "unknown_sound"
	var tone: Dictionary = score_tone(text)
	var pd: Dictionary = MindKeeperModel.prosody_delta(f, float(tone.get("valence", 0.0)),
			float(tone.get("arousal", 0.0)))
	if absf(float(pd.get("valence_delta", 0.0))) > 0.35:
		base["keeper_felt"] = "scold" if float(pd.get("valence_delta", 0.0)) < 0.0 else "comfort"
	return base


static func ui_ack_line(result: Dictionary, _fish_name: String, sim: Node = null, f: Fish = null) -> String:
	return KeeperCare.ui_feedback(result, f, sim)


static func on_creature_named(f: Fish, name: String) -> void:
	if f == null or name.strip_edges() == "":
		return
	var line: String = "I was given a sound that means me"
	EpisodicMemory.encode_episode(f, "named", line, 0.82, f.position)
	FishMind.record_salient(f, "named", line, 0.75, f.position)
	f._keeper_pending = {
		"keeper_felt": "name",
		"keeper_valence": 0.45,
		"keeper_arousal": 0.35,
		"keeper_text": name,
		"t": Time.get_ticks_msec(),
	}
	f._keeper_message_salience = 0.78
	MindLexicon.pair_creature_name(f, name)


static func collect_keeper_bid(f) -> Dictionary:
	if f.get("_keeper_message_salience") == null:
		return {}
	var sal: float = float(f._keeper_message_salience)
	if sal < 0.08:
		return {}
	var intent: String = ""
	if f.get("_keeper_pending") is Dictionary:
		intent = str((f._keeper_pending as Dictionary).get("keeper_intent", ""))
	var coal: Array = ["keeper_message", "player", "social"]
	if intent in ["comfort", "greeting", "name"]:
		coal.append("social")
	if intent == "food":
		coal.append("food")
	if f.get("_convo") is Dictionary and bool((f._convo as Dictionary).get("active", false)):
		coal.append("conversation")
	return {
		"label": "keeper_message",
		"salience": sal * (0.75 + f.familiarity * 0.35),
		"coalition": coal,
		"intent": intent,
		"addressed": true,
	}


static func collect_gaze_bid(f) -> Dictionary:
	if not gaze_enabled() or gaze_fish_id == "" or str(f.id) != gaze_fish_id:
		return {}
	if gaze_seconds < 2.8:
		return {}
	var shy: float = 1.0 - f._trait("boldness")
	var sal: float = clampf(0.28 + gaze_seconds * 0.06 + shy * 0.22, 0.0, 0.92)
	return {"label": "being_watched", "salience": sal, "coalition": ["player", "social"]}


static func collect_cursor_bid(f) -> Dictionary:
	if cursor_near_fish_id == "" or str(f.id) != cursor_near_fish_id:
		return {}
	if cursor_speed > 2.4:
		return {"label": "threat", "salience": 0.38, "coalition": ["threat", "player"]}
	if cursor_speed < 0.35:
		return {"label": "player", "salience": 0.22 + f.familiarity * 0.12, "coalition": ["player"]}
	return {}


static func tick_gaze(follow_fish: Fish, dt: float, camera_still: bool) -> void:
	if not gaze_enabled() or follow_fish == null or not is_instance_valid(follow_fish):
		gaze_fish_id = ""
		gaze_seconds = 0.0
		return
	if camera_still:
		if gaze_fish_id != str(follow_fish.id):
			gaze_fish_id = str(follow_fish.id)
			gaze_seconds = 0.0
		gaze_seconds += dt
	else:
		gaze_seconds = maxf(0.0, gaze_seconds - dt * 2.0)


static func set_mic_rms(v: float) -> void:
	if mic_enabled():
		mic_rms = clampf(v, 0.0, 1.0)
	else:
		mic_rms = 0.0


static func mic_arousal_bump() -> float:
	if not mic_enabled() or mic_rms < 0.02:
		return 0.0
	return clampf(mic_rms * 0.35, 0.0, 0.45)
