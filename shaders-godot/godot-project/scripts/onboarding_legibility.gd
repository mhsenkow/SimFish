# Onboarding & legibility — copy, glossary, scenario metadata, HUD enrichment.
# See docs/ONBOARDING_LEGIBILITY_IDEAS.md
class_name OnboardingLegibility
extends RefCounted

const GLOBAL_PREFS := "user://global_prefs.cfg"

const GLOSSARY: Dictionary = {
	"NH₃": "Ammonia — fish waste before bacteria break it down. Spikes in new tanks; toxic if it stays high.",
	"NO₂": "Nitrite — mid-cycle marker. Bacteria convert ammonia to nitrite, then to safer nitrate.",
	"NO₃": "Nitrate — the end of the nitrogen cycle. Plants consume it; water changes dilute it.",
	"O₂": "Dissolved oxygen — fish breathe it. Plants make it by day; aeration and surface ripple help.",
	"KH": "Carbonate hardness — buffers pH swings. Stable KH keeps chemistry calm.",
	"GH": "General hardness — dissolved minerals. Affects plant and fish health.",
	"pearling": "Tiny bubbles on leaves — plants photosynthesizing hard. A sign the tank is breathing well.",
	"biofilm": "Thin bacterial film on surfaces — shrimp and snails graze it; it's part of the food web.",
	"cycling": "The nitrogen cycle boot-up — ammonia rises, then nitrite, then the tank stabilizes.",
	"Walstad": "A low-tech planted tank where plants, bacteria, and animals close the nutrient loop.",
	"hardscape": "Rocks and wood — structure for fish and anchor points for plants.",
	"aquascape": "The art of arranging substrate, stones, and plants in the tank.",
	"Iwagumi": "Minimal stone-garden layout — lots of negative space, one calm school.",
	"substrate": "Tank floor material — sand, soil, or gravel. Feeds roots and shapes algae risk.",
	"mouthbrooder": "A fish that carries eggs or fry in its mouth until they're ready.",
}

const TANK_TELLS: Array[Dictionary] = [
	{"cue": "Gulping at the surface", "meaning": "Low dissolved oxygen", "action": "Increase aeration or reduce stocking; add plants."},
	{"cue": "Hiding in plants", "meaning": "Stress or fear", "action": "Check water, crowding, or recent scares."},
	{"cue": "Gill flush (rapid operculum)", "meaning": "Ammonia or nitrite irritation", "action": "Let the cycle finish; avoid overfeeding."},
	{"cue": "Glass surfing / pacing", "meaning": "Crowding or boredom", "action": "More space, cover, or tankmates."},
	{"cue": "Clamped fins", "meaning": "Illness or chronic stress", "action": "Inspect water and reduce stressors."},
	{"cue": "Sleeping on the bottom (night)", "meaning": "Normal rest", "action": "None — let them sleep."},
	{"cue": "Sluggish by day", "meaning": "Rest debt or poor water", "action": "Check O₂ and ammonia; dim lights at night."},
	{"cue": "Pearling on leaves", "meaning": "Plants thriving", "action": "Enjoy — the tank is breathing well."},
]

const SCENARIO_PLAIN_NAMES: Dictionary = {
	"walstad": "Walstad — dense jungle community",
	"iwagumi": "Iwagumi — minimalist stone garden",
	"blackwater": "Blackwater — tea-stained biotope",
	"reef": "Reef — saltwater coral cube",
	"cichlid_rock": "Cichlid hex — territorial pairs",
	"polyp_lab": "Polyp lab — fishless microcosm",
	"nature_aquarium": "Nature aquarium — full behavior showcase",
	"apex_predator": "Apex den — predator territories",
	"shrimp_sanctuary": "Shrimp sanctuary — nano colony",
	"dutch_competition": "Dutch — high-CO₂ red plants",
	"nano_reef": "Nano reef — warmth tutorial",
	"beginner_sandbox": "Beginner sandbox — safest learning tank",
	"wildcard": "Surprise me — random or AI roll",
}

