# Persistent tank configuration.
#
# Registered as an Autoload (singleton) so settings survive scene reloads.
# When the user changes settings + hits "Apply", the panel updates fields
# here then reloads the scene. World.gd reads these on _ready to apply.
#
# To make this an autoload, add to project.godot:
#   [autoload]
#   TankConfig="*res://scripts/tank_config.gd"

extends Node

# ---- Rendering parameters ----
# Internal SubViewport resolution. Smaller = more pixelated / chunkier.
# Common choices: 256x144 (chunky), 384x216, 512x288 (default), 768x432.
var render_width: int = 512
var render_height: int = 288
# Palette quantize shader strength.
var dither_strength: float = 0.85
# If false, the palette pass is bypassed and you see raw HDR colors. Useful
# for spotting bugs in lighting + composition.
var palette_enabled: bool = true
# Volumetric fog parameters.
var fog_density: float = 0.02
var fog_anisotropy: float = 0.3
var fog_ambient_inject: float = 0.05
# Camera.
var camera_fov: float = 50.0
# Anti-aliasing on the SubViewport. 0=off, 1=2x, 2=4x, 3=8x.
var msaa: int = 0
# Camera state - preserved across scene reloads so changing settings doesn't
# snap the view back to the default. Saved by main.gd.save_camera_state()
# right before a panel triggers reload_current_scene.
var camera_yaw: float = -0.55
var camera_pitch: float = 0.48
var camera_radius: float = 17.5
var camera_target_x: float = 0.0
var camera_target_y: float = 3.0
var camera_target_z: float = 0.0
# A "do we have one saved?" flag - false on first launch means use defaults.
var camera_state_saved: bool = false

# ---- Mobile / device settings ----
# Engine.max_fps cap. 0 = uncapped (desktop default). On mobile we default to 60
# to keep battery + thermals reasonable; user can change via settings.
var fps_cap: int = 0
# Device tier guess - set once on first launch from screen size + DPI heuristic
# (see main._auto_pick_device_tier). Used to set sensible initial render scale.
# Values: "" (not yet picked), "low", "mid", "high".
var device_tier: String = ""
# True once the player has seen and dismissed the gesture tutorial overlay.
var tutorial_seen: bool = false
# Runtime-only flag (not persisted): set by the tank menu's "Guided setup"
# entry so main.gd launches the step-by-step walkthrough when the tank opens.
# Consumed (cleared) once the walkthrough begins.
var walkthrough_pending: bool = false
# Unix seconds at last clean quit. Used to show "you were away for X" on
# resume. 0 = never quit cleanly (first launch).
var last_quit_unix: int = 0

# ---- Tank shape + dimensions ----
# Glass + substrate geometry. Each shape clips substrate fill + spawn
# regions appropriately so creatures don't appear outside the walls.
#   box       - default rectangular prism (4 walls)
#   cube      - same rectangular geom but enforces W=D (single dimension)
#   hex       - regular hexagonal prism (6 walls)
#   triangle  - equilateral triangular prism (3 walls)
#   cylinder  - vertical round tank (constant circular footprint)
#   sphere    - dome bowl (hemisphere — walls taper inward with height)
var tank_shape: String = "box"
var tank_half_w: float = 8.0
var tank_half_d: float = 4.0
var tank_height: float = 7.0
var water_surface_fraction: float = 0.93  # water reaches 93% up the tank
var substrate_depth_fraction: float = 0.23  # substrate is 23% of tank height

# ---- Lighting ----
# light_energy: 0-1 multiplier on the directional + ambient brightness
# light_yaw: 0-1 normalised position (rotation around Y axis)
# light_pitch: 0-1, 0 = top-down, 1 = horizontal
var light_energy: float = 0.5
var light_yaw: float = 0.5
var light_pitch: float = 0.3
# light_color shifts warm/cool: 0 = cool blue daylight, 1 = warm tungsten
var light_warmth: float = 0.6
# Visible aquarium fixture above the tank. Two physical layouts:
#   "bar"       - long horizontal LED bar spanning ~80% of tank width.
#                 Casts a wide focused beam down via multiple spots.
#   "spotlight" - single circular pendant fixture, narrower beam.
var light_fixture: String = "bar"
# Height of the fixture above the water surface (1.0 = level with tank top).
var light_height: float = 1.4
# Size of the fixture as a fraction of tank width.
var light_size: float = 0.75
# Show volumetric beams (god rays). On by default for high-fidelity startup experience.
var light_volumetric: bool = true
# Show surface caustics scrolling across the substrate. On by default.
var light_caustics: bool = true

# Procedural music settings.
var music_enabled: bool = true
var music_volume: float = 0.7
var music_complexity: float = 0.5
# Layer toggles + how strongly the tank ecosystem steers tone/tempo.
var music_ambient_enabled: bool = true
var music_events_enabled: bool = true
var music_environment_enabled: bool = true
var music_event_volume: float = 0.75
var music_reactivity: float = 0.65
# auto | calm | bright | deep
var music_mood: String = "auto"
# ambient | trance | hybrid — continuous bed character
var music_style: String = "hybrid"
# 0..1 — BPM, kick, arp density, filter sweep intensity
var music_energy: float = 0.42
# Sound studio — tank coupling & layer mix (0..1 unless noted).
var music_coupling_floor: float = 0.55
var music_smooth_rate: float = 0.55
var music_phrase_churn: float = 0.5
var music_tempo_follow: float = 0.72
var music_kick_mix: float = 0.5
var music_bass_mix: float = 0.6
var music_arp_mix: float = 0.62
var music_pad_mix: float = 0.78
var music_hat_mix: float = 0.38
var music_sidechain: float = 0.55
var music_filter_open: float = 0.38
var music_delay_amount: float = 0.22
var music_accent_density: float = 0.5
var music_influence_fish: float = 1.0
var music_influence_plants: float = 1.0
var music_influence_bloom: float = 1.0
var music_influence_o2: float = 1.0
var music_influence_day: float = 1.0
var music_influence_aeration: float = 1.0
var music_influence_biomass: float = 1.0
var music_seed: int = 1

# ---- Room environment ----
# A "scene" around the tank — desk, wall, lamp, props. Lifts the tank
# from floating-in-void to "sitting in a room." Defaults to "void"
# (the classic look) so existing tanks open unchanged. Each preset's
# colors are chosen from the palette so the room quantizes cleanly
# alongside the tank.
var environment_preset: String = "void"

