extends RefCounted

# SENTIENCE_THE_NIGHT_WATCH — sleep architecture, dreams, away-life, night shift.

const TankMind = preload("res://scripts/tank_mind.gd")
const FishMind = preload("res://scripts/fish_mind.gd")
const FishMindScience = preload("res://scripts/fish_mind_science.gd")
const EpisodicMemory = preload("res://scripts/episodic_memory.gd")
const MakeItThere = preload("res://scripts/make_it_there.gd")
const NightWatchExtras = preload("res://scripts/night_watch_extras.gd")

enum SleepStage { AWAKE, NREM, REM, MICRO }


static func tick_sim(sim, dt: float, room_idle_s: float) -> void:
	if sim == null:
		return
	TankMind.tick(sim, dt, room_idle_s)
	NightWatchExtras.tick_all(sim, dt, room_idle_s)
	_tick_night_consolidation(sim, dt)
	_tick_collective_contagion(sim, dt)
	_apply_tank_mood_overlay(sim)
	_tick_guardian_vigil(sim, dt)


static func tick_sleep(f: Fish, sim, dt: float) -> void:
	if f == null or sim == null:
		return
	var dl: float = float(sim.daylight())
	var phase: float = TankMind._float_prop(sim, "day_phase", 0.5)
	var wants_sleep: bool = NightWatchExtras.quorum_wants_sleep(f, dl, sim)
	# Night disturbance (#19).
	if _keeper_disturbed_night(sim, dl):
		if f._asleep:
			f._rest_debt = clampf(f._rest_debt + dt * 0.08, 0.0, 1.0)
			f._asleep = false
			f._dreaming = false
			f._sleep_depth = 0.0
			f._sleep_stage = SleepStage.AWAKE
	if f.hunger > 0.6 or f._startle_remaining > 0.0 or f.partner != null \
			or f.brooding_remaining > 0.0:
		wants_sleep = false
	# Insomniac (#18).
	if f.stress > 0.72 or f.spooked > 0.45:
		wants_sleep = false
		f._rest_debt = clampf(f._rest_debt + dt * 0.015, 0.0, 1.0)
	if f.maturity == 0:
		wants_sleep = false
		_tick_microsleep(f, dt)
		f._asleep = false
		f._dreaming = false
		return
	if wants_sleep:
		_settle_nook(f, sim)
		_advance_sleep_stages(f, sim, dt, dl, phase)
	else:
		_wake_fish(f, dt, dl, phase)
	if f._asleep:
		_discharge_rest_debt(f, dt)
	else:
		_accumulate_rest_debt(f, dt, dl)
	_tick_dream_content(f, sim, dt)
	NightWatchExtras.tick_sleep_extras(f, sim, dt, dl, phase)
	_tick_sleep_cluster(f, sim, dt)
	_pick_night_watcher(sim)


static func dream_wisp(f: Fish) -> String:
	if not f._asleep or not f._dreaming:
		return ""
	return str(f.get("_dream_wisp") if f.get("_dream_wisp") != null else "")


static func startle_scale(f: Fish) -> float:
	if f == null or not f._asleep:
		return 1.0
	var depth: float = float(f.get("_sleep_depth") if f.get("_sleep_depth") != null else 0.0)
	return lerpf(1.0, 0.06, clampf(depth, 0.0, 1.0))


static func sleep_stage_name(f: Fish) -> String:
	var names: Array = ["awake", "nrem", "rem", "micro"]
	var st: int = int(f.get("_sleep_stage") if f.get("_sleep_stage") != null else 0)
	return str(names[clampi(st, 0, names.size() - 1)])


