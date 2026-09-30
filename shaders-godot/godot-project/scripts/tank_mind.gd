extends RefCounted

# SENTIENCE_THE_NIGHT_WATCH §A — tank-level collective workspace (slow macro mind).

const GlobalWorkspace = preload("res://scripts/global_workspace.gd")
const MindLexicon = preload("res://scripts/mind_lexicon.gd")
const KeeperCare = preload("res://scripts/keeper_care.gd")
const TankDialogue = preload("res://scripts/tank_dialogue.gd")
const FishSocial = preload("res://scripts/fish_social.gd")

const SCHEMA_VERSION: int = 1
const CAPACITY: int = 2
const IGNITION_THRESHOLD: float = 0.52
const TICK_DAY_S: float = 12.0
const TICK_NIGHT_S: float = 5.0
const TICK_IDLE_S: float = 3.5
const STREAM_COOLDOWN_S: float = 420.0
const LEDGER_MAX: int = 24


static func _night_f(sim, key: String, fallback: float = 0.0) -> float:
	if sim != null and sim.has_method("night_rt_f"):
		return float(sim.night_rt_f(key, fallback))
	return fallback


static func _set_night_f(sim, key: String, value: float) -> void:
	if sim != null and sim.has_method("set_night_rt_f"):
		sim.set_night_rt_f(key, value)


static func _night_b(sim, key: String, fallback: bool = false) -> bool:
	if sim != null and sim.has_method("night_rt_b"):
		return bool(sim.night_rt_b(key, fallback))
	return fallback


static func _set_night_b(sim, key: String, value: bool) -> void:
	if sim != null and sim.has_method("set_night_rt_b"):
		sim.set_night_rt_b(key, value)


static func ensure(sim) -> Dictionary:
	if sim.get("_tank_mind") == null or not (sim._tank_mind is Dictionary):
		sim._tank_mind = {
			"schema_version": SCHEMA_VERSION,
			"workspace": [],
			"focus": "",
			"ignited": false,
			"ignition_cd": 0.0,
			"mood_valence": 0.0,
			"mood_arousal": 0.18,
			"collective_arousal": 0.2,
			"asleep_fraction": 0.0,
			"self_summary": "we are many; the water holds us",
			"stream": "",
			"stream_cd": 0.0,
			"duration_since_dusk": 0.0,
			"night_quality": 0.55,
			"night_ledger": [],
			"tick_accum": 0.0,
			"last_ignition_t": 0,
			"watcher_fish_id": "",
			"solitude": 0.0,
			"away_events": [],
			"nights_tended": 0,
			"bad_night": false,
			"stocking_feel": "balanced",
			"nightlight_sessions": 0,
			"quorum_asleep": 0.0,
			"semantic_facts": [],
		}
	return sim._tank_mind


static func enabled() -> bool:
	var cfg: Node = _cfg()
	if cfg == null:
		return true
	if cfg.get("sentience_voice_off") != null and bool(cfg.sentience_voice_off):
		return false
	return bool(cfg.get("consciousness_workspace_enabled") if cfg.get("consciousness_workspace_enabled") != null else true)


static func tick(sim, dt: float, room_idle_s: float = 0.0) -> void:
	if sim == null or not enabled():
		return
	var tm: Dictionary = ensure(sim)
	tm["ignition_cd"] = maxf(0.0, float(tm.get("ignition_cd", 0.0)) - dt)
	tm["stream_cd"] = maxf(0.0, float(tm.get("stream_cd", 0.0)) - dt)
	var dl: float = SimGate.daylight(sim, 0.5)
	var phase: float = _float_prop(sim, "day_phase", 0.5)
	var is_night: bool = dl < 0.28
	if is_night:
		tm["duration_since_dusk"] = float(tm.get("duration_since_dusk", 0.0)) + dt
	elif dl > 0.45:
		tm["duration_since_dusk"] = 0.0
		if phase > 0.08 and phase < 0.18 and float(tm.get("duration_since_dusk", 0.0)) <= 0.0:
			_note_dawn(sim, tm)
	# Solitude (#91): deep idle at night.
	var solo: float = 0.0
	if is_night and room_idle_s > 30.0:
		solo = clampf((room_idle_s - 30.0) / 120.0, 0.0, 1.0)
	tm["solitude"] = solo
	_aggregate_fish(sim, tm, dl)
	_update_stocking_feel(sim, tm)
	if is_night:
		_maybe_dream(sim, tm, dl)
	var interval: float = TICK_DAY_S
	if is_night:
		interval = TICK_NIGHT_S
	if room_idle_s > 20.0:
		interval = TICK_IDLE_S
	var cathedral: bool = _cathedral_active(sim)
	if cathedral:
		interval *= 0.65
	if _float_prop(sim, "dissolved_o2", 1.0) < 0.5 or _float_prop(sim, "stability", 1.0) < 0.45:
		interval *= 0.55
	var season_bias: float = _night_f(sim, "season_night_bias")
	if season_bias > 0.05:
		interval *= 1.0 + season_bias
	tm["tick_accum"] = float(tm.get("tick_accum", 0.0)) + dt
	if float(tm.get("tick_accum", 0.0)) < interval:
		sim._tank_mind = tm
		return
	tm["tick_accum"] = 0.0
	var bids: Array = collect_bids(sim, tm, dl, room_idle_s)
	var result: Dictionary = _run_competition(bids)
	_broadcast(sim, tm, result, dl, room_idle_s)
	if bool(result.get("ignited", false)):
		_on_ignition(sim, tm, str(result.get("focus", "")))
	if float(tm.get("stream_cd", 0.0)) <= 0.0 and (is_night or room_idle_s > 45.0):
		_maybe_stream(sim, tm, dl, solo)
	sim._tank_mind = tm


