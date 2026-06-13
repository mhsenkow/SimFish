# Environmental selection pressure — nudges offspring genomes toward traits that
# fit the current tank (light, warmth, O₂, substrate richness).
#
# Called at breeding / seeding time so lineages adapt to how the player runs
# their tank, on top of random mutation.

extends RefCounted
class_name EvolutionPressure


static func sample_from_sim(sim: Node, pos: Variant = null) -> Dictionary:
	var p: Dictionary = {
		"light": 0.5,
		"warmth": 0.6,
		"substrate": 0.5,
		"o2": 0.55,
		"saltwater": false,
		"cover": 0.0,
		"edge": 0.5,
		"depth": 0.5,
		"substrate_local": 0.5,
	}
	var cfg: Node = null
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		cfg = (main_loop as SceneTree).root.get_node_or_null("/root/TankConfig")
	if cfg != null:
		var light_v: Variant = cfg.get("light_energy")
		var warmth_v: Variant = cfg.get("light_warmth")
		p.light = clampf(float(light_v) if light_v != null else 0.5, 0.0, 1.0)
		p.warmth = clampf(float(warmth_v) if warmth_v != null else 0.6, 0.0, 1.0)
		var prof_v: Variant = cfg.call("current_substrate_profile")
		if prof_v is Dictionary:
			var prof: Dictionary = prof_v
			var baseline: float = float(prof.get("nutrient_baseline", 0.3))
			p.substrate = clampf(baseline / 0.85, 0.0, 1.0)
			p.saltwater = not not prof.get("is_saltwater", false)
	if sim != null and sim.get("dissolved_o2") != null:
		p.o2 = clampf(float(sim.dissolved_o2), 0.0, 1.0)
	if sim != null and pos is Vector3:
		var world: Node = sim.get_parent()
		if world != null and world.has_method("habitat_profile_at"):
			var h: Variant = world.habitat_profile_at(pos)
			if h is Dictionary:
				var habitat_d: Dictionary = h
				p.cover = clampf(float(habitat_d.get("cover", p.cover)), 0.0, 1.0)
				p.edge = clampf(float(habitat_d.get("edge", p.edge)), 0.0, 1.0)
				p.depth = clampf(float(habitat_d.get("depth", p.depth)), 0.0, 1.0)
				p.substrate_local = clampf(
					float(habitat_d.get("substrate_local", p.substrate_local)), 0.0, 1.0)
	return p


static func _env_tint(pressure: Dictionary) -> Color:
	var light: float = float(pressure.get("light", 0.5))
	var warmth: float = float(pressure.get("warmth", 0.5))
	var salt: bool = not not pressure.get("saltwater", false)
	if salt:
		return Color(0.35 + warmth * 0.2, 0.55 + light * 0.15, 0.75 + light * 0.2)
	return Color(0.45 + warmth * 0.35, 0.38 + light * 0.28, 0.18 + (1.0 - warmth) * 0.12)


static func nudge_color(c: Color, pressure: Dictionary, strength: float = 0.08) -> Color:
	return c.lerp(_env_tint(pressure), strength)