const ENVIRONMENT_PRESETS: Dictionary = {
	"void": {
		"label": "Void (no room)",
		"description": "Classic isolated tank floating in dark. No table, no walls, no props.",
	},
	"bedroom_desk": {
		"label": "Bedroom desk",
		"description": "Warm wooden desk + plaster back wall + a small bedside lamp. Cozy nighttime feel.",
		"desk_color": [128, 88, 56],
		"wall_color": [212, 200, 178],
		"accent_color": [220, 165, 90],
		"light_color": [255, 235, 200],
		"include_lamp": true,
		"include_books": true,
		"include_plant": true,
		"include_window": true,
		"include_clock": true,
		"include_record_player": true,
		"include_mug": true,
	},
	"sunny_window": {
		"label": "Sunny window",
		"description": "Pale wood ledge + bright daylight from a virtual window. Crisp daytime feel.",
		"desk_color": [200, 175, 142],
		"wall_color": [232, 224, 208],
		"accent_color": [200, 220, 240],
		"light_color": [255, 248, 232],
		"include_lamp": false,
		"include_books": true,
		"include_plant": true,
		"include_window": true,
		"include_clock": true,
		"include_mug": true,
	},
	"dark_cabinet": {
		"label": "Dark cabinet",
		"description": "Black-walnut cabinet with cool fluorescent fill. Aquarium-shop / display feel.",
		"desk_color": [56, 40, 32],
		"wall_color": [42, 38, 44],
		"accent_color": [110, 130, 140],
		"light_color": [220, 232, 240],
		"include_lamp": false,
		"include_books": false,
		"include_plant": false,
		"include_lava_lamp": true,
		"include_clock": true,
	},
	"forest_window": {
		"label": "Forest window",
		"description": "Mossy log shelf + cool green light filtered through trees outside. Quiet, plant-forward.",
		"desk_color": [88, 76, 60],
		"wall_color": [128, 148, 120],
		"accent_color": [130, 170, 110],
		"light_color": [220, 240, 215],
		"include_lamp": false,
		"include_books": false,
		"include_plant": true,
		"include_window": true,
		"include_mug": true,
		"include_lava_lamp": true,
	},
}


func current_environment_profile() -> Dictionary:
	return ENVIRONMENT_PRESETS.get(environment_preset, ENVIRONMENT_PRESETS["void"])


# ---- Fauna ----
# If true, respawn 10 of each creature if the tank is empty.
var auto_respawn_fauna: bool = false
var auto_feed_fauna: bool = false

# ---- Tank population preset ----
# Selects the initial stocking of the tank. Each preset specifies how many
# of each species spawn AND a phenotype-range modifier so the founding
# generation has a distinctive look. Custom uses the inline counts.
var tank_preset: String = "classic_community"
var custom_glassdart_count: int = 14
var custom_mudsifter_count: int = 5
var custom_shrimp_count: int = 12

