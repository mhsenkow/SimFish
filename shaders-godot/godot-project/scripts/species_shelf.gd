# Playable fish people expect to see, in the same genome format as
# TankConfig.SPECIES_LIBRARY. Colour varieties share a morph palette.
# Tanks choose who appears by naming these ids in a preset stocking dict.
extends RefCounted
class_name SpeciesShelf


static func entries() -> Dictionary:
	var out: Dictionary = {}
	_add(out, "black_balloon_molly", "Black balloon molly",
		"Short, round, solid black livebearer. The shop balloon molly.",
		_livebearer(Color8(18, 16, 20), Color8(40, 38, 44), {
			"body_shape": "globiform", "body_depth_factor": 1.46,
			"body_elongation": 0.78, "fin_length_factor": 0.72,
			"dorsal_height_factor": 0.62, "pattern_type": 0, "tail_shape": 1,
			"swim_pattern": "shoal", "adult_voxel_scale": 0.16,
		}))
	_add(out, "gold_balloon_molly", "Gold balloon molly",
		"The same round balloon body in gold.",
		_livebearer(Color8(232, 176, 48), Color8(160, 90, 30), {
			"body_shape": "globiform", "body_depth_factor": 1.42,
			"body_elongation": 0.8, "fin_length_factor": 0.74,
			"dorsal_height_factor": 0.66, "pattern_type": 0, "tail_shape": 1,
			"swim_pattern": "shoal", "adult_voxel_scale": 0.16,
		}))
	_add(out, "sailfin_molly", "Sailfin molly",
		"Silver molly with a tall dorsal sail.",
		_livebearer(Color8(186, 196, 204), Color8(70, 78, 88), {
			"body_depth_factor": 1.08, "body_elongation": 1.05,
			"dorsal_height_factor": 1.72, "finnage": 1.65,
			"fin_length_factor": 1.35, "pattern_type": 0, "tail_shape": 1,
			"swim_pattern": "cruise", "adult_voxel_scale": 0.2,
		}))
	_add(out, "marble_molly", "Marble molly",
		"Black-and-white marbled molly. Colour rolls from the molly palette.",
		_livebearer(Color8(230, 230, 226), Color8(28, 26, 30), {
			"mixed_morphs": true, "morph_palette": "molly",
			"body_depth_factor": 1.12, "body_elongation": 1.02,
			"dorsal_height_factor": 0.95, "pattern_type": 2, "tail_shape": 1,
			"swim_pattern": "shoal", "adult_voxel_scale": 0.18,
		}))
	_add(out, "platy", "Platy",
		"Stocky livebearer. A mixed colony rolls sunset, wag, and mickey-mouse colours.",
		_livebearer(Color8(214, 96, 48), Color8(40, 36, 34), {
			"mixed_morphs": true, "morph_palette": "platy",
			"body_depth_factor": 1.24, "body_elongation": 0.9,
			"dorsal_height_factor": 0.84, "pattern_type": 0, "tail_shape": 1,
			"swim_pattern": "shoal", "adult_voxel_scale": 0.14,
		}))
	_add(out, "sunset_platy", "Sunset platy",
		"Orange-to-yellow platy with a deeper body than a guppy.",
		_livebearer(Color8(240, 120, 36), Color8(255, 196, 64), {
			"body_depth_factor": 1.2, "body_elongation": 0.92,
			"dorsal_height_factor": 0.88, "pattern_type": 4, "tail_shape": 1,
			"swim_pattern": "shoal", "adult_voxel_scale": 0.14,
		}))
	_add(out, "swordtail", "Swordtail",
		"Green swordtail. Males carry a long lower sword.",
		_livebearer(Color8(92, 168, 86), Color8(210, 48, 42), {
			"body_elongation": 1.28, "body_depth_factor": 0.96,
			"dorsal_height_factor": 0.78, "fin_length_factor": 1.7,
			"finnage": 1.45, "pattern_type": 4, "tail_shape": 0,
			"swim_pattern": "cruise", "adult_voxel_scale": 0.18,
			"snout_pointed": true,
		}))
	_add(out, "black_swordtail", "Black swordtail",
		"Solid black swordtail.",
		_livebearer(Color8(22, 20, 24), Color8(48, 44, 50), {
			"body_elongation": 1.24, "body_depth_factor": 0.98,
			"dorsal_height_factor": 0.8, "fin_length_factor": 1.55,
			"pattern_type": 0, "tail_shape": 0, "swim_pattern": "cruise",
			"adult_voxel_scale": 0.18, "snout_pointed": true,
		}))
	_add(out, "mosquito_fish", "Mosquitofish",
		"Slim, plain livebearer. Smaller and duller than a guppy.",
		_livebearer(Color8(150, 148, 130), Color8(90, 88, 70), {
			"body_elongation": 1.36, "body_depth_factor": 0.7,
			"dorsal_height_factor": 0.55, "fin_length_factor": 0.7,
			"pattern_type": 0, "tail_shape": 0, "swim_pattern": "shoal",
			"adult_voxel_scale": 0.09, "dimorphic": false,
		}))
	_cichlid(out, "ram", "Ram cichlid", "Small, round, gold ram with a dark flank spot.",
		Color8(214, 170, 64), Color8(40, 48, 70), 0.15, 1.36, 0.91, 9, 1.05)
	_cichlid(out, "apisto", "Apistogramma", "Dwarf cichlid. A pair guards a cave.",
		Color8(186, 140, 70), Color8(40, 36, 32), 0.14, 1.28, 0.94, 3, 0.98)
	_cichlid(out, "krib", "Kribensis", "Red-bellied krib. Compact and territorial.",
		Color8(120, 90, 60), Color8(190, 40, 48), 0.16, 1.32, 0.96, 2, 1.12)
	_cichlid(out, "convict", "Convict cichlid", "Black bars on a pale body. Fierce parents.",
		Color8(214, 206, 190), Color8(24, 22, 26), 0.18, 1.22, 1.0, 3, 0.9)
	_cichlid(out, "firemouth", "Firemouth cichlid", "Grey body, red throat and belly.",
		Color8(150, 140, 128), Color8(200, 40, 36), 0.2, 1.26, 1.02, 0, 1.18)
	_cichlid(out, "jewel", "Jewel cichlid", "Spangled flanks and a red belly.",
		Color8(70, 110, 90), Color8(190, 48, 42), 0.2, 1.4, 0.98, 9, 1.22)
	_cichlid(out, "oscar", "Oscar", "Large, slow, spotted centerpiece. One to a tank.",
		Color8(120, 78, 48), Color8(40, 32, 28), 0.42, 1.62, 0.9, 2, 1.35)
	_cichlid(out, "discus", "Discus", "Round, tall, slow. A planted discus group.",
		Color8(196, 150, 110), Color8(70, 90, 140), 0.3, 1.92, 0.82, 3, 1.48)
	_cichlid(out, "frontosa", "Frontosa", "Deep-water cichlid with a heavy forehead.",
		Color8(70, 110, 160), Color8(20, 24, 36), 0.28, 1.5, 0.95, 3, 1.28)
	out["frontosa"]["genome"]["nuchal_hump"] = 1.15
	_cichlid(out, "yellow_lab", "Yellow lab", "Solid yellow mbuna.",
		Color8(240, 196, 40), Color8(180, 130, 30), 0.16, 1.16, 1.05, 0, 0.86)
	out["yellow_lab"]["genome"]["body_shape"] = "fusiform"
	out["yellow_lab"]["genome"]["swim_pattern"] = "cruise"
	_cichlid(out, "demasoni", "Demasoni", "Blue-black barred mbuna.",
		Color8(30, 70, 150), Color8(12, 16, 28), 0.13, 1.12, 1.08, 3, 0.82)
	out["demasoni"]["genome"]["body_shape"] = "fusiform"
	_cichlid(out, "acei", "Acei", "Slender blue mbuna that schools more than it fights.",
		Color8(48, 110, 180), Color8(20, 40, 70), 0.16, 0.94, 1.22, 0, 0.74)
	out["acei"]["genome"]["body_shape"] = "fusiform"
	out["acei"]["genome"]["schooling_strength"] = 0.8
	_cichlid(out, "peacock", "Peacock cichlid", "Colourful hap with a mild forehead hump.",
		Color8(40, 120, 170), Color8(220, 80, 40), 0.22, 1.44, 1.0, 9, 1.3)
	out["peacock"]["genome"]["nuchal_hump"] = 0.45
	_schooler(out, "neon_tetra", "Neon tetra", "Slim blue-and-red tetra. Smaller than the cardinal.",
		Color8(180, 30, 40), Color8(40, 160, 220), 0.16, 0.76, 1.18, 4, "school")
	_schooler(out, "black_neon", "Black neon tetra", "A white-gold stripe on a dark body.",
		Color8(36, 40, 48), Color8(220, 200, 120), 0.17, 0.8, 1.12, 4, "school")
	_schooler(out, "lemon_tetra", "Lemon tetra", "Translucent yellow schooler.",
		Color8(230, 210, 80), Color8(180, 150, 40), 0.17, 0.9, 1.08, 0, "school")
	_schooler(out, "glowlight", "Glowlight tetra", "A copper stripe on a clear body.",
		Color8(210, 170, 140), Color8(220, 90, 40), 0.15, 0.74, 1.16, 4, "school")
	_schooler(out, "penguin_tetra", "Penguin tetra", "Silver tetra with a black wedge toward the tail.",
		Color8(190, 196, 200), Color8(20, 22, 28), 0.18, 0.88, 1.1, 3, "school")
	_schooler(out, "congo_tetra", "Congo tetra", "Large iridescent tetra with long fins.",
		Color8(90, 140, 160), Color8(180, 80, 70), 0.24, 1.06, 1.32, 0, "cruise")
	out["congo_tetra"]["genome"]["finnage"] = 1.45
	_schooler(out, "chili_rasbora", "Chili rasbora", "Tiny red rasbora for a nano.",
		Color8(200, 40, 42), Color8(120, 24, 28), 0.08, 0.68, 1.05, 0, "shoal")
	_schooler(out, "galaxy_rasbora", "Galaxy rasbora", "Tiny dark body with pale spots.",
		Color8(40, 48, 70), Color8(210, 200, 170), 0.08, 0.72, 1.02, 2, "shoal")
	_schooler(out, "scissortail", "Scissortail rasbora", "Silver rasbora with a forked, marked tail.",
		Color8(176, 186, 190), Color8(40, 48, 56), 0.16, 0.84, 1.2, 4, "school")
	_schooler(out, "lambchop", "Lambchop rasbora", "A dark shoulder blotch on a copper body.",
		Color8(170, 110, 70), Color8(40, 28, 24), 0.14, 0.82, 1.06, 3, "shoal")
	_bottom(out, "panda_cory", "Panda cory", "Pale cory with black patches.",
		Color8(210, 200, 180), Color8(24, 22, 26), 0.14, 1.12, 2)
	_bottom(out, "pygmy_cory", "Pygmy cory", "Tiny mid-water cory, not a floor-only catfish.",
		Color8(170, 160, 130), Color8(50, 46, 36), 0.09, 0.92, 0)
	out["pygmy_cory"]["genome"]["swim_pattern"] = "shoal"
	out["pygmy_cory"]["genome"]["preferred_y"] = 3.2
	_bottom(out, "julii_cory", "Julii cory", "Spotted cory.",
		Color8(180, 160, 120), Color8(40, 36, 28), 0.15, 1.06, 2)
	_bottom(out, "clown_loach", "Clown loach", "Orange loach with black bands. Needs a group.",
		Color8(220, 110, 36), Color8(20, 16, 16), 0.22, 1.32, 3)
	out["clown_loach"]["genome"]["body_shape"] = "fusiform"
	out["clown_loach"]["genome"]["swim_pattern"] = "shoal"
	_bottom(out, "yoyo_loach", "Yoyo loach", "Banded loach that prowls the floor.",
		Color8(196, 170, 90), Color8(30, 28, 26), 0.16, 0.9, 3)
	out["yoyo_loach"]["genome"]["body_elongation"] = 1.42
	out["yoyo_loach"]["genome"]["body_shape"] = "anguilliform"
	_bottom(out, "panda_garra", "Panda garra", "Algae grazer with a sucker mouth.",
		Color8(200, 190, 170), Color8(20, 18, 18), 0.14, 1.0, 2)
	out["panda_garra"]["genome"]["ventral_sucker"] = true
	out["panda_garra"]["genome"]["wood_grazer"] = true
	out["panda_garra"]["genome"]["mouth_orientation"] = 1
	_center(out, "halfmoon_betta", "Halfmoon betta", "One show betta with a 180-degree tail.",
		Color8(40, 90, 180), Color8(20, 30, 60), {
			"finnage": 2.05, "fin_length_factor": 1.9, "dorsal_height_factor": 1.4,
			"body_depth_factor": 1.15, "pattern_type": 0, "tail_shape": 1,
			"swim_pattern": "cruise", "is_territorial": true, "adult_voxel_scale": 0.16,
		})
	_center(out, "crowntail_betta", "Crowntail betta", "Betta with a reduced, spiky fin margin.",
		Color8(160, 30, 40), Color8(40, 16, 20), {
			"finnage": 1.55, "fin_length_factor": 1.45, "dorsal_height_factor": 1.22,
			"body_depth_factor": 1.08, "pattern_type": 3, "tail_shape": 0,
			"swim_pattern": "cruise", "is_territorial": true, "adult_voxel_scale": 0.15,
		})
	_center(out, "pearl_gourami", "Pearl gourami", "Tall, spotted gourami.",
		Color8(170, 130, 110), Color8(90, 50, 40), {
			"body_shape": "compressed", "body_depth_factor": 1.52,
			"dorsal_height_factor": 1.15, "pattern_type": 2, "tail_shape": 1,
			"swim_pattern": "hover", "adult_voxel_scale": 0.24, "labyrinth_breather": true,
		})
	_center(out, "honey_gourami", "Honey gourami", "Small gold gourami. Peaceful.",
		Color8(220, 160, 50), Color8(140, 70, 30), {
			"body_depth_factor": 1.16, "dorsal_height_factor": 0.92,
			"pattern_type": 0, "tail_shape": 1, "swim_pattern": "hover",
			"adult_voxel_scale": 0.13, "labyrinth_breather": true,
		})
	_center(out, "sparkling_gourami", "Sparkling gourami", "Tiny transparent gourami.",
		Color8(180, 190, 170), Color8(80, 90, 70), {
			"body_depth_factor": 0.86, "body_elongation": 1.1,
			"dorsal_height_factor": 0.6, "pattern_type": 2, "tail_shape": 0,
			"swim_pattern": "shoal", "adult_voxel_scale": 0.09, "labyrinth_breather": true,
		})
	_center(out, "paradise_fish", "Paradise fish", "Barred, long-finned anabantoid.",
		Color8(40, 90, 160), Color8(190, 50, 40), {
			"body_depth_factor": 1.34, "finnage": 1.55, "dorsal_height_factor": 1.25,
			"pattern_type": 3, "tail_shape": 1, "swim_pattern": "cruise",
			"is_territorial": true, "adult_voxel_scale": 0.2, "labyrinth_breather": true,
		})
	_center(out, "pea_puffer", "Pea puffer", "Tiny round puffer for a planted tank. Not a community fish.",
		Color8(150, 140, 70), Color8(30, 40, 28), {
			"body_shape": "globiform", "body_depth_factor": 1.2,
			"dorsal_height_factor": 0.58, "pattern_type": 2, "tail_shape": 1,
			"swim_pattern": "hover", "adult_voxel_scale": 0.1,
			"locomotion_type": "ostraciiform", "jaw_claw_size": 0.4,
			"is_territorial": true, "schooling_strength": 0.05,
		})
	_center(out, "figure_eight_puffer", "Figure-eight puffer", "Brackish puffer with a dark figure-eight mark.",
		Color8(190, 170, 110), Color8(30, 28, 24), {
			"body_shape": "globiform", "body_depth_factor": 1.28,
			"dorsal_height_factor": 0.64, "pattern_type": 3, "tail_shape": 1,
			"swim_pattern": "hover", "adult_voxel_scale": 0.16,
			"locomotion_type": "ostraciiform", "is_territorial": true,
		})
	_center(out, "bumblebee_goby", "Bumblebee goby", "Tiny banded goby that sits on the sand.",
		Color8(230, 200, 60), Color8(20, 18, 16), {
			"body_depth_factor": 0.9, "body_elongation": 1.05,
			"dorsal_height_factor": 0.7, "pattern_type": 3, "tail_shape": 1,
			"swim_pattern": "shuffle", "adult_voxel_scale": 0.08,
			"ventral_sucker": true, "schooling_strength": 0.2,
		})
	_center(out, "dragon_goby", "Dragon goby", "Long, spotted goby. One or two.",
		Color8(70, 78, 90), Color8(30, 34, 40), {
			"body_shape": "depressed", "body_elongation": 1.85,
			"body_depth_factor": 0.7, "dorsal_height_factor": 0.5,
			"pattern_type": 2, "tail_shape": 1, "swim_pattern": "shuffle",
			"adult_voxel_scale": 0.26, "ventral_sucker": true,
		})
	_center(out, "reedfish", "Reedfish", "Banded rope-eel that noses through plants.",
		Color8(160, 110, 60), Color8(30, 24, 18), {
			"body_shape": "anguilliform", "body_elongation": 2.15,
			"body_depth_factor": 0.55, "dorsal_height_factor": 0.4,
			"pattern_type": 3, "tail_shape": 0, "swim_pattern": "meander",
			"locomotion_type": "anguilliform", "adult_voxel_scale": 0.2,
		})
	_center(out, "glass_cat", "Glass catfish", "Clear, long-whiskered midwater catfish.",
		Color8(200, 210, 214), Color8(160, 170, 176), {
			"body_elongation": 1.55, "body_depth_factor": 0.62,
			"dorsal_height_factor": 0.48, "pattern_type": 0, "tail_shape": 0,
			"swim_pattern": "shoal", "has_barbels": true, "adipose_fin": true,
			"adult_voxel_scale": 0.16,
		})
	_center(out, "upside_down_cat", "Upside-down catfish", "Spotted catfish that swims belly-up.",
		Color8(50, 48, 56), Color8(190, 180, 150), {
			"body_depth_factor": 1.05, "body_elongation": 1.15,
			"dorsal_height_factor": 0.85, "pattern_type": 2, "tail_shape": 0,
			"swim_pattern": "cruise", "has_barbels": true, "mouth_orientation": -1,
			"adult_voxel_scale": 0.16,
		})
	_center(out, "synodontis", "Synodontis", "Spotted squeaker catfish.",
		Color8(150, 130, 90), Color8(40, 32, 24), {
			"body_depth_factor": 1.18, "dorsal_height_factor": 1.05,
			"pattern_type": 2, "tail_shape": 0, "swim_pattern": "shuffle",
			"has_barbels": true, "armor_plates": true, "adult_voxel_scale": 0.2,
		})
	_center(out, "ropefish", "Ropefish", "Long, banded eel-like fish.",
		Color8(140, 90, 50), Color8(30, 22, 16), {
			"body_shape": "anguilliform", "body_elongation": 2.35,
			"body_depth_factor": 0.5, "dorsal_height_factor": 0.35,
			"pattern_type": 3, "tail_shape": 0, "swim_pattern": "meander",
			"locomotion_type": "anguilliform", "adult_voxel_scale": 0.22,
		})
	_center(out, "snakehead", "Snakehead", "Large ambush predator. One, alone.",
		Color8(70, 80, 55), Color8(30, 36, 24), {
			"body_elongation": 1.45, "body_depth_factor": 0.95,
			"dorsal_height_factor": 0.7, "pattern_type": 2, "tail_shape": 1,
			"swim_pattern": "cruise", "snout_pointed": true,
			"is_territorial": true, "adult_voxel_scale": 0.36,
			"schooling_strength": 0.0, "max_speed": 2.2,
		})
	_center(out, "flowerhorn", "Flowerhorn", "Deep cichlid with a large nuchal hump.",
		Color8(190, 80, 40), Color8(40, 24, 20), {
			"body_shape": "compressed", "body_depth_factor": 1.55,
			"dorsal_height_factor": 1.2, "nuchal_hump": 1.45,
			"pattern_type": 2, "tail_shape": 1, "swim_pattern": "hover",
			"is_territorial": true, "adult_voxel_scale": 0.28,
			"locomotion_type": "labriform",
		})
	return out


