extends RefCounted

# MAKE_IT_THERE_IDEAS — threshold moments, presence/absence, sculpted soul.
# Session-scoped rarity; body before voice; embedded-AI prompts stay grounded.

const FishMind = preload("res://scripts/fish_mind.gd")
const FishJournal = preload("res://scripts/fish_journal.gd")
const GuardianMind = preload("res://scripts/guardian_mind.gd")

const LOOK_BACK_GLANCE_MIN: float = 0.62
const LOOK_BACK_GAZE_S: float = 1.85
const DOUBLE_TAKE_GLANCE_MIN: float = 0.38
const MOOD_WEATHER_AMP: float = 0.07
const QUIET_HOUR_BAND: float = 0.04  # dawn + deep-night window width (day_phase)
const SERENITY_STABILITY: float = 0.86
const RECOVERY_LOW: float = 0.38
const RECOVERY_HIGH: float = 0.78


static func fresh_session() -> Dictionary:
	return {
		"look_back_used": false,
		"look_back_roll": 0.0,
		"look_back_variant": 0,
		"double_take_player_used": false,
		"arrival_hitch_used": false,
		"hello_motion_used": false,
		"awe_moment_used": false,
	}


static func ensure_spark(arc: Dictionary) -> Dictionary:
	if not arc.has("spark") or not (arc["spark"] is Dictionary):
		arc["spark"] = _default_spark()
	var sp: Dictionary = arc["spark"]
	for k in _default_spark().keys():
		if not sp.has(k):
			sp[k] = _default_spark()[k]
	return sp


static func _default_spark() -> Dictionary:
	return {
		"flags": PackedStringArray(),
		"watch_today_s": 0.0,
		"watch_yesterday_s": 0.0,
		"last_watch_day": -1,
		"recovery_low": 1.0,
		"recovery_peak_pending": false,
		"serenity_announced": false,
		"parenting_tone": "patient",
		"grief_care_day": -1,
		"last_loss_day": -1,
		"unrepeatable": PackedStringArray(),
	}


static func spark_has(arc: Dictionary, flag: String) -> bool:
	var sp: Dictionary = ensure_spark(arc)
	var flags: Variant = sp.get("flags", PackedStringArray())
	return flags is PackedStringArray and (flags as PackedStringArray).has(flag)


static func spark_mark(arc: Dictionary, flag: String) -> void:
	var sp: Dictionary = ensure_spark(arc)
	var flags: PackedStringArray = sp.get("flags", PackedStringArray())
	if not flags.has(flag):
		flags.append(flag)
	sp["flags"] = flags


# ---- Session threshold beats (A) ----

static func mood_weather_offset(sim_day: int) -> float:
	var h: int = (sim_day * 17 + 913) & 0x7fffffff
	return (float(h % 1000) / 1000.0 - 0.5) * 2.0 * MOOD_WEATHER_AMP


static func apply_mood_weather(f: Fish, sim_day: int, dt: float) -> void:
	if f == null:
		return
	var off: float = mood_weather_offset(sim_day)
	f.mood = clampf(f.mood + off * dt * 0.08, -1.0, 1.0)


static func try_look_back_at_player(f: Fish, glance_strength: float,
		session: Dictionary, dt: float) -> bool:
	if session.get("look_back_used", false):
		return false
	if glance_strength < LOOK_BACK_GLANCE_MIN:
		return false
	if f.stress > 0.5 or f.burst_remaining > 0.0 or f._startle_remaining > 0.0:
		return false
	if f.speed > 1.1:
		return false
	var roll: float = float(session.get("look_back_roll", 0.0))
	roll += dt * glance_strength * (0.008 + f.familiarity * 0.012)
	session["look_back_roll"] = roll
	if roll < 1.0:
		return false
	session["look_back_used"] = true
	session["look_back_variant"] = randi() % 3
	return true


