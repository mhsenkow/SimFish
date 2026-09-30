extends RefCounted

# Gamified keeper loop: steady the tank first, then fish open up to conversation.
# Guardian fish can translate tank stress into care hints (advisor mode).

enum Tier { CRISIS, STRESSED, STEADY, THRIVING }


static func stats_from_sim(sim: Node) -> Dictionary:
	if sim == null:
		return {}
	var s: Dictionary = {}
	if sim.get("dissolved_o2") != null:
		s["dissolved_o2"] = float(sim.dissolved_o2)
	if sim.has_method("fish_stocking_ratio"):
		s["fish_stocking_ratio"] = float(sim.fish_stocking_ratio())
	if sim.has_method("fish_carrying_capacity"):
		s["fish_carrying_capacity"] = int(sim.fish_carrying_capacity())
	if sim.get("fish") is Array:
		s["fish_total"] = (sim.fish as Array).size()
	if sim.get("waste") is Array:
		s["waste_particles"] = (sim.waste as Array).size()
	if sim.get("algae") is Array:
		s["algae_clusters"] = (sim.algae as Array).size()
	if sim.get("bloom_intensity") != null:
		s["bloom_intensity"] = float(sim.bloom_intensity)
	if sim.get("water_chemistry") != null:
		var wc = sim.water_chemistry
		s["ammonia"] = float(wc.ammonia)
		s["nitrite"] = float(wc.nitrite)
		s["nitrate"] = float(wc.nitrate)
		if wc.has_method("toxic_ammonia_level"):
			s["toxic_ammonia"] = float(wc.toxic_ammonia_level())
	if sim.has_method("_is_saltwater_tank"):
		s["is_saltwater"] = bool(sim._is_saltwater_tank())
		if sim.has_method("_max_reef_bleach"):
			s["reef_bleach_level"] = float(sim._max_reef_bleach())
		if sim.get("water_chemistry") != null:
			s["alkalinity_proxy"] = float(sim.water_chemistry.alkalinity_proxy)
		if sim.has_method("_tank_warmth_sample"):
			s["effective_warmth"] = float(sim._tank_warmth_sample())
	var biomass: int = 0
	if sim.get("plants") is Array:
		for p in sim.plants:
			if is_instance_valid(p) and p.has_method("biomass"):
				biomass += int(p.biomass())
	s["plant_total_biomass"] = biomass
	return s


static func mood_score(stats: Dictionary) -> float:
	var o2: float = float(stats.get("dissolved_o2", 0.85))
	var ammonia: float = float(stats.get("ammonia", 0.0))
	if not not stats.get("is_saltwater", false):
		var bleach: float = float(stats.get("reef_bleach_level", 0.0))
		var alk: float = float(stats.get("alkalinity_proxy", 8.0))
		var warmth: float = float(stats.get("effective_warmth", 0.55))
		return clampf(
			0.35 * o2
			+ 0.28 * clampf(1.0 - bleach, 0.0, 1.0)
			+ 0.20 * clampf((alk - 6.8) / 1.4, 0.0, 1.0)
			+ 0.17 * clampf(1.0 - maxf(0.0, warmth - 0.78) * 3.2, 0.0, 1.0),
			0.0, 1.0)
	var biomass: float = float(stats.get("plant_total_biomass", 0))
	var algae: float = float(stats.get("algae_clusters", 0))
	var waste: float = float(stats.get("waste_particles", 0))
	var score: float = clampf(
		0.30 * o2
		+ 0.30 * clampf(biomass / 600.0, 0.0, 1.0)
		+ 0.20 * clampf(1.0 - algae / 60.0, 0.0, 1.0)
		+ 0.20 * clampf(1.0 - waste / 100.0, 0.0, 1.0)
		- clampf(ammonia * 0.25, 0.0, 0.35),
		0.0, 1.0)
	var toxic: float = float(stats.get("toxic_ammonia", ammonia * 0.35))
	if ammonia >= 0.18 or toxic >= 0.08:
		return minf(score, 0.42)
	return score