# difficulty: 0 easy, 1 moderate, 2 hard; recommended first-tank; maintenance warning
const SCENARIO_META: Dictionary = {
	"walstad": {"tier": 0, "tier_why": "Balanced community · forgiving plants", "recommended": true},
	"beginner_sandbox": {"tier": 0, "tier_why": "Light stocking · established cycle · no predators", "recommended": true},
	"iwagumi": {"tier": 1, "tier_why": "Bright light · watch algae on sand"},
	"blackwater": {"tier": 1, "tier_why": "Dim warm biotope · tannins darken water"},
	"shrimp_sanctuary": {"tier": 0, "tier_why": "No fish predators · shrimp-focused"},
	"nature_aquarium": {"tier": 1, "tier_why": "Busy stocking · lots to watch"},
	"cichlid_rock": {"tier": 1, "tier_why": "Territorial pairs · needs space"},
	"reef": {"tier": 2, "tier_why": "Saltwater · warmth and alk matter"},
	"nano_reef": {"tier": 2, "tier_why": "Teaches bleaching · manage warmth"},
	"polyp_lab": {"tier": 1, "tier_why": "Fishless · bloom cycles are the show"},
	"apex_predator": {"tier": 2, "tier_why": "Higher maintenance — sparse plants", "maint_warning": true},
	"dutch_competition": {"tier": 2, "tier_why": "High CO₂ · demands trimming", "maint_warning": true},
	"wildcard": {"tier": 1, "tier_why": "Random combo — preview before commit"},
}

const CURATED_PICKS: Array[String] = ["beginner_sandbox", "walstad", "nature_aquarium"]

const SUBSTRATE_BLURBS: Dictionary = {
	"aquasoil": "Rich plant soil — feeds roots, can tint water early",
	"sand": "Clean look — poor nutrients; needs careful planting",
	"eco_complete": "Pre-loaded nutrients — fast algae risk if over-lit",
	"inert_gravel": "Neutral floor — plants need root tabs",
	"ocean_sand": "Reef floor — for corals, not freshwater plants",
}

const AERATION_BLURBS: Dictionary = {
	"filter": "Hang-on filter — good flow and biofiltration",
	"disk": "Lots of bubbles — great O₂, strips CO₂ plants want",
	"stick": "Gentle bubble wand — moderate aeration",
	"none": "Still surface — fine for heavily planted low-tech tanks",
}

const WALKTHROUGH_EFFECTS: Dictionary = {
	"plant": "+O₂ · shade · nutrient uptake",
	"snail": "+cleanup crew · algae & detritus",
	"shrimp": "+scavengers · biofilm & mulm",
	"fish": "+motion · the closed loop closes",
	"hardscape": "+cover · territory structure",
}


static func tier_label(tier: int) -> String:
	match tier:
		0: return "Easy"
		1: return "Moderate"
		_: return "Hard"


static func tier_color(tier: int) -> Color:
	match tier:
		0: return Color8(120, 210, 140)
		1: return Color8(220, 190, 100)
		_: return Color8(230, 120, 110)


static func cheat_sheet_lines(mobile: bool) -> PackedStringArray:
	if mobile:
		return PackedStringArray([
			"Drag — orbit camera",
			"Pinch — zoom",
			"Two-finger drag — pan · twist — roll",
			"Tap water — feed fish",
			"Double-tap — reset camera",
			"Long-press — auto-orbit",
			"Edge-swipe — Settings",
			"Tap creature — inspect",
			"Tap stat chips — chemistry / history / mood",
			"❓ rail — Help & glossary",
		])
	return PackedStringArray([
		"O — Settings · R — Rendering · M — Sound · Shift+M — Motion debug",
		"B — Aquascape · [ / ] — brush size · Backspace — undo",
		"C — Follow portal · ←/→ — cycle follow · Esc — release",
		"H — Focus mode · P — Pause · T — Timelapse · F — reset camera",
		"1–8 — Sim speed · F12 — Photo",
		"Click water — feed · 9 / 0 — food type",
		"Shift+click water — tap glass (startle)",
		"Right-drag — dolly · Space+drag — pan · G — auto-orbit",
		"Click stat chips — history / water / mood / alerts",
		"? / Shift+/ — this help · K — Residents",
		"Right rail — Create · World · Look · System · Alerts · ❓ Help",
	])