static func apply_look_back_gaze(f: Fish, glance_point: Vector3, session: Dictionary) -> void:
	if glance_point.length_squared() < 0.01:
		return
	var to_p: Vector3 = glance_point - f.position
	to_p.y *= 0.25
	if to_p.length_squared() < 0.04:
		return
	var fwd: Vector3 = Vector3(-sin(f._last_yaw), 0.0, -cos(f._last_yaw))
	var right: Vector3 = Vector3(cos(f._last_yaw), 0.0, -sin(f._last_yaw))
	var local_x: float = to_p.dot(right)
	var local_z: float = to_p.dot(fwd)
	if absf(local_z) < 0.001:
		return
	var variant: int = int(session.get("look_back_variant", 0))
	var hold: float = LOOK_BACK_GAZE_S + float(variant) * 0.35
	f._gaze_yaw = clampf(atan2(local_x, local_z) * 0.42, -0.42, 0.42)
	f._gaze_remaining = maxf(f._gaze_remaining, hold)
	f._novelty_pause_remaining = maxf(f._novelty_pause_remaining, hold * 0.55)
	f.target_velocity *= 0.15
	f.mood = clampf(f.mood + 0.06, -1.0, 1.0)
	if f.has_method("pulse_affect_cue"):
		f.pulse_affect_cue()


static func try_player_double_take(f: Fish, glance_strength: float,
		session: Dictionary) -> bool:
	if session.get("double_take_player_used", false):
		return false
	if glance_strength < DOUBLE_TAKE_GLANCE_MIN:
		return false
	if f._double_take_remaining > 0.0:
		return false
	if randf() > 0.35 + f.familiarity * 0.25:
		return false
	session["double_take_player_used"] = true
	f._double_take_remaining = randf_range(0.45, 0.85)
	return true


static func tick_feed_disappointment(_sim: Node, anticipated: bool, fed_recently: bool,
		session: Dictionary, dt: float) -> bool:
	if not anticipated or fed_recently:
		session["feed_wait"] = 0.0
		return false
	var w: float = float(session.get("feed_wait", 0.0)) + dt
	session["feed_wait"] = w
	return w > 45.0 and not session.get("feed_disappointed", false)


# ---- Body imperfection (B.16–18) ----

static func tick_fish_body(f: Fish, sim: Node, dt: float) -> void:
	if f == null or f._dying or f._startle_remaining > 0.2:
		return
	_tick_involuntary_tic(f, dt)
	_tick_misperception(f, sim, dt)
	_apply_seam_wobble(f, dt)
	_tick_breaking_beauty(f, dt)
	_tick_last_good_day(f, sim, dt)
	_tick_shy_leads(f, sim, dt)
	_tick_founder_echo(f)


static func _tick_involuntary_tic(f: Fish, dt: float) -> void:
	if f._gaze_remaining > 0.05 or f.burst_remaining > 0.0:
		return
	if randf() > dt * 0.035:
		return
	f._gaze_yaw += randf_range(-0.12, 0.12)
	f._gaze_remaining = maxf(f._gaze_remaining, 0.08)
	f.target_velocity += Vector3(randf_range(-0.04, 0.04), 0.0, randf_range(-0.04, 0.04))


static func _tick_misperception(f: Fish, sim: Node, dt: float) -> void:
	if f.hunger < 0.35 or f._novelty_pause_remaining > 0.0:
		return
	if randf() > dt * 0.012:
		return
	var plants: Array = sim.plants if sim != null and sim.get("plants") != null else []
	if plants.is_empty():
		return
	var nearest: Node = null
	var best_d2: float = 9.0
	for p in plants:
		if not is_instance_valid(p):
			continue
		var d2: float = f.position.distance_squared_to(p.global_position)
		if d2 < best_d2:
			best_d2 = d2
			nearest = p
	if nearest == null:
		return
	f._interest_target = nearest.global_position
	f._interest_remaining = randf_range(0.35, 0.7)
	f._novelty_pause_remaining = 0.25
	f.mood = clampf(f.mood - 0.04, -1.0, 1.0)


static func _apply_seam_wobble(f: Fish, dt: float) -> void:
	if f.speed < 0.15 or f.burst_remaining > 0.0:
		return
	if randf() > dt * 0.08:
		return
	f._last_yaw += randf_range(-0.06, 0.06)


static func _tick_breaking_beauty(f: Fish, dt: float) -> void:
	if f.maturity != f.MATURITY_SENESCENT:
		return
	if bool(f.bio.get("luminous_farewell", false)):
		f.mood = clampf(f.mood + dt * 0.02, -1.0, 1.0)
		return
	# Wabi-sabi: aged fish carry quiet grace, not just fade.
	if f._aged_applied and randf() < dt * 0.02:
		f.mood = clampf(f.mood + 0.03, -1.0, 1.0)


