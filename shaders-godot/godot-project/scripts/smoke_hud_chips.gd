extends SceneTree

# PLAYER_WISH #280 — chip expand strings for mood / water / alert must exist.


func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_hud_chips")
	var stats: Dictionary = {
		"dissolved_o2": 0.82, "ammonia": 0.04, "nitrite": 0.02, "nitrate": 8.0,
		"is_saltwater": false, "cycle_label": "cycled", "sim_day_label": "Day 12",
		"stability": 0.8, "waste_particles": 4, "algae_clusters": 2,
	}
	var mood: String = OnboardingLegibility.mood_driver(stats, 0.8)
	t.check(not mood.is_empty(), "mood expand string exists")
	var water: PackedStringArray = OnboardingLegibility.water_detail_lines(stats)
	t.check(water.size() >= 3, "water expand has chemistry lines")
	var o2_alert: PackedStringArray = OnboardingLegibility.alert_guidance("low_o2", stats)
	t.check(o2_alert.size() >= 1 and String(o2_alert[0]).length() > 8,
		"low-O2 alert expand exists")
	var nh3_alert: PackedStringArray = OnboardingLegibility.alert_guidance("ammonia", stats)
	t.check(nh3_alert.size() >= 1 and String(nh3_alert[0]).length() > 8,
		"ammonia alert expand exists")
	var nit_alert: PackedStringArray = OnboardingLegibility.alert_guidance("nitrite", stats)
	t.check(nit_alert.size() >= 1, "nitrite alert expand exists")
	var nh3: Dictionary = OnboardingLegibility.chemistry_row("nh3", 0.04, stats)
	t.check(String(nh3.get("text", "")).contains("ppm"), "NH₃ row shows ppm")
	var no2: Dictionary = OnboardingLegibility.chemistry_row("no2", 0.05, stats)
	t.check(String(no2.get("text", "")).contains("ppm"), "NO₂ row shows ppm")
	var no3: Dictionary = OnboardingLegibility.chemistry_row("no3", 8.0, stats)
	t.check(String(no3.get("text", "")).contains("ppm"), "NO₃ row shows ppm")
	var o2: Dictionary = OnboardingLegibility.chemistry_row("o2", 0.82, stats)
	t.check(String(o2.get("text", "")).contains("%"), "O₂ row stays percent")
	quit(t.finish())