# ---- Species library ----
# Every fish species the world can spawn lives here. Each entry has a label
# (for the UI), a description (shown next to the preset), and a `genome`
# dict that gets handed straight to Fish.init_genome().
#
# Adding a new species: append an entry here, reference it in a preset's
# "stocking" dict. World.gd reads from the library so no changes there are
# needed when you add a fish.
#
# The "genome" dict reuses the fish.gd genome keys verbatim. See fish.gd's
# init_genome() for the canonical list (base_color, accent_color,
# adult_voxel_scale, max_age_s, max_speed, schooling_strength, etc.) plus
# the body phenotypes (fin_length_factor, body_elongation, body_depth_factor,
# head_proportion, dorsal_height_factor, tail_fork_depth, pattern_type).
const SPECIES_LIBRARY: Dictionary = {
	"glassdart": {
		"label": "Cardinal tetra",
		"description": "Mid-water schoolers. The signature neon-blue stripe runs the full body over a deep scarlet lower flank. Streamlined and fast.",
		"genome": {
			"species": "glassdart",
			# Cardinal tetra: the iconic two-tone flank. base_color is the
			# scarlet body, marking_color is the electric neon-blue dorsal
			# stripe, accent is a slightly deeper scarlet shadow on the lower
			# flank (pattern_type 4 paints upper=marking, lower=accent).
			"base_color": Color8(220, 32, 50),
			"marking_color": Color8(70, 185, 245),
			"accent_color": Color8(190, 26, 42),
			"adult_voxel_scale": 0.18,
			"size_potential": 0.95,
			"jaw_claw_size": 0.05,
			"max_age_s": 220.0,
			"max_speed": 2.0,
			"schooling_strength": 1.6,
			"separation_radius": 0.55,
			"herbivory": 0.4,
			"fecundity": 0.8,
			"clutch_size": 2,
			"preferred_y": 4.0,
			"body_elongation": 1.10,
			"body_depth_factor": 0.85,
			"swim_pattern": "school",
			"pattern_type": 4,                # two-tone band - blue over red
			"tail_shape": 0,                  # forked - signature tetra tail
			"eye_size_factor": 1.0,
			# Tetras have a distinctive adipose fin between the dorsal and
			# the tail. Combined with the slim torpedo body + deep fork it
			# makes them instantly recognisable as "tetra-shaped".
			"adipose_fin": true,
			"body_shape": "fusiform",
		},
	},
	"mudsifter": {
		"label": "Mudsifter (kuhli-like)",
		"description": "Bottom-dweller. Banded orange + chocolate. Sifts substrate for detritus.",
		"genome": {
			"species": "mudsifter",
			# Kuhli-loach inspired: bright orange with dark chocolate bands.
			"base_color": Color8(225, 130, 50),
			"accent_color": Color8(60, 35, 25),
			"adult_voxel_scale": 0.22,
			"size_potential": 1.15,
			"jaw_claw_size": 0.42,
			"max_age_s": 280.0,
			"max_speed": 1.2,
			"schooling_strength": 0.5,
			"separation_radius": 0.7,
			"herbivory": 1.0,
			"fecundity": 0.5,
			"clutch_size": 3,
			"preferred_y": 2.4,
			"body_elongation": 1.45,             # long snake-like loach body
			"body_depth_factor": 0.75,
			"head_proportion": 1.15,
			"pattern_type": 3,                  # vertical bars
			"swim_pattern": "shuffle",
			# Loach skeleton: long body, downturned mouth, barbels, small eyes
			# and a square paddle tail.
			"has_barbels": true,
			"mouth_orientation": 1,
			"eye_size_factor": 0.7,
			"ventral_profile": 0.75,            # flat bottom
			"back_arch": 1.0,
			"tail_shape": 3,                    # square paddle
			"snail_predator": true,             # loaches LOVE snails
			# Loaches are anguilliform - long tube body, no apparent
			# segmentation. Extra rear filler voxels close the gap
			# between the body and the tail peduncle.
			"body_shape": "anguilliform",
		},
	},
	"betta": {
		"label": "Betta (solo apex)",
		"description": "Solitary carnivore. Iridescent royal-blue with magenta finnage. Long sweeping arcs.",
		"genome": {
			"species": "betta",
			# Vibrant royal blue with hot magenta finnage; iridescent
			# turquoise marking flash on the flank.
			"base_color": Color8(40, 90, 235),
			"accent_color": Color8(245, 90, 180),
			"tail_color": Color8(235, 70, 165),
			"marking_color": Color8(60, 215, 200),
			"adult_voxel_scale": 0.28,
			"size_potential": 1.35,
			"jaw_claw_size": 0.38,
			"max_age_s": 420.0,
			"max_speed": 1.6,
			"schooling_strength": 0.0,
			"separation_radius": 1.0,
			"herbivory": 0.0,
			"fecundity": 0.0,
			"clutch_size": 0,
			"preferred_y": 3.8,
			"fin_length_factor": 1.45,
			"dorsal_height_factor": 1.35,
			"tail_fork_depth": 0.7,
			"swim_pattern": "cruise",
			"tail_shape": 2,                    # lyre - long flowing trailing rays
			"eye_size_factor": 1.1,
			"back_arch": 1.15,                  # mild hump
			# Bettas have an anal fin almost as long as the body itself,
			# sweeping back behind them. Combined with the long lyre tail
			# and tall dorsal, the silhouette reads as "all flowing fin".
			"anal_fin_length_factor": 1.5,
			# Veil finnage: billowing trailing caudal/dorsal/anal drapery -
			# the unmistakable show-betta silhouette.
			"finnage": 1.6,
			# Labyrinth organ: bettas breathe atmospheric air at the surface.
			"labyrinth_breather": true,
		},
	},
	"killifish": {
		"label": "Killifish",
		"description": "Surface darter. Brilliant turquoise + orange. Short-lived, breeds prolifically.",
		"genome": {
			"species": "killifish",
			# Vivid turquoise body with hot orange accents.
			"base_color": Color8(20, 200, 215),
			"accent_color": Color8(255, 110, 35),
			"adult_voxel_scale": 0.14,
			"size_potential": 1.0,
			"jaw_claw_size": 0.14,
			"max_age_s": 150.0,
			"max_speed": 1.7,
			"schooling_strength": 0.4,
			"separation_radius": 0.5,
			"herbivory": 0.3,
			"fecundity": 1.6,
			"clutch_size": 3,
			"preferred_y": 5.2,
			"body_elongation": 1.20,
			"body_depth_factor": 0.85,
			"fin_length_factor": 1.25,
			"dorsal_height_factor": 1.15,
			"pattern_type": 2,
			"color_dot_count": 3,
			"swim_pattern": "dart",
			# Killifish skeleton: upturned mouth for surface feeding, big bug
			# eyes, slightly arched back, square paddle tail.
			"mouth_orientation": -1,
			"eye_size_factor": 1.35,
			"back_arch": 1.1,
			"tail_shape": 3,                    # square paddle
			# Subtle adipose fin sits between the dorsal and tail. Real
			# killifish have one - it reads as "this is not a tetra-tetra
			# but it shares the lineage." Helps differentiate from danios.
			"adipose_fin": true,
			"guards_clutch": true,
		},
	},
	"guppy": {
		"label": "Guppy",
		"description": "Dark slate body with a brilliant scarlet fan tail. Loose mid-water shoals.",
		"genome": {
			"species": "guppy",
			# Matches the user's photo: charcoal-grey body, brilliant red
			# flowing tail (a separate tail_color zone, see fish.gd).
			"base_color": Color8(45, 50, 60),
			"accent_color": Color8(255, 240, 90),
			"tail_color": Color8(240, 55, 30),
			"dimorphic": true,                   # males flashy, females silver
			"adult_voxel_scale": 0.11,
			"size_potential": 1.10,
			"jaw_claw_size": 0.08,
			"max_age_s": 180.0,
			"max_speed": 1.5,
			"schooling_strength": 0.7,
			"separation_radius": 0.4,
			"herbivory": 0.6,
			"fecundity": 1.8,
			"clutch_size": 4,
			"preferred_y": 3.6,
			"body_elongation": 0.95,
			"body_depth_factor": 1.0,
			"fin_length_factor": 1.55,           # extra long signature tail
			"tail_fork_depth": 0.3,
			"pattern_type": 2,
			"finnage": 1.3,                      # fancy-male flowing fan tail
			"swim_pattern": "shoal",
			"tail_shape": 1,                     # fan - signature guppy
			"eye_size_factor": 1.05,
			"ventral_profile": 1.1,
			# Livebearer: real guppies are viviparous. Females carry fry
			# internally; sim_driver._lay_eggs branches on this flag to
			# spawn free-swimming fry directly instead of plant-laid eggs.
			"is_livebearer": true,
		},
	},
	"pufferfish": {
		"label": "Dwarf pufferfish",
		"description": "Round, slow, solitary. Lemon-yellow with dark spots. Meanders, hunts shrimp.",
		"genome": {
			"species": "pufferfish",
			# Bright lemon yellow with strong dark spots - high contrast.
			"base_color": Color8(255, 220, 60),
			"accent_color": Color8(50, 40, 25),
			"adult_voxel_scale": 0.22,
			"size_potential": 1.50,
			"jaw_claw_size": 0.72,
			"max_age_s": 360.0,
			"max_speed": 0.7,
			"schooling_strength": 0.0,
			"separation_radius": 1.3,
			"herbivory": 0.0,
			"fecundity": 0.15,
			"clutch_size": 1,
			"preferred_y": 3.0,
			"body_elongation": 0.65,
			"body_depth_factor": 1.55,
			"head_proportion": 1.25,
			"fin_length_factor": 0.55,
			"dorsal_height_factor": 0.6,
			"tail_fork_depth": 0.4,
			"pattern_type": 2,
			"color_dot_count": 4,
			"swim_pattern": "meander",
			# Puffer signature: HUGE bug eyes, round belly, square stubby tail,
			# no barbels, slight downward mouth (they sucker-mouth onto snails).
			"eye_size_factor": 1.55,
			"ventral_profile": 1.45,            # super round belly
			"back_arch": 1.05,
			"tail_shape": 3,                    # square paddle
			"snail_predator": true,             # puffer #1 snail killer
			# Globiform body - the puffer needs to read as a near-sphere,
			# not a stretched body with a bulgy belly. The body_shape
			# branch in fish.gd adds wraparound voxels (front + rear caps
			# and lateral cheeks) that close out the silhouette.
			"body_shape": "globiform",
		},
	},
	"danio": {
		"label": "Zebra danio",
		"description": "Fast top schooler. Iridescent silver with electric-blue stripes. Restless.",
		"genome": {
			"species": "danio",
			# Iridescent silver-cyan with electric blue lateral stripe.
			"base_color": Color8(220, 235, 250),
			"accent_color": Color8(20, 80, 220),
			"adult_voxel_scale": 0.15,
			"size_potential": 0.95,
			"jaw_claw_size": 0.04,
			"max_age_s": 200.0,
			"max_speed": 2.4,
			"schooling_strength": 1.8,
			"separation_radius": 0.45,
			"herbivory": 0.5,
			"fecundity": 1.0,
			"clutch_size": 3,
			"preferred_y": 4.6,
			"body_elongation": 1.30,
			"body_depth_factor": 0.75,
			"pattern_type": 1,
			"swim_pattern": "school",
			"tail_shape": 0,                    # forked
			"eye_size_factor": 1.0,
		},
	},
	"corydoras": {
		"label": "Corydoras (armored cat)",
		"description": "Peppered bronze armor. Tight bottom group, shuffles between plants.",
		"genome": {
			"species": "corydoras",
			# Bronze cory with high-contrast dark peppering.
			"base_color": Color8(210, 165, 95),
			"accent_color": Color8(40, 30, 20),
			"adult_voxel_scale": 0.18,
			"size_potential": 1.05,
			"jaw_claw_size": 0.36,
			"max_age_s": 360.0,
			"max_speed": 0.9,
			"schooling_strength": 1.0,
			"separation_radius": 0.5,
			"herbivory": 0.95,
			"fecundity": 0.4,
			"clutch_size": 3,
			"preferred_y": 2.0,
			"body_elongation": 1.10,
			"body_depth_factor": 1.10,
			"head_proportion": 1.20,
			"pattern_type": 2,
			"color_dot_count": 3,
			"swim_pattern": "shuffle",
			# Cory signature: barbels under the mouth, armor plating, flat
			# bottom, small beady eyes, downturned sifter mouth, square tail.
			"has_barbels": true,
			"armor_plates": true,
			"mouth_orientation": 1,
			"eye_size_factor": 0.75,
			"ventral_profile": 0.70,            # flat
			"back_arch": 1.0,
			"tail_shape": 3,                    # square paddle
			"algae_grazer": true,               # corydoras graze algae + biofilm
			"guards_clutch": true,
		},
	},
	"angelfish": {
		"label": "Angelfish",
		"description": "Tall slow centerpiece. Pearl white with jet-black bars. Hovers in pairs.",
		"genome": {
			"species": "angelfish",
			# Pure pearl white with jet black bars - real angelfish striking look.
			"base_color": Color8(250, 250, 252),
			"accent_color": Color8(15, 15, 25),
			"adult_voxel_scale": 0.26,
			"size_potential": 1.20,
			"jaw_claw_size": 0.18,
			"max_age_s": 480.0,
			"max_speed": 0.9,
			"schooling_strength": 0.3,
			"separation_radius": 1.1,
			"herbivory": 0.4,
			"fecundity": 0.3,
			"clutch_size": 2,
			"preferred_y": 3.6,
			"body_elongation": 0.85,
			"body_depth_factor": 1.75,
			"fin_length_factor": 1.65,
			"dorsal_height_factor": 1.7,
			"tail_fork_depth": 0.9,
			"pattern_type": 3,
			"bar_edged": true,                  # crisp jet-black vertical bars
			"swim_pattern": "hover",
			# Angelfish signature: tall arched body, lyre tail, mid-sized eyes.
			"tail_shape": 2,                    # lyre
			"eye_size_factor": 1.0,
			"back_arch": 1.45,                  # tall arched silhouette
			"ventral_profile": 1.15,
			# Angelfish-defining silhouette traits:
			#  - compressed body: tall thin disc, the unmistakable
			#    angelfish profile (extra voxels above + below midline).
			#  - matching trailing anal fin: equal length to the dorsal so
			#    the fish reads symmetrical top-to-bottom, with two long
			#    sweeping fins front-to-back like a diamond.
			#  - pointed snout: cichlid wedge face, not a blunt round
			#    cory-style head.
			"body_shape": "compressed",
			"anal_fin_length_factor": 1.7,
			"snout_pointed": true,
			"guards_clutch": true,
		},
	},
	"harlequin_rasbora": {
		"label": "Harlequin rasbora",
		"description": "Tight copper-orange shoal with the signature jet-black 'pork-chop' wedge over the rear flank. Peaceful mid-water schoolers.",
		"genome": {
			"species": "harlequin_rasbora",
			# Warm copper-orange body with a deep black rear wedge.
			"base_color": Color8(225, 130, 70),
			"accent_color": Color8(235, 150, 95),
			"marking_color": Color8(22, 20, 28),
			"adult_voxel_scale": 0.13,
			"size_potential": 0.85,
			"jaw_claw_size": 0.03,
			"max_age_s": 230.0,
			"max_speed": 1.7,
			"schooling_strength": 1.5,
			"separation_radius": 0.5,
			"herbivory": 0.45,
			"fecundity": 0.9,
			"clutch_size": 2,
			"preferred_y": 4.0,
			"body_elongation": 0.95,
			"body_depth_factor": 1.05,           # slightly deep rasbora body
			"pattern_type": 5,                   # rear-flank black wedge
			"swim_pattern": "shoal",
			"tail_shape": 0,                     # forked
			"eye_size_factor": 1.05,
			"body_shape": "fusiform",
		},
	},
	"dwarf_gourami": {
		"label": "Dwarf gourami",
		"description": "Deep-bodied labyrinth centerpiece. Flame-red flanks washed with iridescent turquoise, long pelvic feelers, and habitual surface air-gulping.",
		"genome": {
			"species": "dwarf_gourami",
			# Flame red base with a turquoise two-tone wash and red finnage.
			"base_color": Color8(205, 55, 45),
			"marking_color": Color8(55, 175, 195),
			"accent_color": Color8(170, 40, 35),
			"tail_color": Color8(220, 80, 60),
			"adult_voxel_scale": 0.23,
			"size_potential": 1.25,
			"jaw_claw_size": 0.10,
			"max_age_s": 400.0,
			"max_speed": 0.95,
			"schooling_strength": 0.2,
			"separation_radius": 1.0,
			"herbivory": 0.5,
			"fecundity": 0.3,
			"clutch_size": 2,
			"preferred_y": 4.4,                  # upper-mid; visits the surface
			"body_elongation": 0.8,
			"body_depth_factor": 1.6,            # deep, laterally compressed
			"fin_length_factor": 1.15,
			"dorsal_height_factor": 1.3,
			"tail_fork_depth": 0.4,
			"pattern_type": 4,                   # two-tone turquoise-over-red band
			"swim_pattern": "cruise",
			"tail_shape": 1,                     # fan
			"eye_size_factor": 1.1,
			"back_arch": 1.3,                    # arched anabantid profile
			"ventral_profile": 1.1,
			"anal_fin_length_factor": 1.3,       # long anabantid anal fin
			# Anabantid signatures: thread-like pelvic feelers + labyrinth
			# organ for atmospheric surface breathing.
			"ventral_feelers": true,
			"labyrinth_breather": true,
			"body_shape": "compressed",
			"guards_clutch": true,
		},
	},
	"reef_fish": {
		"label": "Mixed reef school",
		"description": "Single 'species' built to look like a mixed reef community - clownfish, tangs, chromis, anthias. Every individual rolls a unique morph at spawn.",
		"genome": {
			"species": "reef_fish",
			# Bright tropical baseline. The mixed_morphs path in fish.gd
			# init_genome OVERWRITES base_color / accent_color / pattern /
			# shape per individual so this baseline is rarely seen
			# unchanged. Strong saturation so even the random jitters
			# stay vivid.
			"base_color": Color8(245, 165, 40),       # Clownfish orange default
			"accent_color": Color8(255, 255, 255),    # crisp white bars
			"adult_voxel_scale": 0.16,
			"size_potential": 1.15,
			"jaw_claw_size": 0.20,
			"max_age_s": 260.0,
			"max_speed": 1.6,
			"schooling_strength": 0.6,                # loose - reef fish don't tight-school
			"separation_radius": 0.7,
			"herbivory": 0.5,                          # mixed reef diet
			"fecundity": 0.6,
			"clutch_size": 2,
			"preferred_y": 3.6,
			"body_elongation": 0.95,
			"body_depth_factor": 1.10,
			"fin_length_factor": 1.0,
			"swim_pattern": "shoal",
			"tail_shape": 1,
			"eye_size_factor": 1.1,
			# Mixed-morph spawn flag: each individual gets random tropical
			# colors, body_shape, pattern, tail_shape so the school reads
			# as multiple "species". See fish.gd init_genome handling.
			"mixed_morphs": true,
		},
	},
}