static func simulate_away_gap(sim, gap_s: int) -> PackedStringArray:
	if sim == null or gap_s < 60:
		return PackedStringArray()
	var tm: Dictionary = TankMind.ensure(sim)
	var events: PackedStringArray = PackedStringArray()
	var steps: int = clampi(int(gap_s / 1800.0), 1, 48)
	var step_s: float = float(gap_s) / float(steps)
	for _i in steps:
		if sim.has_method("daylight"):
			var advance: float = step_s / maxf(float(sim.day_length_s) if sim.get("day_length_s") != null else 600.0, 60.0)
			sim.day_phase = fmod(float(sim.day_phase) + advance, 1.0)
		TankMind.tick_coarse(sim, step_s, true)
		if randf() < 0.22:
			sim._away_dream_count = int(sim._away_dream_count if sim.get("_away_dream_count") != null else 0) + 1
		if TankMind._float_prop(sim, "stability", 1.0) > 0.55 and randf() < 0.08:
			events.append("kept its rhythm while you were gone")
		elif randf() < 0.06:
			events.append("weathered a quiet scare alone")
	if gap_s >= 86400:
		events.append("a full water-turn passed in the dark")
	elif gap_s >= 3600:
		events.append("the tank lived its own hours")
	NightWatchExtras.simulate_long_absence(sim, gap_s, events)
	tm["away_events"] = events.duplicate()
	sim._tank_mind = tm
	return events


static func away_summary_extra(sim, gap_s: int) -> Dictionary:
	var tm: Dictionary = TankMind.ensure(sim)
	var lines: PackedStringArray = TankMind.away_recap_lines(sim)
	var out: Dictionary = {
		"tank_focus": str(tm.get("focus", "")),
		"night_quality": snappedf(float(tm.get("night_quality", 0.5)), 0.01),
		"tank_self": str(tm.get("self_summary", "")),
		"nights_tended": int(tm.get("nights_tended", 0)),
	}
	if not lines.is_empty():
		out["tank_away_lines"] = lines
	if gap_s >= 3600 and float(tm.get("night_quality", 0.5)) > 0.55:
		out["managed_alone"] = true
	var dl: float = float(sim.daylight()) if sim.has_method("daylight") else 0.5
	var phase: float = TankMind._float_prop(sim, "day_phase", 0.5)
	if dl < 0.32 or (phase > 0.65 and phase < 0.88):
		out["returned_in_dark"] = true
	return out


static func _wants_sleep(f: Fish, dl: float) -> bool:
	if f.swim_pattern == "shuffle":
		return dl > 0.82
	return dl < 0.14


static func _keeper_disturbed_night(sim, dl: float) -> bool:
	if dl > 0.35:
		return false
	return sim.night_is_disturbed() if sim != null and sim.has_method("night_is_disturbed") else false


static func note_night_disturbance(sim) -> void:
	if sim != null and sim.has_method("note_night_disturbance"):
		sim.note_night_disturbance()


static func _settle_nook(f: Fish, sim) -> void:
	if f._sleep_have_nook:
		return
	f._sleep_nook = f.position
	f._sleep_have_nook = true
	if sim.has_method("log_story_event") and randf() < 0.04:
		var nm: String = f.fish_name if f.fish_name != "" else "someone"
		sim.log_story_event("%s tucked into a nook for the night." % nm, true)


static func _advance_sleep_stages(f: Fish, sim, dt: float, dl: float, phase: float) -> void:
	f._asleep = true
	var depth_target: float = 0.85 if dl < 0.1 else 0.55
	if f.stress > 0.45:
		depth_target *= 0.6
	f._sleep_depth = lerpf(float(f.get("_sleep_depth") if f.get("_sleep_depth") != null else 0.0),
			depth_target, clampf(dt * 0.35, 0.0, 1.0))
	var depth: float = float(f._sleep_depth)
	if depth > 0.72:
		f._sleep_stage = SleepStage.NREM
	elif depth > 0.4:
		f._sleep_stage = SleepStage.REM if randf() < 0.35 else SleepStage.NREM
	else:
		f._sleep_stage = SleepStage.MICRO
	# REM / dream gate (#11, #21).
	var dream_chance: float = 0.012 if f._sleep_stage == SleepStage.REM else 0.004
	if f._sleep_stage == SleepStage.NREM and depth > 0.8 and randf() < 0.008:
		_run_sleep_spindle(f, sim)
	f._dreaming = randf() < dream_chance * (1.0 + depth)
	if not f._dreaming:
		f._dream_note_logged = false
	elif not f._dream_note_logged:
		f._dream_note_logged = true
		_log_dream_episode(f, sim)
	# Gradual dawn wake (#20).
	if phase > 0.02 and phase < 0.12 and dl > 0.18:
		if depth < 0.45 or randf() < dt * 0.4:
			f._asleep = false
			f._dreaming = false
			f._sleep_depth = 0.0
			f._dream_wisp = ""
			f._sleep_stage = SleepStage.AWAKE