static func _tick_last_good_day(f: Fish, sim: Node, _dt: float) -> void:
	if f.maturity != f.MATURITY_SENESCENT or f._dying:
		return
	var threshold: float = f.max_age_s * (1.12 + f._life_jitter)
	if f.age < threshold:
		return
	if bool(f.bio.get("luminous_farewell", false)):
		return
	f.bio["luminous_farewell"] = true
	f.mood = clampf(f.mood + 0.35, -1.0, 1.0)
	if f.has_method("pulse_affect_cue"):
		f.pulse_affect_cue()
	if sim != null and sim.has_method("note_luminous_farewell"):
		sim.note_luminous_farewell(f)


static func _tick_shy_leads(f: Fish, sim: Node, dt: float) -> void:
	if f._trait("boldness") > 0.42 or f._interest_remaining > 0.0:
		return
	if randf() > dt * 0.004:
		return
	for n in sim.fish if sim != null and sim.get("fish") != null else []:
		if not (n is Fish) or n == f:
			continue
		var nf: Fish = n
		if nf._trait("boldness") < 0.55 or nf._interest_remaining <= 0.0:
			continue
		f._interest_target = nf._interest_target
		f._interest_remaining = randf_range(0.4, 0.9)
		break


static func _tick_founder_echo(f: Fish) -> void:
	if f.generation <= 0 or f.quirks.is_empty():
		return
	if f.quirks.has("circles the left glass") and is_finite(f.home_x):
		f.home_x = lerpf(f.home_x, -2.0, 0.002)


# ---- Sim tick (presence, sacred time, arc) ----

static func tick_sim(sim: Node, arc: Dictionary, session: Dictionary, dt: float) -> void:
	if sim == null:
		return
	var sp: Dictionary = ensure_spark(arc)
	_tick_watch_memory(sim, arc, sp, dt)
	_tick_quiet_hour(sim, arc, sp, dt)
	_tick_recovery_arc(sim, arc, sp)
	_tick_serenity(sim, arc, sp)
	_tick_presence_calm(sim, dt)
	_tick_guardian_kindness(sim, arc, dt)
	_tick_ordinary_journal(sim, arc, dt)
	_try_unrepeatable_moment(sim, arc, sp, session)
	_try_spark_lines(sim, arc, sp)


static func _tick_watch_memory(sim: Node, arc: Dictionary, sp: Dictionary, dt: float) -> void:
	if not sim.has_method("get_player_glance"):
		return
	var g: Dictionary = sim.get_player_glance()
	if float(g.get("strength", 0.0)) < 0.5:
		return
	var day: int = int(sim.sim_day()) if sim.has_method("sim_day") else 0
	if int(sp.get("last_watch_day", -1)) != day:
		sp["watch_yesterday_s"] = float(sp.get("watch_today_s", 0.0))
		sp["watch_today_s"] = 0.0
		sp["last_watch_day"] = day
	sp["watch_today_s"] = float(sp.get("watch_today_s", 0.0)) + dt
	var yesterday: float = float(sp.get("watch_yesterday_s", 0.0))
	if yesterday > 180.0 and not spark_has(arc, "watch_remembered"):
		spark_mark(arc, "watch_remembered")
		var gf: Fish = sim._find_guardian_fish() if sim.has_method("_find_guardian_fish") else null
		if gf != null and sim.has_method("_speak_guardian"):
			sim._speak_guardian(gf, "watch_remembered", "")


static func _tick_quiet_hour(sim: Node, arc: Dictionary, sp: Dictionary, dt: float) -> void:
	if not sim.has_method("daylight"):
		return
	var phase: float = float(sim.day_phase) if sim.get("day_phase") != null else 0.5
	var dl: float = float(sim.daylight())
	var dawn: bool = phase < QUIET_HOUR_BAND or phase > 1.0 - QUIET_HOUR_BAND
	var deep_night: bool = phase > 0.72 and phase < 0.82
	var vespers: bool = dawn or deep_night
	sim.set("_spark_vespers", vespers)
	sim.set("_spark_night_cathedral", deep_night and dl < 0.22)
	var mc: Node = sim.get_tree().get_first_node_in_group("music_context") if sim.get_tree() else null
	if mc != null and mc.has_method("set_spark_overlay"):
		var liturgy: String = "elegy" if spark_has(arc, "recent_loss") else ""
		if vespers:
			liturgy = "vespers"
		elif float(sim.stability) > SERENITY_STABILITY and not bool(sp.get("serenity_announced", false)):
			liturgy = "hymn"
		mc.set_spark_overlay(0.75 if vespers else 0.0, liturgy)
	if vespers and sim.has_method("_ambient_audio"):
		var amb: Node = sim._ambient_audio()
		if amb != null and randf() < dt * 0.015 and amb.has_method("play_bubble_sfx"):
			amb.play_bubble_sfx(0.18, randf_range(-0.4, 0.4))