func species_label(key: String) -> String:
	var entry: Dictionary = SPECIES_LIBRARY.get(key, {})
	return entry.get("label", key)


# Each preset's "stocking" dict maps species_name -> count. "shrimp" is
# handled by world's _spawn_initial_shrimp() separately. New species can
# be added without changing world.gd - just append them to a stocking
# dict here.
const TANK_PRESETS: Dictionary = {
	"empty": {
		"label": "Empty (build it yourself)",
		"stocking": {},
		"phenotype_spread": 0.0,
		"description": "A bare tank with substrate only - no plants, fauna, or hardscape. Used by the guided walkthrough so you stock everything by hand.",
	},
	"classic_community": {
		"label": "Classic community",
		"stocking": {
			"glassdart": 10, "harlequin_rasbora": 8, "corydoras": 6,
			"dwarf_gourami": 2, "shrimp": 10,
		},
		"phenotype_spread": 0.6,
		"description": "The textbook beginner freshwater community: a cardinal tetra school, a harlequin rasbora shoal, a corydoras bottom group, a dwarf gourami centerpiece pair, and a cherry shrimp cleanup crew.",
	},
	"community": {
		"label": "Community (balanced)",
		"stocking": {
			"glassdart": 12, "mudsifter": 4, "guppy": 4, "corydoras": 3,
			"betta": 1, "shrimp": 12,
		},
		"phenotype_spread": 1.0,
		"description": "Balanced mix: tetras + guppies + bottom group + 1 betta apex.",
	},
	"tetra_school": {
		"label": "Tetra school (peaceful)",
		"stocking": {
			"glassdart": 22, "danio": 8, "shrimp": 18,
		},
		"phenotype_spread": 0.5,
		"description": "Pure schoolers (tetras + danios) + dense shrimp colony. No apex.",
	},
	"apex_tank": {
		"label": "Apex predator + prey",
		"stocking": {
			"glassdart": 6, "guppy": 4, "mudsifter": 2,
			"betta": 1, "pufferfish": 1, "shrimp": 20,
		},
		"phenotype_spread": 0.8,
		"description": "Lots of prey + a betta and a puffer competing for the snacks.",
	},
	"diverse": {
		"label": "Diverse founding stock",
		"stocking": {
			"glassdart": 8, "danio": 4, "guppy": 4, "killifish": 4,
			"mudsifter": 3, "corydoras": 3, "betta": 1, "shrimp": 12,
		},
		"phenotype_spread": 2.5,
		"description": "Wide phenotype spread + every species. Evolution diverges fast.",
	},
	"crazy": {
		"label": "Crazy evolution",
		"stocking": {
			"glassdart": 7, "danio": 5, "guppy": 5, "killifish": 4,
			"mudsifter": 4, "corydoras": 4, "angelfish": 2, "pufferfish": 2,
			"betta": 1, "shrimp": 20,
		},
		"phenotype_spread": 5.0,
		"description": "Extreme founder variation: oversized, elongated, and claw-heavy morphs from day one.",
	},
	"single_species": {
		"label": "Single species (clones)",
		"stocking": {"glassdart": 20, "shrimp": 8},
		"phenotype_spread": 0.0,
		"description": "All glassdarts start identical. Drift emerges slowly.",
	},
	"exotic_mix": {
		"label": "Exotic mix (full reef)",
		"stocking": {
			"killifish": 5, "guppy": 6, "danio": 6, "pufferfish": 1,
			"angelfish": 2, "corydoras": 4, "shrimp": 14,
		},
		"phenotype_spread": 1.2,
		"description": "All 6 new species, no glassdart/betta. Angelfish centerpiece + puffer.",
	},
	"showcase": {
		"label": "Showcase tank",
		"stocking": {
			"angelfish": 2, "killifish": 4, "guppy": 6, "corydoras": 4,
			"shrimp": 12,
		},
		"phenotype_spread": 0.8,
		"description": "Tall angelfish over a guppy + corydoras + killifish community. No predators.",
	},
	"custom": {
		"label": "Custom",
		"stocking": {},
		"phenotype_spread": 1.0,
		"description": "Set counts manually below.",
	},
	"reef": {
		"label": "Reef (saltwater)",
		"stocking": {
			# Single species, but mixed_morphs + high phenotype_spread mean
			# every individual reads as a different reef fish (clownfish,
			# tang, chromis, anthias-shaped morphs). No shrimp - this is a
			# pure reef community.
			"reef_fish": 16,
		},
		"phenotype_spread": 3.5,
		"substrate": "ocean_sand",
		"description": "Coral reef + mixed tropical school. Each fish unique. Plants replaced by corals.",
	},
}


