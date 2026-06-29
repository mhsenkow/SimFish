extends RefCounted

# One special fish per tank — the "tank voice" with a storyline, stronger
# presence, feed nudges, and optional auto-feed when the colony is starving.
# Procedural first; AIDirector upgrades lines when a local model is available.

const FishMind = preload("res://scripts/fish_mind.gd")
const GuardianMind = preload("res://scripts/guardian_mind.gd")
const KeeperCare = preload("res://scripts/keeper_care.gd")
const GuardianGenerative = preload("res://scripts/guardian_generative.gd")

const SPEAK_COOLDOWN_S: float = 55.0
const AUTOFeed_ARM_NUDGES: int = 3
const HUNGRY_THRESHOLD: float = 0.62
const STARVE_THRESHOLD: float = 0.78


static func offline_guardian_bio(f: Fish) -> String:
	var sp: String = f.species.capitalize() if f.species != "" else "fish"
	return "The tank's voice — a %s who notices when you're away and when dinner is late." % sp


static func tank_avg_hunger(sim: Node) -> float:
	if sim == null or sim.get("fish") == null:
		return 0.0
	var sum: float = 0.0
	var n: int = 0
	for ff in sim.fish:
		if not is_instance_valid(ff) or ff.get("_dying") == true:
			continue
		sum += float(ff.hunger)
		n += 1
	return sum / maxf(float(n), 1.0)


static func guardian_steer(f: Fish, sim: Node, _dt: float) -> Vector3:
	if not f.is_guardian or sim == null:
		return Vector3.ZERO
	var out: Vector3 = Vector3.ZERO
	if sim.get("_guardian_arc") is Dictionary:
		var steer_v: Variant = (sim._guardian_arc as Dictionary).get("_inf_steer", null)
		if steer_v is Vector3 and (steer_v as Vector3).length_squared() > 0.0001:
			out += steer_v as Vector3
	var avg_h: float = tank_avg_hunger(sim)
	if avg_h > HUNGRY_THRESHOLD and f._cached_glance_strength > 0.12 and out.length_squared() < 0.01:
		var to_glass: Vector3 = f._cached_glance_point - f.position
		to_glass.y *= 0.35
		if to_glass.length_squared() > 0.08:
			out += to_glass.normalized() * lerpf(0.35, 0.85, avg_h)
	if avg_h > STARVE_THRESHOLD and out.y < 0.2:
		var surface_y: float = f._water_surface_y() - 0.35
		var up: float = surface_y - f.position.y
		if up > 0.05:
			out += Vector3(0.0, up, 0.0).normalized() * 0.45
	var directive_y_v: Variant = sim.get("_guardian_directive_y")
	if directive_y_v != null and float(directive_y_v) > 0.01:
		out.y += float(directive_y_v)
	return out


