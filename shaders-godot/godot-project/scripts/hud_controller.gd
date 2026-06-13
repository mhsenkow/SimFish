# HUD chip helpers for water chemistry / cycle display.
class_name HudController
extends RefCounted


static func water_chip_primary(stats: Dictionary) -> String:
	var mode: String = String(stats.get("hud_mode", "established"))
	if mode == "reef" or not not stats.get("is_saltwater", false):
		var warmth: float = float(stats.get("effective_warmth", 0.55))
		return "warmth %d%%" % int(round(warmth * 100.0))
	var cycle: String = String(stats.get("cycle_label", ""))
	if mode == "cycle" and not cycle.is_empty():
		return cycle.capitalize()
	var o2: float = float(stats.get("dissolved_o2", 1.0))
	return "%d%%" % int(round(o2 * 100.0))


static func water_chip_subtitle(stats: Dictionary) -> String:
	var o2: float = float(stats.get("dissolved_o2", 1.0))
	var o2_pct: int = int(round(o2 * 100.0))
	var mode: String = String(stats.get("hud_mode", "established"))
	if mode == "reef" or not not stats.get("is_saltwater", false):
		var alk: float = float(stats.get("alkalinity_proxy", 8.0))
		return "O₂ %d%% · alk %.1f" % [o2_pct, alk]
	var cycle: String = String(stats.get("cycle_label", ""))
	var day: String = String(stats.get("sim_day_label", ""))
	if mode == "cycle":
		if day.is_empty():
			return "O₂ %d%%" % o2_pct
		return "%s · O₂ %d%%" % [day, o2_pct]
	if cycle.is_empty():
		return "O₂ %d%%" % o2_pct
	return "O₂ %d%% · %s" % [o2_pct, cycle]


static func water_chip_warn(stats: Dictionary) -> bool:
	var o2: float = float(stats.get("dissolved_o2", 1.0))
	if not not stats.get("is_saltwater", false):
		return o2 < 0.50 or float(stats.get("alkalinity_proxy", 8.0)) < 7.0
	var nitrite: float = float(stats.get("nitrite", 0.0))
	var ammonia: float = float(stats.get("ammonia", 0.0))
	return o2 < 0.50 or nitrite >= 0.22 or ammonia >= 0.28


static func flora_chip_subtitle(stats: Dictionary) -> String:
	var biomass: int = int(stats.get("plant_total_biomass", 0))
	var bloom: float = float(stats.get("bloom_intensity", 0.0))
	var floater: float = float(stats.get("floater_coverage", 0.0))
	var base: String = "biomass %d" % biomass
	if bloom >= 0.35:
		base += " · bloom"
	base += WorldFloaterManager.flora_coverage_sublabel(floater)
	return base


static func alert_guidance_lines(stats: Dictionary, kind: String) -> PackedStringArray:
	var lines: PackedStringArray = []
	match kind:
		"bleach":
			lines.append("Corals are bleaching — zooxanthellae leaving the tissue.")
			lines.append("Check warmth (lights panel) and O₂. Heater off lowers heat near the rod.")
			lines.append("Alk proxy: %.1f · warmth %d%%" % [
				float(stats.get("alkalinity_proxy", 8.0)),
				int(round(float(stats.get("effective_warmth", 0.55)) * 100.0)),
			])
		"low_o2":
			lines.append("Dissolved O₂ is critically low.")
			lines.append("Increase aeration or reduce stocking; floaters and plants help during daylight.")
		"ammonia":
			lines.append("Ammonia spike — normal early in a Walstad cycle.")
			lines.append("Keep plants growing; trim floaters if bloom murk is shading them.")
			var fc: float = float(stats.get("floater_coverage", 0.0))
			if fc > 0.15:
				lines.append("Surface floaters at %d%% — may be blocking light below." % int(round(fc * 100.0)))
		"nitrite":
			lines.append("Nitrite spike — bacteria colony catching up.")
			lines.append("Avoid overfeeding; established plants accelerate the cycle.")
		"algae":
			lines.append("Algae clusters high — grazers and floaters can thin the bloom.")
		"waste":
			lines.append("Detritus building up — snails, shrimp, and corys recycle mulm.")
		_:
			lines.append("No active alert — tap water chip for chemistry detail.")
	return lines


static func water_detail_lines(stats: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	var day: String = String(stats.get("sim_day_label", ""))
	if not not stats.get("is_saltwater", false):
		if not day.is_empty():
			lines.append("%s · reef" % day)
		lines.append("Warmth: %d%%" % int(round(float(stats.get("effective_warmth", 0.55)) * 100.0)))
		lines.append("O₂: %d%%" % int(round(float(stats.get("dissolved_o2", 0.0)) * 100.0)))
		lines.append("Alk proxy: %.1f" % float(stats.get("alkalinity_proxy", 8.0)))
		lines.append("Nutrients: %.2f" % float(stats.get("reef_nutrients", 0.0)))
		return lines
	if not day.is_empty():
		lines.append("%s · %s" % [day, String(stats.get("cycle_label", "—"))])
	lines.append("O₂: %d%%" % int(round(float(stats.get("dissolved_o2", 0.0)) * 100.0)))
	lines.append("NH₃: %.2f" % float(stats.get("ammonia", 0.0)))
	lines.append("NO₂: %.2f" % float(stats.get("nitrite", 0.0)))
	lines.append("NO₃: %.2f" % float(stats.get("nitrate", 0.0)))
	lines.append("Bacteria: %d%%" % int(round(float(stats.get("bacteria_colony", 0.0)) * 100.0)))
	var recycle: float = float(stats.get("trophic_recycle_hour_pct", 0.0))
	if recycle > 0.01:
		lines.append("Nutrient recycle (1h): %d%%" % int(round(recycle * 100.0)))
	lines.append("Phase: %s" % String(stats.get("cycle_label", "—")))
	return lines