static func control_hint_for_context(ctx: String) -> String:
	match ctx:
		"aquascape":
			return "Paint substrate · place hardscape · [ / ] brush · Backspace undo · B exit"
		"follow":
			return "← / → cycle subjects · Esc release · C portal"
		"immersive":
			return "Tap edge for controls · H exit focus"
		"mobile":
			return "Drag look · tap water feed · double-tap reset · ❓ help"
		_:
			return "Drag look · tap water feed · tap chips for details · ? help"


static func mood_driver(stats: Dictionary, mood_score: float) -> String:
	if not not stats.get("is_saltwater", false):
		var bleach: float = float(stats.get("reef_bleach_level", 0.0))
		if bleach >= 0.35:
			return "stressed — coral bleaching"
		var o2: float = float(stats.get("dissolved_o2", 1.0))
		if o2 < 0.5:
			return "stressed — low O₂"
		return "content — reef stable"
	var o2f: float = float(stats.get("dissolved_o2", 1.0))
	var nh3: float = float(stats.get("ammonia", 0.0))
	var waste: int = int(stats.get("waste_particles", 0))
	var algae: int = int(stats.get("algae_clusters", 0))
	if o2f < 0.5:
		return "stressed — low O₂"
	if nh3 >= 0.25:
		return "stressed — ammonia"
	if float(stats.get("nitrite", 0.0)) >= 0.22:
		return "stressed — nitrite"
	if waste > 30:
		return "stressed — detritus building"
	if algae > 20:
		return "stressed — algae bloom"
	if mood_score >= 0.78:
		return "thriving — balanced loop"
	if mood_score >= 0.55:
		return "ok — steady"
	if mood_score >= 0.32:
		return "stressed — trending down"
	return "crashing — needs care"


static func day_phase_label(phase: float) -> String:
	var p: float = fposmod(phase, 1.0)
	if p < 0.125:
		return "dawn"
	if p < 0.375:
		return "day"
	if p < 0.5:
		return "dusk"
	if p < 0.875:
		return "night"
	return "dawn"


static func tank_status_glance(stats: Dictionary, mood_score: float) -> Dictionary:
	var headline: String = _status_headline(stats)
	var detail: String = _status_detail(stats, mood_score)
	var warn: bool = _status_is_warn(stats, mood_score)
	return {"headline": headline, "detail": detail, "warn": warn}


static func tank_status_footer(stats: Dictionary, _mood_score: float) -> String:
	# One actionable line the chip bar doesn't spell out. Empty → show control hints.
	if float(stats.get("dissolved_o2", 1.0)) < 0.45:
		return "Raise aeration or trim surface floaters blocking gas exchange"
	if float(stats.get("ammonia", 0.0)) >= 0.22:
		return "Ease feeding — bacteria and plants need time to clear ammonia"
	if float(stats.get("nitrite", 0.0)) >= 0.18:
		return "Mid-cycle nitrite — usually brief; avoid heavy feeding"
	if float(stats.get("fish_stocking_ratio", 0.0)) > 1.08:
		return "Stocking above capacity — expect crowding and O₂ drain"
	if not not stats.get("is_saltwater", false):
		if float(stats.get("reef_bleach_level", 0.0)) >= 0.3:
			return "Corals bleaching — lower warmth or check alkalinity"
		if float(stats.get("alkalinity_proxy", 8.0)) < 7.0:
			return "Reef alkalinity soft — buffer may need attention"
	var tip: String = _status_action_tip(stats)
	if tip != "":
		return tip
	var mode: String = String(stats.get("hud_mode", ""))
	if mode == "cycle":
		var bac: int = int(round(float(stats.get("bacteria_colony", 0.0)) * 100.0))
		if bac < 40:
			return "Cycle boot-up — bacteria at %d%%, light feeding only" % bac
	return ""


