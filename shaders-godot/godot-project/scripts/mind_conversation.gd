extends RefCounted

# SENTIENCE_THE_CONVERSATION — keeper ↔ fish exchange (not a chatbot).

const MindLexicon = preload("res://scripts/mind_lexicon.gd")
const MindNarrator = preload("res://scripts/mind_narrator.gd")
const MindKeeperModel = preload("res://scripts/mind_keeper_model.gd")
const KeeperInput = preload("res://scripts/keeper_input.gd")

const SESSION_TTL_S: float = 20.0
const SESSION_EXTEND_S: float = 8.0
const MAX_RING: int = 6
const GUARDIAN_RING_MAX: int = 10
const BURST_REPLY_MAX: int = 1
const MISHEAR_CHANCE: float = 0.12
const INITIATE_COOLDOWN_S: float = 45.0


static func ensure_convo(f: Fish) -> Dictionary:
	if f.get("_convo") == null or not (f._convo is Dictionary):
		f._convo = {
			"active": false,
			"ttl": 0.0,
			"turn": "keeper",
			"burst_replies": 0,
			"last_keeper_t": 0,
			"focus": "",
			"initiate_cd": 0.0,
			"pending_goodbye": false,
			"away_message": "",
		}
	return f._convo


static func ensure_ring(f: Fish) -> Array:
	if f.get("_dialogue_ring") == null or not (f._dialogue_ring is Array):
		f._dialogue_ring = []
	return f._dialogue_ring


static func _maybe_mishear_token(f: Fish, tokens: PackedStringArray) -> String:
	if tokens.is_empty():
		return ""
	var voice_seed: int = MindNarrator.voice_style_seed(str(f.id), f.personality)
	var roll: int = (voice_seed + Time.get_ticks_msec()) & 0x7fffffff
	if float(roll % 1000) / 1000.0 > MISHEAR_CHANCE:
		return ""
	var lex: Dictionary = MindLexicon.ensure_dict(f)
	if lex.is_empty():
		return ""
	var heard: String = tokens[0]
	if MindLexicon.comprehend(f, heard):
		return ""
	var best: String = ""
	var best_d: int = 999
	for k in lex:
		var d: int = absi(k.length() - heard.length())
		if d < best_d:
			best_d = d
			best = k
	if best != "" and best != heard:
		return best
	return ""


static func on_keeper_submit(f: Fish, text: String, sim: Node, result: Dictionary) -> void:
	var tokens: PackedStringArray = text.strip_edges().to_lower().split(" ", false)
	var misheard: String = _maybe_mishear_token(f, tokens)
	if misheard != "":
		f._keeper_pending["keeper_misheard"] = misheard
		f._keeper_pending["keeper_intent"] = "misheard"
	MindKeeperModel.on_keeper_line(f, text, result, sim)
	var convo: Dictionary = ensure_convo(f)
	convo["active"] = true
	convo["ttl"] = SESSION_TTL_S
	convo["turn"] = "fish"
	convo["last_keeper_t"] = Time.get_ticks_msec()
	convo["focus"] = str(f._keeper_pending.get("keeper_intent", "keeper_message"))
	convo["burst_replies"] = int(convo.get("burst_replies", 0))
	var ring: Array = ensure_ring(f)
	ring.append({"role": "keeper", "text": text.strip_edges().substr(0, 80), "t": Time.get_ticks_msec()})
	while ring.size() > MAX_RING:
		ring.pop_front()
	f._dialogue_ring = ring
	# Bond from real exchange (#17).
	if not bool(result.get("too_wary", false)):
		f.familiarity = clampf(f.familiarity + 0.025, 0.0, 1.0)
		f._curiosity_about_keeper = clampf(f._curiosity_about_keeper + 0.04, 0.0, 1.0)