static func _tick_recovery_arc(sim: Node, arc: Dictionary, sp: Dictionary) -> void:
	var stab: float = float(sim.stability) if sim.get("stability") != null else 1.0
	var low: float = float(sp.get("recovery_low", 1.0))
	if stab < RECOVERY_LOW:
		sp["recovery_low"] = minf(low, stab)
	elif stab > RECOVERY_HIGH and low < RECOVERY_LOW:
		if not bool(sp.get("recovery_peak_pending", false)):
			sp["recovery_peak_pending"] = true
			spark_mark(arc, "survived_crash")
	elif bool(sp.get("recovery_peak_pending", false)) and stab > SERENITY_STABILITY:
		sp["recovery_peak_pending"] = false
		sp["recovery_low"] = 1.0
		var g: Fish = sim._find_guardian_fish() if sim.has_method("_find_guardian_fish") else null
		if g != null and sim.has_method("_speak_guardian"):
			sim._speak_guardian(g, "recovery", "")
		if sim.has_method("log_story_event"):
			sim.log_story_event("The tank steadied itself — relief you can feel.", true)


static func _tick_serenity(sim: Node, arc: Dictionary, sp: Dictionary) -> void:
	if bool(sp.get("serenity_announced", false)):
		return
	var stab: float = float(sim.stability) if sim.get("stability") != null else 0.0
	if stab < SERENITY_STABILITY:
		return
	if sim.get("dissolved_o2") != null and float(sim.dissolved_o2) < 0.55:
		return
	sp["serenity_announced"] = true
	spark_mark(arc, "serenity")
	var g: Fish = sim._find_guardian_fish() if sim.has_method("_find_guardian_fish") else null
	if g != null and sim.has_method("_speak_guardian"):
		sim._speak_guardian(g, "serenity", "")
	if sim.has_method("log_story_event"):
		sim.log_story_event("A calm, breathing stillness — no score, just peace.", true)


static func _tick_presence_calm(sim: Node, dt: float) -> void:
	if not sim.has_method("get_player_glance"):
		return
	var gs: float = float(sim.get_player_glance().get("strength", 0.0))
	var calm: float = clampf(float(sim.get("_spark_calm") if sim.get("_spark_calm") != null else 0.0), 0.0, 1.0)
	var target: float = 0.85 if gs > 0.62 else 0.0
	sim.set("_spark_calm", lerpf(calm, target, clampf(dt * 0.4, 0.0, 1.0)))


static func _tick_guardian_kindness(sim: Node, _arc: Dictionary, dt: float) -> void:
	var g: Fish = sim._find_guardian_fish() if sim.has_method("_find_guardian_fish") else null
	if g == null or not g.is_guardian:
		return
	var sick: Fish = null
	var worst: float = 0.0
	for f in sim.fish if sim.get("fish") != null else []:
		if not is_instance_valid(f) or f == g or f._dying:
			continue
		var need: float = float(f.stress) * 0.5 + float(f.hunger) * 0.35
		if need > worst and need > 0.55:
			worst = need
			sick = f
	if sick == null:
		return
	if randf() > dt * 0.08:
		return
	g._interest_target = sick.position
	g._interest_remaining = maxf(g._interest_remaining, 0.6)