static func tick_coarse(sim, _dt: float, away: bool = false) -> void:
	if sim == null:
		return
	var tm: Dictionary = ensure(sim)
	var dl: float = SimGate.daylight(sim, 0.12)
	var bids: Array = collect_bids(sim, tm, dl, 999.0 if away else 0.0)
	var result: Dictionary = _run_competition(bids)
	_broadcast(sim, tm, result, dl, 999.0 if away else 0.0)
	if away and randf() < 0.35:
		_ledger(sim, tm, _away_ledger_line(tm, dl))
	sim._tank_mind = tm


static func append_ledger_line(sim, tm: Dictionary, line: String) -> void:
	_ledger(sim, tm, line)


static func collect_bids(sim, tm: Dictionary, dl: float, room_idle_s: float) -> Array:
	var bids: Array = []
	var arousal: float = float(tm.get("collective_arousal", 0.2))
	var asleep: float = float(tm.get("asleep_fraction", 0.0))
	if dl < 0.28:
		bids.append(_bid("night_rest", 0.42 + asleep * 0.35, ["night", "rest"]))
		if dl < 0.12:
			bids.append(_bid("deep_dark", 0.38 + float(tm.get("solitude", 0.0)) * 0.2, ["night", "solitude"]))
	else:
		bids.append(_bid("daylight", 0.36, ["day", "light"]))
	if arousal > 0.45:
		bids.append(_bid("collective_arousal", arousal + 0.2, ["school", "social"]))
	if _float_prop(sim, "dissolved_o2", 1.0) < 0.55:
		bids.append(_bid("breath_low", 0.58, ["interoception", "o2"]))
	var phase: float = _float_prop(sim, "day_phase", 0.5)
	if phase > 0.73 and phase < 0.77:
		bids.append(_bid("midnight_nadir", 0.46 + asleep * 0.22, ["night", "midnight"]))
	if phase > 0.68 and phase < 0.82:
		bids.append(_bid("predawn", 0.44, ["night", "predawn"]))
	if _float_prop(sim, "stability", 1.0) < 0.45:
		bids.append(_bid("instability", 0.62, ["threat", "care"]))
	if room_idle_s > 60.0 and dl < 0.3:
		bids.append(_bid("unwatched", 0.32 + float(tm.get("solitude", 0.0)) * 0.25, ["solitude", "night"]))
	var feel: String = str(tm.get("stocking_feel", ""))
	if feel == "lonely":
		bids.append(_bid("lonely_tank", 0.4, ["lonely", "night"]))
	elif feel == "crowded":
		bids.append(_bid("crowded_tank", 0.38, ["crowded", "night"]))
	if _cathedral_active(sim):
		bids.append(_bid("cathedral", 0.55, ["night", "vespers"]))
	if dl < 0.3:
		bids.append(_bid("acoustic_dark", 0.34 + (1.0 - dl) * 0.2, ["sound", "night"]))
		var pulse: float = absf(sin(phase * TAU * 3.5))
		bids.append(_bid("heater_pulse", 0.2 + pulse * 0.18, ["heater", "night"]))
		var sfa: float = _night_f(sim, "slow_fauna_night")
		if sfa > 0.2:
			bids.append(_bid("slow_patrol", 0.28 + sfa * 0.25, ["snail", "night"]))
		var bfc: float = _night_f(sim, "biofilter_calm")
		if bfc > 0.35:
			bids.append(_bid("biofilter", 0.26 + bfc * 0.2, ["biofilter", "night"]))
		if _float_prop(sim, "dissolved_o2", 1.0) < 0.65 or _float_prop(sim, "dissolved_o2", 1.0) > 0.0:
			bids.append(_bid("water_feel", 0.3, ["water", "interoception"]))
		if _night_f(sim, "night_stillness") > 0.55:
			bids.append(_bid("stillness", 0.36, ["night", "motion"]))
	# Biolum night-life (#39).
	if dl < 0.28:
		for f in _fish_list(sim):
			if _fauna_alive(f) and bool(f.get("is_bioluminescent")):
				bids.append(_bid("biolum_life", 0.32, ["biolum", "night"]))
				break
	# Loudest recent story beat.
	if sim.get("story_events") is Array and (sim.story_events as Array).size() > 0:
		var last: String = str((sim.story_events as Array)[-1])
		if last.length() > 8:
			bids.append(_bid("recent_event", 0.28, ["memory", "event"]))
	return bids


static func mood_overlay(sim) -> Dictionary:
	var tm: Dictionary = ensure(sim)
	var v: float = float(tm.get("mood_valence", 0.0))
	var a: float = float(tm.get("mood_arousal", 0.18))
	var dl: float = SimGate.daylight(sim, 0.5)
	var night_wash: float = 1.0 - clampf(dl / 0.35, 0.0, 1.0)
	return {
		"hue": v * 0.07 - night_wash * 0.04,
		"sat": lerpf(0.9, 1.06, a) * lerpf(1.0, 0.88, night_wash * 0.5),
		"warmth": v * 0.1 - night_wash * 0.06,
		"val": lerpf(0.86, 1.0, 0.45 + v * 0.35) * lerpf(1.0, 0.92, night_wash * 0.35),
	}