func current_tank_preset() -> Dictionary:
	return TANK_PRESETS.get(tank_preset, TANK_PRESETS["community"])


# ---- Aeration / air system ----
# walstad loom models a tank-wide dissolved-O2 level (0..1, 1=saturated) that
# is filled by the chosen aeration fixture, replenished by plant photosynthesis
# during the day, and consumed by fish + shrimp respiration. Fish gulp at the
# surface when O2 falls too low.
#
# Fixture types - each has a distinct visible shape AND a different air
# injection rate:
#   "none"     - no fixture, no injection from equipment
#   "disk"     - flat air-stone disk on substrate, dense fine-bubble curtain,
#                HIGH air rate. Best aeration but a big visual footprint.
#   "stick"    - long thin air-stone bar (a.k.a. "bubble wand"). Medium rate,
#                spread out along the back wall.
#   "filter"   - hang-on-back style filter return: vertical intake/return tube
#                with bubbles trickling up + a horizontal spout that disturbs
#                the surface. Medium rate but ADDS visible water flow.
var aeration_type: String = "disk"
var aeration_strength: float = 0.6      # 0..1, scales injection rate
var aeration_x_frac: float = 0.0        # -1..1, lateral position in tank

const AERATION_PROFILES: Dictionary = {
	"none": {
		"label": "None (no aeration)",
		"air_rate": 0.0,
		"flow_rate": 0.0,
		"description": "No equipment. Relies on plant photosynthesis + surface gas exchange. Low-stock tanks only.",
	},
	"disk": {
		"label": "Bubble disk (air stone)",
		"air_rate": 1.0,
		"flow_rate": 0.15,
		"description": "Round porous disk on substrate. Dense fine bubble column. Highest aeration. Strips CO2 fast - poor for high-tech planted tanks.",
	},
	"stick": {
		"label": "Bubble stick / wand",
		"air_rate": 0.7,
		"flow_rate": 0.10,
		"description": "Long thin air stone along back wall. Wide bubble curtain. Medium aeration, evenly distributed.",
	},
	"filter": {
		"label": "Hang-on-back filter",
		"air_rate": 0.55,
		"flow_rate": 1.0,
		"description": "Vertical intake + return spout. Moderate aeration via surface agitation, but creates strong water flow that schools fish enjoy.",
	},
}


func current_aeration_profile() -> Dictionary:
	return AERATION_PROFILES.get(aeration_type, AERATION_PROFILES["disk"])


