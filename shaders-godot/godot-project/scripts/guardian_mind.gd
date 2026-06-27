extends RefCounted

# Persistent inner-state for the Guardian companion (#10–19). Stored inside
# `_guardian_arc["mind"]` and serialized with the tank save (v6+).

const HUNGRY_THRESHOLD: float = 0.62

const MAX_MEMORIES: int = 24
const MAX_FEELINGS: int = 12
const MAX_RECENT_LINES: int = 8
const MAX_RITUALS: int = 6


static func ensure_mind(arc: Dictionary) -> Dictionary:
	if not arc.has("mind") or not (arc["mind"] is Dictionary):
		arc["mind"] = _default_mind()
	var mind: Dictionary = arc["mind"]
	for k in _default_mind().keys():
		if not mind.has(k):
			mind[k] = _default_mind()[k]
	return mind


static func _default_mind() -> Dictionary:
	return {
		"mood": "watchful",
		"wants": PackedStringArray(["be fed on time", "keep the tank calm"]),
		"beliefs": PackedStringArray(["the big shape brings food", "light means morning"]),
		"recent_feelings": PackedStringArray(),
		"memories_of_you": PackedStringArray(),
		"player_moniker": "the big shape",
		"preferences": {"corner": "front glass", "food": "pellets"},
		"visit_count": 0,
		"last_visit_unix": 0,
		"last_depart_unix": 0,
		"longest_gap_s": 0,
		"rituals": {},
		"personality_drift": "curious",
		"predecessor_name": "",
		"predecessor_note": "",
		"world_read": "",
		"player_read": "",
	}


static func record_visit(arc: Dictionary, unix: int, gap_s: int) -> void:
	var mind: Dictionary = ensure_mind(arc)
	mind["visit_count"] = int(mind.get("visit_count", 0)) + 1
	if gap_s > int(mind.get("longest_gap_s", 0)):
		mind["longest_gap_s"] = gap_s
	mind["last_visit_unix"] = unix
	_push_memory(mind, "you came back after %s away" % _gap_words(gap_s) if gap_s >= 120 else "you returned")
	if gap_s >= 86400 * 2:
		mind["mood"] = "wistful"
		_push_feeling(mind, "lonely while you were gone")
	elif gap_s >= 3600:
		mind["mood"] = "relieved"


static func record_departure(arc: Dictionary, unix: int) -> void:
	var mind: Dictionary = ensure_mind(arc)
	mind["last_depart_unix"] = unix
	mind["mood"] = "settled"
	_push_feeling(mind, "quiet after you left")


static func record_player_action(arc: Dictionary, action: String, detail: String = "") -> void:
	var mind: Dictionary = ensure_mind(arc)
	match action:
		"fed":
			mind["mood"] = "content"
			_push_memory(mind, "you fed us%s" % (" (%s)" % detail if detail != "" else ""))
			_track_ritual(mind, "feeding")
		"watched":
			mind["mood"] = "warm"
			_push_feeling(mind, "you watched the glass")
		"startled":
			mind["mood"] = "alert"
			_push_feeling(mind, "a sudden motion at the glass")
		"tap":
			_track_ritual(mind, "hello tap")
		"away_recap":
			if detail != "":
				_push_memory(mind, detail)
	_push_feeling(mind, action)


static func update_wants(f: Node, sim: Node, arc: Dictionary) -> void:
	var mind: Dictionary = ensure_mind(arc)
	var wants: PackedStringArray = PackedStringArray()
	var avg_h: float = _tank_avg_hunger(sim)
	if avg_h > HUNGRY_THRESHOLD:
		wants.append("eat soon")
	if float(f.get("stress") if f.get("stress") != null else 0.0) > 0.5:
		wants.append("feel safe again")
	if sim != null and sim.water_chemistry != null:
		var nh3: float = float(sim.water_chemistry.ammonia)
		if nh3 > 0.3:
			wants.append("cleaner water")
	if wants.is_empty():
		wants.append("a calm day")
	mind["wants"] = wants


static func update_world_read(sim: Node, arc: Dictionary) -> void:
	if sim == null:
		return
	var mind: Dictionary = ensure_mind(arc)
	var parts: Array[String] = []
	if sim.has_method("daylight"):
		var dl: float = float(sim.daylight())
		if dl < 0.2:
			parts.append("night in the tank")
		elif dl < 0.45:
			parts.append("dawn light on the glass")
		elif dl > 0.75:
			parts.append("late-day glow")
		else:
			parts.append("midday brightness")
	if sim.water_chemistry != null:
		var nh3: float = float(sim.water_chemistry.ammonia)
		var o2: float = float(sim.get("dissolved_o2") if sim.get("dissolved_o2") != null else 1.0)
		if nh3 > 0.35:
			parts.append("the water feels wrong")
		elif o2 < 0.5:
			parts.append("breathing feels thin")
		else:
			parts.append("the water feels steady")
	mind["world_read"] = ", ".join(parts)


static func update_player_read(arc: Dictionary, feed_history: Array) -> void:
	var mind: Dictionary = ensure_mind(arc)
	var visits: int = int(mind.get("visit_count", 0))
	if visits >= 30:
		mind["player_read"] = "you keep coming back — I know your rhythm"
	elif visits >= 10:
		mind["player_read"] = "you visit often enough that I expect you"
	elif visits <= 2:
		mind["player_read"] = "I am still learning your patterns"
	else:
		mind["player_read"] = "sometimes you stay, sometimes you vanish"
	if feed_history.size() >= 3:
		mind["player_read"] += "; you usually feed around the same time"
	if mind.get("longest_gap_s", 0) >= 86400 * 3:
		mind["player_moniker"] = "the long-absent shape"
	elif visits >= 20:
		mind["player_moniker"] = "my keeper"