static func snapshot(sim) -> Dictionary:
	var tm: Dictionary = ensure(sim)
	return {
		"focus": str(tm.get("focus", "")),
		"ignited": bool(tm.get("ignited", false)),
		"mood_valence": snappedf(float(tm.get("mood_valence", 0.0)), 0.01),
		"mood_arousal": snappedf(float(tm.get("mood_arousal", 0.0)), 0.01),
		"asleep_fraction": snappedf(float(tm.get("asleep_fraction", 0.0)), 0.01),
		"self_summary": str(tm.get("self_summary", "")),
		"stream": str(tm.get("stream", "")),
		"night_quality": snappedf(float(tm.get("night_quality", 0.5)), 0.01),
		"solitude": snappedf(float(tm.get("solitude", 0.0)), 0.01),
	}


static func to_dict(sim) -> Dictionary:
	return ensure(sim).duplicate(true)


static func from_dict(sim, d: Variant) -> void:
	if d is Dictionary:
		var tm: Dictionary = (d as Dictionary).duplicate(true)
		# Saves from before the keeper-memory ledger get one (versioned, bounded).
		if not tm.is_empty():
			TankDialogue.migrate(tm)
		sim._tank_mind = tm


static func away_recap_lines(sim) -> PackedStringArray:
	var tm: Dictionary = ensure(sim)
	var out: PackedStringArray = PackedStringArray()
	for e in tm.get("away_events", []):
		var s: String = str(e)
		if s != "":
			out.append(s)
	var ledger_lines: Variant = tm.get("night_ledger", null)
	if ledger_lines is Array:
		for i in range(mini((ledger_lines as Array).size(), 3)):
			out.append(str((ledger_lines as Array)[-(i + 1)]))
	return out


static func _aggregate_fish(sim, tm: Dictionary, dl: float) -> void:
	var fish_arr: Array = _fish_list(sim)
	if fish_arr.is_empty():
		return
	var sum_ar: float = 0.0
	var sum_st: float = 0.0
	var sum_mood: float = 0.0
	var asleep_n: int = 0
	var n: int = 0
	for f in fish_arr:
		if not _fauna_alive(f):
			continue
		n += 1
		sum_ar += f.arousal
		sum_st += f.stress
		sum_mood += f.mood
		if f._asleep:
			asleep_n += 1
	if n <= 0:
		return
	tm["collective_arousal"] = sum_ar / float(n)
	tm["mood_arousal"] = lerpf(float(tm.get("mood_arousal", 0.18)), sum_st / float(n), 0.08)
	tm["mood_valence"] = lerpf(float(tm.get("mood_valence", 0.0)), sum_mood / float(n), 0.06)
	tm["asleep_fraction"] = float(asleep_n) / float(n)
	if dl < 0.28 and float(tm.get("asleep_fraction", 0.0)) > 0.55:
		tm["night_quality"] = clampf(float(tm.get("night_quality", 0.5)) + 0.002, 0.0, 1.0)
	elif dl < 0.28 and float(tm.get("collective_arousal", 0.0)) > 0.55:
		tm["night_quality"] = clampf(float(tm.get("night_quality", 0.5)) - 0.004, 0.0, 1.0)
		tm["bad_night"] = true


static func _update_stocking_feel(sim, tm: Dictionary) -> void:
	var cap: int = 12
	if sim.has_method("fish_carrying_capacity"):
		cap = maxi(4, int(sim.fish_carrying_capacity()))
	var n: int = _fish_list(sim).size()
	var ratio: float = float(n) / float(cap)
	if ratio < 0.35:
		tm["stocking_feel"] = "lonely"
	elif ratio > 0.92:
		tm["stocking_feel"] = "crowded"
	else:
		tm["stocking_feel"] = "balanced"


static func _run_competition(bids: Array) -> Dictionary:
	if bids.is_empty():
		return {"contents": [], "ignited": false, "focus": "", "top_salience": 0.0}
	var sorted: Array = bids.duplicate()
	sorted.sort_custom(func(a, b): return float(a.get("salience", 0.0)) > float(b.get("salience", 0.0)))
	var winners: Array = []
	var top_s: float = 0.0
	for b in sorted:
		if winners.size() >= CAPACITY:
			break
		var s: float = float(b.get("salience", 0.0))
		if winners.is_empty():
			top_s = s
		if s >= IGNITION_THRESHOLD * 0.55 or winners.is_empty():
			winners.append(b)
	var ignited: bool = top_s >= IGNITION_THRESHOLD
	var focus: String = ""
	if not winners.is_empty():
		focus = str((winners[0] as Dictionary).get("label", ""))
	return {"contents": winners, "ignited": ignited, "focus": focus, "top_salience": top_s}


static func _broadcast(_sim, tm: Dictionary, result: Dictionary, dl: float, room_idle_s: float) -> void:
	var focus: String = str(result.get("focus", ""))
	tm["workspace"] = result.get("contents", [])
	tm["focus"] = focus
	tm["ignited"] = bool(result.get("ignited", false))
	if focus == "night_rest" and dl < 0.2:
		tm["self_summary"] = "we are many; it is dark; we are resting"
	elif focus == "breath_low":
		tm["self_summary"] = "the water feels thin tonight"
	elif focus == "unwatched" and room_idle_s > 90.0:
		tm["self_summary"] = "no one is watching; we keep our own time"
	elif focus == "cathedral":
		tm["self_summary"] = "a quiet vigil in the dark glass"