static func tier_from_stats(stats: Dictionary) -> int:
	var mood: float = mood_score(stats)
	if mood < 0.32:
		return Tier.CRISIS
	if mood < 0.55:
		return Tier.STRESSED
	if float(stats.get("fish_stocking_ratio", 0.0)) > 1.08:
		return Tier.STRESSED
	if float(stats.get("dissolved_o2", 1.0)) < 0.45:
		return Tier.STRESSED
	if float(stats.get("ammonia", 0.0)) >= 0.22:
		return Tier.STRESSED
	if mood < 0.78:
		return Tier.STEADY
	return Tier.THRIVING


static func tier_from_sim(sim: Node) -> int:
	return tier_from_stats(stats_from_sim(sim))


static func tier_label(tier: int) -> String:
	match tier:
		Tier.CRISIS:
			return "crisis"
		Tier.STRESSED:
			return "stressed"
		Tier.STEADY:
			return "steady"
		Tier.THRIVING:
			return "thriving"
		_:
			return "steady"


static func primary_action_hint(sim: Node) -> String:
	var stats: Dictionary = stats_from_sim(sim)
	var mood: float = mood_score(stats)
	return OnboardingLegibility.tank_status_footer(stats, mood)


static func conversation_openness(sim: Node, f: Fish) -> float:
	if f == null:
		return 0.0
	var tier: int = tier_from_sim(sim)
	var bond: float = clampf(float(f.familiarity), 0.0, 1.0)
	match tier:
		Tier.CRISIS:
			return clampf(bond * 0.22, 0.05, 0.35)
		Tier.STRESSED:
			return clampf(0.12 + bond * 0.42, 0.1, 0.58)
		Tier.STEADY:
			return clampf(0.38 + bond * 0.38, 0.25, 0.88)
		Tier.THRIVING:
			return clampf(0.55 + bond * 0.42, 0.4, 1.0)
	return 0.45


static func can_verbal_reply(sim: Node, f: Fish, too_wary: bool) -> bool:
	if too_wary:
		return false
	return conversation_openness(sim, f) >= 0.38


static func note_keeper_ambient(f: Fish, kind: String, strength: float = 0.5) -> void:
	if f == null:
		return
	if f.get("_keeper_pending") == null:
		f._keeper_pending = {}
	var kp: Dictionary = f._keeper_pending as Dictionary
	match kind:
		"feed":
			kp["keeper_intent"] = "food"
			kp["keeper_felt"] = "care"
			kp["keeper_valence"] = 0.25
		"water_change", "prune":
			kp["keeper_intent"] = "comfort"
			kp["keeper_felt"] = "calm"
			kp["keeper_valence"] = 0.18
		"gaze":
			kp["keeper_intent"] = "greeting"
			kp["keeper_felt"] = "neutral"
			kp["keeper_valence"] = 0.1
		_:
			return
	kp["keeper_arousal"] = clampf(strength, 0.0, 1.0)
	f._keeper_pending = kp


const _MotionFieldScript = preload("res://scripts/motion_field.gd")

static func broadcast_keeper_ambient(sim: Node, world_pos: Vector3, kind: String,
		strength: float = 0.5, radius: float = 8.0) -> void:
	if sim == null or sim.get("fish") == null:
		return
	var r2: float = radius * radius
	for ff in sim.fish:
		if is_instance_valid(ff) and ff.position.distance_squared_to(world_pos) <= r2:
			note_keeper_ambient(ff, kind, strength)
	if kind == "calm" and sim.get("fish") != null:
		_MotionFieldScript.inject_calm(sim.fish, world_pos, strength * 0.45)


static func is_comfort_intent(interp: Dictionary) -> bool:
	var felt: String = str(interp.get("keeper_felt", ""))
	var intent: String = str(interp.get("keeper_intent", ""))
	if felt == "comfort" or intent == "comfort":
		return true
	var lower: String = str(interp.get("keeper_text", "")).to_lower()
	return lower.contains("safe") or lower.contains("calm") or lower.contains("okay")