static func apply_fish_offspring(g: Dictionary, pressure: Dictionary) -> void:
	var light: float = float(pressure.get("light", 0.5))
	var sub: float = float(pressure.get("substrate", 0.5))
	var o2: float = float(pressure.get("o2", 0.55))
	var cover: float = float(pressure.get("cover", 0.0))
	var edge: float = float(pressure.get("edge", 0.5))
	var depth: float = float(pressure.get("depth", 0.5))
	var strength: float = 0.07 + light * 0.04

	if g.get("base_color") is Color:
		g["base_color"] = nudge_color(g["base_color"], pressure, strength)
	if g.get("accent_color") is Color:
		g["accent_color"] = nudge_color(g["accent_color"], pressure, strength * 0.7)
	if g.get("tail_color") is Color:
		g["tail_color"] = nudge_color(g["tail_color"], pressure, strength * 0.5)

	if g.has("preferred_y") and o2 < 0.48:
		g["preferred_y"] = float(g["preferred_y"]) + (0.48 - o2) * 1.2
	if g.has("herbivory"):
		g["herbivory"] = clampf(float(g["herbivory"]) + (sub - 0.5) * 0.12, 0.0, 1.0)
	if g.has("algae_grazer") and sub > 0.62 and randf() < 0.12:
		g["algae_grazer"] = true
	if light > 0.72 and g.has("preferred_y"):
		g["preferred_y"] = float(g["preferred_y"]) + 0.08
	# Hardscape niches: high-cover zones favor armored, benthic, camouflaged
	# body plans; open zones favor streamlined schooling forms.
	if cover > 0.45:
		if g.has("armor_plates") and randf() < cover * 0.25:
			g["armor_plates"] = true
		if g.has("has_barbels") and randf() < cover * 0.20:
			g["has_barbels"] = true
		if g.has("jaw_claw_size"):
			g["jaw_claw_size"] = clampf(
				float(g["jaw_claw_size"]) + cover * 0.14 + randf_range(-0.04, 0.06), 0.0, 1.2)
		if g.has("mouth_orientation") and randf() < 0.15:
			g["mouth_orientation"] = 1
		if g.has("schooling_strength"):
			g["schooling_strength"] = clampf(
				float(g["schooling_strength"]) - cover * 0.08, 0.35, 2.0)
	if edge < 0.35:
		if g.has("body_shape") and randf() < 0.12:
			g["body_shape"] = "fusiform"
		if g.has("schooling_strength"):
			g["schooling_strength"] = clampf(
				float(g["schooling_strength"]) + (0.35 - edge) * 0.25, 0.35, 2.0)
	if depth > 0.68 and g.has("mouth_orientation"):
		g["mouth_orientation"] = 1 if randf() < 0.65 else int(g["mouth_orientation"])
	elif depth < 0.32 and g.has("mouth_orientation"):
		g["mouth_orientation"] = -1 if randf() < 0.45 else int(g["mouth_orientation"])
	# Benthic + sheltered niches favor flattened sucker-bellied bottom dwellers
	# (hillstream loaches, plecos, gobies), with barbels for substrate sifting.
	if depth > 0.62 and cover > 0.4:
		if g.has("body_shape") and randf() < 0.10:
			g["body_shape"] = "depressed"
		if g.has("ventral_sucker") and randf() < cover * 0.3:
			g["ventral_sucker"] = true
		if g.has("body_width_factor"):
			g["body_width_factor"] = clampf(
				float(g["body_width_factor"]) + cover * 0.12, 0.5, 1.8)
		if g.has("barbel_count") and randf() < 0.2:
			g["barbel_count"] = clampi(int(g["barbel_count"]) + 2, 0, 8)
			g["has_barbels"] = true
	# Saltwater perciforms overwhelmingly carry the spiny + soft two-dorsal.
	if bool(pressure.get("saltwater", false)) and g.has("second_dorsal") and randf() < 0.25:
		g["second_dorsal"] = true
	if g.has("size_potential"):
		g["size_potential"] = clampf(
			float(g["size_potential"]) + (0.5 - edge) * 0.08 + (sub - 0.5) * 0.10
				+ randf_range(-0.04, 0.05),
			0.6, 2.4)