# ---- Substrate ----
# Four substrate "types" with different fertility characteristics. Each
# affects plant growth via SubstrateGrid.NUTRIENT_BASELINE and the
# RESERVOIR_LEAK_PER_TICK (organic richness slowly seeping into water).
var substrate_type: String = "aquasoil"
# Set by settings Apply so the next scene load rebuilds terrain from the
# newly chosen substrate instead of restoring the old saved voxel grid.
var rebuild_terrain_on_load: bool = false

const SUBSTRATE_PROFILES: Dictionary = {
	"aquasoil": {
		"label": "Aquasoil",
		"nutrient_baseline": 0.30,
		"reservoir_leak": 0.00015,
		"colors": [
			Color8(26, 18, 12), Color8(44, 31, 21), Color8(67, 47, 31),
			Color8(93, 65, 40), Color8(120, 85, 56), Color8(149, 113, 78),
		],
		"description": "Rich planted-tank substrate. Default. Plants thrive.",
	},
	"sand": {
		"label": "Sand",
		"nutrient_baseline": 0.10,
		"reservoir_leak": 0.00003,
		"colors": [
			Color8(180, 165, 130), Color8(200, 185, 150), Color8(215, 200, 168),
			Color8(225, 215, 185), Color8(235, 225, 200), Color8(245, 235, 215),
		],
		"description": "Inert white sand. Poor nutrients. Plants grow slowly.",
	},
	"eco_complete": {
		"label": "Eco-Complete",
		"nutrient_baseline": 0.50,
		"reservoir_leak": 0.00030,
		"colors": [
			Color8(15, 12, 10), Color8(28, 22, 18), Color8(40, 32, 26),
			Color8(55, 45, 36), Color8(70, 58, 46), Color8(90, 74, 60),
		],
		"description": "Volcanic black substrate. Very rich. Algae risk.",
	},
	"inert_gravel": {
		"label": "Inert Gravel",
		"nutrient_baseline": 0.05,
		"reservoir_leak": 0.0,
		"colors": [
			Color8(85, 85, 96), Color8(105, 105, 115), Color8(125, 125, 135),
			Color8(145, 145, 155), Color8(165, 165, 175), Color8(185, 185, 195),
		],
		"description": "Sterile gravel. Plants survive only on water column dosing.",
	},
	"ocean_sand": {
		"label": "Ocean sand (saltwater)",
		# Corals don't draw nutrients from substrate the same way plants do
		# - they get most of their energy via photosynthetic zooxanthellae.
		# We keep a small substrate nutrient baseline so the existing
		# plant.tick() growth path still works.
		"nutrient_baseline": 0.12,
		"reservoir_leak": 0.00005,
		"colors": [
			Color8(228, 215, 188), Color8(238, 226, 200), Color8(245, 234, 210),
			Color8(250, 240, 218), Color8(252, 245, 226), Color8(255, 250, 235),
		],
		# is_saltwater flips the world build from plants → corals and
		# unlocks the reef_fish species library entry.
		"is_saltwater": true,
		"description": "Crushed coral / aragonite sand. Reef tank substrate. Spawns corals + reef fish.",
	},
}


func current_substrate_profile() -> Dictionary:
	return SUBSTRATE_PROFILES.get(substrate_type, SUBSTRATE_PROFILES["aquasoil"])


# Save/load via Godot's user settings file. Survives app restarts.
#
# Multi-tank: each tank slot has its own config.cfg under
# user://tanks/<slot>/config.cfg. The TankSaves singleton owns the slot
# layout and tells us which slot is active. Falls back to the legacy
# single-file path on first launch (TankSaves' migration step copies the
# old file into slot 1 so this is a tight backstop, not a hot path).
const LEGACY_SAVE_PATH := "user://tank_config.cfg"