static func _wake_fish(f: Fish, dt: float, _dl: float, _phase: float) -> void:
	if f._asleep and f._dreaming:
		f._dream_wisp = ""
		if f.mood > -0.2:
			f.mood = clampf(f.mood + 0.03, -1.0, 1.0)
	f._asleep = false
	f._dreaming = false
	f._sleep_depth = maxf(0.0, float(f.get("_sleep_depth") if f.get("_sleep_depth") != null else 0.0) - dt * 0.25)
	f._sleep_stage = SleepStage.AWAKE if f._sleep_depth < 0.08 else SleepStage.MICRO
	f._sleep_have_nook = false


static func _tick_microsleep(f: Fish, dt: float) -> void:
	if f.stress < 0.4 and randf() < dt * 0.02:
		f._sleep_stage = SleepStage.MICRO
		f._sleep_depth = 0.15


static func _discharge_rest_debt(f: Fish, dt: float) -> void:
	var rate: float = 0.018
	if int(f.get("_sleep_stage") if f.get("_sleep_stage") != null else 0) == SleepStage.NREM:
		rate = 0.035
	f._rest_debt = maxf(0.0, f._rest_debt - dt * rate)


static func _accumulate_rest_debt(f: Fish, dt: float, dl: float) -> void:
	if dl < 0.25:
		f._rest_debt = clampf(f._rest_debt + dt * 0.025, 0.0, 1.0)


static func _run_sleep_spindle(f: Fish, sim) -> void:
	f._sleep_twitch_t = 0.08
	EpisodicMemory.consolidate_sleep(f)
	if sim != null and sim.has_method("note_away_dream"):
		pass


static func _log_dream_episode(f: Fish, sim) -> void:
	var note: String = _dream_line(f)
	f._dream_wisp = note
	FishMind.record_salient(f, "dream", note, 0.42, f.position)
	EpisodicMemory.encode_episode(f, "dream", note, 0.38, f.position)
	if sim != null and sim.has_method("note_away_dream"):
		sim.note_away_dream()
	NightWatchExtras.try_guardian_dream_journal(sim, note)
	# Nightmare (#23).
	if f.stress > 0.55 or f._mate_grief > 0.4:
		f._sleep_twitch_t = 0.22
		f.spooked = clampf(f.spooked + 0.12, 0.0, 1.0)
		f._dream_wisp = "a scare replayed in sleep"


static func _dream_line(f: Fish) -> String:
	if f.hunger > 0.55:
		return "flakes drifting in half-sleep"
	if f._mate_grief > 0.35:
		return "someone missing in the dark water"
	for e in f.salient_memories:
		var k: String = String(e.get("kind", ""))
		var t: String = String(e.get("text", ""))
		if k == "keeper" or k == "keeper_word":
			return "your sound in sleep"
		if k == "fed" or k == "food":
			return "the bright drop again"
		if t != "":
			return t.substr(0, mini(t.length(), 40))
	return "something half-remembered in sleep"


static func _tick_dream_content(f: Fish, sim, dt: float) -> void:
	if not f._asleep:
		return
	FishMindScience.tick_sleep_replay(f)
	if f._dreaming and randf() < dt * 0.06:
		FishMindScience.reconsolidate_memory(f, "startled", f.stress < 0.35)
	# Nocturnal cognition (#31).
	if f.swim_pattern == "shuffle" and sim != null:
		var dl: float = float(sim.daylight())
		if dl < 0.35 and not f._asleep:
			f.curiosity_drive = clampf(f.curiosity_drive + dt * 0.02, 0.0, 1.0)