static func _status_headline(stats: Dictionary) -> String:
	var parts: Array[String] = []
	var day: String = String(stats.get("sim_day_label", ""))
	if day != "":
		parts.append(day)
	if stats.has("day_phase"):
		var phase: String = day_phase_label(float(stats.get("day_phase", 0.25)))
		# Skip "day" — "Day 15 · day" reads as a bug next to the sim-day label.
		if phase != "day":
			parts.append(phase)
	if not not stats.get("is_saltwater", false):
		parts.append("O₂ %d%%" % int(round(float(stats.get("dissolved_o2", 0.0)) * 100.0)))
		parts.append("warmth %d%%" % int(round(float(stats.get("effective_warmth", 0.55)) * 100.0)))
		parts.append("alk %.1f" % float(stats.get("alkalinity_proxy", 8.0)))
		var bleach: float = float(stats.get("reef_bleach_level", 0.0))
		if bleach >= 0.18:
			parts.append("bleach %d%%" % int(round(bleach * 100.0)))
		return " · ".join(parts)
	var mode: String = String(stats.get("hud_mode", "established"))
	var cycle: String = String(stats.get("cycle_label", ""))
	if mode == "cycle" and cycle != "":
		parts.append(cycle)
	elif mode == "growth" and cycle != "":
		parts.append(cycle)
	parts.append("O₂ %d%%" % int(round(float(stats.get("dissolved_o2", 1.0)) * 100.0)))
	var nh3: float = float(stats.get("ammonia", 0.0))
	var no2: float = float(stats.get("nitrite", 0.0))
	if nh3 >= 0.15:
		parts.append("NH₃ %.2f" % nh3)
	elif no2 >= 0.12:
		parts.append("NO₂ %.2f" % no2)
	else:
		parts.append("stable %d%%" % int(round(clampf(float(stats.get("stability", 1.0)), 0.0, 1.0) * 100.0)))
	return " · ".join(parts)


static func _status_population_line(stats: Dictionary) -> String:
	var fish: int = int(stats.get("fish_total", 0))
	var shrimp: int = int(stats.get("shrimp_total", 0))
	var snails: int = int(stats.get("snails_total", 0))
	var plants: int = int(stats.get("plants_alive", 0))
	var cap: int = int(stats.get("fish_carrying_capacity", 0))
	var ratio: float = float(stats.get("fish_stocking_ratio", 0.0))
	var bits: Array[String] = []
	if fish > 0:
		if cap > 0:
			var fish_bit: String = "%d/%d fish" % [fish, cap]
			if ratio > 1.05:
				fish_bit += " · over cap"
			bits.append(fish_bit)
		else:
			bits.append("%d fish" % fish)
	if shrimp > 0:
		bits.append("%d shrimp" % shrimp)
	if snails > 0:
		bits.append("%d snails" % snails)
	if plants > 0:
		bits.append("%d plants" % plants)
	return " · ".join(bits)


static func _status_detail(stats: Dictionary, _mood_score: float) -> String:
	var parts: Array[String] = []
	if not not stats.get("is_saltwater", false):
		var pop: String = _status_population_line(stats)
		if pop != "":
			parts.append(pop)
		var bleach: float = float(stats.get("reef_bleach_level", 0.0))
		if bleach >= 0.35:
			parts.append("corals bleaching — lower warmth or boost O₂")
		elif float(stats.get("dissolved_o2", 1.0)) < 0.5:
			parts.append("low O₂ — fish may gulp at the surface")
		elif float(stats.get("alkalinity_proxy", 8.0)) < 7.2:
			parts.append("alkalinity soft — reef chemistry drifting")
	else:
		var pop2: String = _status_population_line(stats)
		if pop2 != "":
			parts.append(pop2)
	var tip: String = _status_action_tip(stats)
	if tip != "":
		parts.append(tip)
	if parts.is_empty():
		return "tap water chip for chemistry"
	return " · ".join(parts)