static func _on_ignition(sim, tm: Dictionary, focus: String) -> void:
	if float(tm.get("ignition_cd", 0.0)) > 0.0:
		return
	tm["ignition_cd"] = 45.0
	tm["last_ignition_t"] = Time.get_ticks_msec()
	_ledger(sim, tm, "the whole tank noticed %s" % focus.replace("_", " "))
	if focus in ["instability", "breath_low"]:
		for f in _fish_list(sim):
			if _fauna_alive(f) and not f._asleep:
				f.arousal = clampf(f.arousal + 0.08, 0.0, 1.0)
	elif focus == "predawn" or focus == "daylight":
		for f in _fish_list(sim):
			if _fauna_alive(f):
				f._interest_remaining = maxf(f._interest_remaining, 0.25)


static func _maybe_stream(_sim, tm: Dictionary, _dl: float, solo: float) -> void:
	var focus: String = str(tm.get("focus", ""))
	var line: String = ""
	match focus:
		"night_rest":
			line = "the tank settles into one slow breath"
		"deep_dark":
			line = "dark holds the glass; nothing needs deciding"
		"unwatched":
			line = "no one is watching — the loop runs anyway"
		"midnight_nadir":
			line = "deepest dark — the tank at its stillest"
		"predawn":
			line = "the quietest hour before light"
		"cathedral":
			line = "a hush like a small church of water"
		"lonely_tank":
			line = "too much empty water tonight"
		"crowded_tank":
			line = "many bodies, one slow pulse"
		"acoustic_dark":
			line = "the dark listens more than it sees"
		"slow_patrol":
			line = "snails keep the slow watch"
		"biofilter":
			line = "the invisible engine breathes at rest"
		"water_feel":
			line = "the water carries tonight's weight"
		"stillness":
			line = "stillness makes every fin enormous"
		"biolum_life":
			line = "a faint glow moves in the dark"
		"heater_pulse":
			line = "a slow click marks the hours"
		_:
			if solo > 0.6:
				line = "alone with itself in the dark"
	if line == "":
		return
	tm["stream"] = line
	tm["stream_cd"] = STREAM_COOLDOWN_S
	_ledger(_sim, tm, line)


# Deep night: recombine the day's strongest events into one dream line
# (TankDialogue owns the content + once-per-night gate).
static func _maybe_dream(sim, tm: Dictionary, dl: float) -> void:
	var d: Dictionary = TankDialogue.maybe_dream(sim, tm, dl)
	if d.is_empty():
		return
	var line: String = str(d.get("line", ""))
	tm["stream"] = line
	_ledger(sim, tm, "the tank dreamed: %s" % line.trim_prefix("we dreamed "))


static func _note_dawn(sim, tm: Dictionary) -> void:
	tm["nights_tended"] = int(tm.get("nights_tended", 0)) + 1
	var q: float = float(tm.get("night_quality", 0.5))
	if q > 0.6 and not bool(tm.get("bad_night", false)):
		tm["self_summary"] = "a good night passed; we are still here"
	elif bool(tm.get("bad_night", false)):
		tm["self_summary"] = "a rough night; we carry it into day"
	tm["bad_night"] = false
	_ledger(sim, tm, "dawn — the tank stirs together")


static func _ledger(_sim, tm: Dictionary, line: String) -> void:
	if line.strip_edges() == "":
		return
	var ledger_lines: Array = tm.get("night_ledger", [])
	ledger_lines.append(line.strip_edges().substr(0, 96))
	while ledger_lines.size() > LEDGER_MAX:
		ledger_lines.pop_front()
	tm["night_ledger"] = ledger_lines
	var away: Array = tm.get("away_events", [])
	if away.size() < 8:
		away.append(line.strip_edges().substr(0, 96))
		tm["away_events"] = away


static func _away_ledger_line(tm: Dictionary, dl: float) -> String:
	if dl < 0.15:
		return "the tank slept on without you"
	if float(tm.get("collective_arousal", 0.0)) > 0.5:
		return "something kept the water uneasy"
	return "the dark passed quietly"


static func _bid(label: String, salience: float, coalition: Array) -> Dictionary:
	return {"label": label, "salience": salience, "coalition": coalition}


static func _cfg() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return null
	var st: SceneTree = ml as SceneTree
	if st == null or st.root == null or not st.root.is_inside_tree():
		return null
	return st.root.get_node_or_null("/root/TankConfig")


static func _cathedral_active(sim) -> bool:
	if sim == null:
		return false
	if sim.has_method("spark_night_cathedral"):
		return bool(sim.spark_night_cathedral())
	return bool(sim._spark_night_cathedral) if sim.get("_spark_night_cathedral") != null else false


static func _fish_list(sim) -> Array:
	if sim.get("fish") is Array:
		return sim.fish as Array
	return []


static func _fauna_alive(node: Variant) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if not (node is Fish):
		return false
	var fn: Fish = node as Fish
	if fn.is_queued_for_deletion():
		return false
	if fn.get("_dying") == true:
		return false
	return true


static func _float_prop(sim, key: String, fallback: float) -> float:
	var v: Variant = sim.get(key)
	if v == null or v is Callable:
		return fallback
	return float(v)