static func apply_shrimp_offspring(g: Dictionary, pressure: Dictionary) -> void:
	var strength: float = 0.09
	var cover: float = float(pressure.get("cover", 0.0))
	var edge: float = float(pressure.get("edge", 0.5))
	if g.get("base_color") is Color:
		g["base_color"] = nudge_color(g["base_color"], pressure, strength)
	if g.get("accent_color") is Color:
		g["accent_color"] = nudge_color(g["accent_color"], pressure, strength * 0.6)
	var sub: float = float(pressure.get("substrate", 0.5))
	var local_sub: float = float(pressure.get("substrate_local", sub))
	if g.has("max_speed"):
		g["max_speed"] = clampf(float(g["max_speed"])
			+ (local_sub - 0.5) * 0.08 + (0.45 - cover) * 0.03 + (0.45 - edge) * 0.02,
			0.4, 1.4)
	if g.has("claw_size"):
		g["claw_size"] = clampf(
			float(g["claw_size"]) + cover * 0.16 + local_sub * 0.06 + randf_range(-0.05, 0.08),
			0.0, 1.2)
	if g.has("body_length_factor"):
		g["body_length_factor"] = clampf(
			float(g["body_length_factor"]) + (0.5 - edge) * 0.12 + randf_range(-0.07, 0.09),
			0.75, 1.7)
	# Expanded crustacean architecture pressure. Sheltered saltwater hardscape
	# occasionally pushes a lineage toward crab / mantis body plans; open, low-
	# cover water favors filter-feeding fans. Rostrum + eye-stalks drift gently.
	var salt: bool = bool(pressure.get("saltwater", false))
	if g.has("body_shape") and salt and cover > 0.45 and randf() < 0.06:
		g["body_shape"] = "crab" if randf() < 0.6 else "mantis"
	if g.has("filter_fans") and cover < 0.3 and randf() < 0.08:
		g["filter_fans"] = true
	if g.has("rostrum_length"):
		g["rostrum_length"] = clampf(
			float(g["rostrum_length"]) + randf_range(-0.05, 0.08), 0.0, 1.5)
	if g.has("eye_stalk_length"):
		g["eye_stalk_length"] = clampf(
			float(g["eye_stalk_length"]) + (cover - 0.5) * 0.06, 0.0, 1.0)
	# Aposematism vs camouflage. Toxic / well-armed lineages evolve brighter,
	# bolder warning markings so predators learn to leave them alone; cryptic
	# lineages in dense cover instead drift toward low-contrast, muted camo. This
	# couples shrimp appearance to their own defenses and to the predators around
	# them (fish only prey on shrimp below a toxin threshold).
	var toxin: float = float(g.get("toxin_level", 0.0))
	var spines: float = float(g.get("defense_spines", 0.0))
	var warning: float = clampf(maxf(toxin, spines * 0.6), 0.0, 1.0)
	if g.has("pattern_intensity"):
		g["pattern_intensity"] = clampf(
			float(g["pattern_intensity"]) + warning * 0.18 - cover * 0.12, 0.0, 1.0)
	if g.has("pattern_density"):
		g["pattern_density"] = clampf(
			float(g["pattern_density"]) + warning * 0.15 - cover * 0.08, 0.0, 1.0)
	if warning > 0.45 and g.get("accent_color") is Color:
		var warn_hue: Color = (Color(1.0, 0.78, 0.1) if randf() < 0.6
			else Color(0.95, 0.2, 0.12))
		g["accent_color"] = (g["accent_color"] as Color).lerp(warn_hue, 0.12 + warning * 0.12)
	elif cover > 0.5 and g.get("base_color") is Color:
		g["base_color"] = (g["base_color"] as Color).lerp(
			Color(0.32, 0.30, 0.22), 0.08 + cover * 0.06)


static func apply_snail_shell_color(c: Color, pressure: Dictionary) -> Color:
	var warmth: float = float(pressure.get("warmth", 0.5))
	var sub: float = float(pressure.get("substrate", 0.5))
	var out: Color = nudge_color(c, pressure, 0.06 + warmth * 0.04)
	if sub > 0.55:
		out = out.lerp(Color(0.55, 0.48, 0.32), 0.05)
	return out


static func apply_plant_ramp(ramp: Array, pressure: Dictionary) -> void:
	if ramp.size() != 6:
		return
	var light: float = float(pressure.get("light", 0.5))
	var sub: float = float(pressure.get("substrate", 0.5))
	var cover: float = float(pressure.get("cover", 0.0))
	var local_sub: float = float(pressure.get("substrate_local", sub))
	var green_push: Color = Color(0.25, 0.55 + light * 0.2, 0.18)
	var rich_push: Color = Color(0.18, 0.48 + local_sub * 0.25, 0.14)
	var shade_push: Color = Color(0.14, 0.36, 0.20)
	for i in range(maxi(2, ramp.size() - 3), ramp.size()):
		if ramp[i] is Color:
			var c: Color = ramp[i]
			c = c.lerp(green_push, 0.04 * light)
			c = c.lerp(rich_push, 0.03 * local_sub)
			if cover > 0.35:
				c = c.lerp(shade_push, 0.02 * cover)
			ramp[i] = c


static func apply_plant_seed_config(cfg: Dictionary, pressure: Dictionary) -> void:
	if cfg.is_empty():
		return
	var cover: float = float(pressure.get("cover", 0.0))
	var edge: float = float(pressure.get("edge", 0.5))
	var light: float = float(pressure.get("light", 0.5))
	var local_sub: float = float(pressure.get("substrate_local", 0.5))
	if cfg.has("growth_rate"):
		cfg["growth_rate"] = clampf(float(cfg["growth_rate"])
			+ (local_sub - 0.5) * 0.03 - cover * 0.01, 0.06, 0.42)
	if cfg.has("max_height"):
		cfg["max_height"] = clampi(int(round(float(cfg["max_height"])
			+ (0.5 - edge) * 2.0 + (light - 0.5) * 2.0)), 4, 42)
	if cfg.has("leaf_form") and randf() < 0.20:
		if cover > 0.5:
			cfg["leaf_form"] = "paddle"
		elif edge < 0.35 and light > 0.6:
			cfg["leaf_form"] = "ribbon"