static func tick(f: Fish, dt: float, sim: Node) -> void:
	var convo: Dictionary = ensure_convo(f)
	convo["initiate_cd"] = maxf(0.0, float(convo.get("initiate_cd", 0.0)) - dt)
	if not bool(convo.get("active", false)):
		_tick_initiation(f, sim, dt, convo)
		f._convo = convo
		return
	var was_active: bool = true
	convo["ttl"] = float(convo.get("ttl", 0.0)) - dt
	# Graceful end when gaze drifts (#15).
	if KeeperInput.gaze_fish_id != str(f.id) and KeeperInput.gaze_seconds < 1.0:
		convo["ttl"] -= dt * 0.6
	if float(convo.get("ttl", 0.0)) <= 0.0:
		if was_active and not bool(convo.get("pending_goodbye", false)):
			convo["pending_goodbye"] = true
			_queue_goodbye(f, sim)
		convo["active"] = false
		convo["turn"] = "keeper"
		convo["burst_replies"] = 0
		convo["focus"] = ""
		convo["pending_goodbye"] = false
	# Interruption (#16): threat steals focus.
	if f.attention_focus == "threat" or f.spooked > 0.5:
		_cancel_reply_generation(f)
		convo["active"] = false
		convo["burst_replies"] = 0
	f._convo = convo
	# Decay burst counter slowly.
	if int(convo.get("burst_replies", 0)) > 0 and not bool(convo.get("active", false)):
		convo["burst_replies"] = 0
	if f._asleep or (f.stress < 0.35 and f.arousal < 0.3):
		MindKeeperModel.consolidate_idle(f, sim)


static func overhear_nearby(listener: Fish, speaker: Fish, dt: float) -> void:
	if speaker == null or listener == null or speaker == listener:
		return
	if not session_active(speaker):
		return
	if listener.position.distance_squared_to(speaker.position) > 12.0:
		return
	if speaker.arousal >= 0.35:
		listener.arousal = clampf(
				listener.arousal + speaker.arousal * dt * 0.08 * listener.schooling_strength,
				0.0, 1.0)
	listener._keeper_message_salience = maxf(float(listener._keeper_message_salience), 0.18)


static func set_away_message(f: Fish, line: String) -> void:
	var convo: Dictionary = ensure_convo(f)
	convo["away_message"] = line.strip_edges().substr(0, 80)
	f._convo = convo


static func consume_away_message(f: Fish) -> String:
	var convo: Dictionary = ensure_convo(f)
	var msg: String = str(convo.get("away_message", ""))
	if msg != "":
		convo["away_message"] = ""
		f._convo = convo
	return msg


static func bond_arc_label(f: Fish) -> String:
	var km: Dictionary = MindKeeperModel.ensure(f)
	var conv: int = int(km.get("conversation_count", 0))
	if conv < 2:
		return ""
	if f.familiarity < 0.35:
		return "still wary of talk"
	if conv >= 20 and float(km.get("care_trust", 0.0)) > 0.6:
		return "knows your voice well"
	if conv >= 8:
		return "learning your rhythms"
	return ""


static func _tick_initiation(f: Fish, sim: Node, dt: float, convo: Dictionary) -> void:
	if float(convo.get("initiate_cd", 0.0)) > 0.0:
		return
	if f.familiarity < 0.55 or f._curiosity_about_keeper < 0.5:
		return
	if KeeperInput.gaze_fish_id != str(f.id) or KeeperInput.gaze_seconds < 5.0:
		return
	if f.attention_focus == "threat" or f.spooked > 0.35:
		return
	if not MindNarrator.global_voice_ready():
		return
	if sim == null or not sim.has_method("speak_creature_thought"):
		return
	if randf() > dt * 0.035:
		return
	convo["initiate_cd"] = INITIATE_COOLDOWN_S
	convo["active"] = true
	convo["ttl"] = SESSION_TTL_S * 0.6
	convo["turn"] = "fish"
	convo["focus"] = "initiate"
	f._convo = convo
	sim.speak_creature_thought(f, "keeper_initiate")


static func _queue_goodbye(f: Fish, sim: Node) -> void:
	if sim == null or not sim.has_method("speak_creature_thought"):
		return
	if f.familiarity < 0.4:
		return
	if not MindNarrator.global_voice_ready():
		if f.has_method("answer_affect_cue"):
			f.answer_affect_cue("pulse")
		return
	sim.speak_creature_thought(f, "keeper_goodbye")