static func apply_comfort_effects(f: Fish, interp: Dictionary, sim: Node) -> Dictionary:
	var out: Dictionary = {"applied": false, "soothe": 0.0, "attention_shift": false}
	if f == null or not is_comfort_intent(interp):
		return out
	var open: float = conversation_openness(sim, f)
	var soothe: float = 0.025 + open * 0.055
	if str(interp.get("keeper_felt", "")) == "comfort":
		soothe += 0.015
	var lower: String = str(interp.get("keeper_text", "")).to_lower()
	if lower.contains("safe") or lower.contains("trust"):
		soothe += 0.02
	f.spooked = maxf(0.0, f.spooked - soothe)
	f.stress = maxf(0.0, f.stress - soothe * 0.85)
	f.mood = clampf(f.mood + float(interp.get("keeper_valence", 0.0)) * 0.06 + soothe * 0.5, -1.0, 1.0)
	out["applied"] = true
	out["soothe"] = soothe
	# Shift attention when bond + tank allow — comfort can pierce threat focus.
	if open >= 0.32 and f.attention_focus == "threat":
		if float(interp.get("keeper_valence", 0.0)) > 0.05 or str(interp.get("keeper_felt", "")) == "comfort":
			f.attention_focus = "keeper_message"
			f._keeper_message_salience = maxf(float(f._keeper_message_salience), 0.52)
			out["attention_shift"] = true
	return out


static func compute_too_wary(f: Fish) -> bool:
	if f == null:
		return true
	return f.spooked > 0.35 or f.stress > 0.55 or f.attention_focus == "threat"


static func bond_stage(f: Fish, sim: Node) -> int:
	var open: float = conversation_openness(sim, f)
	if open < 0.22:
		return 0
	if open < 0.42:
		return 1
	if open < 0.62:
		return 2
	return 3


static func bond_stage_label(stage: int) -> String:
	match stage:
		0: return "stranger"
		1: return "listening"
		2: return "trusting"
		3: return "conversing"
	return "listening"


static func placeholder_for_fish(f: Fish, sim: Node) -> String:
	var tier: int = tier_from_sim(sim)
	var nm: String = f.fish_name if f != null and f.fish_name != "" else "they"
	if f != null and f.is_guardian and tier <= Tier.STRESSED:
		return "advisor mode — ask me what the tank needs…"
	match tier:
		Tier.CRISIS, Tier.STRESSED:
			return "steady the tank first — then %s can talk back…" % nm
		Tier.STEADY:
			return "say something… (comfort words land easier now)"
		_:
			return "say something… (Enter to send)"


static func placeholder_for_tank(sim: Node) -> String:
	match tier_from_sim(sim):
		Tier.CRISIS, Tier.STRESSED:
			return "speak to the tank… (it's struggling — ask how it is)"
		_:
			# Rotate a hint at the inner-life questions the tank can answer.
			var hints: Array = ["Enter to send, Esc to clear", "ask what it's thinking",
					"ask what it dreamed", "ask who is friends with whom", "ask about a fish by name"]
			var slot: int = int(float(Time.get_ticks_msec()) / 45000.0) % hints.size()
			return "speak to the tank… (%s)" % hints[slot]


# Short status line under a tank exchange: what the tank understood and who
# is about to answer.
static func tank_feedback(result: Dictionary, sim: Node) -> String:
	if not bool(result.get("ok", false)):
		if str(result.get("reason", "")) == "ears_off":
			return "Keeper ears off — enable in Settings → AI"
		return ""
	var parts: Array[String] = []
	var heard: PackedStringArray = result.get("understood", PackedStringArray())
	if heard.is_empty():
		parts.append("the tank caught your tone, not your words")
	else:
		parts.append("understood: %s" % ", ".join(heard))
	parts.append("tank %s" % tier_label(int(result.get("tank_tier", tier_from_sim(sim)))))
	match str(result.get("promise", "")):
		"feed":
			parts.append("it will remember you said you'd feed")
		"water":
			parts.append("it will remember you said you'd fix the water")
		"air":
			parts.append("it will remember you said you'd help it breathe")
	match str(result.get("intent", "")):
		"dream":
			parts.append("asked about its dream")
		"thinking":
			parts.append("asked what it's thinking")
		"friend":
			parts.append("asked about friendships")
		"about":
			parts.append("asked about one of them")
	var ids: PackedStringArray = result.get("responder_ids", PackedStringArray())
	var n: int = ids.size()
	if n > 0:
		parts.append("%d answering" % n)
	if int(result.get("tank_tier", Tier.STEADY)) <= Tier.STRESSED:
		var hint: String = primary_action_hint(sim)
		if hint != "":
			parts.append("→ %s" % hint)
	return " · ".join(parts)


