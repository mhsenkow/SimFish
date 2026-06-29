extends RefCounted

const FishMind = preload("res://scripts/fish_mind.gd")
const GuardianGenerative = preload("res://scripts/guardian_generative.gd")

# Persistent inner-state for the Guardian companion (#10–19). Stored inside
# `_guardian_arc["mind"]` and serialized with the tank save (v6+).

const HUNGRY_THRESHOLD: float = 0.62

const MAX_MEMORIES: int = 24
const MAX_FEELINGS: int = 12
const MAX_RECENT_LINES: int = 8
const MAX_RITUALS: int = 6

const CHAPTER_TITLES: Array[String] = [
	"First watch",
	"Learning hunger",
	"Shared rhythm",
	"Steady keeper",
	"Elder voice",
]


static func ensure_mind(arc: Dictionary) -> Dictionary:
	if not arc.has("mind") or not (arc["mind"] is Dictionary):
		arc["mind"] = _default_mind()
	var mind: Dictionary = arc["mind"]
	for k in _default_mind().keys():
		if not mind.has(k):
			mind[k] = _default_mind()[k]
	GuardianGenerative.ensure(arc)
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
		"predecessor_moniker": "",
		"predecessor_memories": PackedStringArray(),
		"shared_milestones": PackedStringArray(),
		"tank_started_day": -1,
		"generations_witnessed": 0,
		"world_read": "",
		"player_read": "",
		"quiet_moments": PackedStringArray(),
		"legend_note": "",
	}


static func chapter_title(chapter: int) -> String:
	var idx: int = clampi(chapter, 0, CHAPTER_TITLES.size() - 1)
	return CHAPTER_TITLES[idx]


static func voice_maturity(arc: Dictionary, tank_age_s: float) -> float:
	var mind: Dictionary = ensure_mind(arc)
	var visits: int = int(mind.get("visit_count", 0))
	var age_m: float = clampf(tank_age_s / (86400.0 * 14.0), 0.0, 1.0)
	var visit_m: float = clampf(float(visits) / 28.0, 0.0, 1.0)
	return clampf(age_m * 0.55 + visit_m * 0.45, 0.0, 1.0)


static func maybe_advance_chapter(arc: Dictionary, tank_age_s: float) -> void:
	var ch: int = int(arc.get("chapter", 0))
	var mind: Dictionary = ensure_mind(arc)
	var visits: int = int(mind.get("visit_count", 0))
	if visits >= 8:
		ch = maxi(ch, 1)
	if visits >= 20:
		ch = maxi(ch, 2)
	if tank_age_s >= 86400.0 * 5.0:
		ch = maxi(ch, 3)
	if tank_age_s >= 86400.0 * 21.0:
		ch = maxi(ch, 4)
	arc["chapter"] = mini(ch, CHAPTER_TITLES.size() - 1)


static func record_quiet_moment(arc: Dictionary, line: String) -> void:
	var text: String = line.strip_edges()
	if text == "":
		return
	var mind: Dictionary = ensure_mind(arc)
	var qm: PackedStringArray = mind.get("quiet_moments", PackedStringArray())
	qm.append(text)
	while qm.size() > 6:
		qm.remove_at(0)
	mind["quiet_moments"] = qm


static func compose_quiet_inner_line(sim: Node, _arc: Dictionary, gap_s: int) -> String:
	var dl: float = float(sim.daylight()) if sim != null and sim.has_method("daylight") else 0.5
	if gap_s >= 3600 and dl < 0.25:
		return "while you slept I watched the light move on the glass"
	if gap_s >= 7200:
		return "the tank kept its own time while you were away"
	if dl < 0.18:
		return "night here is quiet — just the filter and the slow drift of light"
	return "I had a little while alone with the water"


