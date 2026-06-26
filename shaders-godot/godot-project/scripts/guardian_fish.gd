extends RefCounted

# One special fish per tank — the "tank voice" with a storyline, stronger
# presence, feed nudges, and optional auto-feed when the colony is starving.
# Procedural first; AIDirector can polish lines when Ollama is available.

const FishMind = preload("res://scripts/fish_mind.gd")

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
	var avg_h: float = tank_avg_hunger(sim)
	if avg_h > HUNGRY_THRESHOLD and f._cached_glance_strength > 0.12:
		var to_glass: Vector3 = f._cached_glance_point - f.position
		to_glass.y *= 0.35
		if to_glass.length_squared() > 0.08:
			out += to_glass.normalized() * lerpf(0.35, 0.85, avg_h)
	if avg_h > STARVE_THRESHOLD:
		var surface_y: float = f._water_surface_y() - 0.35
		var up: float = surface_y - f.position.y
		if up > 0.05:
			out += Vector3(0.0, up, 0.0).normalized() * 0.45
	var directive_y_v: Variant = sim.get("_guardian_directive_y")
	if directive_y_v != null and float(directive_y_v) > 0.01:
		out.y += float(directive_y_v)
	return out


static func arc_chapter_line(f: Fish, _sim: Node, chapter: int, situation: String) -> String:
	var nm: String = f.fish_name if f.fish_name != "" else "Someone"
	match situation:
		"arrival":
			return "%s settles in — the tank has a voice now." % nm
		"feed_nudge":
			match chapter:
				0: return "...hey. food?"
				1: return "...still hungry up here."
				2: return "...please? we're waiting."
				_: return "...the others are hungry too."
		"autofeed_on":
			return "Fine — I'll keep everyone fed until you're back."
		"water_stress":
			return "...something's wrong with the water."
		"morning":
			return "...morning. lights mean breakfast, right?"
		"successor":
			return "%s picks up where the last voice left off." % nm
		"lost":
			return "The tank feels quieter."
		_:
			return "..."

static func guardian_thought(f: Fish, sim: Node) -> String:
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
	# Returns optional {text, action, situation} — cheap tank scan only.
	var out: Dictionary = {}
	if not f.is_guardian or sim == null:
		return out
	var speak_cd: float = float(arc.get("speak_cd", 0.0))
	speak_cd = maxf(0.0, speak_cd - dt)
	arc["speak_cd"] = speak_cd
	if speak_cd > 0.0:
		return out

	var avg_h: float = tank_avg_hunger(sim)
	var nudges: int = int(arc.get("feed_nudges", 0))
	var chapter: int = int(arc.get("chapter", 0))
	var situation: String = ""
	var action: String = ""

	if sim.water_chemistry != null:
		var nh3: float = float(sim.water_chemistry.ammonia)
		var no2: float = float(sim.water_chemistry.nitrite)
		if nh3 > 0.45 or no2 > 0.5:
			situation = "water_stress"
	elif avg_h > STARVE_THRESHOLD:
		situation = "feed_nudge"
		action = "drop_feed"
		nudges += 1
		arc["feed_nudges"] = nudges
		if nudges >= AUTOFeed_ARM_NUDGES and not bool(arc.get("autofeed_done", false)):
			var cfg := sim.get_node_or_null("/root/TankConfig")
			var may: bool = cfg == null or bool(cfg.get("guardian_may_enable_autofeed"))
			var already: bool = cfg != null and bool(cfg.auto_feed_fauna)
			if may and not already:
				action = "enable_autofeed"
				arc["autofeed_done"] = true
				situation = "autofeed_on"
				chapter = mini(chapter + 1, 4)
				arc["chapter"] = chapter
	elif avg_h > HUNGRY_THRESHOLD and randf() < dt * 0.08:
		situation = "feed_nudge"
		action = "nudge_feed"
		nudges += 1
		arc["feed_nudges"] = nudges
	elif sim.has_method("daylight"):
		var dl: float = float(sim.daylight())
		var was: float = float(arc.get("last_daylight", dl))
		arc["last_daylight"] = dl
		if was < 0.2 and dl > 0.35 and f.familiarity > 0.2:
			situation = "morning"

	if situation == "":
		return out

	var line: String = arc_chapter_line(f, sim, chapter, situation)
	out = {"text": line, "action": action, "situation": situation}
	arc["speak_cd"] = SPEAK_COOLDOWN_S
	return out