static func ui_feedback(result: Dictionary, f: Fish, sim: Node) -> String:
	if not bool(result.get("ok", false)):
		match str(result.get("reason", "")):
			"ears_off":
				return "Keeper ears off — enable in Settings → AI"
			_:
				return ""
	var nm: String = f.fish_name if f != null and f.fish_name != "" else "they"
	var tier: int = int(result.get("tank_tier", tier_from_sim(sim)))
	var tier_nm: String = tier_label(tier)
	var stage: int = int(result.get("bond_stage", bond_stage(f, sim)))
	var parts: Array[String] = []
	parts.append("you → \"%s\"" % str(result.get("text", "")))
	parts.append("%s · tank %s · bond %s" % [nm, tier_nm, bond_stage_label(stage)])
	if bool(result.get("comfort_applied", false)):
		var bits: Array[String] = ["soothed"]
		if bool(result.get("attention_shift", false)):
			bits.append("turned toward you")
		parts.append(" · ".join(bits))
	if tier <= Tier.STRESSED:
		var hint: String = str(result.get("care_hint", ""))
		if hint != "":
			parts.append("→ %s" % hint)
	if bool(result.get("too_wary", false)):
		parts.append("too wary to answer in words now")
	elif bool(result.get("tank_blocks_words", false)):
		parts.append("heard you — fix the water for full replies")
	elif bool(result.get("attending", false)):
		parts.append("attending")
	else:
		parts.append("heard, mind elsewhere")
	return " · ".join(parts)


static func guardian_advisor_line(f: Fish, sim: Node) -> String:
	if f == null or not f.is_guardian:
		return ""
	var tier: int = tier_from_sim(sim)
	if tier >= Tier.STEADY:
		return ""
	var hint: String = primary_action_hint(sim)
	if hint == "":
		hint = "ease feeding, trim plants, or add aeration"
	var moniker: String = f.fish_name if f.fish_name != "" else "I"
	if tier == Tier.CRISIS:
		return "%s — I can't think straight in here. %s" % [moniker, hint]
	return "%s — steady the tank first? %s" % [moniker, hint]


static func maybe_guardian_interject(sim: Node, speaker: Fish) -> String:
	if sim == null or speaker == null or speaker.is_guardian:
		return ""
	if tier_from_sim(sim) > Tier.STRESSED:
		return ""
	if not sim.has_method("_find_guardian_fish"):
		return ""
	var g: Fish = sim._find_guardian_fish()
	if g == null or not is_instance_valid(g):
		return ""
	return guardian_advisor_line(g, sim)


static func tank_needs_care_nudge(sim: Node) -> bool:
	return tier_from_sim(sim) <= Tier.STRESSED


# Say-box placeholder while a fish (or the tank) is waiting on an answer.
static func placeholder_for_question(q: Dictionary) -> String:
	if q.is_empty():
		return ""
	return "answer %s… (Enter to reply)" % str(q.get("name", "them"))


# Status line after the keeper answered a fish's question: how much of the
# answer actually landed (MindLexicon comprehension).
static func question_answer_feedback(res: Dictionary) -> String:
	if res.is_empty():
		return ""
	var nm: String = str(res.get("name", "they"))
	var understood: PackedStringArray = res.get("understood", PackedStringArray())
	if str(res.get("tone", "")) == "harsh":
		return "%s shrank from the tone" % nm
	if float(res.get("comprehension", 0.0)) >= 0.5:
		return "%s understood most of it — and will remember" % nm
	if not understood.is_empty():
		return "%s caught \"%s\" — the rest was sound" % [nm, understood[0]]
	return "%s didn't know the words, but felt the answer" % nm