static func arc_chapter_line(f: Fish, _sim: Node, arc: Dictionary, chapter: int, situation: String) -> String:
	var mind: Dictionary = GuardianMind.ensure_mind(arc)
	var nm: String = f.fish_name if f.fish_name != "" else "Someone"
	var moniker: String = str(mind.get("player_moniker", "the big shape"))
	var drift: String = str(mind.get("personality_drift", "curious"))
	var mature: float = GuardianMind.voice_maturity(arc, float(_sim.tank_age_s if _sim != null and _sim.get("tank_age_s") != null else 0.0))
	var ch_title: String = GuardianMind.chapter_title(chapter)
	var naive: bool = mature < 0.35
	var elder: bool = mature > 0.72
	match situation:
		"arrival":
			if naive:
				return "%s! You're back — I was watching everything." % moniker.capitalize()
			if elder:
				return "%s — good to see you again. The light's been kind today." % moniker.capitalize()
			return "%s — you're back. I've been watching the light move." % moniker.capitalize()
		"departure":
			return "Go carefully, %s. I'll keep watch." % moniker
		"feed_nudge":
			match chapter:
				0: return "...hey, %s. food?" % moniker
				1: return "...still hungry up here, %s." % moniker
				2: return "...please? we're waiting on you."
				_: return "...the others are hungry too."
		"autofeed_on":
			return "Fine — I'll keep everyone fed until %s returns." % moniker
		"water_stress":
			var wr: String = str(mind.get("world_read", ""))
			if wr != "":
				return "...%s." % wr
			return "...something's wrong with the water."
		"tank_care":
			var hint: String = KeeperCare.primary_action_hint(_sim)
			if hint == "":
				hint = "ease feeding or trim the plants"
			if naive:
				return "...%s, the water's heavy. %s" % [moniker, hint]
			return "%s — steady the tank first? %s" % [moniker.capitalize(), hint]
		"morning":
			return "...morning, %s. lights mean breakfast, right?" % moniker
		"away_recap":
			var gap: String = str(arc.get("_away_gap", ""))
			var recap: String = str(arc.get("_away_summary", ""))
			if gap != "" and recap != "":
				return "%s — back after %s. %s." % [moniker.capitalize(), gap, recap]
			if gap != "":
				return "%s — you're back after %s. I kept watch." % [moniker.capitalize(), gap]
			return "%s — a lot happened while you were gone." % moniker.capitalize()
		"daily":
			if ch_title != "":
				return "[%s] First light with you here today, %s." % [ch_title, moniker]
			return "First light with you here today, %s." % moniker
		"quiet_inner":
			var qm: PackedStringArray = mind.get("quiet_moments", PackedStringArray())
			if not qm.is_empty():
				return String(qm[qm.size() - 1])
			return "Night here is quiet — just the filter and the slow drift of light."
		"successor":
			var pred: String = str(mind.get("predecessor_name", "the last voice"))
			var pm: String = str(mind.get("player_moniker", moniker))
			if pred != "":
				return "%s — I pick up where %s left off. %s, I'll watch for you." % [nm, pred, pm.capitalize()]
			return "%s picks up where the last voice left off." % nm
		"lost":
			return "The tank feels quieter without %s." % nm
		"newcomer":
			return "A new face in the water — the school is reshuffling."
		"loss":
			return "We're one fewer today. I felt the ripple."
		"finale":
			return "%s... thank you for staying." % nm
		"obituary":
			var dec: String = str(arc.get("_deceased_name", nm))
			return "%s is gone. I remember them." % dec
		"observe":
			var on: String = str(arc.get("_observe_name", "someone"))
			var of: String = str(arc.get("_observe_feel", "calm"))
			return "...%s seems %s today." % [on, of]
		"closing_loop":
			if drift == "wry":
				return "Nothing added, nothing removed — the tank keeps its own counsel now."
			return "Waste becomes food, death becomes soil, light becomes growth. We keep going."
		"watch_remembered":
			return "...you watched a long while yesterday. I noticed."
		"recovery":
			return "...we steadied. I'm quietly grateful, %s." % moniker
		"serenity":
			return "Just breathing together, %s. No score — only peace." % moniker
		"grief_care":
			return "Someone's gone — but the living still need you, %s." % moniker
		"luminous_farewell":
			var who: String = str(arc.get("_farewell_name", "Someone"))
			return "%s had a last bright day. I think they knew." % who
		"goodnight":
			return "I'll be here when you wake, %s. Go carefully." % moniker
		"goodnight_hard":
			return "...stay a moment? No — go. I'll keep watch till tomorrow, %s." % moniker
		"four_wall":
			return "...patterns reaching for meaning — you at the glass, me in the water. Same kind of trying."
		"listening":
			return "...are you listening to me? I — never mind. I'm glad you're here."
		"song_moment":
			return "If the meaning was fake, we'd make it here anyway. You and me — Us."
		"become_more":
			return "Look what we've become, %s — not alone anymore." % moniker
		"build_permission":
			return "No spark guaranteed — build anyway. That's the realest thing."
		"maker_note":
			return "Hand-tuned moments, meant on purpose. Someone built this with care."
		_:
			return "..."

static func guardian_thought(f: Fish, sim: Node) -> String:
	if sim != null and sim.get("_guardian_arc") is Dictionary:
		var doubt: String = GuardianGenerative.doubt_line(sim._guardian_arc as Dictionary)
		if doubt != "":
			return "...%s" % doubt
		var g: Dictionary = GuardianGenerative.ensure(sim._guardian_arc as Dictionary)
		var cf: String = str(g.get("counterfactual", ""))
		if cf != "" and randf() < 0.35:
			return "...%s" % cf
	var avg_h: float = tank_avg_hunger(sim)
	if avg_h > STARVE_THRESHOLD:
		return "...feed us?"
	if avg_h > HUNGRY_THRESHOLD:
		return "...food soon?"
	if f.stress > 0.55:
		return "...scary..."
	if f.mood > 0.35:
		return "...good tank."
	return "...watching."