static func _cancel_reply_generation(f: Fish) -> void:
	var glm: Node = _autoload("GuardianLlm")
	if glm != null and glm.has_method("cancel_thought_generation"):
		var kt: String = str(f._keeper_pending.get("keeper_text", ""))
		glm.call("cancel_thought_generation", reply_cache_key(f, kt))


static func deliberation_reply_hint(f: Fish) -> String:
	if not bool(f.get("_delib_active")):
		return ""
	if bool(f.get("_delib_decided")):
		return "approach" if int(f.get("_delib_choice")) == 0 else "avoid"
	return "…"


static func untranslated_interiority(f: Fish, spoken: String) -> String:
	var inner: String = str(f.get("_thought_stream") if f.get("_thought_stream") != null else "")
	if inner.strip_edges() == "" or inner.strip_edges() == spoken.strip_edges():
		return ""
	if inner.length() > spoken.length() + 8:
		return inner.strip_edges().substr(0, 48)
	return ""


static func _autoload(name: String) -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return null
	var st: SceneTree = ml as SceneTree
	if st == null or st.root == null or not st.root.is_inside_tree():
		return null
	return st.root.get_node_or_null("/root/" + name)


static func session_active(f: Fish) -> bool:
	var convo: Dictionary = ensure_convo(f)
	return bool(convo.get("active", false))


static func dialogue_snippet(f: Fish) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for e in ensure_ring(f):
		if e is Dictionary:
			var role: String = str(e.get("role", ""))
			var txt: String = str(e.get("text", ""))
			if txt != "":
				out.append("%s: %s" % [role, txt])
	return out


static func should_reply_words(_f: Fish, result: Dictionary) -> bool:
	if not bool(result.get("ok", false)):
		return false
	if bool(result.get("too_wary", false)):
		return false
	var cfg := _tank_config()
	if cfg != null and bool(cfg.get("sentience_voice_off")):
		return false
	if cfg != null and cfg.has_method("effective_fish_thought_voice_enabled") \
			and not bool(cfg.effective_fish_thought_voice_enabled()):
		return false
	return true


static func should_reply_model(f: Fish, _result: Dictionary) -> bool:
	if not MindNarrator.global_voice_ready():
		return false
	var convo: Dictionary = ensure_convo(f)
	if int(convo.get("burst_replies", 0)) >= BURST_REPLY_MAX:
		return false
	return true


static func should_reply_nonverbal(_f: Fish, result: Dictionary) -> bool:
	return bool(result.get("ok", false)) and bool(result.get("too_wary", false))


static func nonverbal_answer_kind(f: Fish, result: Dictionary) -> String:
	if bool(result.get("too_wary", false)):
		return "turn_away"
	if not should_reply_words(f, result):
		return "pulse"
	var cfg := _tank_config()
	if cfg != null and not bool(cfg.effective_fish_thought_voice_enabled()):
		return "gaze_lock"
	return ""


static func note_reply(f: Fish, line: String, sim: Node) -> void:
	var convo: Dictionary = ensure_convo(f)
	convo["turn"] = "keeper"
	convo["ttl"] = SESSION_EXTEND_S
	convo["burst_replies"] = int(convo.get("burst_replies", 0)) + 1
	f._convo = convo
	var ring: Array = ensure_ring(f)
	ring.append({"role": "fish", "text": line.strip_edges().substr(0, 80), "t": Time.get_ticks_msec()})
	while ring.size() > MAX_RING:
		ring.pop_front()
	f._dialogue_ring = ring
	MindNarrator.mark_voice_spoke()
	# Lasting affect (#52): comfort/scold from pending keeper tone.
	var felt: String = str(f._keeper_pending.get("keeper_felt", "neutral"))
	var val: float = float(f._keeper_pending.get("keeper_valence", 0.0))
	if felt == "comfort" or val > 0.2:
		f.stress = maxf(0.0, f.stress - 0.04)
		f.mood = clampf(f.mood + 0.05, -1.0, 1.0)
	elif felt == "scold" or val < -0.2:
		f.stress = clampf(f.stress + 0.05, 0.0, 1.0)
		f.mood = clampf(f.mood - 0.06, -1.0, 1.0)
	if sim != null and sim.has_method("append_fish_journal_entry"):
		var keeper_line: String = str(f._keeper_pending.get("keeper_text", ""))
		if keeper_line != "" and line != "":
			sim.append_fish_journal_entry(f,
					"Keeper: \"%s\" · I said: \"%s\"" % [keeper_line, line],
					PackedStringArray(["conversation", "keeper"]))
			MindKeeperModel.record_greeting_ritual(f, keeper_line, line)
	var inner: String = untranslated_interiority(f, line)
	if inner != "":
		f._thought_stream = inner