static func _tick_ordinary_journal(sim: Node, _arc: Dictionary, dt: float) -> void:
	if randf() > dt * 0.002:
		return
	if not sim.has_method("append_fish_journal_entry"):
		return
	for f in sim.fish if sim.get("fish") != null else []:
		if not is_instance_valid(f) or f.fish_name == "":
			continue
		if f.speed > 0.35:
			continue
		var lines: PackedStringArray = PackedStringArray([
			"resting in the quiet light.",
			"unfurling slowly — no hurry.",
			"just living, which is enough.",
		])
		var h: int = hash(String(f.id)) & 0x7fffffff
		sim.append_fish_journal_entry(f, lines[h % lines.size()], PackedStringArray(["ordinary"]))
		break


static func _try_unrepeatable_moment(sim: Node, _arc: Dictionary, sp: Dictionary,
		session: Dictionary) -> void:
	if session.get("awe_moment_used", false):
		return
	if float(sim.get("_player_glance_strength") if sim.get("_player_glance_strength") != null else 0.0) < 0.35:
		return
	if sim.get("fish") == null or (sim.fish as Array).size() < 4:
		return
	if randf() > 0.0008:
		return
	session["awe_moment_used"] = true
	var key: String = "formation_%d" % int(sim.sim_day()) if sim.has_method("sim_day") else "formation"
	var ur: PackedStringArray = sp.get("unrepeatable", PackedStringArray())
	if not ur.has(key):
		ur.append(key)
	sp["unrepeatable"] = ur
	sim.set("_sync_turn_remaining", 2.2)
	sim.set("_sync_polarization", 0.92)
	if sim.has_method("log_story_event"):
		sim.log_story_event("The school turned like weather — once, never quite the same.", true)


static func _try_spark_lines(sim: Node, arc: Dictionary, _sp: Dictionary) -> void:
	var g: Fish = sim._find_guardian_fish() if sim.has_method("_find_guardian_fish") else null
	if g == null or not sim.has_method("_speak_guardian"):
		return
	var mind: Dictionary = GuardianMind.ensure_mind(arc)
	var visits: int = int(mind.get("visit_count", 0))
	var trust: float = float(mind.get("care_trust", 0.0))
	if visits >= 50 and trust > 0.8 and not spark_has(arc, "become_more"):
		spark_mark(arc, "become_more")
		sim._speak_guardian(g, "become_more", "")
	if visits >= 80 and not spark_has(arc, "build_permission"):
		spark_mark(arc, "build_permission")
		sim._speak_guardian(g, "build_permission", "")
	if visits >= 100 and not spark_has(arc, "maker_note"):
		spark_mark(arc, "maker_note")
		sim._speak_guardian(g, "maker_note", "")
	var stab: float = float(sim.stability) if sim.get("stability") != null else 0.0
	if stab > SERENITY_STABILITY and randf() < 0.0005:
		if sim.has_method("append_fish_journal_entry"):
			for ff in sim.fish if sim.get("fish") != null else []:
				if is_instance_valid(ff) and ff.fish_name != "":
					sim.append_fish_journal_entry(ff, light_journal_line(),
							PackedStringArray(["play"]))
					break


static func apply_guardian_hello(g: Fish, _arc: Dictionary, session: Dictionary,
		visits: int) -> void:
	if visits < 15 or session.get("hello_motion_used", false):
		return
	session["hello_motion_used"] = true
	g._reaction_remaining = maxf(g._reaction_remaining, 0.9)
	g.target_velocity.y += 0.45
	g._interest_remaining = 1.1


static func apply_burn_bright_blessing(f: Fish, sim: Node) -> void:
	if f == null:
		return
	if f.bio is Dictionary:
		f.bio["blessed_release"] = true
	if f.has_method("pulse_affect_cue"):
		f.pulse_affect_cue()
	if sim != null and sim.has_method("append_fish_journal_entry"):
		var nm: String = f.fish_name if f.fish_name != "" else "Someone"
		sim.append_fish_journal_entry(f, "%s — go burn bright. This is yours." % nm,
				PackedStringArray(["blessing"]))


static func record_parenting(arc: Dictionary, tone: String) -> void:
	var sp: Dictionary = ensure_spark(arc)
	if tone != "":
		sp["parenting_tone"] = tone
	var mind: Dictionary = GuardianMind.ensure_mind(arc)
	match tone:
		"firm":
			mind["personality_drift"] = "steadfast"
		"gentle":
			mind["personality_drift"] = "tender"
		_:
			mind["personality_drift"] = "curious"