static func _add(out: Dictionary, id: String, label: String, desc: String, genome: Dictionary) -> void:
	genome["species"] = id
	out[id] = {"label": label, "description": desc, "genome": genome}


static func _base(base: Color, accent: Color) -> Dictionary:
	return {
		"locomotion_type": "subcarangiform",
		"base_color": base, "accent_color": accent,
		"adult_voxel_scale": 0.16, "max_speed": 1.4, "max_age_s": 240.0,
		"schooling_strength": 0.45, "separation_radius": 0.6,
		"herbivory": 0.5, "fecundity": 0.6, "clutch_size": 2,
		"preferred_y": 3.4, "body_elongation": 1.0, "body_depth_factor": 1.0,
		"body_shape": "fusiform", "swim_pattern": "shoal",
		"pattern_type": 0, "tail_shape": 0, "eye_size_factor": 1.0,
	}


static func _livebearer(base: Color, accent: Color, over: Dictionary) -> Dictionary:
	var g: Dictionary = _base(base, accent)
	g["is_livebearer"] = true
	g["dimorphic"] = true
	g["fecundity"] = 1.4
	g["clutch_size"] = 4
	g["herbivory"] = 0.7
	g.merge(over, true)
	return g


static func _cichlid(out: Dictionary, id: String, label: String, desc: String,
		base: Color, accent: Color, scale: float, depth: float, elong: float,
		pattern: int, dorsal: float) -> void:
	var g: Dictionary = _base(base, accent)
	g.merge({
		"locomotion_type": "labriform",
		"body_shape": "compressed",
		"body_depth_factor": depth,
		"body_elongation": elong,
		"dorsal_height_factor": dorsal,
		"pattern_type": pattern,
		"tail_shape": 1,
		"swim_pattern": "hover",
		"adult_voxel_scale": scale,
		"schooling_strength": 0.15,
		"is_territorial": true,
		"guards_clutch": true,
		"max_speed": 1.05,
	}, true)
	_add(out, id, label, desc, g)