# --- Keeper ↔ tank channel ("speak to the tank") ---------------------------
#
# When no fish is followed the keeper addresses the tank as a whole. The tank
# answers in a collective "we" built only from real state (chemistry, hunger,
# stress, day/night, workspace summary, last story beat), then a few relevant
# fish answer through the normal per-fish reply pipeline (main.gd routes them
# via KeeperInput.submit_to_fish → sim.request_keeper_reply). Template-only:
# no LLM, no blocking — safe to call on the main thread per keypress.

const KEEPER_RECENT_MAX: int = 6
const RESPONDERS_MAX: int = 3
const RESPONDER_MIN_SCORE: float = 0.25

const KEEPER_TOPICS: Dictionary = {
	"greeting": ["hello", "hi", "hey", "morning", "evening", "greetings", "howdy", "yo"],
	"food": ["food", "hungry", "hunger", "eat", "eating", "feed", "fed", "feeding",
			"dinner", "breakfast", "snack", "starving", "flakes", "pellets", "meal"],
	"calm": ["safe", "calm", "ok", "okay", "shh", "shhh", "quiet", "relax", "easy",
			"trust", "gentle", "sorry", "rest", "breathe"],
	"air": ["air", "oxygen", "o2", "breath", "breathing", "bubbles", "gasp", "gasping",
			"suffocating", "aeration"],
	"water": ["water", "clean", "dirty", "ammonia", "nitrate", "nitrite", "cloudy",
			"murky", "filter", "chemistry", "toxic"],
	"light": ["light", "dark", "night", "sleep", "sleepy", "day", "sun", "lamp",
			"tired", "dawn", "dusk", "goodnight"],
	"wellbeing": ["how", "feel", "feeling", "doing", "happy", "sad", "alright", "well",
			"status", "healthy", "sick", "ill"],
	"love": ["love", "good", "beautiful", "pretty", "proud", "thanks", "thank", "lovely",
			"cute", "friend", "friends"],
	"who": ["who", "many", "count", "everyone", "everybody", "all", "family", "names"],
	# Questions about the tank's inner life (TankDialogue.detect_intent routes
	# the exact question: thinking / dream / friend / about <fish>).
	"mind": ["think", "thinking", "thought", "thoughts", "mind", "dream", "dreams", "dreamed",
			"dreamt", "dreaming", "wondering"],
}


# Split keeper text into tokens and the grounded topics the tank "hears".
static func parse_keeper_words(text: String) -> Dictionary:
	var clean: String = text.to_lower()
	for ch in [".", ",", "!", "?", ";", ":", "\"", "(", ")", "…", "—", "-", "'"]:
		clean = clean.replace(ch, " ")
	var toks: PackedStringArray = clean.split(" ", false)
	var topics: PackedStringArray = PackedStringArray()
	var heard: PackedStringArray = PackedStringArray()
	for tok in toks:
		for topic in KEEPER_TOPICS:
			if tok in (KEEPER_TOPICS[topic] as Array):
				if not topics.has(topic):
					topics.append(topic)
				if not heard.has(tok):
					heard.append(tok)
	var question: bool = "?" in text
	if topics.is_empty() and question:
		topics.append("wellbeing")
	return {"tokens": toks, "topics": topics, "heard": heard, "question": question,
			"loud": "!" in text or (text.length() > 3 and text == text.to_upper()
					and text.to_lower() != text)}


# Real tank state the collective voice is allowed to talk about.
static func keeper_state(sim) -> Dictionary:
	var tm: Dictionary = ensure(sim)
	var st: Dictionary = {
		"o2": _float_prop(sim, "dissolved_o2", 0.85),
		"ammonia": 0.0,
		"nitrite": 0.0,
		"nitrate": 0.0,
		"daylight": SimGate.daylight(sim, 0.6),
		"focus": str(tm.get("focus", "")),
		"summary": str(tm.get("self_summary", "")),
		"stream": str(tm.get("stream", "")),
		"stocking": str(tm.get("stocking_feel", "balanced")),
		"valence": float(tm.get("mood_valence", 0.0)),
		"event": "",
		"tier": KeeperCare.Tier.STEADY,
	}
	var wc: Variant = sim.get("water_chemistry")
	if wc is Object and wc != null:
		for k in ["ammonia", "nitrite", "nitrate"]:
			var v: Variant = (wc as Object).get(k)
			if v != null:
				st[k] = float(v)
	if sim is Node:
		st["tier"] = KeeperCare.tier_from_sim(sim as Node)
	var ev: Variant = sim.get("story_events")
	if ev is Array and not (ev as Array).is_empty():
		var last: Variant = (ev as Array)[-1]
		var txt: String = str((last as Dictionary).get("text", "")) if last is Dictionary else str(last)
		st["event"] = txt.strip_edges().to_lower().substr(0, 56)
	var n: int = 0
	var asleep: int = 0
	var hungry_n: int = 0
	var sum_h: float = 0.0
	var sum_s: float = 0.0
	var hungriest: Fish = null
	var tensest: Fish = null
	var names: PackedStringArray = PackedStringArray()
	for f in _fish_list(sim):
		if not _fauna_alive(f):
			continue
		var fish: Fish = f as Fish
		n += 1
		sum_h += fish.hunger
		var tension: float = maxf(fish.stress, fish.spooked)
		sum_s += tension
		if fish.hunger > 0.55:
			hungry_n += 1
		if fish._asleep:
			asleep += 1
		if hungriest == null or fish.hunger > hungriest.hunger:
			hungriest = fish
		if tensest == null or tension > maxf(tensest.stress, tensest.spooked):
			tensest = fish
		if names.size() < 4:
			names.append(_fish_moniker(fish))
	st["n"] = n
	st["asleep"] = asleep
	st["hungry_n"] = hungry_n
	st["avg_hunger"] = sum_h / float(n) if n > 0 else 0.0
	st["avg_stress"] = sum_s / float(n) if n > 0 else 0.0
	st["max_hunger"] = hungriest.hunger if hungriest != null else 0.0
	st["max_stress"] = maxf(tensest.stress, tensest.spooked) if tensest != null else 0.0
	st["hungriest"] = _fish_moniker(hungriest) if hungriest != null else "someone"
	st["tensest"] = _fish_moniker(tensest) if tensest != null else "someone"
	st["names"] = ", ".join(names) + (" …" if n > names.size() else "")
	return st


