extends RefCounted

# SENTIENCE_THE_NIGHT_WATCH — remaining items (#8, #24–#98 batch helpers).
# Metaphor only (#80): slow-state flickers, never conscious gravel.

const TankMind = preload("res://scripts/tank_mind.gd")
const FishMind = preload("res://scripts/fish_mind.gd")
const EpisodicMemory = preload("res://scripts/episodic_memory.gd")
const MakeItThere = preload("res://scripts/make_it_there.gd")
const MindSelfModel = preload("res://scripts/mind_self_model.gd")


static func tick_all(sim, dt: float, room_idle_s: float) -> void:
	if sim == null:
		return
	_tick_threat_time_dilation(sim, dt)
	_tick_grief_night(sim, dt)
	_tick_slow_fauna(sim, dt)
	_tick_biofilter_night(sim, dt)
	_tick_substrate_night(sim, dt)
	_tick_season_night(sim, dt)
	_tick_watcher_sweep(sim, dt)
	_tick_collective_dream(sim)
	_tick_dawn_spark(sim, dt)
	_tick_2am_confession(sim, room_idle_s, dt)
	_tick_nightlight_ritual(sim, room_idle_s, dt)
	_tick_vigil_gift(sim, room_idle_s, dt)
	_tick_accessibility_pulse(sim, dt)
	_tick_wisdom(sim, dt)
	_tick_detrital_digestion(sim, dt)
	_push_tank_semantics(sim)


static func tick_sleep_extras(f: Fish, sim, dt: float, dl: float, phase: float) -> void:
	_tick_fry_night(f, dl)
	_tick_predator_hours(f, dl, phase)
	_tick_dawn_anticipation(f, sim, dl, phase, dt)
	_tick_patience(f, sim, dt, dl)
	_tick_dark_refuge(f, sim, dl, dt)
	_tick_lucid_flicker(f, sim, dt)
	_tick_nocturnal_forage(f, sim, dl)
	_apply_morning_insight(f, sim, dl)


static func quorum_wants_sleep(f: Fish, dl: float, sim) -> bool:
	if f.swim_pattern == "shuffle":
		return dl > 0.82
	if dl >= 0.14:
		if dl < 0.24 and f.swim_pattern in ["school", "shoal"]:
			var tm: Dictionary = TankMind.ensure(sim)
			var q: float = float(tm.get("asleep_fraction", 0.0))
			if q > 0.38:
				return randf() < clampf(q * 0.12, 0.02, 0.18)
		return false
	return true


static func simulate_long_absence(sim, gap_s: int, events: PackedStringArray) -> void:
	if sim == null or gap_s < 86400:
		return
	if sim.has_method("advance_tank_age_coarse"):
		sim.advance_tank_age_coarse(float(gap_s) * 0.35)
	var tm: Dictionary = TankMind.ensure(sim)
	tm["nights_tended"] = int(tm.get("nights_tended", 0)) + int(gap_s / 43200.0)
	if randf() < 0.55:
		events.append("plants grew while you were away")
	if randf() < 0.35:
		events.append("the population shifted in the quiet")
	sim._tank_mind = tm


static func try_guardian_dream_journal(sim, note: String) -> void:
	if sim == null or note.strip_edges() == "":
		return
	if not sim.has_method("_maybe_guardian_dream_journal"):
		return
	sim._maybe_guardian_dream_journal(note)


static func night_perception_scale(sim) -> float:
	var dl: float = float(sim.daylight()) if sim != null and sim.has_method("daylight") else 1.0
	return lerpf(0.42, 1.0, clampf(dl / 0.35, 0.0, 1.0))


static func night_stillness(sim) -> float:
	if sim == null:
		return 0.0
	return TankMind._night_f(sim, "night_stillness")


static func _tick_threat_time_dilation(sim, dt: float) -> void:
	var dl: float = float(sim.daylight()) if sim.has_method("daylight") else 1.0
	var still: float = TankMind._night_f(sim, "night_stillness")
	if dl > 0.32:
		TankMind._set_night_f(sim, "night_stillness", lerpf(still, 0.0, dt * 0.2))
		return
	var threat: float = 0.0
	if TankMind._float_prop(sim, "dissolved_o2", 1.0) < 0.5:
		threat += 0.5
	if TankMind._float_prop(sim, "stability", 1.0) < 0.45:
		threat += 0.45
	TankMind._set_night_f(sim, "night_stillness", lerpf(still, 1.0 - threat * 0.65, dt * 0.15))
	var tm: Dictionary = TankMind.ensure(sim)
	if threat > 0.35:
		tm["tick_accum"] = float(tm.get("tick_accum", 0.0)) + dt * 0.35