static func _schooler(out: Dictionary, id: String, label: String, desc: String,
		base: Color, accent: Color, scale: float, depth: float, elong: float,
		pattern: int, swim: String) -> void:
	var g: Dictionary = _base(base, accent)
	g.merge({
		"body_depth_factor": depth,
		"body_elongation": elong,
		"dorsal_height_factor": 0.7 + depth * 0.15,
		"pattern_type": pattern,
		"tail_shape": 0,
		"swim_pattern": swim,
		"adult_voxel_scale": scale,
		"schooling_strength": 1.4,
		"adipose_fin": true,
		"max_speed": 1.8,
		"preferred_y": 4.0,
	}, true)
	_add(out, id, label, desc, g)


static func _bottom(out: Dictionary, id: String, label: String, desc: String,
		base: Color, accent: Color, scale: float, depth: float, pattern: int) -> void:
	var g: Dictionary = _base(base, accent)
	g.merge({
		"body_depth_factor": depth,
		"dorsal_height_factor": 0.65,
		"pattern_type": pattern,
		"tail_shape": 1,
		"swim_pattern": "shuffle",
		"adult_voxel_scale": scale,
		"schooling_strength": 0.55,
		"has_barbels": true,
		"armor_plates": true,
		"preferred_y": 1.2,
		"mouth_orientation": 1,
		"herbivory": 0.9,
		"max_speed": 1.0,
	}, true)
	_add(out, id, label, desc, g)


static func _center(out: Dictionary, id: String, label: String, desc: String,
		base: Color, accent: Color, over: Dictionary) -> void:
	var g: Dictionary = _base(base, accent)
	g.merge(over, true)
	_add(out, id, label, desc, g)