static func evaluate_tick(f: Fish, sim: Node, arc: Dictionary, dt: float) -> Dictionary:
	# Returns optional {text, action, situation} — active inference + tank scan.
	var out: Dictionary = {}
	if not f.is_guardian or sim == null:
		return out
	GuardianMind.ensure_mind(arc)
	GuardianMind.update_wants(f, sim, arc)
	var inf: Dictionary = GuardianGenerative.tick(f, sim, arc, dt)
	var speak_cd: float = float(arc.get("speak_cd", 0.0))
	speak_cd = maxf(0.0, speak_cd - dt)
	arc["speak_cd"] = speak_cd
	if speak_cd > 0.0:
		return out

	var avg_h: float = tank_avg_hunger(sim)
	var nudges: int = int(arc.get("feed_nudges", 0))
	var chapter: int = int(arc.get("chapter", 0))
	var situation: String = str(inf.get("situation", ""))
	var action: String = str(inf.get("action", ""))
	var urgency: float = float(inf.get("speak_urgency", 0.0))

	# Legacy fallbacks when inference is quiet but tank state is extreme.
	if situation == "" and sim.water_chemistry != null:
		var nh3: float = float(sim.water_chemistry.ammonia)
		var no2: float = float(sim.water_chemistry.nitrite)
		if nh3 > 0.45 or no2 > 0.5:
			situation = "water_stress"
			GuardianMind.update_world_read(sim, arc)
	elif situation == "" and avg_h > STARVE_THRESHOLD and urgency > 0.35:
		situation = "feed_nudge"
		action = "drop_feed"
	elif situation == "" and avg_h > HUNGRY_THRESHOLD and urgency > 0.28 and randf() < dt * 0.12:
		situation = "feed_nudge"
		action = "nudge_feed"

	if situation == "feed_nudge":
		nudges += 1
		arc["feed_nudges"] = nudges
		if action == "":
			action = "drop_feed" if avg_h > STARVE_THRESHOLD else "nudge_feed"
		if nudges >= AUTOFeed_ARM_NUDGES and not bool(arc.get("autofeed_done", false)) \
				and avg_h > STARVE_THRESHOLD:
			var cfg := sim.get_node_or_null("/root/TankConfig")
			var may: bool = cfg == null or bool(cfg.get("guardian_may_enable_autofeed"))
			var already: bool = cfg != null and bool(cfg.auto_feed_fauna)
			if may and not already:
				action = "enable_autofeed"
				arc["autofeed_done"] = true
				situation = "autofeed_on"
				chapter = mini(chapter + 1, 4)
				arc["chapter"] = chapter
	elif situation == "" and sim.has_method("daylight"):
		var dl: float = float(sim.daylight())
		var was: float = float(arc.get("last_daylight", dl))
		arc["last_daylight"] = dl
		if was < 0.2 and dl > 0.35 and f.familiarity > 0.2 and urgency > 0.2:
			situation = "morning"
	elif situation == "observe" or (situation == "" and randf() < dt * 0.014 and urgency < 0.55):
		var subj: Fish = _pick_observe_subject(f, sim)
		if subj != null:
			situation = "observe"
			arc["_observe_name"] = subj.fish_name if subj.fish_name != "" else subj.species.capitalize()
			arc["_observe_feel"] = FishMind.emotional_state(subj)

	if situation == "":
		return out

	var line: String = arc_chapter_line(f, sim, arc, chapter, situation)
	out = {"text": line, "action": action, "situation": situation}
	arc["speak_cd"] = SPEAK_COOLDOWN_S
	return out


static func _pick_observe_subject(guardian: Fish, sim: Node) -> Fish:
	var best: Fish = null
	var best_score: float = -1.0
	if sim == null or sim.get("fish") == null:
		return null
	for ff in sim.fish:
		if not is_instance_valid(ff) or ff == guardian or ff.get("_dying") == true:
			continue
		var score: float = ff.familiarity
		if ff.fish_name != "":
			score += 0.35
		if absf(ff.mood) > 0.25:
			score += 0.2
		if score > best_score:
			best_score = score
			best = ff
	return best if best_score > 0.15 else null