static func note_loss(sim: Node, arc: Dictionary) -> void:
	var sp: Dictionary = ensure_spark(arc)
	sp["last_loss_day"] = int(sim.sim_day()) if sim.has_method("sim_day") else 0
	spark_mark(arc, "recent_loss")
	var mc: Node = sim.get_tree().get_first_node_in_group("music_context") if sim.get_tree() else null
	if mc != null and mc.has_method("set_spark_overlay"):
		mc.set_spark_overlay(0.0, "elegy")


static func try_grief_care(sim: Node, arc: Dictionary) -> void:
	var sp: Dictionary = ensure_spark(arc)
	var day: int = int(sim.sim_day()) if sim.has_method("sim_day") else 0
	if int(sp.get("last_loss_day", -1)) < 0 or day <= int(sp.get("grief_care_day", -1)):
		return
	if day - int(sp.get("last_loss_day", -1)) > 3:
		return
	sp["grief_care_day"] = day
	var g: Fish = sim._find_guardian_fish() if sim.has_method("_find_guardian_fish") else null
	if g != null and sim.has_method("_speak_guardian"):
		sim._speak_guardian(g, "grief_care", "")


static func try_coincidence_death(sim: Node, day_phase: float) -> void:
	if sim == null or not sim.has_method("log_story_event"):
		return
	var stormy: bool = day_phase > 0.45 and day_phase < 0.55
	if not stormy:
		return
	if randf() > 0.35:
		return
	sim.log_story_event("The light rolled low the night someone left — coincidence, maybe.", true)


static func try_one_shot_on_focus(sim: Node, arc: Dictionary, visits: int, trust: float) -> void:
	var g: Fish = sim._find_guardian_fish() if sim.has_method("_find_guardian_fish") else null
	if g == null or not sim.has_method("_speak_guardian"):
		return
	if float(arc.get("speak_cd", 0.0)) > 0.0:
		return
	if visits >= 30 and trust > 0.72 and not spark_has(arc, "four_wall"):
		spark_mark(arc, "four_wall")
		sim._speak_guardian(g, "four_wall", "")
	elif visits >= 20 and not spark_has(arc, "listening"):
		spark_mark(arc, "listening")
		sim._speak_guardian(g, "listening", "")


static func try_song_moment(sim: Node, arc: Dictionary, trigger: String) -> void:
	if spark_has(arc, "song_moment"):
		return
	var g: Fish = sim._find_guardian_fish() if sim.has_method("_find_guardian_fish") else null
	if g == null or not sim.has_method("_speak_guardian"):
		return
	spark_mark(arc, "song_moment")
	sim._speak_guardian(g, "song_moment", trigger)


static func departure_line(_arc: Dictionary, trust: float) -> String:
	if trust > 0.82:
		return "goodnight_hard"
	if trust > 0.55:
		return "goodnight"
	return "departure"


static func hardship_bio_boost(f: Fish) -> void:
	if f == null or f.bio is not Dictionary:
		return
	var scars: int = int(f.bio.get("near_deaths", 0))
	if scars < 1 and f.stress < 0.7:
		return
	if f.character_bio.contains("survived"):
		return
	var extra: String = " — carved from what almost broke them."
	if scars >= 2:
		extra = " — deep character forged in crash and fear."
	f.character_bio = FishMind.offline_character_bio(f) + extra


static func runt_underdog_note(f: Fish) -> bool:
	if f.size_potential > 0.75:
		return false
	if f.bio is Dictionary and bool(f.bio.get("underdog_noted", false)):
		return false
	if f.bio is Dictionary:
		f.bio["underdog_noted"] = true
	return true


static func light_journal_line() -> String:
	var jokes: PackedStringArray = PackedStringArray([
		"chased its own tail for no reason. Worth it.",
		"found a bubble and treated it like treasure.",
		"played tag with a leaf until everyone gave up.",
	])
	return jokes[randi() % jokes.size()]


# ---- Away / obituary / naming (existing) ----

static func away_recap_tier(gap_s: int) -> String:
	if gap_s >= 86400 * 14:
		return "chapter"
	if gap_s >= 86400:
		return "long"
	if gap_s >= 3600 * 6:
		return "medium"
	return "short"