static func enrich_context(ctx: Dictionary, f: Fish, sim: Node = null) -> Dictionary:
	var out: Dictionary = ctx.duplicate(true)
	out["dialogue_recent"] = dialogue_snippet(f)
	out["conversation_active"] = session_active(f)
	out["keeper_comprehension"] = float(f._keeper_pending.get("keeper_comprehension", 0.5))
	out["keeper_intent"] = str(f._keeper_pending.get("keeper_intent", ""))
	if f._keeper_pending.has("keeper_misheard"):
		out["keeper_misheard"] = str(f._keeper_pending.get("keeper_misheard", ""))
	var convo: Dictionary = ensure_convo(f)
	out["conversation_focus"] = str(convo.get("focus", ""))
	out["intimacy"] = clampf(f.familiarity * 0.7 + f._curiosity_about_keeper * 0.3, 0.0, 1.0)
	out["deliberation_hint"] = deliberation_reply_hint(f)
	var fading: String = _fading_word_hint(f)
	if fading != "":
		out["fading_word"] = fading
	out = MindKeeperModel.merge_context(out, f, sim)
	var arc: String = bond_arc_label(f)
	if arc != "":
		out["bond_arc"] = arc
	if f.is_guardian:
		out["dialogue_ring_max"] = GUARDIAN_RING_MAX
	var sm: Variant = out.get("self_model", null)
	if sm is Dictionary:
		var conf: float = float((sm as Dictionary).get("confidence", 1.0))
		out["self_confidence"] = conf
	return out


static func _fading_word_hint(f: Fish) -> String:
	var lex: Dictionary = MindLexicon.ensure_dict(f)
	for k in lex:
		if MindLexicon.fading_token(f, k):
			return k
	return ""


static func reply_cache_key(f: Fish, keeper_text: String) -> String:
	var h: int = 0
	var kt: String = keeper_text.strip_edges()
	for i in kt.length():
		h = ((h << 5) - h + kt.unicode_at(i)) & 0x7fffffff
	return "%s|keeper_reply|%d|v%d" % [
		str(f.id), h,
		MindNarrator.voice_style_seed(str(f.id), f.personality),
	]


static func to_dict(f: Fish) -> Dictionary:
	return {
		"convo": ensure_convo(f).duplicate(true),
		"dialogue_ring": ensure_ring(f).duplicate(true),
		"keeper_model": MindKeeperModel.to_dict(f),
	}


static func from_dict(f: Fish, d: Variant) -> void:
	if not (d is Dictionary):
		return
	var convo: Variant = (d as Dictionary).get("convo", null)
	if convo is Dictionary:
		f._convo = (convo as Dictionary).duplicate(true)
	var ring: Variant = (d as Dictionary).get("dialogue_ring", null)
	if ring is Array:
		f._dialogue_ring = (ring as Array).duplicate(true)
	MindKeeperModel.from_dict(f, (d as Dictionary).get("keeper_model", null))


static func _tank_config() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return null
	var st: SceneTree = ml as SceneTree
	if st == null or st.root == null or not st.root.is_inside_tree():
		return null
	return st.root.get_node_or_null("/root/TankConfig")