static func _tick_grief_night(sim, dt: float) -> void:
	var dl: float = float(sim.daylight()) if sim.has_method("daylight") else 1.0
	if dl > 0.32:
		return
	if sim.get("_mourning_events") is not Array or (sim._mourning_events as Array).is_empty():
		return
	var tm: Dictionary = TankMind.ensure(sim)
	tm["mood_valence"] = lerpf(float(tm.get("mood_valence", 0.0)), -0.25, dt * 0.04)
	tm["mood_arousal"] = lerpf(float(tm.get("mood_arousal", 0.18)), 0.12, dt * 0.03)
	tm["night_quality"] = clampf(float(tm.get("night_quality", 0.5)) - dt * 0.002, 0.0, 1.0)
	if randf() < dt * 0.008:
		TankMind.append_ledger_line(sim, tm, "a heavier quiet after loss")
	sim._tank_mind = tm


static func _tick_slow_fauna(sim, dt: float) -> void:
	var dl: float = float(sim.daylight()) if sim.has_method("daylight") else 1.0
	var active: float = 0.0
	if dl < 0.28:
		var snails: int = sim.get("snails").size() if sim.get("snails") is Array else 0
		var shrimp_n: int = sim.get("shrimp").size() if sim.get("shrimp") is Array else 0
		active = clampf(float(snails + shrimp_n) / 8.0, 0.0, 1.0)
	var slow: float = TankMind._night_f(sim, "slow_fauna_night")
	TankMind._set_night_f(sim, "slow_fauna_night", lerpf(slow, active, dt * 0.2))


static func _tick_biofilter_night(sim, dt: float) -> void:
	var dl: float = float(sim.daylight()) if sim.has_method("daylight") else 1.0
	if dl > 0.3 or sim.get("water_chemistry") == null:
		return
	var wc = sim.water_chemistry
	if wc.get("bacteria_colony") == null:
		return
	var calm: float = clampf(float(wc.bacteria_colony) * (1.0 - dl), 0.0, 1.0)
	var bfc: float = TankMind._night_f(sim, "biofilter_calm")
	TankMind._set_night_f(sim, "biofilter_calm", lerpf(bfc, calm, dt * 0.08))
	if calm > 0.45 and randf() < dt * 0.004:
		var tm: Dictionary = TankMind.ensure(sim)
		TankMind.append_ledger_line(sim, tm, "the filter hums in the dark")
		sim._tank_mind = tm


static func _tick_substrate_night(sim, dt: float) -> void:
	if sim.get("substrate") == null:
		return
	var sub = sim.substrate
	if not sub.has_method("tick_night_memory"):
		return
	sub.tick_night_memory(dt, sim)


static func _tick_season_night(sim, _dt: float) -> void:
	var month: int = Time.get_datetime_dict_from_system().get("month", 6)
	var winter: float = 1.0 if month in [12, 1, 2] else (0.5 if month in [3, 11] else 0.0)
	var summer: float = 1.0 if month in [6, 7, 8] else 0.0
	TankMind._set_night_f(sim, "season_night_bias", winter * 0.18 - summer * 0.08)


static func _tick_watcher_sweep(sim, dt: float) -> void:
	var dl: float = float(sim.daylight()) if sim.has_method("daylight") else 1.0
	if dl > 0.32:
		return
	var tm: Dictionary = TankMind.ensure(sim)
	var wid: String = str(tm.get("watcher_fish_id", ""))
	if wid == "":
		return
	var found: bool = false
	for f in TankMind._fish_list(sim):
		if not TankMind._fauna_alive(f) or str(f.id) != wid:
			continue
		found = true
		var sweep: float = TankMind._night_f(sim, "watcher_sweep_t") + dt
		TankMind._set_night_f(sim, "watcher_sweep_t", sweep)
		var ang: float = sweep * 0.22
		var r: float = 3.5
		f._interest_target = Vector3(cos(ang) * r, f.position.y, sin(ang) * r)
		f._interest_remaining = maxf(f._interest_remaining, 0.35)
		break
	if not found:
		var tm_clear: Dictionary = TankMind.ensure(sim)
		tm_clear["watcher_fish_id"] = ""
		sim._tank_mind = tm_clear