func _current_save_path() -> String:
	var saves := get_node_or_null("/root/TankSaves")
	if saves == null:
		return LEGACY_SAVE_PATH
	return saves.config_path(int(saves.active_slot))


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("tank", "half_w", tank_half_w)
	cfg.set_value("tank", "half_d", tank_half_d)
	cfg.set_value("tank", "height", tank_height)
	cfg.set_value("tank", "shape", tank_shape)
	cfg.set_value("tank", "dome", tank_shape == "sphere")
	cfg.set_value("light", "energy", light_energy)
	cfg.set_value("light", "yaw", light_yaw)
	cfg.set_value("light", "pitch", light_pitch)
	cfg.set_value("light", "warmth", light_warmth)
	cfg.set_value("light", "fixture", light_fixture)
	cfg.set_value("light", "height", light_height)
	cfg.set_value("light", "size", light_size)
	cfg.set_value("light", "volumetric", light_volumetric)
	cfg.set_value("light", "caustics", light_caustics)
	cfg.set_value("music", "enabled", music_enabled)
	cfg.set_value("music", "volume", music_volume)
	cfg.set_value("music", "complexity", music_complexity)
	cfg.set_value("music", "ambient_enabled", music_ambient_enabled)
	cfg.set_value("music", "events_enabled", music_events_enabled)
	cfg.set_value("music", "environment_enabled", music_environment_enabled)
	cfg.set_value("music", "event_volume", music_event_volume)
	cfg.set_value("music", "reactivity", music_reactivity)
	cfg.set_value("music", "mood", music_mood)
	cfg.set_value("music", "style", music_style)
	cfg.set_value("music", "energy", music_energy)
	cfg.set_value("music", "coupling_floor", music_coupling_floor)
	cfg.set_value("music", "smooth_rate", music_smooth_rate)
	cfg.set_value("music", "phrase_churn", music_phrase_churn)
	cfg.set_value("music", "tempo_follow", music_tempo_follow)
	cfg.set_value("music", "kick_mix", music_kick_mix)
	cfg.set_value("music", "bass_mix", music_bass_mix)
	cfg.set_value("music", "arp_mix", music_arp_mix)
	cfg.set_value("music", "pad_mix", music_pad_mix)
	cfg.set_value("music", "hat_mix", music_hat_mix)
	cfg.set_value("music", "sidechain", music_sidechain)
	cfg.set_value("music", "filter_open", music_filter_open)
	cfg.set_value("music", "delay_amount", music_delay_amount)
	cfg.set_value("music", "accent_density", music_accent_density)
	cfg.set_value("music", "influence_fish", music_influence_fish)
	cfg.set_value("music", "influence_plants", music_influence_plants)
	cfg.set_value("music", "influence_bloom", music_influence_bloom)
	cfg.set_value("music", "influence_o2", music_influence_o2)
	cfg.set_value("music", "influence_day", music_influence_day)
	cfg.set_value("music", "influence_aeration", music_influence_aeration)
	cfg.set_value("music", "influence_biomass", music_influence_biomass)
	cfg.set_value("music", "seed", music_seed)
	cfg.set_value("environment", "preset", environment_preset)
	cfg.set_value("substrate", "type", substrate_type)
	cfg.set_value("substrate", "rebuild_terrain", rebuild_terrain_on_load)
	cfg.set_value("aeration", "type", aeration_type)
	cfg.set_value("aeration", "strength", aeration_strength)
	cfg.set_value("aeration", "x_frac", aeration_x_frac)
	cfg.set_value("fauna", "auto_respawn", auto_respawn_fauna)
	cfg.set_value("fauna", "auto_feed", auto_feed_fauna)
	cfg.set_value("preset", "tank", tank_preset)
	cfg.set_value("preset", "glassdarts", custom_glassdart_count)
	cfg.set_value("preset", "mudsifters", custom_mudsifter_count)
	cfg.set_value("preset", "shrimp", custom_shrimp_count)
	cfg.set_value("render", "width", render_width)
	cfg.set_value("render", "height", render_height)
	cfg.set_value("render", "dither", dither_strength)
	cfg.set_value("render", "palette_enabled", palette_enabled)
	cfg.set_value("render", "fog_density", fog_density)
	cfg.set_value("render", "fog_anisotropy", fog_anisotropy)
	cfg.set_value("render", "fog_ambient_inject", fog_ambient_inject)
	cfg.set_value("render", "fov", camera_fov)
	cfg.set_value("render", "msaa", msaa)
	cfg.set_value("camera", "saved", camera_state_saved)
	cfg.set_value("camera", "yaw", camera_yaw)
	cfg.set_value("camera", "pitch", camera_pitch)
	cfg.set_value("camera", "radius", camera_radius)
	cfg.set_value("camera", "target_x", camera_target_x)
	cfg.set_value("camera", "target_y", camera_target_y)
	cfg.set_value("camera", "target_z", camera_target_z)
	cfg.set_value("mobile", "fps_cap", fps_cap)
	cfg.set_value("mobile", "device_tier", device_tier)
	cfg.set_value("mobile", "tutorial_seen", tutorial_seen)
	cfg.set_value("mobile", "last_quit_unix", last_quit_unix)
	cfg.save(_current_save_path())


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(_current_save_path())
	if err != OK:
		# Fallback: legacy single-file path (in case TankSaves hasn't migrated
		# yet — shouldn't happen in normal flow because autoloads load in
		# declaration order, but cheap safety net).
		err = cfg.load(LEGACY_SAVE_PATH)
		if err != OK:
			return
	tank_half_w = cfg.get_value("tank", "half_w", tank_half_w)
	tank_half_d = cfg.get_value("tank", "half_d", tank_half_d)
	tank_height = cfg.get_value("tank", "height", tank_height)
	tank_shape = cfg.get_value("tank", "shape", tank_shape)
	# Legacy saves used "sphere" for the vertical cylinder tank.
	if tank_shape == "sphere" and not bool(cfg.get_value("tank", "dome", false)):
		tank_shape = "cylinder"
	light_energy = cfg.get_value("light", "energy", light_energy)
	light_yaw = cfg.get_value("light", "yaw", light_yaw)
	light_pitch = cfg.get_value("light", "pitch", light_pitch)
	light_warmth = cfg.get_value("light", "warmth", light_warmth)
	light_fixture = cfg.get_value("light", "fixture", light_fixture)
	light_height = cfg.get_value("light", "height", light_height)
	light_size = cfg.get_value("light", "size", light_size)
	light_volumetric = cfg.get_value("light", "volumetric", light_volumetric)
	light_caustics = cfg.get_value("light", "caustics", light_caustics)
	music_enabled = cfg.get_value("music", "enabled", music_enabled)
	music_volume = cfg.get_value("music", "volume", music_volume)
	music_complexity = cfg.get_value("music", "complexity", music_complexity)
	music_ambient_enabled = cfg.get_value("music", "ambient_enabled", music_ambient_enabled)
	music_events_enabled = cfg.get_value("music", "events_enabled", music_events_enabled)
	music_environment_enabled = cfg.get_value("music", "environment_enabled", music_environment_enabled)
	music_event_volume = cfg.get_value("music", "event_volume", music_event_volume)
	music_reactivity = cfg.get_value("music", "reactivity", music_reactivity)
	music_mood = cfg.get_value("music", "mood", music_mood)
	music_style = cfg.get_value("music", "style", music_style)
	music_energy = cfg.get_value("music", "energy", music_energy)
	music_coupling_floor = cfg.get_value("music", "coupling_floor", music_coupling_floor)
	music_smooth_rate = cfg.get_value("music", "smooth_rate", music_smooth_rate)
	music_phrase_churn = cfg.get_value("music", "phrase_churn", music_phrase_churn)
	music_tempo_follow = cfg.get_value("music", "tempo_follow", music_tempo_follow)
	music_kick_mix = cfg.get_value("music", "kick_mix", music_kick_mix)
	music_bass_mix = cfg.get_value("music", "bass_mix", music_bass_mix)
	music_arp_mix = cfg.get_value("music", "arp_mix", music_arp_mix)
	music_pad_mix = cfg.get_value("music", "pad_mix", music_pad_mix)
	music_hat_mix = cfg.get_value("music", "hat_mix", music_hat_mix)
	music_sidechain = cfg.get_value("music", "sidechain", music_sidechain)
	music_filter_open = cfg.get_value("music", "filter_open", music_filter_open)
	music_delay_amount = cfg.get_value("music", "delay_amount", music_delay_amount)
	music_accent_density = cfg.get_value("music", "accent_density", music_accent_density)
	music_influence_fish = cfg.get_value("music", "influence_fish", music_influence_fish)
	music_influence_plants = cfg.get_value("music", "influence_plants", music_influence_plants)
	music_influence_bloom = cfg.get_value("music", "influence_bloom", music_influence_bloom)
	music_influence_o2 = cfg.get_value("music", "influence_o2", music_influence_o2)
	music_influence_day = cfg.get_value("music", "influence_day", music_influence_day)
	music_influence_aeration = cfg.get_value("music", "influence_aeration", music_influence_aeration)
	music_influence_biomass = cfg.get_value("music", "influence_biomass", music_influence_biomass)
	music_seed = int(cfg.get_value("music", "seed", music_seed))
	environment_preset = cfg.get_value("environment", "preset", environment_preset)
	substrate_type = cfg.get_value("substrate", "type", substrate_type)
	rebuild_terrain_on_load = cfg.get_value("substrate", "rebuild_terrain", rebuild_terrain_on_load)
	aeration_type = cfg.get_value("aeration", "type", aeration_type)
	aeration_strength = cfg.get_value("aeration", "strength", aeration_strength)
	aeration_x_frac = cfg.get_value("aeration", "x_frac", aeration_x_frac)
	auto_respawn_fauna = cfg.get_value("fauna", "auto_respawn", auto_respawn_fauna)
	auto_feed_fauna = cfg.get_value("fauna", "auto_feed", auto_feed_fauna)
	tank_preset = cfg.get_value("preset", "tank", tank_preset)
	custom_glassdart_count = cfg.get_value("preset", "glassdarts", custom_glassdart_count)
	custom_mudsifter_count = cfg.get_value("preset", "mudsifters", custom_mudsifter_count)
	custom_shrimp_count = cfg.get_value("preset", "shrimp", custom_shrimp_count)
	render_width = cfg.get_value("render", "width", render_width)
	render_height = cfg.get_value("render", "height", render_height)
	dither_strength = cfg.get_value("render", "dither", dither_strength)
	palette_enabled = cfg.get_value("render", "palette_enabled", palette_enabled)
	fog_density = cfg.get_value("render", "fog_density", fog_density)
	fog_anisotropy = cfg.get_value("render", "fog_anisotropy", fog_anisotropy)
	fog_ambient_inject = cfg.get_value("render", "fog_ambient_inject", fog_ambient_inject)
	camera_fov = cfg.get_value("render", "fov", camera_fov)
	msaa = cfg.get_value("render", "msaa", msaa)
	camera_state_saved = cfg.get_value("camera", "saved", false)
	camera_yaw = cfg.get_value("camera", "yaw", camera_yaw)
	camera_pitch = cfg.get_value("camera", "pitch", camera_pitch)
	camera_radius = cfg.get_value("camera", "radius", camera_radius)
	camera_target_x = cfg.get_value("camera", "target_x", camera_target_x)
	camera_target_y = cfg.get_value("camera", "target_y", camera_target_y)
	camera_target_z = cfg.get_value("camera", "target_z", camera_target_z)
	fps_cap = cfg.get_value("mobile", "fps_cap", fps_cap)
	device_tier = cfg.get_value("mobile", "device_tier", device_tier)
	tutorial_seen = cfg.get_value("mobile", "tutorial_seen", tutorial_seen)
	last_quit_unix = cfg.get_value("mobile", "last_quit_unix", last_quit_unix)