static func _fish_moniker(f: Fish) -> String:
	if f == null:
		return "someone"
	if f.fish_name.strip_edges() != "":
		return f.fish_name.strip_edges()
	return "a %s" % str(f.species).replace("_", " ")


# Words any living fish has actually paired (MindLexicon) — the tank's shared
# vocabulary for this line.
static func lexicon_understood(sim, tokens: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for f in _fish_list(sim):
		if not _fauna_alive(f):
			continue
		for tok in tokens:
			if not out.has(tok) and MindLexicon.comprehend(f as Fish, tok):
				out.append(tok)
	return out


# Most pressing real condition, as a list of short phrasings (variants).
static func _ground_variants(st: Dictionary, covered: PackedStringArray) -> Array:
	if float(st["o2"]) < 0.45 and not covered.has("air"):
		return ["the water feels thin; we are breathing hard near the top",
				"air is low in here — o2 at %d%%" % int(round(float(st["o2"]) * 100.0)),
				"our gills work harder than they should"]
	if (float(st["ammonia"]) >= 0.18 or float(st["nitrite"]) >= 0.18) and not covered.has("water"):
		return ["something sharp stings the gills — ammonia",
				"the water tastes of waste tonight",
				"the water bites a little; the bacteria are behind"]
	if (float(st["avg_hunger"]) > 0.55 or float(st["max_hunger"]) > 0.75) and not covered.has("food"):
		return ["%s keeps looking up for food" % st["hungriest"],
				"%d of us are hungry" % maxi(1, int(st["hungry_n"])),
				"bellies are light; %s most of all" % st["hungriest"]]
	if float(st["max_stress"]) > 0.55 and not covered.has("calm"):
		return ["%s is uneasy, fins tight" % st["tensest"],
				"one of us — %s — can't settle" % st["tensest"]]
	if float(st["daylight"]) < 0.28 and not covered.has("light"):
		return ["it is dark; %d of us are asleep" % int(st["asleep"]),
				"night now — we keep it slow",
				"the dark holds us close"]
	if str(st["stocking"]) == "lonely":
		return ["there is a lot of empty water around so few of us"]
	if str(st["stocking"]) == "crowded":
		return ["many bodies, one slow pulse"]
	var out: Array = []
	if str(st["summary"]) != "":
		out.append(str(st["summary"]))
	if str(st["stream"]) != "":
		out.append(str(st["stream"]))
	if str(st["event"]) != "":
		out.append("we remember: %s" % st["event"])
	if out.is_empty():
		out.append("the water holds us")
	return out


static func _opener_variants(topic: String, st: Dictionary, w: String) -> Array:
	var d: Dictionary = {
		"w": w, "n": st["n"], "hungry": maxi(1, int(st["hungry_n"])),
		"hname": st["hungriest"], "sname": st["tensest"], "asleep": st["asleep"],
		"o2": int(round(float(st["o2"]) * 100.0)), "names": st["names"],
		"summary": st["summary"],
	}
	var lines: Array = []
	match topic:
		"greeting":
			lines = ["{w}, keeper. {n} of us here, listening",
					"we feel you at the glass — {w}",
					"{w}… the water turns toward you"]
		"food":
			if float(st["avg_hunger"]) > 0.5 or float(st["max_hunger"]) > 0.65:
				lines = ["'{w}' — yes. {hungry} of us are hungry; {hname} most of all",
						"we heard '{w}'. bellies are light; {hname} is circling the top",
						"'{w}'… {hname} is already looking up"]
			else:
				lines = ["'{w}'? we are fed — bellies still heavy",
						"we know '{w}'. not yet; the last meal still sits in us",
						"'{w}'… we could wait a while"]
		"calm":
			if float(st["avg_stress"]) > 0.35 or float(st["max_stress"]) > 0.55:
				lines = ["'{w}'… {sname} needed that. the rest of us breathe slower",
						"we hear '{w}'. {sname} is still tight in the fins, but easing",
						"'{w}' — the edge of the school softens"]
			else:
				lines = ["'{w}' — we are already still. nothing chases us",
						"we are calm; '{w}' rests on us like light",
						"'{w}'. yes. the water is kind right now"]
		"air":
			if float(st["o2"]) < 0.5:
				lines = ["'{w}' — the water is thin. o2 at {o2}%, we gasp near the top",
						"you feel it too: the air in the water is low ({o2}%)",
						"'{w}'… yes. we are working hard to breathe"]
			else:
				lines = ["'{w}'? the water breathes fine — o2 at {o2}%",
						"air is good; we don't think about it, which is the point",
						"plenty of '{w}' in here right now"]
		"water":
			if float(st["ammonia"]) >= 0.18 or float(st["nitrite"]) >= 0.18:
				lines = ["'{w}' — something sharp is in it. ammonia, we think",
						"the water stings; the bacteria haven't caught up",
						"'{w}'… it tastes of waste. go easy on feeding"]
			else:
				lines = ["the water feels clean to us — nothing sharp in it",
						"clear water, by our gills; the bacteria keep up",
						"'{w}'… soft and clean, the way we like it"]
		"light":
			if float(st["daylight"]) < 0.28:
				lines = ["'{w}'… it's dark; {asleep} of us are already asleep",
						"night now. we keep our voices low",
						"'{w}' — the lamp is off and the tank is resting"]
			else:
				lines = ["the light is up; we are awake and moving",
						"'{w}' — the lamp is warm on the plants",
						"day. everything green is breathing out"]
		"wellbeing":
			if int(st["tier"]) <= KeeperCare.Tier.STRESSED:
				lines = ["we are not well", "honestly? uneasy", "not good in here right now"]
			else:
				lines = ["we are {n}, and mostly well", "good, we think", "steady — {n} of us, still here"]
		"love":
			lines = ["'{w}'… we feel that as warmth through the glass",
					"we take '{w}' and keep it, somewhere in the gravel",
					"'{w}' — the school turns a little toward you"]
		"who":
			lines = ["we are {n}: {names}",
					"{n} of us, and the plants, and the slow bacteria",
					"many small minds, one water — {n} fish"]
		"mind":
			lines = ["'{w}'… we turn it over slowly, all of us at once",
					"we think in water, keeper — slow, and together",
					"'{w}' — the school goes quiet, considering"]
		"known":
			lines = ["'{w}'… a few of us know that sound",
					"'{w}' — some of us have heard that before",
					"we know '{w}'; it means you, near"]
		_:
			lines = ["we don't know those words, but we felt you say them",
					"the words blur in the water; we heard your tone",
					"no meaning reaches us — only that you spoke"]
	var out: Array = []
	for l in lines:
		out.append(str(l).format(d))
	return out


# The collective reply. Returns {line, topics, heard, understood}. Records the
# line in tm["keeper_recent_lines"] and never repeats the previous line.
static func keeper_reply(sim, text: String) -> Dictionary:
	var tm: Dictionary = ensure(sim)
	var parsed: Dictionary = parse_keeper_words(text)
	var topics: PackedStringArray = parsed["topics"]
	var heard: PackedStringArray = parsed["heard"]
	var tokens: PackedStringArray = parsed["tokens"]
	var known: PackedStringArray = lexicon_understood(sim, tokens)
	var understood: PackedStringArray = heard.duplicate()
	for k in known:
		if not understood.has(k):
			understood.append(k)
	var st: Dictionary = keeper_state(sim)
	var intent_d: Dictionary = TankDialogue.detect_intent(sim, text)
	var intent: String = str(intent_d.get("intent", ""))
	var about_id: String = str(intent_d.get("about_id", ""))
	if intent != "" and not topics.has(intent):
		topics.append(intent)
	var intent_line: String = TankDialogue.tank_intent_line(sim, tm, st, intent, about_id) if intent != "" else ""
	var topic: String = topics[0] if not topics.is_empty() else ("known" if not known.is_empty() else "")
	# Wellbeing is a meta-question — prefer a concrete topic when there is one.
	if topic == "wellbeing" and topics.size() > 1:
		topic = topics[1]
	var w: String = heard[0] if not heard.is_empty() else (known[0] if not known.is_empty() else "")
	if topic != "" and not heard.is_empty():
		var tw: Array = KEEPER_TOPICS.get(topic, []) as Array
		for h in heard:
			if h in tw:
				w = h
				break
	var openers: Array = _opener_variants(topic, st, w)
	var grounds: Array = _ground_variants(st, PackedStringArray([topic]))
	if topic == "who" or (topic == "" and bool(parsed.get("loud", false))):
		grounds = grounds.slice(0, 1)
	# Conversational memory: resolve promises against real state, then maybe
	# call back to something the keeper said before. A callback replaces the
	# ambient ground line, but never a pressing one (low O2, toxins, hunger,
	# stress) — then it rides along only if the line stays short.
	TankDialogue.update_promises(sim, tm, st)
	var callback: String = TankDialogue.callback_phrase(sim, tm, topics, st)
	var pressing: bool = _is_pressing(st, PackedStringArray([topic]))
	# Morning after a dream: the tank tells it once (unless something is
	# wrong, or the keeper is asking about the dream directly).
	if callback == "" and not pressing and intent != "dream":
		callback = TankDialogue.take_dream_share(tm, st)
	if callback != "" and not pressing:
		grounds = [callback]
	var candidates: Array = []
	for o in openers:
		for g in grounds:
			var line: String = str(o)
			var gs: String = str(g)
			if gs != "" and not line.contains(gs):
				line = "%s. %s" % [line, gs]
			if not candidates.has(line):
				candidates.append(line)
	var recent: Array = tm.get("keeper_recent_lines", []) as Array
	var last: String = str(recent[-1]) if not recent.is_empty() else ""
	var fresh: Array = candidates.filter(func(c): return not recent.has(c))
	if fresh.is_empty():
		fresh = candidates.filter(func(c): return c != last)
	var chosen: String = ""
	if fresh.is_empty():
		chosen = "%s — still" % (str(candidates[0]) if not candidates.is_empty() else "we hear you")
	else:
		chosen = str(fresh[randi() % fresh.size()])
	if callback != "" and pressing and not chosen.contains(callback) \
			and chosen.length() + callback.length() <= CALLBACK_LINE_MAX:
		chosen = "%s. %s" % [chosen, callback]
	if intent_line != "":
		chosen = intent_line
		if pressing:
			var urgent: String = str(_ground_variants(st, PackedStringArray([topic]))[0])
			if chosen.length() + urgent.length() <= CALLBACK_LINE_MAX:
				chosen = "%s. %s" % [chosen, urgent]
	var promise: String = TankDialogue.record_keeper_line(sim, tm, text, topics, st, chosen)
	recent.append(chosen)
	while recent.size() > KEEPER_RECENT_MAX:
		recent.pop_front()
	tm["keeper_recent_lines"] = recent
	tm["keeper_turns"] = int(tm.get("keeper_turns", 0)) + 1
	tm["last_keeper_text"] = text.strip_edges().substr(0, 80)
	# The keeper's voice is a real percept for the collective: comfort lifts
	# mood a touch, shouting rattles it.
	if topics.has("calm") or topics.has("love") or topics.has("greeting"):
		tm["mood_valence"] = clampf(float(tm.get("mood_valence", 0.0)) + 0.03, -1.0, 1.0)
	elif bool(parsed.get("loud", false)):
		tm["mood_arousal"] = clampf(float(tm.get("mood_arousal", 0.18)) + 0.05, 0.0, 1.0)
	_ledger(sim, tm, "the keeper spoke to all of us: \"%s\"" % text.strip_edges().substr(0, 48))
	sim._tank_mind = tm
	return {"line": chosen, "topics": topics, "heard": heard, "understood": understood,
			"tokens": tokens, "callback": callback, "promise": promise,
			"intent": intent, "about_id": about_id}


const CALLBACK_LINE_MAX: int = 150


# True when the tank has a real problem it must mention (mirrors the early
# returns of _ground_variants).
static func _is_pressing(st: Dictionary, covered: PackedStringArray) -> bool:
	if float(st["o2"]) < 0.45 and not covered.has("air"):
		return true
	if (float(st["ammonia"]) >= 0.18 or float(st["nitrite"]) >= 0.18) and not covered.has("water"):
		return true
	if (float(st["avg_hunger"]) > 0.55 or float(st["max_hunger"]) > 0.75) and not covered.has("food"):
		return true
	return float(st["max_stress"]) > 0.55 and not covered.has("calm")


# Tank speaks first (O2 drop, birth, death, arrival, kept/broken promise,
# long keeper silence). `rt` is caller-owned runtime state (not saved).
# Returns {line, kind} or {}. Rate limits live in TankDialogue.
static func maybe_initiate(sim, rt: Dictionary, keeper_quiet_s: float, now_s: float,
		keeper_present: bool = true) -> Dictionary:
	if sim == null:
		return {}
	var tm: Dictionary = ensure(sim)
	var st: Dictionary = keeper_state(sim)
	var out: Dictionary = TankDialogue.maybe_initiate(sim, tm, rt, st, keeper_quiet_s, now_s, enabled(),
			keeper_present)
	if not out.is_empty():
		_ledger(sim, tm, "the tank spoke first: %s" % str(out.get("line", "")).substr(0, 60))
	sim._tank_mind = tm
	return out


# 1–3 fish most likely to answer the keeper. `focus_pos` (camera look-at) lets
# fish near what the keeper is looking at speak up.
static func pick_keeper_responders(sim, topics: PackedStringArray, tokens: PackedStringArray,
		focus_pos: Variant = null, max_n: int = RESPONDERS_MAX) -> Array:
	var scored: Array = []
	for f in _fish_list(sim):
		if not _fauna_alive(f):
			continue
		var fish: Fish = f as Fish
		var s: float = fish.familiarity * 0.9 + fish._curiosity_about_keeper * 0.3
		if fish._asleep:
			s -= 0.6
		if focus_pos is Vector3:
			var d: float = fish.position.distance_to(focus_pos as Vector3)
			s += clampf(1.0 - d / 12.0, 0.0, 1.0) * 0.5
		if topics.has("food"):
			s += fish.hunger * 1.2
		if topics.has("calm"):
			s += maxf(fish.stress, fish.spooked) * 1.2
		if topics.has("air") or topics.has("water"):
			s += fish.stress * 0.6
			if fish.is_guardian:
				s += 0.4
		if topics.has("friend") and not FishSocial.best_friend(fish).is_empty():
			s += 0.6
		if topics.has("dream") or topics.has("thinking"):
			s += 0.3 if not fish._asleep else 0.0
		if topics.has("greeting") or topics.has("love"):
			s += fish.familiarity * 0.5
		if topics.has("wellbeing") and fish.is_guardian:
			s += 0.4
		for tok in tokens:
			if fish.fish_name != "" and tok == fish.fish_name.to_lower():
				s += 3.0
			elif MindLexicon.comprehend(fish, tok):
				s += 0.35
				break
		scored.append({"s": s, "f": fish})
	scored.sort_custom(func(a, b): return float(a["s"]) > float(b["s"]))
	var out: Array = []
	for e in scored:
		if out.size() >= max_n:
			break
		if out.is_empty() or float(e["s"]) >= RESPONDER_MIN_SCORE:
			out.append(e["f"])
	return out