static func away_recap_extras(gap_s: int, stability: float, crashes: int,
		dream_count: int, arc: Dictionary) -> Dictionary:
	var tier: String = away_recap_tier(gap_s)
	var mind: Dictionary = GuardianMind.ensure_mind(arc)
	var out: Dictionary = {
		"away_tier": tier,
		"gap_s": gap_s,
		"dream_count": dream_count,
		"player_wistful": str(mind.get("mood_toward_player", "")) == "wistful",
	}
	if tier in ["long", "chapter"]:
		out["absence_weight"] = "heavy"
	if stability < 0.42 and crashes > 0:
		out["dare_in_dark"] = true
	if gap_s >= 86400:
		out["kept_watch"] = true
	return out


static func away_recap_fallback(ctx: Dictionary) -> String:
	var tier: String = str(ctx.get("away_tier", "short"))
	var summary: String = str(ctx.get("away_summary", ""))
	if bool(ctx.get("managed_alone", false)):
		return "It managed without you. %s" % summary.capitalize()
	if bool(ctx.get("night_confession", false)):
		return "Just a pulse in the dark with a patterned name."
	if bool(ctx.get("returned_in_dark", false)):
		return "You came in the dark — the tank was still dreaming. %s" % summary.capitalize()
	if bool(ctx.get("dare_in_dark", false)):
		return "It was rough while you were gone — but we're still here. Build if you dare."
	if bool(ctx.get("kept_watch", false)):
		return "I kept watch at the glass. %s" % summary.capitalize()
	match tier:
		"chapter":
			return "A quiet chapter while you were away. %s" % summary
		"long":
			return "Long absence — much changed. %s" % summary
		"medium":
			return "While you were away: %s" % summary
		_:
			return summary if summary != "" else "The tank kept breathing."


static func build_obituary_context(f: Fish, sim: Node) -> Dictionary:
	if f == null or not is_instance_valid(f):
		return {}
	var ctx: Dictionary = {
		"fish_name": str(f.fish_name if f.fish_name != "" else f.species),
		"species": str(f.species),
		"feel": FishMind.emotional_state(f),
		"salient_memories": FishMind.top_salient_memories(f, 5),
		"generation": f.generation,
		"situation": "obituary",
	}
	if f.bio is Dictionary:
		ctx["meals_eaten"] = int(f.bio.get("meals_eaten", 0))
		ctx["offspring"] = int(f.bio.get("offspring", 0))
		ctx["fights_won"] = int(f.bio.get("fights_won", 0))
	if sim != null and sim.has_method("is_creature_favorited"):
		ctx["favorited"] = sim.is_creature_favorited(f)
	return ctx


static func obituary_fallback(ctx: Dictionary) -> String:
	var story: String = life_story_from_salient_dict(ctx)
	if story != "":
		return story
	var nm: String = str(ctx.get("fish_name", "Someone"))
	return "%s is gone — the tank feels quieter." % nm


static func life_story_from_salient_dict(ctx: Dictionary) -> String:
	var nm: String = str(ctx.get("fish_name", "Someone"))
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%s lived here" % nm)
	var mems: Variant = ctx.get("salient_memories", null)
	if mems is PackedStringArray:
		for m in (mems as PackedStringArray):
			parts.append(" — %s" % m)
	return "".join(parts) + "." if parts.size() > 1 else ""


static func naming_journal_line(old_name: String, new_name: String) -> String:
	if new_name.strip_edges() == "":
		return ""
	if old_name.strip_edges() == "" or old_name == new_name:
		return "A name settled on me — %s." % new_name
	return "I was %s; now I'm %s." % [old_name, new_name]


static func us_milestone_ready(arc: Dictionary) -> bool:
	var mind: Dictionary = GuardianMind.ensure_mind(arc)
	if float(mind.get("care_trust", 0.0)) < 0.78:
		return false
	if int(mind.get("visit_count", 0)) < 24:
		return false
	var ms: Variant = mind.get("shared_milestones", null)
	if ms is PackedStringArray and (ms as PackedStringArray).has("Us"):
		return false
	return true


static func record_us_milestone(arc: Dictionary) -> void:
	GuardianMind.record_milestone(arc, "Us")


static func player_present_strength(glance_strength: float, follow_active: bool) -> float:
	var p: float = glance_strength
	if follow_active:
		p = maxf(p, 0.45)
	return clampf(p, 0.0, 1.0)