func _ready() -> void:
	load_from_disk()


# Switch the live config to a different tank slot. Called by the menu when
# the player opens a tank — sets the active slot on TankSaves, then reloads
# all fields from that slot's config.cfg.
#
# Resets to script defaults BEFORE loading. Without this, opening a brand-new
# slot (no config.cfg yet) would leave the previous tank's fields in place —
# so the "new tank" the player just created would silently inherit the
# previous tank's preset, substrate, lighting, etc.
func switch_to_slot(slot: int) -> void:
	var saves := get_node_or_null("/root/TankSaves")
	if saves != null:
		saves.set_active(slot)
	reset_to_defaults()
	load_from_disk()


# Reset every per-tank field back to the value declared at the top of this
# file. Used by switch_to_slot so a new slot doesn't inherit from the slot
# the player just left.
#
# Device-level fields (fps_cap, device_tier, tutorial_seen, last_quit_unix)
# are intentionally NOT reset — those reflect the device the user is on, not
# the tank they happen to be in.
func reset_to_defaults() -> void:
	# Tank shape + dimensions.
	tank_shape = "box"
	tank_half_w = 8.0
	tank_half_d = 4.0
	tank_height = 7.0
	# Lighting.
	light_energy = 0.5
	light_yaw = 0.5
	light_pitch = 0.3
	light_warmth = 0.6
	light_fixture = "bar"
	light_height = 1.4
	light_size = 0.75
	light_volumetric = true
	light_caustics = true
	music_enabled = true
	music_volume = 0.7
	music_complexity = 0.5
	music_ambient_enabled = true
	music_events_enabled = true
	music_environment_enabled = true
	music_event_volume = 0.75
	music_reactivity = 0.65
	music_mood = "auto"
	music_style = "hybrid"
	music_energy = 0.55
	music_coupling_floor = 0.55
	music_smooth_rate = 0.55
	music_phrase_churn = 0.5
	music_tempo_follow = 0.72
	music_kick_mix = 0.65
	music_bass_mix = 0.75
	music_arp_mix = 0.85
	music_pad_mix = 0.7
	music_hat_mix = 0.55
	music_sidechain = 0.72
	music_filter_open = 0.5
	music_delay_amount = 0.35
	music_accent_density = 0.5
	music_influence_fish = 1.0
	music_influence_plants = 1.0
	music_influence_bloom = 1.0
	music_influence_o2 = 1.0
	music_influence_day = 1.0
	music_influence_aeration = 1.0
	music_influence_biomass = 1.0
	music_seed = 1
	environment_preset = "void"
	# Fauna behavior.
	auto_respawn_fauna = false
	auto_feed_fauna = false
	# Preset + custom counts.
	tank_preset = "classic_community"
	custom_glassdart_count = 14
	custom_mudsifter_count = 5
	custom_shrimp_count = 12
	# Substrate.
	substrate_type = "aquasoil"
	# Aeration.
	aeration_type = "disk"
	aeration_strength = 0.6
	aeration_x_frac = 0.0
	# Render pipeline.
	render_width = 512
	render_height = 288
	dither_strength = 0.85
	palette_enabled = true
	fog_density = 0.02
	fog_anisotropy = 0.3
	fog_ambient_inject = 0.05
	camera_fov = 50.0
	msaa = 0
	# Camera view.
	camera_state_saved = false
	camera_yaw = -0.55
	camera_pitch = 0.48
	camera_radius = 17.5
	camera_target_x = 0.0
	camera_target_y = 3.0
	camera_target_z = 0.0


func randomize_music_params(wild: bool = false) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	music_seed = rng.randi_range(1, 999999)
	music_volume = rng.randf_range(0.45, 0.9)
	music_complexity = rng.randf_range(0.25, 0.95)
	music_event_volume = rng.randf_range(0.35, 1.0)
	music_reactivity = rng.randf_range(0.4, 1.0)
	music_energy = rng.randf_range(0.25, 0.95)
	music_coupling_floor = rng.randf_range(0.35, 0.85)
	music_smooth_rate = rng.randf_range(0.2, 0.95)
	music_phrase_churn = rng.randf_range(0.15, 0.95)
	music_tempo_follow = rng.randf_range(0.35, 1.0)
	music_kick_mix = rng.randf_range(0.2, 1.0)
	music_bass_mix = rng.randf_range(0.25, 1.0)
	music_arp_mix = rng.randf_range(0.2, 1.0)
	music_pad_mix = rng.randf_range(0.15, 1.0)
	music_hat_mix = rng.randf_range(0.1, 0.95)
	music_sidechain = rng.randf_range(0.25, 1.0)
	music_filter_open = rng.randf_range(0.15, 1.0)
	music_delay_amount = rng.randf_range(0.0, 0.75)
	music_accent_density = rng.randf_range(0.15, 1.0)
	music_influence_fish = rng.randf_range(0.35, 1.5)
	music_influence_plants = rng.randf_range(0.35, 1.5)
	music_influence_bloom = rng.randf_range(0.35, 1.5)
	music_influence_o2 = rng.randf_range(0.35, 1.5)
	music_influence_day = rng.randf_range(0.35, 1.5)
	music_influence_aeration = rng.randf_range(0.25, 1.5)
	music_influence_biomass = rng.randf_range(0.35, 1.5)
	music_ambient_enabled = rng.randf() > 0.15
	music_events_enabled = rng.randf() > 0.08
	music_environment_enabled = rng.randf() > 0.2
	if wild or rng.randf() > 0.35:
		var moods: Array[String] = ["auto", "calm", "bright", "deep"]
		music_mood = moods[rng.randi_range(0, moods.size() - 1)]
	if wild or rng.randf() > 0.25:
		var styles: Array[String] = ["ambient", "hybrid", "trance"]
		music_style = styles[rng.randi_range(0, styles.size() - 1)]