static func note_legend(arc: Dictionary, name: String, tank_age_s: float, generations: int) -> String:
	var days: int = int(round(tank_age_s / 86400.0))
	var note: String = "%s watched %d days, %d generations." % [name, days, generations]
	var mind: Dictionary = ensure_mind(arc)
	mind["legend_note"] = note
	return note


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
			GuardianGenerative.note_feed(arc)
		"watched":
			mind["mood"] = "warm"
			_push_feeling(mind, "you watched the glass")
			GuardianGenerative.note_keeper_present(arc)
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
	var longest_gap: int = int(mind.get("longest_gap_s", 0))
	if visits >= 30:
		mind["player_read"] = "you keep coming back — I know your rhythm"
	elif visits >= 10:
		mind["player_read"] = "you visit often enough that I expect you"
	elif visits <= 2:
		mind["player_read"] = "I am still learning your patterns"
	else:
		mind["player_read"] = "sometimes you stay, sometimes you vanish"
	if feed_history.size() >= 3:
		var sum_m: float = 0.0
		for m_v in feed_history:
			sum_m += float(m_v)
		var avg_m: int = int(round(sum_m / float(feed_history.size())))
		var hr: int = int(round(float(avg_m) / 60.0))
		mind["usual_feed_hour"] = hr
		if hr < 6:
			mind["player_read"] += "; you often feed before dawn"
		elif hr < 11:
			mind["player_read"] += "; you usually come in the morning"
		elif hr < 15:
			mind["player_read"] += "; midday is often when you feed"
		elif hr < 19:
			mind["player_read"] += "; you tend to come in the afternoon"
		else:
			mind["player_read"] += "; evening feeds are your habit"
	var care: float = 0.45
	if visits >= 20:
		care += 0.2
	if feed_history.size() >= 5:
		care += 0.15
	if longest_gap < 86400:
		care += 0.1
	elif longest_gap >= 86400 * 3:
		care -= 0.15
	mind["care_trust"] = snappedf(clampf(care, 0.0, 1.0), 0.01)
	if care >= 0.75:
		mind["player_read"] += "; the tank trusts your care"
	elif care <= 0.35 and longest_gap >= 86400 * 2:
		mind["player_read"] += "; we've been holding on alone awhile"
	if longest_gap >= 86400 * 3:
		mind["player_moniker"] = "the long-absent shape"
	elif visits >= 40 and longest_gap < 86400:
		mind["player_moniker"] = "my keeper"
	elif visits >= 15:
		mind["player_moniker"] = "the familiar shape"
	elif visits <= 2:
		mind["player_moniker"] = "the big shape"


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


static func record_milestone(arc: Dictionary, label: String) -> void:
	if label.strip_edges() == "":
		return
	var mind: Dictionary = ensure_mind(arc)
	var ms: PackedStringArray = mind.get("shared_milestones", PackedStringArray())
	if ms.has(label):
		return
	ms.append(label.strip_edges())
	while ms.size() > 12:
		ms.remove_at(0)
	mind["shared_milestones"] = ms


static func note_tank_started(arc: Dictionary, sim_day: int) -> void:
	var mind: Dictionary = ensure_mind(arc)
	if int(mind.get("tank_started_day", -1)) < 0 and sim_day >= 0:
		mind["tank_started_day"] = sim_day
		record_milestone(arc, "since you started this tank")


static func note_generation(arc: Dictionary, generation: int) -> void:
	var mind: Dictionary = ensure_mind(arc)
	var prev: int = int(mind.get("generations_witnessed", 0))
	if generation > prev:
		mind["generations_witnessed"] = generation
		if generation >= 2:
			record_milestone(arc, "%d generations have passed" % generation)


static func inherit_predecessor_bond(arc: Dictionary, pred_name: String,
		pred_moniker: String, pred_memories: PackedStringArray) -> void:
	var mind: Dictionary = ensure_mind(arc)
	mind["predecessor_name"] = pred_name
	mind["predecessor_moniker"] = pred_moniker
	mind["predecessor_memories"] = pred_memories
	if pred_name != "":
		record_milestone(arc, "inheriting %s's watch" % pred_name)


static func remember_line(arc: Dictionary, line: String) -> void:
	var mind: Dictionary = ensure_mind(arc)
	var recent: PackedStringArray = mind.get("recent_lines", PackedStringArray())
	recent.append(line.strip_edges())
	while recent.size() > MAX_RECENT_LINES:
		recent.remove_at(0)
	mind["recent_lines"] = recent


