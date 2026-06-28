extends RefCounted

# class_name intentionally omitted — callers preload this script as
# `const MindLexicon = preload(...)` (see creature_naming.gd).

# SENTIENCE_THE_DARING_MIND §C + CONVERSATION §C — grounded private vocabulary.

const EpisodicMemory = preload("res://scripts/episodic_memory.gd")
const FishMind = preload("res://scripts/fish_mind.gd")
const FishMindScience = preload("res://scripts/fish_mind_science.gd")

const MAX_WORDS: int = 12
const DECAY_RATE: float = 0.0008
const PAIR_THRESHOLD: int = 3
const TEACH_CONFIRM: int = 5
const FADING_THRESHOLD: float = 0.12


static func ensure_dict(f: Fish) -> Dictionary:
	if f.get("_learned_words") == null or not (f._learned_words is Dictionary):
		f._learned_words = {}
	return f._learned_words


static func normalize_token(text: String) -> String:
	var t: String = text.strip_edges().to_lower()
	if t.is_empty():
		return ""
	var parts: PackedStringArray = t.split(" ", false)
	if parts.is_empty():
		return t.substr(0, 24)
	return parts[0].substr(0, 24)


static func try_pair_on_feed(f: Fish, sim: Node) -> void:
	if sim == null or not sim.has_method("feed_anticipation_active"):
		return
	if not bool(sim.feed_anticipation_active()):
		return
	_pair_event(f, "dinner", "food", sim)


static func try_pair_on_keeper_word(f: Fish, text: String, sim: Node) -> void:
	var tok: String = normalize_token(text)
	if tok == "":
		return
	var kind: String = "keeper"
	if sim != null and sim.has_method("feed_anticipation_active") \
			and bool(sim.feed_anticipation_active()):
		kind = "food"
	var cell: int = FishMind.heatmap_cell_at(f, f.position)
	if cell >= 0 and f.feed_heatmap[cell] > 0.35:
		kind = "place"
	_pair_event(f, tok, kind, sim)


static func _situation_hash(f: Fish) -> String:
	var ws: String = f.attention_focus
	var cell: int = FishMind.heatmap_cell_at(f, f.position)
	return "%s|%d" % [ws, cell]


static func _pair_event(f: Fish, token: String, kind: String, sim: Node) -> void:
	var lex: Dictionary = ensure_dict(f)
	var entry: Dictionary = lex.get(token, {})
	if entry.is_empty():
		entry = {"kind": kind, "pairings": 0, "strength": 0.0, "last_t": 0}
	var sit: String = _situation_hash(f)
	var teach_key: String = "%s@%s" % [token, sit]
	entry["pairings"] = int(entry.get("pairings", 0)) + 1
	entry["strength"] = clampf(float(entry.get("strength", 0.0)) + 0.12, 0.0, 1.0)
	entry["kind"] = kind
	entry["last_t"] = Time.get_ticks_msec()
	entry["situation"] = sit
	entry["teach_count"] = int(entry.get("teach_count", 0))
	if str(entry.get("last_situation", "")) == sit:
		entry["teach_count"] = int(entry.get("teach_count", 0)) + 1
	else:
		entry["teach_count"] = 1
	entry["last_situation"] = sit
	entry["teach_situation"] = teach_key
	# Episodic/percept grounding (#21).
	var tags: PackedStringArray = PackedStringArray([f.attention_focus])
	if kind == "place":
		var cell: int = FishMind.heatmap_cell_at(f, f.position)
		tags = PackedStringArray(["place|%d" % cell])
		entry["place_cell"] = cell
	entry["embed"] = EpisodicMemory.embed("keeper_word", token, tags)
	lex[token] = entry
	# Food generalization (#26).
	if kind == "food" and int(entry.get("pairings", 0)) >= 2:
		_weak_generalize(f, token, lex)
	while lex.size() > MAX_WORDS:
		_prune_weakest(lex)
	f._learned_words = lex
	var pairs: int = int(entry.get("pairings", 0))
	if pairs == PAIR_THRESHOLD:
		_log_understood(f, token, sim, false)
	if int(entry.get("teach_count", 0)) == TEACH_CONFIRM:
		if f.has_method("answer_affect_cue"):
			f.answer_affect_cue("flare")
		_log_understood(f, token, sim, true)


static func _weak_generalize(_f: Fish, token: String, lex: Dictionary) -> void:
	for alias in ["food", "flake", "dinner"]:
		if alias == token or lex.has(alias):
			continue
		lex[alias] = {
			"kind": "food",
			"pairings": 1,
			"strength": float(lex[token].get("strength", 0.5)) * 0.45,
			"last_t": Time.get_ticks_msec(),
			"generalized_from": token,
		}


