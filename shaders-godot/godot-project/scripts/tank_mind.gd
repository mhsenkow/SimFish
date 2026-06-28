extends RefCounted

# SENTIENCE_THE_NIGHT_WATCH §A — tank-level collective workspace (slow macro mind).

const GlobalWorkspace = preload("res://scripts/global_workspace.gd")

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
	var dl: float = float(sim.daylight()) if sim.has_method("daylight") else 0.5
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
	var dl: float = 0.12
	if sim.has_method("daylight"):
		dl = float(sim.daylight())
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
	var dl: float = float(sim.daylight()) if sim != null and sim.has_method("daylight") else 0.5
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
		sim._tank_mind = (d as Dictionary).duplicate(true)


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
	if node == null or not (node is Fish):
		return false
	if not is_instance_valid(node):
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