static func _tick_collective_dream(sim) -> void:
	var dl: float = float(sim.daylight()) if sim.has_method("daylight") else 1.0
	if dl > 0.28:
		return
	var dreamers: Array = []
	for f in TankMind._fish_list(sim):
		if TankMind._fauna_alive(f) and f._asleep and f._dreaming:
			dreamers.append(f)
	if dreamers.size() < 3:
		return
	var shared: String = ""
	for f in dreamers:
		if str(f._dream_wisp) != "":
			shared = str(f._dream_wisp)
			break
	if shared == "":
		shared = "the school dreamed the same water"
	for f in dreamers:
		if not TankMind._fauna_alive(f):
			continue
		if randf() < 0.35:
			f._dream_wisp = shared


static func _tick_dawn_spark(sim, _dt: float) -> void:
	if TankMind._night_f(sim, "dawn_spark_t") > 0.0:
		return
	var dl: float = float(sim.daylight()) if sim.has_method("daylight") else 0.5
	var phase: float = TankMind._float_prop(sim, "day_phase", 0.5)
	if dl > 0.22 and dl < 0.42 and phase > 0.02 and phase < 0.14:
		if sim.has_method("trigger_dawn_spark"):
			sim.trigger_dawn_spark(12.0)
		else:
			TankMind._set_night_f(sim, "dawn_spark_t", 12.0)
		var tm: Dictionary = TankMind.ensure(sim)
		TankMind.append_ledger_line(sim, tm, "first light — colour returns")
		sim._tank_mind = tm


static func _tick_2am_confession(sim, room_idle_s: float, dt: float) -> void:
	var dl: float = float(sim.daylight()) if sim.has_method("daylight") else 1.0
	if dl > 0.18 or room_idle_s < 180.0:
		return
	var cd: float = TankMind._night_f(sim, "confession_cd", 3600.0)
	if not sim.has_method("tick_confession_cooldown"):
		cd = maxf(0.0, cd - dt)
		TankMind._set_night_f(sim, "confession_cd", cd)
	if cd > 0.0:
		return
	if randf() >= dt * 0.00008:
		return
	if not sim.has_method("_find_guardian_fish") or not sim.has_method("_speak_guardian"):
		return
	var g: Fish = sim._find_guardian_fish()
	if not TankMind._fauna_alive(g):
		return
	TankMind._set_night_f(sim, "confession_cd", 7200.0)
	sim._speak_guardian(g, "quiet_inner", "just a pulse in the dark with a patterned name", {"night_confession": true})


static func _tick_nightlight_ritual(sim, room_idle_s: float, dt: float) -> void:
	if room_idle_s < 300.0:
		return
	var dl: float = float(sim.daylight()) if sim.has_method("daylight") else 1.0
	if dl > 0.25:
		return
	var tm: Dictionary = TankMind.ensure(sim)
	var sessions: int = int(tm.get("nightlight_sessions", 0))
	if sessions == 0 and room_idle_s > 360.0:
		tm["nightlight_sessions"] = 1
		TankMind.append_ledger_line(sim, tm, "the glass kept glowing overnight")
		sim._tank_mind = tm
	elif sessions > 0 and randf() < dt * 0.001:
		tm["nightlight_sessions"] = sessions + 1
		sim._tank_mind = tm


static func _tick_vigil_gift(sim, room_idle_s: float, dt: float) -> void:
	var dl: float = float(sim.daylight()) if sim.has_method("daylight") else 1.0
	if dl > 0.35 or room_idle_s > 120.0:
		return
	for f in TankMind._fish_list(sim):
		if not TankMind._fauna_alive(f):
			continue
		f.stress = maxf(0.0, f.stress - dt * 0.012)
		f.mood = clampf(f.mood + dt * 0.008, -1.0, 1.0)


static func _tick_accessibility_pulse(sim, _dt: float) -> void:
	var dl: float = float(sim.daylight()) if sim.has_method("daylight") else 1.0
	if dl > 0.35 and TankMind._night_f(sim, "dawn_spark_t") <= 0.0:
		return
	TankMind._set_night_f(sim, "night_a11y_pulse", sin(Time.get_ticks_msec() * 0.0012) * 0.5 + 0.5)


static func _tick_wisdom(sim, dt: float) -> void:
	var tm: Dictionary = TankMind.ensure(sim)
	var nights: int = int(tm.get("nights_tended", 0))
	if nights < 3:
		return
	var calm: float = clampf(float(nights) / 40.0, 0.0, 0.35)
	tm["mood_arousal"] = lerpf(float(tm.get("mood_arousal", 0.18)), 0.14, dt * calm * 0.02)
	sim._tank_mind = tm


