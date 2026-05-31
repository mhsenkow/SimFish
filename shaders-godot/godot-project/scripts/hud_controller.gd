# HUD chip helpers for water chemistry / cycle display.
class_name HudController
extends RefCounted

static func water_chip_subtitle(stats: Dictionary) -> String:
	var o2: float = float(stats.get("dissolved_o2", 1.0))
	var o2_pct: int = int(round(o2 * 100.0))
	var cycle: String = String(stats.get("cycle_label", ""))
	if cycle.is_empty():
		return "O₂ %d%%" % o2_pct
	return "O₂ %d%% · %s" % [o2_pct, cycle]


static func water_detail_lines(stats: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	lines.append("O₂: %d%%" % int(round(float(stats.get("dissolved_o2", 0.0)) * 100.0)))
	lines.append("NH₃: %.2f" % float(stats.get("ammonia", 0.0)))
	lines.append("NO₂: %.2f" % float(stats.get("nitrite", 0.0)))
	lines.append("NO₃: %.2f" % float(stats.get("nitrate", 0.0)))
	lines.append("Phase: %s" % String(stats.get("cycle_label", "—")))
	return lines