static func _status_action_tip(stats: Dictionary) -> String:
	if float(stats.get("filter_clog", 0.0)) > 0.42:
		return "filter flow dropping — rinse soon"
	if int(stats.get("algae_clusters", 0)) > 18:
		return "algae bloom — snails or less light help"
	if int(stats.get("waste_particles", 0)) > 28:
		return "mulm building — cleanup crew busy"
	if float(stats.get("nitrate", 0.0)) > 40.0:
		return "nitrate high — plants or a water change"
	var mode: String = String(stats.get("hud_mode", ""))
	if mode == "cycle":
		var bac: int = int(round(float(stats.get("bacteria_colony", 0.0)) * 100.0))
		if bac < 45:
			return "cycle boot-up — bacteria at %d%%" % bac
	return ""


static func _status_is_warn(stats: Dictionary, mood_score: float) -> bool:
	if mood_score < 0.32:
		return true
	if float(stats.get("dissolved_o2", 1.0)) < 0.5:
		return true
	if float(stats.get("ammonia", 0.0)) >= 0.25:
		return true
	if float(stats.get("nitrite", 0.0)) >= 0.22:
		return true
	if float(stats.get("reef_bleach_level", 0.0)) >= 0.3:
		return true
	return false



static func chemistry_row(key: String, value: float, _stats: Dictionary) -> Dictionary:
	# Returns {text, tint} tint: 0 green, 1 amber, 2 red
	match key:
		"o2":
			var pct: int = int(round(value * 100.0))
			var tint: int = 0 if pct >= 50 else (1 if pct >= 30 else 2)
			return {
				"text": "O₂: %d%% — %s (safe ≥ 50%%)" % [
					pct,
					"good" if tint == 0 else ("low" if tint == 1 else "critical"),
				],
				"tint": tint,
			}
		"nh3":
			var tint2: int = 0 if value < 0.15 else (1 if value < 0.28 else 2)
			return {
				"text": "NH₃: %.2f — %s" % [
					value,
					"trace" if tint2 == 0 else ("elevated, mildly toxic" if tint2 == 1 else "toxic — cycle or plants needed"),
				],
				"tint": tint2,
			}
		"no2":
			var tint3: int = 0 if value < 0.12 else (1 if value < 0.22 else 2)
			return {
				"text": "NO₂: %.2f — %s" % [
					value,
					"safe" if tint3 == 0 else ("spiking — bacteria catching up" if tint3 == 1 else "dangerous"),
				],
				"tint": tint3,
			}
		"no3":
			var tint4: int = 0 if value < 25.0 else (1 if value < 50.0 else 2)
			return {
				"text": "NO₃: %.2f — %s (plants use this)" % [
					value,
					"fine" if tint4 == 0 else ("high" if tint4 == 1 else "very high"),
				],
				"tint": tint4,
			}
		"stability":
			var pct_s: int = int(round(clampf(value, 0.0, 1.0) * 100.0))
			var tint5: int = 0 if pct_s >= 70 else (1 if pct_s >= 45 else 2)
			return {
				"text": "Stability: %d%% — %s (rises as the tank matures)" % [
					pct_s,
					"serene" if tint5 == 0 else ("finding balance" if tint5 == 1 else "unsettled"),
				],
				"tint": tint5,
			}
		_:
			return {"text": "%s: %.2f" % [key, value], "tint": 0}