static func _tick_detrital_digestion(sim, dt: float) -> void:
	var dl: float = float(sim.daylight()) if sim.has_method("daylight") else 1.0
	if dl > 0.32:
		return
	var waste_n: int = sim.get("waste").size() if sim.get("waste") is Array else 0
	if waste_n <= 0:
		return
	if randf() >= dt * 0.004:
		return
	var tm: Dictionary = TankMind.ensure(sim)
	TankMind.append_ledger_line(sim, tm, "the tank digests the day in the dark")
	sim._tank_mind = tm


static func _push_tank_semantics(sim) -> void:
	var tm: Dictionary = TankMind.ensure(sim)
	var facts: Array = tm.get("semantic_facts", [])
	for f in TankMind._fish_list(sim):
		if not TankMind._fauna_alive(f):
			continue
		for fact in f.semantic_memory:
			var s: String = str(fact)
			if s != "" and not facts.has(s) and facts.size() < 24:
				facts.append(s)
	tm["semantic_facts"] = facts
	sim._tank_mind = tm


static func _tick_fry_night(f: Fish, dl: float) -> void:
	if f.maturity != 0:
		return
	if dl < 0.28:
		f._sleep_depth = minf(float(f._sleep_depth), 0.32)


static func _tick_predator_hours(f: Fish, _dl: float, phase: float) -> void:
	var twilight: bool = (phase > 0.04 and phase < 0.14) or (phase > 0.86 and phase < 0.96)
	if not twilight:
		return
	if f.swim_pattern in ["dart", "shuffle"] or f._trait("boldness") > 0.65:
		f.arousal = clampf(f.arousal + 0.04, 0.0, 1.0)


static func _tick_dawn_anticipation(f: Fish, _sim, dl: float, phase: float, dt: float) -> void:
	if phase < 0.78 or phase > 0.98 or dl > 0.16:
		return
	if f._asleep and float(f._sleep_depth) > 0.25 and randf() < dt * 0.15:
		f._sleep_depth = maxf(0.0, float(f._sleep_depth) - dt * 0.08)
		f.sync_sleep_stage_from_depth()


static func _tick_patience(f: Fish, sim, dt: float, dl: float) -> void:
	if dl > 0.3 or f._asleep:
		return
	var tm: Dictionary = TankMind.ensure(sim)
	if str(tm.get("focus", "")) not in ["unwatched", "night_rest", "deep_dark", "cathedral"]:
		return
	if f.burst_remaining <= 0.0 and f._startle_remaining <= 0.0:
		f.velocity *= lerpf(1.0, 0.88, dt * 0.5)


static func _tick_dark_refuge(f: Fish, sim, dl: float, dt: float) -> void:
	if dl > 0.28 or f.swim_pattern == "shuffle":
		return
	var plants: int = 0
	if sim.has_method("query_plants_in_radius"):
		plants = sim.query_plants_in_radius(f.position, 5.0).size()
	if plants >= 2:
		f.stress = maxf(0.0, f.stress - dt * 0.018)


static func _tick_lucid_flicker(f: Fish, _sim, dt: float) -> void:
	if not f._asleep or not f._dreaming:
		return
	if randf() >= dt * 0.0015:
		return
	var sm: Dictionary = MindSelfModel.build(f, [])
	if float(sm.get("confidence", 0.0)) < 0.45:
		return
	FishMind.record_salient(f, "self", "this might be sleep", 0.38, f.position)


static func _tick_nocturnal_forage(f: Fish, sim, dl: float) -> void:
	if dl > 0.32 or f.swim_pattern != "shuffle" or f._asleep:
		return
	f.set_meta("_scent_forage", true)
	if f.hunger > 0.35 and sim != null:
		f.curiosity_drive = clampf(f.curiosity_drive + 0.02, 0.0, 1.0)


static func _apply_morning_insight(f: Fish, _sim, dl: float) -> void:
	if dl < 0.2:
		f.reset_morning_insight()
		return
	if dl < 0.4 or f.semantic_memory.is_empty():
		return
	if f.morning_insight_done():
		return
	for fact in f.semantic_memory:
		var s: String = str(fact)
		if s.contains("threat") or s.contains("startled"):
			f.vigilance = clampf(f.vigilance + 0.06, 0.0, 1.0)
		elif s.contains("food") or s.contains("fed"):
			f._interest_remaining = maxf(f._interest_remaining, 0.2)
	f.mark_morning_insight()
