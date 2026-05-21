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
var camera_yaw: float = -0.35
var camera_pitch: float = 0.30
var camera_radius: float = 14.0
var camera_target_x: float = 0.0
var camera_target_y: float = 3.0
var camera_target_z: float = 0.0
# A "do we have one saved?" flag - false on first launch means use defaults.
var camera_state_saved: bool = false

# ---- Tank shape + dimensions ----
# Glass + substrate geometry. Each shape clips substrate fill + spawn
# regions appropriately so creatures don't appear outside the walls.
#   box       - default rectangular prism (4 walls)
#   cube      - same rectangular geom but enforces W=D (single dimension)
#   hex       - regular hexagonal prism (6 walls)
#   triangle  - equilateral triangular prism (3 walls)
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
# Show volumetric beams (god rays). Off can save a bit of GPU.
var light_volumetric: bool = true

# ---- Tank population preset ----
# Selects the initial stocking of the tank. Each preset specifies how many
# of each species spawn AND a phenotype-range modifier so the founding
# generation has a distinctive look. Custom uses the inline counts.
var tank_preset: String = "community"
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
		"label": "Glassdart tetra",
		"description": "Mid-water schoolers. Electric blue stripe over scarlet body. Streamlined and fast.",
		"genome": {
			"species": "glassdart",
			# Cardinal-tetra inspired: vivid scarlet body, electric blue accent.
			"base_color": Color8(230, 35, 55),
			"accent_color": Color8(60, 170, 240),
			"adult_voxel_scale": 0.18,
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
			"tail_shape": 0,                  # forked - signature tetra tail
			"eye_size_factor": 1.0,
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
		},
	},
	"betta": {
		"label": "Betta (solo apex)",
		"description": "Solitary carnivore. Iridescent royal-blue with magenta finnage. Long sweeping arcs.",
		"genome": {
			"species": "betta",
			# Vibrant royal blue with hot magenta accents.
			"base_color": Color8(40, 90, 235),
			"accent_color": Color8(245, 90, 180),
			"adult_voxel_scale": 0.28,
			"max_age_s": 420.0,
			"max_speed": 1.6,
			"schooling_strength": 0.0,
			"separation_radius": 1.0,
			"herbivory": 0.0,
			"fecundity": 0.0,
			"clutch_size": 0,
			"preferred_y": 3.8,
			"fin_length_factor": 1.4,
			"dorsal_height_factor": 1.35,
			"tail_fork_depth": 0.7,
			"swim_pattern": "cruise",
			"tail_shape": 2,                    # lyre - long flowing trailing rays
			"eye_size_factor": 1.1,
			"back_arch": 1.15,                  # mild hump
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
			"swim_pattern": "shoal",
			"tail_shape": 1,                     # fan - signature guppy
			"eye_size_factor": 1.05,
			"ventral_profile": 1.1,
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
			"swim_pattern": "hover",
			# Angelfish signature: tall arched body, lyre tail, mid-sized eyes.
			"tail_shape": 2,                    # lyre
			"eye_size_factor": 1.0,
			"back_arch": 1.45,                  # tall arched silhouette
			"ventral_profile": 1.15,
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
}


func current_tank_preset() -> Dictionary:
	return TANK_PRESETS.get(tank_preset, TANK_PRESETS["community"])


# ---- Aeration / air system ----
# Vivarium models a tank-wide dissolved-O2 level (0..1, 1=saturated) that
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
}


func current_substrate_profile() -> Dictionary:
	return SUBSTRATE_PROFILES.get(substrate_type, SUBSTRATE_PROFILES["aquasoil"])


# Save/load via Godot's user settings file. Survives app restarts.
const SAVE_PATH := "user://tank_config.cfg"


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("tank", "half_w", tank_half_w)
	cfg.set_value("tank", "half_d", tank_half_d)
	cfg.set_value("tank", "height", tank_height)
	cfg.set_value("tank", "shape", tank_shape)
	cfg.set_value("light", "energy", light_energy)
	cfg.set_value("light", "yaw", light_yaw)
	cfg.set_value("light", "pitch", light_pitch)
	cfg.set_value("light", "warmth", light_warmth)
	cfg.set_value("light", "fixture", light_fixture)
	cfg.set_value("light", "height", light_height)
	cfg.set_value("light", "size", light_size)
	cfg.set_value("light", "volumetric", light_volumetric)
	cfg.set_value("substrate", "type", substrate_type)
	cfg.set_value("aeration", "type", aeration_type)
	cfg.set_value("aeration", "strength", aeration_strength)
	cfg.set_value("aeration", "x_frac", aeration_x_frac)
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
	cfg.save(SAVE_PATH)


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		return
	tank_half_w = cfg.get_value("tank", "half_w", tank_half_w)
	tank_half_d = cfg.get_value("tank", "half_d", tank_half_d)
	tank_height = cfg.get_value("tank", "height", tank_height)
	tank_shape = cfg.get_value("tank", "shape", tank_shape)
	light_energy = cfg.get_value("light", "energy", light_energy)
	light_yaw = cfg.get_value("light", "yaw", light_yaw)
	light_pitch = cfg.get_value("light", "pitch", light_pitch)
	light_warmth = cfg.get_value("light", "warmth", light_warmth)
	light_fixture = cfg.get_value("light", "fixture", light_fixture)
	light_height = cfg.get_value("light", "height", light_height)
	light_size = cfg.get_value("light", "size", light_size)
	light_volumetric = cfg.get_value("light", "volumetric", light_volumetric)
	substrate_type = cfg.get_value("substrate", "type", substrate_type)
	aeration_type = cfg.get_value("aeration", "type", aeration_type)
	aeration_strength = cfg.get_value("aeration", "strength", aeration_strength)
	aeration_x_frac = cfg.get_value("aeration", "x_frac", aeration_x_frac)
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


func _ready() -> void:
	load_from_disk()