static func apply_personality_drift(arc: Dictionary, event: String) -> void:
	var mind: Dictionary = ensure_mind(arc)
	match event:
		"crash_survived":
			mind["personality_drift"] = "wary"
			mind["mood"] = "wry"
		"doted_on":
			mind["personality_drift"] = "warm"
		"successor":
			mind["personality_drift"] = "hopeful"
		"predecessor_lost":
			mind["personality_drift"] = "mourning"


static func remember_line(arc: Dictionary, line: String) -> void:
	var mind: Dictionary = ensure_mind(arc)
	var recent: PackedStringArray = mind.get("recent_lines", PackedStringArray())
	recent.append(line.strip_edges())
	while recent.size() > MAX_RECENT_LINES:
		recent.remove_at(0)
	mind["recent_lines"] = recent


static func build_ai_context(f: Node, sim: Node, arc: Dictionary, situation: String) -> Dictionary:
	var mind: Dictionary = ensure_mind(arc)
	update_wants(f, sim, arc)
	update_world_read(sim, arc)
	var chapter: int = int(arc.get("chapter", 0))
	var bio: String = str(f.get("character_bio") if f.get("character_bio") != null else "")
	return {
		"fish_name": str(f.get("fish_name") if f.get("fish_name") != null else "Guardian"),
		"species": str(f.get("species") if f.get("species") != null else ""),
		"situation": situation,
		"chapter": chapter,
		"mood": str(mind.get("mood", "watchful")),
		"wants": (mind.get("wants", PackedStringArray()) as PackedStringArray),
		"beliefs": (mind.get("beliefs", PackedStringArray()) as PackedStringArray),
		"memories_of_you": (mind.get("memories_of_you", PackedStringArray()) as PackedStringArray),
		"recent_lines": (mind.get("recent_lines", PackedStringArray()) as PackedStringArray),
		"player_moniker": str(mind.get("player_moniker", "the big shape")),
		"world_read": str(mind.get("world_read", "")),
		"player_read": str(mind.get("player_read", "")),
		"personality_drift": str(mind.get("personality_drift", "curious")),
		"bio": bio,
		"predecessor_note": str(mind.get("predecessor_note", "")),
		"day_phase": str(sim.day_phase if sim != null and sim.get("day_phase") != null else ""),
	}


static func interpreted_situation(_f: Node, _sim: Node, arc: Dictionary, situation: String) -> String:
	var mind: Dictionary = ensure_mind(arc)
	var moniker: String = str(mind.get("player_moniker", "you"))
	match situation:
		"arrival":
			return "%s has returned to the glass" % moniker.capitalize()
		"departure":
			return "%s left; the tank goes quiet" % moniker
		"feed_nudge":
			return "the colony is hungry; hoping %s feeds soon" % moniker
		"autofeed_on":
			return "starvation forced self-care until %s returns" % moniker
		"water_stress":
			return mind.get("world_read", "water chemistry is off")
		"morning":
			return "dawn — expecting breakfast from %s" % moniker
		"away_recap":
			return "catching %s up after an absence" % moniker
		"successor":
			return "a new voice inherits the journal from %s" % str(mind.get("predecessor_name", "the last Guardian"))
		"lost":
			return "the Guardian has died; the tank is quieter"
		"daily":
			return "first visit of the day from %s" % moniker
		"closing_loop":
			return "the Walstad loop is complete — waste becomes food, death soil, light growth"
		_:
			return situation


static func cache_key(guardian_id: String, situation: String, day_label: String) -> String:
	return "%s|%s|%s" % [guardian_id, situation, day_label]


static func default_arc() -> Dictionary:
	return {
		"chapter": 0,
		"speak_cd": 0.0,
		"feed_nudges": 0,
		"autofeed_done": false,
		"last_daylight": 0.0,
		"last_daily_entry_day": -1,
		"mind": _default_mind(),
	}


static func _push_memory(mind: Dictionary, text: String) -> void:
	var mem: PackedStringArray = mind.get("memories_of_you", PackedStringArray())
	mem.append(text)
	while mem.size() > MAX_MEMORIES:
		mem.remove_at(0)
	mind["memories_of_you"] = mem


static func _push_feeling(mind: Dictionary, text: String) -> void:
	var feel: PackedStringArray = mind.get("recent_feelings", PackedStringArray())
	feel.append(text)
	while feel.size() > MAX_FEELINGS:
		feel.remove_at(0)
	mind["recent_feelings"] = feel


static func _track_ritual(mind: Dictionary, ritual_name: String) -> void:
	var rituals: Dictionary = mind.get("rituals", {})
	var count: int = int(rituals.get(ritual_name, 0)) + 1
	rituals[ritual_name] = count
	mind["rituals"] = rituals
	while rituals.size() > MAX_RITUALS:
		var oldest: String = str(rituals.keys()[0])
		rituals.erase(oldest)


static func _gap_words(gap_s: int) -> String:
	if gap_s < 3600:
		return "%d minutes" % int(round(gap_s / 60.0))
	if gap_s < 86400:
		return "%.1f hours" % (float(gap_s) / 3600.0)
	return "%.1f days" % (float(gap_s) / 86400.0)


static func _tank_avg_hunger(sim: Node) -> float:
	if sim == null or sim.get("fish") == null:
		return 0.0
	var sum: float = 0.0
	var n: int = 0
	for ff in sim.fish:
		if not is_instance_valid(ff) or ff.get("_dying") == true:
			continue
		sum += float(ff.get("hunger") if ff.get("hunger") != null else 0.0)
		n += 1
	return sum / maxf(float(n), 1.0)