static func build_ai_context(f: Node, sim: Node, arc: Dictionary, situation: String) -> Dictionary:
	var mind: Dictionary = ensure_mind(arc)
	if f != null:
		update_wants(f, sim, arc)
	update_world_read(sim, arc)
	var chapter: int = int(arc.get("chapter", 0))
	var bio: String = ""
	if f != null:
		bio = str(f.get("character_bio") if f.get("character_bio") != null else "")
	var allowed: PackedStringArray = PackedStringArray()
	if sim != null and sim.get("fish") != null:
		for ff in sim.fish:
			if is_instance_valid(ff):
				var n: String = String(ff.fish_name if ff.fish_name != "" else ff.species)
				if n != "" and not allowed.has(n):
					allowed.append(n)
	var feel: String = str(mind.get("mood", "watchful"))
	var stress: float = 0.0
	if f != null:
		if f.get("mood") != null and f.get("arousal") != null:
			feel = FishMind.emotional_state(f)
		if f.get("stress") != null:
			stress = float(f.stress)
	var ctx: Dictionary = {
		"fish_name": str(f.get("fish_name") if f != null and f.get("fish_name") != null else "Guardian"),
		"species": str(f.get("species") if f != null and f.get("species") != null else ""),
		"situation": situation,
		"chapter": chapter,
		"mood": str(mind.get("mood", "watchful")),
		"feel": feel,
		"wants": (mind.get("wants", PackedStringArray()) as PackedStringArray),
		"beliefs": (mind.get("beliefs", PackedStringArray()) as PackedStringArray),
		"memories_of_you": (mind.get("memories_of_you", PackedStringArray()) as PackedStringArray),
		"recent_lines": (mind.get("recent_lines", PackedStringArray()) as PackedStringArray),
		"player_moniker": str(mind.get("player_moniker", "the big shape")),
		"world_read": str(mind.get("world_read", "")),
		"player_read": str(mind.get("player_read", "")),
		"care_trust": float(mind.get("care_trust", 0.5)),
		"usual_feed_hour": int(mind.get("usual_feed_hour", -1)),
		"personality_drift": str(mind.get("personality_drift", "curious")),
		"bio": bio,
		"predecessor_note": str(mind.get("predecessor_note", "")),
		"predecessor_name": str(mind.get("predecessor_name", "")),
		"predecessor_moniker": str(mind.get("predecessor_moniker", "")),
		"predecessor_memories": mind.get("predecessor_memories", PackedStringArray()),
		"shared_milestones": mind.get("shared_milestones", PackedStringArray()),
		"voice_maturity": voice_maturity(arc, float(sim.tank_age_s if sim != null and sim.get("tank_age_s") != null else 0.0)),
		"chapter_title": chapter_title(chapter),
		"quiet_moments": mind.get("quiet_moments", PackedStringArray()),
		"legend_note": str(mind.get("legend_note", "")),
		"tank_started_day": int(mind.get("tank_started_day", -1)),
		"generations_witnessed": int(mind.get("generations_witnessed", 0)),
		"day_phase": str(sim.day_phase if sim != null and sim.get("day_phase") != null else ""),
		"allowed_fish_names": allowed,
		"stress": snappedf(stress, 0.01),
		"observed_fish": str(arc.get("_observe_name", "")) if situation == "observe" else "",
		"observed_feel": str(arc.get("_observe_feel", "")) if situation == "observe" else "",
		"tank_society": FishMind.society_snapshot(sim) if sim != null else {},
	}
	ctx.merge(GuardianGenerative.context_fields(arc))
	return ctx


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
		"newcomer":
			return "someone new joined the tank"
		"loss":
			return "someone left the tank"
		"observe":
			var on: String = str(arc.get("_observe_name", "someone"))
			var of: String = str(arc.get("_observe_feel", "calm"))
			return "noticing how %s seems %s" % [on, of]
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