static func water_detail_lines(stats: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	var day: String = String(stats.get("sim_day_label", ""))
	if not not stats.get("is_saltwater", false):
		if not day.is_empty():
			lines.append("%s · reef" % day)
		var wrow: Dictionary = chemistry_row("o2", float(stats.get("dissolved_o2", 0.0)), stats)
		lines.append(_tint_prefix(int(wrow.tint)) + String(wrow.text))
		lines.append("Warmth: %d%% · Alk proxy: %.1f" % [
			int(round(float(stats.get("effective_warmth", 0.55)) * 100.0)),
			float(stats.get("alkalinity_proxy", 8.0)),
		])
		return lines
	if not day.is_empty():
		lines.append("%s · %s" % [day, String(stats.get("cycle_label", "—"))])
	for key in ["o2", "nh3", "no2", "no3"]:
		var val: float = float(stats.get(
			{"o2": "dissolved_o2", "nh3": "ammonia", "no2": "nitrite", "no3": "nitrate"}[key],
			0.0))
		if key == "o2":
			val = float(stats.get("dissolved_o2", 0.0))
		var row: Dictionary = chemistry_row(key, val, stats)
		lines.append(_tint_prefix(int(row.tint)) + String(row.text))
	lines.append("pH: %.1f · CO₂: %d%% (plants breathe this)" % [
		float(stats.get("ph", 7.2)),
		int(round(float(stats.get("dissolved_co2", 0.4)) * 100.0)),
	])
	lines.append("KH: %.1f · GH: %.1f · Fe: %d%%" % [
		float(stats.get("kh", 4.0)), float(stats.get("gh", 6.0)),
		int(round(float(stats.get("iron", 0.7)) * 100.0)),
	])
	lines.append("Bacteria colony: %d%%" % int(round(float(stats.get("bacteria_colony", 0.0)) * 100.0)))
	var recycle: float = float(stats.get("trophic_recycle_hour_pct", 0.0))
	if recycle > 0.01:
		lines.append("Nutrient recycle (1h): %d%% — waste→life closed loop" % int(round(recycle * 100.0)))
	var stab: Dictionary = chemistry_row("stability", float(stats.get("stability", 1.0)), stats)
	lines.append(_tint_prefix(int(stab.tint)) + String(stab.text))
	if float(stats.get("filter_clog", 0.0)) > 0.35:
		lines.append("⚠ Filter flow dropping — a rinse would help.")
	lines.append("Phase: %s" % String(stats.get("cycle_label", "—")))
	return lines


static func _tint_prefix(tint: int) -> String:
	match tint:
		2: return "🔴 "
		1: return "🟡 "
		_: return "🟢 "


static func alert_guidance(kind: String, _stats: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	match kind:
		"low_o2":
			lines.append("What's happening: dissolved oxygen is critically low.")
			lines.append("Look for: fish gulping at the surface.")
			lines.append("Helps: increase aeration, reduce feeding, trim blocking floaters.")
		"ammonia":
			lines.append("What's happening: ammonia is elevated.")
			lines.append("Look for: gill flush, listless fish, hiding.")
			lines.append("Helps: keep plants growing; avoid overfeeding; cycle completes in ~1–2 weeks.")
		"nitrite":
			lines.append("What's happening: nitrite spike — mid-cycle.")
			lines.append("Look for: clamped fins, erratic swimming.")
			lines.append("Helps: established plants accelerate bacteria; skip extra feeding.")
		"algae":
			lines.append("What's happening: algae clusters are high.")
			lines.append("Look for: green haze on glass and stones.")
			lines.append("Helps: snails/shrimp graze; balance light vs plants.")
		"waste":
			lines.append("What's happening: detritus is building up.")
			lines.append("Look for: mulm on substrate, cloudy patches.")
			lines.append("Helps: cleanup crew, gentle substrate stir, water change.")
		"bleach":
			lines.append("What's happening: corals are bleaching — symbiotic algae leaving.")
			lines.append("Look for: pale coral tissue, retracted polyps.")
			lines.append("Helps: lower warmth, check O₂ and alkalinity.")
		_:
			lines.append("No active alert — tap water chip for chemistry detail.")
	return lines


static func cycle_banner_text(stats: Dictionary) -> String:
	var day: int = int(stats.get("sim_day", 1))
	var phase: String = String(stats.get("cycle_label", "cycling"))
	return "Cycling: ammonia → nitrite → safe · Day %d of ~14 · %s" % [day, phase]


static func fresh_cycle_intro() -> String:
	return (
		"Your tank is cycling — like a new pond finding its balance. "
		+ "You'll see an ammonia bump for a few days. It's normal. "
		+ "Plants and bacteria will handle it."
	)


static func equilibrium_tooltip() -> String:
	return "Tanks self-balance — this is roughly how many residents it wants once mature."


static func scenario_whats_in_tank(config: Dictionary) -> String:
	var parts: Array[String] = []
	var sub: String = String(config.get("substrate_type", ""))
	if sub != "":
		parts.append(SUBSTRATE_BLURBS.get(sub, sub))
	var aer: String = String(config.get("aeration_type", ""))
	if aer != "":
		parts.append(AERATION_BLURBS.get(aer, aer))
	var co2: float = float(config.get("co2_level", 0.0))
	if co2 > 0.05:
		parts.append("CO₂ injection %.0f%% — faster plant growth" % int(round(co2 * 100.0)))
	else:
		parts.append("Low-tech — no injected CO₂")
	var cyc: String = String(config.get("cycle_start_mode", "established"))
	if cyc == "fresh":
		parts.append("Starts cycling — you'll manage an ammonia spike")
	else:
		parts.append("Established cycle — stable from day one")
	return " · ".join(parts)


static func wildcard_summary(config: Dictionary) -> String:
	return "%s · %s · %s · %s" % [
		String(config.get("tank_shape", "box")).capitalize(),
		String(config.get("substrate_type", "?")).replace("_", " "),
		String(config.get("tank_preset", "?")).replace("_", " "),
		String(config.get("aeration_type", "?")),
	]


static func walstad_one_pager() -> String:
	return (
		"A Walstad tank is a small complete world: fish waste feeds bacteria and plants, "
		+ "plants make oxygen and absorb nitrate, detritus becomes food again. "
		+ "You nudge it — light, feeding, trimming — but the loop keeps itself alive. "
		+ "That's the whole game."
	)


static func search_help(query: String) -> PackedStringArray:
	var q: String = query.to_lower().strip_edges()
	if q.is_empty():
		return PackedStringArray()
	var hits: PackedStringArray = []
	for term in GLOSSARY.keys():
		if q in String(term).to_lower() or q in String(GLOSSARY[term]).to_lower():
			hits.append("%s — %s" % [term, GLOSSARY[term]])
	for row in TANK_TELLS:
		var cue: String = String(row.cue)
		if q in cue.to_lower() or q in String(row.meaning).to_lower():
			hits.append("%s → %s" % [cue, row.meaning])
	for line in cheat_sheet_lines(false):
		if q in line.to_lower():
			hits.append(line)
	return hits


static func affect_label(creature: Node) -> String:
	if creature == null or not is_instance_valid(creature):
		return ""
	if creature is Fish:
		var f: Fish = creature as Fish
		var stress: float = float(f.stress) if f.get("stress") != null else 0.0
		var hunger: float = float(f.hunger) if f.get("hunger") != null else 0.0
		var rest_debt: float = float(f._rest_debt) if f.get("_rest_debt") != null else 0.0
		if stress > 0.65:
			if rest_debt > 0.5:
				return "Tired (rest debt)"
			return "Stressed (crowded)" if stress > 0.8 else "Stressed"
		if hunger > 0.7:
			return "Hungry"
		var mood_val: float = float(f.mood) if f.get("mood") != null else 0.0
		if mood_val > 0.3:
			return "Content"
		return "Calm"
	return "Calm"


static func history_healthy_band(hist_key: String) -> Vector2:
	match hist_key:
		"dissolved_o2":
			return Vector2(0.5, 1.0)
		"fish_total", "plants_alive":
			return Vector2(0.0, -1.0) # no band
		_:
			return Vector2(-1.0, -1.0)


static func global_pref(key: String, default_val: Variant = false) -> Variant:
	var file := ConfigFile.new()
	if file.load(GLOBAL_PREFS) == OK:
		return file.get_value("onboarding", key, default_val)
	return default_val


static func set_global_pref(key: String, value: Variant) -> void:
	var file := ConfigFile.new()
	file.load(GLOBAL_PREFS)
	file.set_value("onboarding", key, value)
	file.save(GLOBAL_PREFS)


static func mark_term_seen(term: String) -> void:
	var seen: Dictionary = global_pref("seen_terms", {})
	seen[term] = true
	set_global_pref("seen_terms", seen)


static func term_seen(term: String) -> bool:
	var seen: Dictionary = global_pref("seen_terms", {})
	return bool(seen.get(term, false))