static func _log_understood(f: Fish, token: String, sim: Node, behavior: bool) -> void:
	if f.get("_word_milestones") == null or not (f._word_milestones is Dictionary):
		f._word_milestones = {}
	if bool((f._word_milestones as Dictionary).get(token, false)):
		return
	f._word_milestones[token] = true
	if f.sim != null and f.sim.has_method("log_story_event"):
		var nm: String = f.fish_name if f.fish_name != "" else f.species
		var day: int = int(f.sim.sim_day()) if f.sim.get("sim_day") != null else 0
		if behavior:
			f.sim.log_story_event("Day %d: %s came when \"%s\" was said." % [day, nm, token])
		else:
			f.sim.log_story_event("Day %d: %s understood \"%s\"." % [day, nm, token])


static func _prune_weakest(lex: Dictionary) -> void:
	var worst: String = ""
	var worst_s: float = 999.0
	for k in lex:
		var s: float = float((lex[k] as Dictionary).get("strength", 0.0))
		if s < worst_s:
			worst_s = s
			worst = k
	if worst != "":
		lex.erase(worst)


static func comprehend(f: Fish, token: String) -> bool:
	var lex: Dictionary = ensure_dict(f)
	var entry: Variant = lex.get(normalize_token(token), null)
	if entry is Dictionary:
		return int((entry as Dictionary).get("pairings", 0)) >= PAIR_THRESHOLD
	return false


static func fading_token(f: Fish, token: String) -> bool:
	var lex: Dictionary = ensure_dict(f)
	var entry: Variant = lex.get(normalize_token(token), null)
	if entry is Dictionary:
		var e: Dictionary = entry as Dictionary
		return int(e.get("pairings", 0)) >= PAIR_THRESHOLD \
				and float(e.get("strength", 0.0)) < FADING_THRESHOLD
	return false


static func tick_decay(f: Fish, dt: float) -> void:
	var lex: Dictionary = ensure_dict(f)
	var dead: Array[String] = []
	for k in lex:
		var e: Dictionary = lex[k]
		e["strength"] = maxf(0.0, float(e.get("strength", 0.0)) - DECAY_RATE * dt * 60.0)
		if float(e["strength"]) <= 0.02:
			dead.append(k)
		else:
			lex[k] = e
	for k in dead:
		lex.erase(k)
	f._learned_words = lex


static func food_bid_boost(f: Fish, text: String) -> float:
	if not comprehend(f, text):
		return 0.0
	var lex: Dictionary = ensure_dict(f)
	var e: Dictionary = lex.get(normalize_token(text), {})
	if str(e.get("kind", "")) == "food":
		return float(e.get("strength", 0.0)) * 0.55
	return 0.0


static func respond_to_known_word(f: Fish, token: String) -> bool:
	var tok: String = normalize_token(token)
	if tok == "":
		return false
	if fading_token(f, tok):
		return false
	if not comprehend(f, tok):
		FishMind.maybe_double_take(f, f.curiosity_drive)
		return false
	var lex: Dictionary = ensure_dict(f)
	var e: Dictionary = lex.get(tok, {})
	var kind: String = str(e.get("kind", ""))
	var acted: bool = false
	match kind:
		"food":
			f.hunger = maxf(0.0, f.hunger - 0.05)
			f.curiosity_drive = clampf(f.curiosity_drive + 0.15, 0.0, 1.0)
			f._keeper_message_salience = maxf(float(f._keeper_message_salience), 0.42)
			acted = true
		"keeper":
			f.familiarity = clampf(f.familiarity + 0.06, 0.0, 1.0)
			if f.has_method("answer_affect_cue"):
				f.answer_affect_cue("gaze_lock")
			acted = true
		"place":
			var cell: int = int(e.get("place_cell", -1))
			if cell >= 0:
				f._behavior_ws_bias = Vector3(0, 0, 0.15)
			acted = true
	if acted and f.sim != null and f.sim.has_method("log_story_event"):
		if f.get("_word_milestones") == null:
			f._word_milestones = {}
		if not bool((f._word_milestones as Dictionary).get("%s_behavior" % tok, false)):
			f._word_milestones["%s_behavior" % tok] = true
			_log_understood(f, tok, f.sim, true)
	return acted


static func pair_creature_name(f: Fish, name: String) -> void:
	var tok: String = normalize_token(name)
	if tok == "":
		return
	_pair_event(f, tok, "name", f.sim)


static func inherit_from_parent(f: Fish, parent: Fish) -> void:
	if parent == null or f.get("_learned_words") is Dictionary and (f._learned_words as Dictionary).size() > 0:
		return
	var plex: Variant = parent.get("_learned_words")
	if plex is Dictionary:
		var out: Dictionary = {}
		for k in (plex as Dictionary):
			var e: Dictionary = (plex[k] as Dictionary).duplicate(true)
			e["strength"] = float(e.get("strength", 0.0)) * 0.35
			e["pairings"] = maxi(1, int(e.get("pairings", 0)) >> 1)
			e["inherited"] = true
			out[k] = e
		f._learned_words = out


static func to_dict(f: Fish) -> Dictionary:
	return ensure_dict(f).duplicate(true)


static func from_dict(f: Fish, d: Variant) -> void:
	if d is Dictionary:
		f._learned_words = (d as Dictionary).duplicate(true)