static func _tick_sleep_cluster(f: Fish, sim, dt: float) -> void:
	if not f._asleep or f.swim_pattern not in ["school", "shoal"]:
		return
	var dl: float = float(sim.daylight()) if sim != null and sim.has_method("daylight") else 1.0
	if dl > 0.28:
		return
	var center: Vector3 = Vector3.ZERO
	var n: int = 0
	for nf in TankMind._fish_list(sim):
		if not TankMind._fauna_alive(nf) or nf == f or not nf._asleep:
			continue
		if nf.position.distance_squared_to(f.position) > 25.0:
			continue
		center += nf.position
		n += 1
	if n <= 0:
		return
	center /= float(n)
	f._sleep_nook = f._sleep_nook.lerp(center, clampf(dt * 0.12, 0.0, 1.0))


static func _pick_night_watcher(sim) -> void:
	if sim == null:
		return
	var dl: float = float(sim.daylight()) if sim.has_method("daylight") else 0.5
	if dl > 0.3:
		return
	var tm: Dictionary = TankMind.ensure(sim)
	var best: Fish = null
	var best_s: float = -1.0
	for f in TankMind._fish_list(sim):
		if not TankMind._fauna_alive(f):
			continue
		f._night_watcher = false
		if f._asleep and float(f.get("_sleep_depth") if f.get("_sleep_depth") != null else 0.0) > 0.5:
			continue
		var s: float = (1.0 - f._trait("boldness")) * 0.4 + f.familiarity * 0.3
		if f.is_guardian:
			s += 0.35
		if f.swim_pattern == "shuffle":
			s += 0.25
		if s > best_s:
			best_s = s
			best = f
	if best != null and TankMind._fauna_alive(best):
		tm["watcher_fish_id"] = str(best.id)
		best._night_watcher = true
	else:
		tm["watcher_fish_id"] = ""
	sim._tank_mind = tm


static func _tick_night_consolidation(sim, dt: float) -> void:
	var dl: float = float(sim.daylight()) if sim.has_method("daylight") else 0.5
	if dl > 0.32:
		return
	for f in TankMind._fish_list(sim):
		if not TankMind._fauna_alive(f):
			continue
		if f._asleep and float(f.get("_sleep_depth") if f.get("_sleep_depth") != null else 0.0) > 0.65:
			if randf() < dt * 0.015:
				EpisodicMemory.consolidate_sleep(f)
				EpisodicMemory.tick_decay(f, dt * 2.5)


static func _tick_collective_contagion(sim, dt: float) -> void:
	var dl: float = float(sim.daylight()) if sim.has_method("daylight") else 0.5
	if dl > 0.35:
		return
	var tm: Dictionary = TankMind.ensure(sim)
	var fish_arr: Array = TankMind._fish_list(sim)
	if fish_arr.is_empty():
		return
	var mean_ar: float = float(tm.get("collective_arousal", 0.2))
	for f in fish_arr:
		if not TankMind._fauna_alive(f):
			continue
		if f._asleep:
			if mean_ar > 0.5 and float(f.get("_sleep_depth") if f.get("_sleep_depth") != null else 0.0) < 0.7:
				f.arousal = clampf(f.arousal + mean_ar * dt * 0.05, 0.0, 1.0)
		else:
			FishMind.apply_arousal_contagion(f, mean_ar, dt)


const VoxelMatRes = preload("res://scripts/voxel_mat.gd")

static func _apply_tank_mood_overlay(sim) -> void:
	var overlay: Dictionary = TankMind.mood_overlay(sim)
	var mc: Node = sim.get_tree().get_first_node_in_group("music_context") if sim.get_tree() else null
	if mc != null and mc.has_method("set_tank_mood_overlay"):
		mc.set_tank_mood_overlay(overlay)
	elif dl_safe(sim) < 0.38:
		VoxelMatRes.apply_music_sync_overlay(overlay, 0.1)


static func _tick_guardian_vigil(sim, _dt: float) -> void:
	if not sim.has_method("_find_guardian_fish"):
		return
	var g: Fish = sim._find_guardian_fish()
	if not TankMind._fauna_alive(g):
		return
	var dl: float = float(sim.daylight()) if sim.has_method("daylight") else 0.5
	if dl > 0.35:
		return
	if g._asleep and g.is_guardian:
		g._asleep = false
		g._sleep_depth = 0.12


static func dl_safe(sim) -> float:
	return float(sim.daylight()) if sim.has_method("daylight") else 0.5
