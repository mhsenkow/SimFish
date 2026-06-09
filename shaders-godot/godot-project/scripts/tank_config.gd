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
# When true, dither strength varies by region (heavy on low-saturation
# water/fog, light on saturated fauna). When false, the legacy uniform
# dither applies everywhere.
var dither_region_aware: bool = true
# When true, the active palette is locally restricted to a hue-bank of
# ~16 nearest indices for each fragment, enforcing the "real" 8-bit feel
# instead of a downsampled HDR blend. Cosmetic — bank picking is per
# fragment, no asset change.
var palette_bank_lock: bool = true
# Soft global outline at color-discontinuities (NES-style readability).
# 0 = off (default), up to 1 = strong dark line on every silhouette.
var outline_strength: float = 0.0
# CRT scanline overlay strength. 0 = off (default). Pairs with palette
# quantize for a heavier retro display feel.
var crt_strength: float = 0.0
# Force integer (nearest-multiple) scaling between SubViewport and the
# display rect so each rendered pixel snaps to a fixed integer block on
# the final monitor. Eliminates subpixel shimmer on creature motion at
# the cost of letterboxing.
var integer_upscale: bool = false
# Adaptive quality — main.gd watches a rolling FPS average and steps the
# SubViewport resolution (plus optionally MSAA / fog) down when frame
# rate falls below the target, then back up when there's headroom.
# Lets a single TankConfig render the tank correctly across desktop +
# mobile without manual tuning.
var adaptive_quality: bool = false
var adaptive_quality_target_fps: int = 55
# Snap the orbit camera to the world-space size of a single render pixel
# so swimming creatures don't sub-pixel-jitter against the static
# substrate / hardscape. Off by default — interferes slightly with very
# smooth auto-orbit cinematography.
var pixel_snap_camera: bool = false
# If false, the palette pass is bypassed and you see raw HDR colors. Useful
# for spotting bugs in lighting + composition.
var palette_enabled: bool = true
# Volumetric fog parameters.
var fog_density: float = 0.02
var fog_anisotropy: float = 0.3
var fog_ambient_inject: float = 0.05
# Global material tint — render overlay; does not mutate saved genomes.
var material_hue_shift: float = 0.0
var material_saturation: float = 1.0
var material_warmth: float = 0.0
var material_value: float = 1.0
var material_weight_fauna: float = 1.0
var material_weight_foliage: float = 1.0
var material_weight_substrate: float = 1.0
var material_weight_hardscape: float = 1.0
var material_weight_water: float = 0.75
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

# ---- Light spectrum ----
# 0.0 = cool / blue-shifted LED (boosts greens, suppresses reds)
# 0.5 = neutral white (default)
# 1.0 = warm / red-shifted LED (boosts reds, dims greens)
# Plant red_potential intensification is scaled by this — real keepers
# pick warm-spectrum bulbs specifically to make red plants pop.
var light_spectrum: float = 0.5

# ---- CO2 dosing ----
# 0.0 = off (no injection, ambient ~equilibrium CO2 only)
# 0.3 = low (passive yeast / DIY, mild boost)
# 0.6 = medium (entry-level regulator, supports most stems)
# 1.0 = high (pressurized + drop checker, supports demanding species like
#       Rotala macrandra, HC Cuba, Eriocaulon)
# Plant red-intensification, pearling intensity, and growth-rate floors
# all read this value via SimDriver.co2_level().
var co2_level: float = 0.0

# ---- AI Companion (optional local Ollama bridge) ----
# When enabled, AIDirector batches calls to a local Ollama instance for
# creature names, biographies, ambient mood drifts, and chronicle lines.
# Defaults are off — the sim is fully playable without it, and offline
# fallback names always work even when toggled on but Ollama isn't running.
var ai_enabled: bool = false
var ai_endpoint: String = "http://localhost:11434"
# Default to qwen2.5:3b — small (~2GB), fast, strong at structured JSON
# outputs, no Meta involvement. The "Use installed model" button in the
# settings panel auto-substitutes from the user's actual installed list.
var ai_model: String = "qwen2.5:3b"
# Optional flavor instruction passed to the name generator: "Greek gods",
# "Lord of the Rings", "Tropical reef", etc. Empty = neutral pool.
var ai_naming_theme: String = ""
# When true, AIDirector composes one-sentence narrations from notable tank
# events. Surfaces via the main HUD when wired. Independent toggle so
# players who like AI names but find narration noisy can keep just names.
var ai_chronicle: bool = false
# True once the user has dismissed the onboarding modal at least once. The
# settings panel uses this to stop nagging.
var ai_onboarding_seen: bool = false

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
# How new tanks pick footprint before the player edits shape sliders.
# auto = portrait → tall round (cylinder), landscape → wide rectangle;
# rect = always box; round = cylinder (square/cube uses shape picker).
var new_tank_fit: String = "auto"
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
# Night-only player toggle — when false the aquarium fixture is off but the
# sim day/night cycle keeps running.
var tank_lights_on: bool = true
# Master kill switch for all aquarium lighting (sun + fixture + ambient).
# When false the tank is essentially pitch black so the user can see how
# their bioluminescence/effects read without the room light fighting them.
var light_master_enabled: bool = true
# When false the day_phase value is frozen — the sun stops moving but the
# rest of the sim (animals, growth, water chem) keeps ticking.
var day_cycle_enabled: bool = true

# ---- Split global vs tank-fixture controls (introduced 2026 lighting pass) ----
# light_energy / light_warmth historically controlled BOTH the postprocess
# tint and the artificial tank fixture. Now they're split so the user can
# dim the global scene while keeping the tank lights bright (or vice versa).
# global_* drives the palette_quantize tint (sun, sky, room).
# tank_fixture_* drives the overhead artificial fixture only.
var global_intensity: float = 0.5
var global_warmth: float = 0.6
var tank_fixture_intensity: float = 0.5
# Full RGB color for the fixture (replaces the warmth axis). Default ≈ warm
# white. Reef tanks like a strong blue here, planted tanks a pink-magenta.
var tank_fixture_color: Color = Color(1.0, 0.95, 0.85)

# ---- Day length + sunset drama ----
# Sim day cycle length in seconds (real time at 1× sim speed). Used to be
# the locked 360s SIM_DRIVER.DAY_LENGTH_S const; now slider-driven.
var day_length_s: float = 360.0
# Multiplier on dusk warmth + deep-night dip. 0 = flat (no sunset drama),
# 1 = legacy default, 2 = exaggerated golden hour + very dark midnight.
var sunset_drama: float = 0.75

# ---- Moonlight + accent point lights ----
var moonlight_enabled: bool = true
var moonlight_intensity: float = 0.4
var moonlight_color: Color = Color(0.55, 0.70, 1.0)
var accent1_enabled: bool = false
var accent1_intensity: float = 0.6
var accent1_color: Color = Color(1.0, 0.45, 0.75)
var accent2_enabled: bool = false
var accent2_intensity: float = 0.6
var accent2_color: Color = Color(0.45, 0.85, 1.0)

# ---- Post-process exposure (palette_quantize uniforms surfaced to user) ----
# Vignette + bloom are new; dither / outline / crt already live in the render
# section of TankConfig (see top of file) — the Light panel writes to those
# directly so there's only one source of truth.
var pp_vignette_strength: float = 0.24
var pp_vignette_falloff: float = 1.6
var pp_bloom_threshold: float = 0.72
var pp_bloom_strength: float = 0.68

# ---- Ambient + sim-driven additions ----
# Lifts the "darkness floor" of master-on night scenes so the user can keep
# moonlit shapes legible. 0 = legacy (pitch night), 1 = bright ambient floor.
var ambient_floor: float = 0.0
# Multiplier on every fish/coral biolum strength uniform. >1 boosts the glow;
# 0 hides biolum entirely. Animation curve in fish.gd is preserved.
var biolum_multiplier: float = 1.0
# Multiplier on the computed caustic intensity. Lets the user dial caustics
# down without flipping the on/off toggle.
var caustic_intensity_user: float = 1.0

# ---- Per-phase tint overrides (advanced custom palette) ----
# When tod_use_overrides is on, _update_palette_tod_tint reads these four
# anchor colors instead of the built-in _TOD_* constants. Lets the user
# paint dawn/day/dusk/night their way.
var tod_use_overrides: bool = false
var tod_dawn_color: Color = Color(1.02, 0.88, 0.82)
var tod_day_color: Color = Color(1.00, 1.00, 1.00)
var tod_dusk_color: Color = Color(1.04, 0.82, 0.70)
var tod_night_color: Color = Color(0.38, 0.42, 0.52)

# Active preset slug. "custom" means "user has touched sliders / not on
# a preset". Setting this to a slug applies the preset's values.
var lighting_preset: String = "custom"

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
# Festival vibe — build/drop architecture, lead, lo-fi character.
# auto = follow tank ; trance = aggressive 16-bar verse / 8-bar build / 16-bar drop ;
# loop = stay in verse (chill background) ; free = let events nudge it.
var music_phrase_form: String = "auto"
var music_drop_intensity: float = 0.7
var music_breakdown_depth: float = 0.7
var music_lead_mix: float = 0.55
var music_lead_detune: float = 0.55
var music_vinyl_crackle: float = 0.2
var music_tape_wow: float = 0.18
var music_jazziness: float = 0.4
var music_swing: float = 0.06
var music_offbeat_hat: float = 0.55
var music_reverb_send: float = 0.45
var music_humanize: float = 0.22
var music_species_palette: float = 0.75
# Extra voices.
var music_sub_bass_mix: float = 0.55
var music_offbeat_bass_mix: float = 0.35
var music_granular_pad: float = 0.25
var music_vocoder_pad: float = 0.25
var music_shaker_mix: float = 0.4
var music_clap_mix: float = 0.45
# Build dramaturgy.
var music_build_drama: float = 0.7
# Tank-state driven sound (auto-tied; knobs scale sensitivity).
var music_bitcrush_algae: float = 0.6
var music_bass_grit: float = 0.5
var music_pump_gate: float = 0.6
# Harmony.
var music_key_mod: float = 0.35
# Master breathe LFO depth (0..1).
var music_breathe_lfo: float = 0.35

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
		"description": "Warm wooden desk + plaster wall + bedside lamp. Pairs with Warm desk lamp lighting.",
		"suggested_lighting": "cozy_shop",
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
		"description": "Pale wood ledge + daylight from a window. Pairs with Window daylight lighting.",
		"suggested_lighting": "sunny",
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
		"label": "Display cabinet",
		"description": "Walnut cabinet + cool room fill. Pairs with Shop display or Dim warm lamp lighting.",
		"suggested_lighting": "shop_display",
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
		"description": "Mossy log shelf + soft green daylight through trees. Pairs with Planted tank lighting.",
		"suggested_lighting": "planted",
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
# Live swim/grouping multipliers — read every fish tick; no reload required.
var fauna_schooling_mult: float = 1.0
var fauna_separation_mult: float = 1.0
var fauna_wander_mult: float = 1.0
var fauna_speed_mult: float = 1.0
var fauna_school_pulse_enabled: bool = true
var fauna_school_pulse_amplitude: float = 0.15
var fauna_mourning_enabled: bool = true
var fauna_player_glance_enabled: bool = true

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
			# Bettas are obligate territorial: alpha males relentlessly
			# chase any same-species intruder out of their zone. With one
			# betta per tank this rarely fires (no conspecific to chase),
			# but two bettas immediately reveal the behavior.
			"is_territorial": true,
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
			# Dwarf puffers are fiercely territorial in real life — they
			# claim a corner and chase out anything that tries to share it.
			"is_territorial": true,
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
			# Angelfish are cichlids — territorial pair-bonders that
			# defend a small zone around their spawning site. With
			# mouthbrooding active too, breeding pairs visibly carry fry
			# in the throat before release.
			"is_territorial": true,
			"is_mouthbrooder": true,
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
	"otocinclus": {
		"label": "Otocinclus (algae grazer)",
		"description": "Small armored catfish that clings to glass + broad-leaf plants and rasps algae. Schools loosely; ignored by most fish. The dedicated freshwater algae-eater the snails can't quite replace.",
		"genome": {
			"species": "otocinclus",
			# Pale tan-brown with a dark lateral stripe running snout-to-tail.
			"base_color": Color8(180, 155, 115),
			"accent_color": Color8(58, 48, 38),
			"marking_color": Color8(85, 70, 55),
			"adult_voxel_scale": 0.12,
			"size_potential": 0.85,
			"jaw_claw_size": 0.04,
			"max_age_s": 280.0,
			"max_speed": 0.85,
			"schooling_strength": 0.85,
			"separation_radius": 0.45,
			# Strong herbivory + the algae_grazer flag drives the existing
			# fish-graze-algae path. Otos make algae a real food source
			# for fish, not just a visual problem for the player.
			"herbivory": 1.0,
			"fecundity": 0.3,
			"clutch_size": 2,
			"preferred_y": 1.4,                  # bottom + glass crawler
			"body_elongation": 1.10,
			"body_depth_factor": 0.85,
			"fin_length_factor": 0.85,
			"dorsal_height_factor": 0.7,
			"tail_fork_depth": 0.35,
			"pattern_type": 1,                   # horizontal stripe
			"swim_pattern": "shuffle",           # glass-cling crawl
			"tail_shape": 0,
			"eye_size_factor": 1.05,
			"mouth_orientation": 1,              # downturned (rasping)
			"armor_plates": true,                # scaleless catfish armor
			"algae_grazer": true,
		},
	},
	"bristlenose_pleco": {
		"label": "Bristlenose pleco (wood rasper)",
		"description": "Stout armored catfish that rasps driftwood for fiber + algae. The big chunky bottom dweller that finally makes driftwood ecologically meaningful. One per tank — they're territorial about their log.",
		"genome": {
			"species": "bristlenose_pleco",
			# Dark mottled brown body with paler belly + bristly snout.
			"base_color": Color8(78, 62, 48),
			"accent_color": Color8(135, 110, 82),
			"marking_color": Color8(45, 35, 28),
			"adult_voxel_scale": 0.20,
			"size_potential": 1.30,
			"jaw_claw_size": 0.10,
			"max_age_s": 540.0,
			"max_speed": 0.55,
			"schooling_strength": 0.0,
			"separation_radius": 1.4,
			"herbivory": 0.9,
			"fecundity": 0.15,
			"clutch_size": 2,
			"preferred_y": 1.0,                  # hugs the bottom + wood
			"body_elongation": 1.25,
			"body_depth_factor": 1.10,
			"head_proportion": 1.30,
			"fin_length_factor": 1.10,
			"dorsal_height_factor": 1.45,
			"tail_fork_depth": 0.30,
			"pattern_type": 2,                   # mottled spots
			"color_dot_count": 5,
			"swim_pattern": "shuffle",
			"tail_shape": 3,                     # square paddle
			"eye_size_factor": 0.85,
			"mouth_orientation": 1,              # underslung rasping mouth
			"has_barbels": true,                 # bristle snout proxy
			"armor_plates": true,
			"algae_grazer": true,
			"is_territorial": true,              # owns the driftwood log
			# Wood-grazing mark — fish.gd reads this to bias scavenge
			# behavior toward driftwood voxels. With wood_grazer=true,
			# the bristlenose visibly hangs on the wood rasping at
			# biofilm instead of cruising the substrate.
			"wood_grazer": true,
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
			# Dwarf gourami defend a territory around their bubble nest;
			# alpha males chase rivals out of home_radius. Mouthbrooding
			# is a creative liberty (real dwarf gourami are bubble-nest
			# builders) — the visible throat-bulge cue reads as parental
			# care, which is the gameplay we want.
			"is_territorial": true,
			"is_mouthbrooder": true,
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
# Lighting presets — applied by Light panel. Each entry sets a subset of
# the lighting vars. Keys omitted in a preset stay at the user's current
# value, so a preset is a "delta" not a full reset. "custom" is the empty
# default for "user is on their own".
const LIGHTING_PRESETS: Dictionary = {
	"sunny": {
		"label": "Window daylight",
		"global_intensity": 0.58, "global_warmth": 0.52,
		"tank_fixture_intensity": 0.36,
		"tank_fixture_color": Color(0.98, 0.96, 0.90),
		"tank_lights_on": false,
		"light_caustics": true,
		"sunset_drama": 0.62,
		"pp_vignette_strength": 0.20, "pp_bloom_strength": 0.62,
	},
	"cozy_shop": {
		"label": "Warm desk lamp",
		"global_intensity": 0.48, "global_warmth": 0.72,
		"tank_fixture_intensity": 0.56,
		"tank_fixture_color": Color(1.0, 0.90, 0.78),
		"tank_lights_on": true, "light_caustics": true,
		"sunset_drama": 0.72,
		"pp_vignette_strength": 0.26, "pp_bloom_strength": 0.66,
	},
	"shop_display": {
		"label": "Shop display",
		"global_intensity": 0.44, "global_warmth": 0.48,
		"tank_fixture_intensity": 0.58,
		"tank_fixture_color": Color(0.94, 0.96, 1.0),
		"tank_lights_on": true, "light_caustics": true,
		"sunset_drama": 0.58,
		"pp_vignette_strength": 0.22, "pp_bloom_strength": 0.64,
	},
	"moonlit": {
		"label": "Moonlit room",
		"global_intensity": 0.34, "global_warmth": 0.28,
		"tank_fixture_intensity": 0.30,
		"tank_fixture_color": Color(0.84, 0.88, 0.94),
		"tank_lights_on": false,
		"moonlight_enabled": true, "moonlight_intensity": 0.42,
		"moonlight_color": Color(0.62, 0.72, 0.88),
		"sunset_drama": 0.82,
		"pp_vignette_strength": 0.28, "pp_bloom_strength": 0.58,
		"pp_bloom_threshold": 0.72,
	},
	"sunset": {
		"label": "Golden hour",
		"global_intensity": 0.54, "global_warmth": 0.76,
		"tank_fixture_intensity": 0.38,
		"tank_fixture_color": Color(1.0, 0.84, 0.70),
		"tank_lights_on": false,
		"sunset_drama": 0.88,
		"pp_vignette_strength": 0.32, "pp_bloom_strength": 0.72,
	},
	"storm": {
		"label": "Overcast day",
		"global_intensity": 0.42, "global_warmth": 0.46,
		"tank_fixture_intensity": 0.40,
		"tank_fixture_color": Color(0.92, 0.94, 0.98),
		"tank_lights_on": false,
		"light_caustics": false,
		"sunset_drama": 0.50,
		"pp_vignette_strength": 0.24, "dither_strength": 0.72,
		"pp_bloom_strength": 0.58,
	},
	"reef": {
		"label": "Reef LEDs",
		"global_intensity": 0.54, "global_warmth": 0.44,
		"tank_fixture_intensity": 0.66,
		"tank_fixture_color": Color(0.78, 0.88, 1.0),
		"tank_lights_on": true, "light_caustics": true,
		"sunset_drama": 0.52,
		"pp_bloom_threshold": 0.68, "pp_bloom_strength": 0.70,
	},
	"planted": {
		"label": "Planted tank",
		"global_intensity": 0.56, "global_warmth": 0.58,
		"tank_fixture_intensity": 0.60,
		"tank_fixture_color": Color(0.94, 0.98, 0.90),
		"tank_lights_on": true, "light_caustics": true,
		"sunset_drama": 0.68,
		"pp_bloom_strength": 0.66,
	},
	"dim_warm": {
		"label": "Dim warm lamp",
		"global_intensity": 0.38, "global_warmth": 0.76,
		"tank_fixture_intensity": 0.48,
		"tank_fixture_color": Color(1.0, 0.86, 0.72),
		"tank_lights_on": true, "light_caustics": true,
		"sunset_drama": 0.55,
		"pp_vignette_strength": 0.26, "pp_bloom_strength": 0.60,
	},
}


func apply_lighting_preset(slug: String) -> void:
	lighting_preset = slug
	if slug == "custom" or not LIGHTING_PRESETS.has(slug):
		return
	var preset: Dictionary = LIGHTING_PRESETS[slug]
	for key in preset.keys():
		if key == "label":
			continue
		set(key, preset[key])


func suggested_lighting_for_environment(env_slug: String) -> String:
	var prof: Dictionary = ENVIRONMENT_PRESETS.get(env_slug, {})
	return String(prof.get("suggested_lighting", ""))


# One-time pairing for saves that picked a room but never chose a lighting preset.
func _pair_environment_lighting_if_legacy() -> void:
	if lighting_preset != "custom" or environment_preset == "void":
		return
	var looks_legacy: bool = (
		is_equal_approx(pp_vignette_strength, 0.35)
		and is_equal_approx(pp_bloom_strength, 0.85)
		and sunset_drama >= 0.95
	)
	if not looks_legacy:
		return
	var suggested: String = suggested_lighting_for_environment(environment_preset)
	if suggested != "":
		apply_lighting_preset(suggested)


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
			"dwarf_gourami": 2, "otocinclus": 3, "shrimp": 12,
		},
		"phenotype_spread": 0.6,
		# Default Walstad jungle — every plant species at full density.
		"plant_palette": {
			"valli": 1.0, "crypt": 1.0, "red_stem": 1.0,
			"carpet": 1.0, "moss": 1.0, "java_fern": 1.0,
		},
		"hardscape_style": "default",
		"description": "The textbook beginner freshwater community: a cardinal tetra school + harlequin rasbora shoal + corydoras bottom team + a dwarf gourami territorial pair (watch the alpha chase the other off his patch and incubate fry in his throat). Cherry shrimp cleanup crew includes 2 amano-style cleaners that station near stressed fish.",
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
		# Sparse plants on the predator tank — leaves clean sight-lines
		# so the betta vs. puffer territorial chases read against the
		# substrate. Two mossy corners give shrimp + prey schools refuge.
		"plant_palette": {
			"valli": 0.3, "crypt": 0.4, "red_stem": 0.2,
			"carpet": 0.55, "moss": 1.2, "java_fern": 0.8,
		},
		"hardscape_style": "predator_corners",
		"terrain_relief": [
			# Two opposing corner mounds give each apex a defensible
			# territory; the middle stays open for chases.
			{"x": -0.65, "z": -0.55, "radius": 4, "mode": "raise"},
			{"x":  0.65, "z":  0.55, "radius": 4, "mode": "raise"},
		],
		"description": "Lots of prey + a betta and a puffer claiming opposite corners. Each apex gets a raised territorial mound; the prey schools try to hold the open middle.",
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
			"angelfish": 2, "dwarf_gourami": 2, "killifish": 4,
			"guppy": 6, "corydoras": 4, "otocinclus": 3,
			"bristlenose_pleco": 1, "shrimp": 14,
		},
		"phenotype_spread": 0.8,
		# Every plant type at moderate density so the showcase has the
		# whole catalogue of leaf forms (ribbon, paddle, lance, needle,
		# moss, paddle-epiphyte) visible at once.
		"plant_palette": {
			"valli": 0.85, "crypt": 1.0, "red_stem": 1.1,
			"carpet": 0.9, "moss": 1.3, "java_fern": 1.3,
		},
		"hardscape_style": "twin_logs",
		"terrain_relief": [
			# Central planted ridge runs front-to-back, with a small
			# foreground dip where the cory team patrols.
			{"x": 0.0,  "z": 0.0,  "radius": 5, "mode": "raise"},
			{"x": 0.0,  "z": 0.65, "radius": 3, "mode": "dig"},
		],
		"description": "Showcase of every behavior: angelfish + dwarf gourami pairs both incubate fry in their throats (visible bulge), defend territories from same-species rivals, and dance distinct courtship patterns. Killifish dart at the surface, guppies parallel-display, corydoras shuffle the substrate. A planted central ridge + twin driftwood logs frame the action.",
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
	# ---- Scenario-specific presets ----
	# Tightly-curated stocking dicts that pair with the new-tank scenario
	# picker. Each is shaped around what THAT scenario wants to show off.
	"polyp_lab": {
		"label": "Polyp lab (no fish)",
		# Zero fish — the showcase here is the sessile + microfauna layer.
		# Heavy shrimp colony so the scavenger loop reads, but the visual
		# centerpiece is the freshwater hydra polyps (hydra_fresh coral
		# form) that world.gd auto-seeds on eco_complete substrate.
		"stocking": {"shrimp": 24},
		"phenotype_spread": 1.4,
		# Visual signature: a single moss-and-needle-grass tuft in the
		# middle of the sphere, no other plants — keeps the polyps and
		# clams visually dominant but with a green island for life. A
		# small driftwood nub sticks up like a fallen branch.
		"plant_palette": {
			"carpet": 0.55, "moss": 0.40, "java_fern": 0.30,
			"valli": 0.0, "crypt": 0.0, "red_stem": 0.0,
		},
		"hardscape_style": "polyp_jar",
		"terrain_relief": [
			# Central low mound where the polyps gather, ringed by a
			# shallow trough so the eye reads it as an "island".
			{"x": 0.0, "z": 0.0, "radius": 3, "mode": "raise"},
			{"x": 0.0, "z": 1.6, "radius": 2, "mode": "dig"},
			{"x": 0.0, "z": -1.6, "radius": 2, "mode": "dig"},
		],
		"description": "Fishless biosphere: dense cherry shrimp colony + freshwater hydra polyps + filter-feeding clams. A single moss-and-grass island in the middle gives shrimp cover; the rest is open substrate.",
	},
	"iwagumi_school": {
		"label": "Iwagumi (single school)",
		# Pure cardinal-tetra school, no apex, sparse cleanup crew.
		"stocking": {"glassdart": 18, "shrimp": 4},
		"phenotype_spread": 0.2,
		# Pure carpet — no stem plants, no rosettes. The negative space
		# carries the composition.
		"plant_palette": {
			"valli": 0.0, "crypt": 0.0, "red_stem": 0.0,
			"carpet": 0.85, "moss": 0.0, "java_fern": 0.0,
		},
		"hardscape_style": "iwagumi",
		"terrain_relief": [
			# Two gentle dunes on either side of the central stone
			# arrangement, classic Iwagumi composition.
			{"x": -0.45, "z": 0.0, "radius": 4, "mode": "raise"},
			{"x":  0.55, "z": 0.0, "radius": 5, "mode": "raise"},
		],
		"description": "Zen-garden minimalism: a single tight cardinal tetra school over sand. Just three stones + a clean carpet — no driftwood, no stems. Two gentle dunes rise on either side of the stones.",
	},
	"cichlid_pairs": {
		"label": "Cichlid pairs",
		# Two centerpiece pairs (angelfish + dwarf gourami) on a corydoras
		# bottom team. No schooling fish, no shrimp — territorial drama is
		# the entertainment.
		"stocking": {
			"angelfish": 2, "dwarf_gourami": 2, "corydoras": 5,
		},
		"phenotype_spread": 0.6,
		# Sword-like blade plants flanking the rocks, with epiphytic java
		# fern on the boulders. No dense back-wall valli forest — clean
		# sight-lines so you can watch the territorial chases.
		"plant_palette": {
			"valli": 0.45, "crypt": 0.8, "red_stem": 0.5,
			"carpet": 0.4, "moss": 0.6, "java_fern": 1.4,
		},
		"hardscape_style": "boulder_field",
		"terrain_relief": [
			# Two raised plateaus (the dominant pair's territories) with
			# a low trough running between them.
			{"x": -0.55, "z": 0.0, "radius": 4, "mode": "raise"},
			{"x":  0.55, "z": 0.0, "radius": 4, "mode": "raise"},
			{"x":  0.0,  "z": 0.0, "radius": 3, "mode": "dig"},
		],
		"description": "Cichlid social drama. Two stone plateaus rise on either side of a central trough — each pair claims one. Java fern on the boulders. Cory team patrols the open lane between.",
	},
	"blackwater_biotope": {
		"label": "Blackwater biotope",
		# Surface darts + bottom shufflers + small guppy mid-water school.
		# No betta/puffer — biotope is peaceful but ecologically rich.
		"stocking": {
			"killifish": 6, "corydoras": 5, "guppy": 4, "shrimp": 8,
		},
		"phenotype_spread": 1.1,
		# Sparse stems, lots of moss-on-driftwood, ribbon vallisneria
		# only at the back. The wood is the star.
		"plant_palette": {
			"valli": 0.8, "crypt": 0.4, "red_stem": 0.2,
			"carpet": 0.25, "moss": 1.6, "java_fern": 1.2,
		},
		"hardscape_style": "blackwater_heavy_wood",
		"terrain_relief": [
			# Asymmetric: one side mounded (where the wood pile sits),
			# the other side dug down so leaf litter pools there.
			{"x": -0.45, "z": -0.30, "radius": 4, "mode": "raise"},
			{"x":  0.45, "z":  0.40, "radius": 3, "mode": "dig"},
		],
		"description": "Amazonian biotope: surface-darting killifish, bottom-sifting cory, livebearer guppies. A tangle of driftwood dominates one side, with a leaf-litter hollow on the other. Moss + java fern carpet the wood.",
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
	cfg.set_value("light", "tank_on", tank_lights_on)
	cfg.set_value("light", "master_enabled", light_master_enabled)
	cfg.set_value("light", "day_cycle_enabled", day_cycle_enabled)
	cfg.set_value("light", "global_intensity", global_intensity)
	cfg.set_value("light", "global_warmth", global_warmth)
	cfg.set_value("light", "tank_fixture_intensity", tank_fixture_intensity)
	cfg.set_value("light", "tank_fixture_color",
		[tank_fixture_color.r, tank_fixture_color.g, tank_fixture_color.b])
	cfg.set_value("light", "day_length_s", day_length_s)
	cfg.set_value("light", "sunset_drama", sunset_drama)
	cfg.set_value("light", "moonlight_enabled", moonlight_enabled)
	cfg.set_value("light", "moonlight_intensity", moonlight_intensity)
	cfg.set_value("light", "moonlight_color",
		[moonlight_color.r, moonlight_color.g, moonlight_color.b])
	cfg.set_value("light", "accent1_enabled", accent1_enabled)
	cfg.set_value("light", "accent1_intensity", accent1_intensity)
	cfg.set_value("light", "accent1_color",
		[accent1_color.r, accent1_color.g, accent1_color.b])
	cfg.set_value("light", "accent2_enabled", accent2_enabled)
	cfg.set_value("light", "accent2_intensity", accent2_intensity)
	cfg.set_value("light", "accent2_color",
		[accent2_color.r, accent2_color.g, accent2_color.b])
	cfg.set_value("light", "pp_vignette_strength", pp_vignette_strength)
	cfg.set_value("light", "pp_vignette_falloff", pp_vignette_falloff)
	cfg.set_value("light", "pp_bloom_threshold", pp_bloom_threshold)
	cfg.set_value("light", "pp_bloom_strength", pp_bloom_strength)
	cfg.set_value("light", "ambient_floor", ambient_floor)
	cfg.set_value("light", "biolum_multiplier", biolum_multiplier)
	cfg.set_value("light", "caustic_intensity_user", caustic_intensity_user)
	cfg.set_value("light", "tod_use_overrides", tod_use_overrides)
	cfg.set_value("light", "tod_dawn_color",
		[tod_dawn_color.r, tod_dawn_color.g, tod_dawn_color.b])
	cfg.set_value("light", "tod_day_color",
		[tod_day_color.r, tod_day_color.g, tod_day_color.b])
	cfg.set_value("light", "tod_dusk_color",
		[tod_dusk_color.r, tod_dusk_color.g, tod_dusk_color.b])
	cfg.set_value("light", "tod_night_color",
		[tod_night_color.r, tod_night_color.g, tod_night_color.b])
	cfg.set_value("light", "preset", lighting_preset)
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
	cfg.set_value("music", "phrase_form", music_phrase_form)
	cfg.set_value("music", "drop_intensity", music_drop_intensity)
	cfg.set_value("music", "breakdown_depth", music_breakdown_depth)
	cfg.set_value("music", "lead_mix", music_lead_mix)
	cfg.set_value("music", "lead_detune", music_lead_detune)
	cfg.set_value("music", "vinyl_crackle", music_vinyl_crackle)
	cfg.set_value("music", "tape_wow", music_tape_wow)
	cfg.set_value("music", "jazziness", music_jazziness)
	cfg.set_value("music", "swing", music_swing)
	cfg.set_value("music", "offbeat_hat", music_offbeat_hat)
	cfg.set_value("music", "reverb_send", music_reverb_send)
	cfg.set_value("music", "humanize", music_humanize)
	cfg.set_value("music", "species_palette", music_species_palette)
	cfg.set_value("music", "sub_bass_mix", music_sub_bass_mix)
	cfg.set_value("music", "offbeat_bass_mix", music_offbeat_bass_mix)
	cfg.set_value("music", "granular_pad", music_granular_pad)
	cfg.set_value("music", "vocoder_pad", music_vocoder_pad)
	cfg.set_value("music", "shaker_mix", music_shaker_mix)
	cfg.set_value("music", "clap_mix", music_clap_mix)
	cfg.set_value("music", "build_drama", music_build_drama)
	cfg.set_value("music", "bitcrush_algae", music_bitcrush_algae)
	cfg.set_value("music", "bass_grit", music_bass_grit)
	cfg.set_value("music", "pump_gate", music_pump_gate)
	cfg.set_value("music", "key_mod", music_key_mod)
	cfg.set_value("music", "breathe_lfo", music_breathe_lfo)
	cfg.set_value("environment", "preset", environment_preset)
	cfg.set_value("substrate", "type", substrate_type)
	cfg.set_value("substrate", "rebuild_terrain", rebuild_terrain_on_load)
	cfg.set_value("aeration", "type", aeration_type)
	cfg.set_value("aeration", "strength", aeration_strength)
	cfg.set_value("aeration", "x_frac", aeration_x_frac)
	cfg.set_value("fauna", "auto_respawn", auto_respawn_fauna)
	cfg.set_value("fauna", "auto_feed", auto_feed_fauna)
	cfg.set_value("fauna", "schooling_mult", fauna_schooling_mult)
	cfg.set_value("fauna", "separation_mult", fauna_separation_mult)
	cfg.set_value("fauna", "wander_mult", fauna_wander_mult)
	cfg.set_value("fauna", "speed_mult", fauna_speed_mult)
	cfg.set_value("fauna", "school_pulse_enabled", fauna_school_pulse_enabled)
	cfg.set_value("fauna", "school_pulse_amplitude", fauna_school_pulse_amplitude)
	cfg.set_value("fauna", "mourning_enabled", fauna_mourning_enabled)
	cfg.set_value("fauna", "player_glance_enabled", fauna_player_glance_enabled)
	cfg.set_value("preset", "tank", tank_preset)
	cfg.set_value("preset", "glassdarts", custom_glassdart_count)
	cfg.set_value("preset", "mudsifters", custom_mudsifter_count)
	cfg.set_value("preset", "shrimp", custom_shrimp_count)
	cfg.set_value("render", "width", render_width)
	cfg.set_value("render", "height", render_height)
	cfg.set_value("render", "dither", dither_strength)
	cfg.set_value("render", "dither_region_aware", dither_region_aware)
	cfg.set_value("render", "palette_bank_lock", palette_bank_lock)
	cfg.set_value("render", "outline_strength", outline_strength)
	cfg.set_value("render", "crt_strength", crt_strength)
	cfg.set_value("render", "integer_upscale", integer_upscale)
	cfg.set_value("render", "pixel_snap_camera", pixel_snap_camera)
	cfg.set_value("render", "adaptive_quality", adaptive_quality)
	cfg.set_value("render", "adaptive_quality_target_fps", adaptive_quality_target_fps)
	cfg.set_value("render", "palette_enabled", palette_enabled)
	cfg.set_value("render", "fog_density", fog_density)
	cfg.set_value("render", "fog_anisotropy", fog_anisotropy)
	cfg.set_value("render", "fog_ambient_inject", fog_ambient_inject)
	cfg.set_value("material", "hue_shift", material_hue_shift)
	cfg.set_value("material", "saturation", material_saturation)
	cfg.set_value("material", "warmth", material_warmth)
	cfg.set_value("material", "value", material_value)
	cfg.set_value("material", "weight_fauna", material_weight_fauna)
	cfg.set_value("material", "weight_foliage", material_weight_foliage)
	cfg.set_value("material", "weight_substrate", material_weight_substrate)
	cfg.set_value("material", "weight_hardscape", material_weight_hardscape)
	cfg.set_value("material", "weight_water", material_weight_water)
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
	cfg.set_value("mobile", "new_tank_fit", new_tank_fit)
	cfg.set_value("plants", "co2_level", co2_level)
	cfg.set_value("plants", "light_spectrum", light_spectrum)
	cfg.set_value("ai", "enabled", ai_enabled)
	cfg.set_value("ai", "endpoint", ai_endpoint)
	cfg.set_value("ai", "model", ai_model)
	cfg.set_value("ai", "naming_theme", ai_naming_theme)
	cfg.set_value("ai", "chronicle", ai_chronicle)
	cfg.set_value("ai", "onboarding_seen", ai_onboarding_seen)
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
	if tank_shape == "sphere" and not cfg.get_value("tank", "dome", false):
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
	tank_lights_on = cfg.get_value("light", "tank_on", tank_lights_on)
	light_master_enabled = cfg.get_value("light", "master_enabled", light_master_enabled)
	day_cycle_enabled = cfg.get_value("light", "day_cycle_enabled", day_cycle_enabled)
	# New split intensity/warmth. Defaults fall back to legacy light_energy
	# /light_warmth so saved tanks from before the split keep their look.
	global_intensity = cfg.get_value("light", "global_intensity", light_energy)
	global_warmth = cfg.get_value("light", "global_warmth", light_warmth)
	tank_fixture_intensity = cfg.get_value("light", "tank_fixture_intensity", light_energy)
	var fix_rgb: Array = cfg.get_value("light", "tank_fixture_color",
		[tank_fixture_color.r, tank_fixture_color.g, tank_fixture_color.b])
	if fix_rgb.size() >= 3:
		tank_fixture_color = Color(float(fix_rgb[0]), float(fix_rgb[1]), float(fix_rgb[2]))
	day_length_s = cfg.get_value("light", "day_length_s", day_length_s)
	sunset_drama = cfg.get_value("light", "sunset_drama", sunset_drama)
	moonlight_enabled = cfg.get_value("light", "moonlight_enabled", moonlight_enabled)
	moonlight_intensity = cfg.get_value("light", "moonlight_intensity", moonlight_intensity)
	var moon_rgb: Array = cfg.get_value("light", "moonlight_color",
		[moonlight_color.r, moonlight_color.g, moonlight_color.b])
	if moon_rgb.size() >= 3:
		moonlight_color = Color(float(moon_rgb[0]), float(moon_rgb[1]), float(moon_rgb[2]))
	accent1_enabled = cfg.get_value("light", "accent1_enabled", accent1_enabled)
	accent1_intensity = cfg.get_value("light", "accent1_intensity", accent1_intensity)
	var a1_rgb: Array = cfg.get_value("light", "accent1_color",
		[accent1_color.r, accent1_color.g, accent1_color.b])
	if a1_rgb.size() >= 3:
		accent1_color = Color(float(a1_rgb[0]), float(a1_rgb[1]), float(a1_rgb[2]))
	accent2_enabled = cfg.get_value("light", "accent2_enabled", accent2_enabled)
	accent2_intensity = cfg.get_value("light", "accent2_intensity", accent2_intensity)
	var a2_rgb: Array = cfg.get_value("light", "accent2_color",
		[accent2_color.r, accent2_color.g, accent2_color.b])
	if a2_rgb.size() >= 3:
		accent2_color = Color(float(a2_rgb[0]), float(a2_rgb[1]), float(a2_rgb[2]))
	pp_vignette_strength = cfg.get_value("light", "pp_vignette_strength", pp_vignette_strength)
	pp_vignette_falloff = cfg.get_value("light", "pp_vignette_falloff", pp_vignette_falloff)
	pp_bloom_threshold = cfg.get_value("light", "pp_bloom_threshold", pp_bloom_threshold)
	pp_bloom_strength = cfg.get_value("light", "pp_bloom_strength", pp_bloom_strength)
	ambient_floor = cfg.get_value("light", "ambient_floor", ambient_floor)
	biolum_multiplier = cfg.get_value("light", "biolum_multiplier", biolum_multiplier)
	caustic_intensity_user = cfg.get_value("light", "caustic_intensity_user", caustic_intensity_user)
	tod_use_overrides = cfg.get_value("light", "tod_use_overrides", tod_use_overrides)
	var _read_color := func(key: String, fallback: Color) -> Color:
		var arr: Array = cfg.get_value("light", key, [fallback.r, fallback.g, fallback.b])
		if arr.size() >= 3:
			return Color(float(arr[0]), float(arr[1]), float(arr[2]))
		return fallback
	tod_dawn_color = _read_color.call("tod_dawn_color", tod_dawn_color)
	tod_day_color = _read_color.call("tod_day_color", tod_day_color)
	tod_dusk_color = _read_color.call("tod_dusk_color", tod_dusk_color)
	tod_night_color = _read_color.call("tod_night_color", tod_night_color)
	lighting_preset = cfg.get_value("light", "preset", lighting_preset)
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
	music_phrase_form = String(cfg.get_value("music", "phrase_form", music_phrase_form))
	music_drop_intensity = cfg.get_value("music", "drop_intensity", music_drop_intensity)
	music_breakdown_depth = cfg.get_value("music", "breakdown_depth", music_breakdown_depth)
	music_lead_mix = cfg.get_value("music", "lead_mix", music_lead_mix)
	music_lead_detune = cfg.get_value("music", "lead_detune", music_lead_detune)
	music_vinyl_crackle = cfg.get_value("music", "vinyl_crackle", music_vinyl_crackle)
	music_tape_wow = cfg.get_value("music", "tape_wow", music_tape_wow)
	music_jazziness = cfg.get_value("music", "jazziness", music_jazziness)
	music_swing = cfg.get_value("music", "swing", music_swing)
	music_offbeat_hat = cfg.get_value("music", "offbeat_hat", music_offbeat_hat)
	music_reverb_send = cfg.get_value("music", "reverb_send", music_reverb_send)
	music_humanize = cfg.get_value("music", "humanize", music_humanize)
	music_species_palette = cfg.get_value("music", "species_palette", music_species_palette)
	music_sub_bass_mix = cfg.get_value("music", "sub_bass_mix", music_sub_bass_mix)
	music_offbeat_bass_mix = cfg.get_value("music", "offbeat_bass_mix", music_offbeat_bass_mix)
	music_granular_pad = cfg.get_value("music", "granular_pad", music_granular_pad)
	music_vocoder_pad = cfg.get_value("music", "vocoder_pad", music_vocoder_pad)
	music_shaker_mix = cfg.get_value("music", "shaker_mix", music_shaker_mix)
	music_clap_mix = cfg.get_value("music", "clap_mix", music_clap_mix)
	music_build_drama = cfg.get_value("music", "build_drama", music_build_drama)
	music_bitcrush_algae = cfg.get_value("music", "bitcrush_algae", music_bitcrush_algae)
	music_bass_grit = cfg.get_value("music", "bass_grit", music_bass_grit)
	music_pump_gate = cfg.get_value("music", "pump_gate", music_pump_gate)
	music_key_mod = cfg.get_value("music", "key_mod", music_key_mod)
	music_breathe_lfo = cfg.get_value("music", "breathe_lfo", music_breathe_lfo)
	environment_preset = cfg.get_value("environment", "preset", environment_preset)
	substrate_type = cfg.get_value("substrate", "type", substrate_type)
	rebuild_terrain_on_load = cfg.get_value("substrate", "rebuild_terrain", rebuild_terrain_on_load)
	aeration_type = cfg.get_value("aeration", "type", aeration_type)
	aeration_strength = cfg.get_value("aeration", "strength", aeration_strength)
	aeration_x_frac = cfg.get_value("aeration", "x_frac", aeration_x_frac)
	auto_respawn_fauna = cfg.get_value("fauna", "auto_respawn", auto_respawn_fauna)
	auto_feed_fauna = cfg.get_value("fauna", "auto_feed", auto_feed_fauna)
	fauna_schooling_mult = cfg.get_value("fauna", "schooling_mult", fauna_schooling_mult)
	fauna_separation_mult = cfg.get_value("fauna", "separation_mult", fauna_separation_mult)
	fauna_wander_mult = cfg.get_value("fauna", "wander_mult", fauna_wander_mult)
	fauna_speed_mult = cfg.get_value("fauna", "speed_mult", fauna_speed_mult)
	fauna_school_pulse_enabled = cfg.get_value("fauna", "school_pulse_enabled", fauna_school_pulse_enabled)
	fauna_school_pulse_amplitude = cfg.get_value("fauna", "school_pulse_amplitude", fauna_school_pulse_amplitude)
	fauna_mourning_enabled = cfg.get_value("fauna", "mourning_enabled", fauna_mourning_enabled)
	fauna_player_glance_enabled = cfg.get_value("fauna", "player_glance_enabled", fauna_player_glance_enabled)
	tank_preset = cfg.get_value("preset", "tank", tank_preset)
	custom_glassdart_count = cfg.get_value("preset", "glassdarts", custom_glassdart_count)
	custom_mudsifter_count = cfg.get_value("preset", "mudsifters", custom_mudsifter_count)
	custom_shrimp_count = cfg.get_value("preset", "shrimp", custom_shrimp_count)
	render_width = cfg.get_value("render", "width", render_width)
	render_height = cfg.get_value("render", "height", render_height)
	dither_strength = cfg.get_value("render", "dither", dither_strength)
	dither_region_aware = cfg.get_value("render", "dither_region_aware", dither_region_aware)
	palette_bank_lock = cfg.get_value("render", "palette_bank_lock", palette_bank_lock)
	outline_strength = cfg.get_value("render", "outline_strength", outline_strength)
	crt_strength = cfg.get_value("render", "crt_strength", crt_strength)
	integer_upscale = cfg.get_value("render", "integer_upscale", integer_upscale)
	pixel_snap_camera = cfg.get_value("render", "pixel_snap_camera", pixel_snap_camera)
	adaptive_quality = cfg.get_value("render", "adaptive_quality", adaptive_quality)
	adaptive_quality_target_fps = cfg.get_value("render", "adaptive_quality_target_fps", adaptive_quality_target_fps)
	palette_enabled = cfg.get_value("render", "palette_enabled", palette_enabled)
	fog_density = cfg.get_value("render", "fog_density", fog_density)
	fog_anisotropy = cfg.get_value("render", "fog_anisotropy", fog_anisotropy)
	fog_ambient_inject = cfg.get_value("render", "fog_ambient_inject", fog_ambient_inject)
	material_hue_shift = cfg.get_value("material", "hue_shift", material_hue_shift)
	material_saturation = cfg.get_value("material", "saturation", material_saturation)
	material_warmth = cfg.get_value("material", "warmth", material_warmth)
	material_value = cfg.get_value("material", "value", material_value)
	material_weight_fauna = cfg.get_value("material", "weight_fauna", material_weight_fauna)
	material_weight_foliage = cfg.get_value("material", "weight_foliage", material_weight_foliage)
	material_weight_substrate = cfg.get_value("material", "weight_substrate", material_weight_substrate)
	material_weight_hardscape = cfg.get_value("material", "weight_hardscape", material_weight_hardscape)
	material_weight_water = cfg.get_value("material", "weight_water", material_weight_water)
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
	new_tank_fit = cfg.get_value("mobile", "new_tank_fit", new_tank_fit)
	co2_level = cfg.get_value("plants", "co2_level", co2_level)
	light_spectrum = cfg.get_value("plants", "light_spectrum", light_spectrum)
	ai_enabled = cfg.get_value("ai", "enabled", ai_enabled)
	ai_endpoint = cfg.get_value("ai", "endpoint", ai_endpoint)
	ai_model = cfg.get_value("ai", "model", ai_model)
	ai_naming_theme = cfg.get_value("ai", "naming_theme", ai_naming_theme)
	ai_chronicle = cfg.get_value("ai", "chronicle", ai_chronicle)
	ai_onboarding_seen = cfg.get_value("ai", "onboarding_seen", ai_onboarding_seen)
	_pair_environment_lighting_if_legacy()
	# Push the freshly-loaded AI settings into the live director (autoload
	# instantiated before us). Safe no-op if AIDirector autoload is missing.
	var ai := get_node_or_null("/root/AIDirector")
	if ai != null and ai.has_method("apply_config"):
		ai.apply_config({
			"ai_enabled": ai_enabled,
			"ai_endpoint": ai_endpoint,
			"ai_model": ai_model,
			"ai_naming_theme": ai_naming_theme,
			"ai_chronicle": ai_chronicle,
		})


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
	apply_screen_fitted_dimensions()
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
	tank_lights_on = true
	light_master_enabled = true
	day_cycle_enabled = true
	global_intensity = 0.5
	global_warmth = 0.6
	tank_fixture_intensity = 0.5
	tank_fixture_color = Color(1.0, 0.95, 0.85)
	day_length_s = 360.0
	sunset_drama = 0.75
	moonlight_enabled = true
	moonlight_intensity = 0.4
	moonlight_color = Color(0.55, 0.70, 1.0)
	accent1_enabled = false
	accent1_intensity = 0.6
	accent1_color = Color(1.0, 0.45, 0.75)
	accent2_enabled = false
	accent2_intensity = 0.6
	accent2_color = Color(0.45, 0.85, 1.0)
	pp_vignette_strength = 0.24
	pp_vignette_falloff = 1.6
	pp_bloom_threshold = 0.72
	pp_bloom_strength = 0.68
	ambient_floor = 0.0
	biolum_multiplier = 1.0
	caustic_intensity_user = 1.0
	tod_use_overrides = false
	tod_dawn_color = Color(1.02, 0.88, 0.82)
	tod_day_color = Color(1.00, 1.00, 1.00)
	tod_dusk_color = Color(1.04, 0.82, 0.70)
	tod_night_color = Color(0.38, 0.42, 0.52)
	lighting_preset = "custom"
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
	music_phrase_form = "auto"
	music_drop_intensity = 0.7
	music_breakdown_depth = 0.7
	music_lead_mix = 0.55
	music_lead_detune = 0.55
	music_vinyl_crackle = 0.2
	music_tape_wow = 0.18
	music_jazziness = 0.4
	music_swing = 0.06
	music_offbeat_hat = 0.55
	music_reverb_send = 0.45
	music_humanize = 0.22
	music_species_palette = 0.75
	music_sub_bass_mix = 0.55
	music_offbeat_bass_mix = 0.35
	music_granular_pad = 0.25
	music_vocoder_pad = 0.25
	music_shaker_mix = 0.4
	music_clap_mix = 0.45
	music_build_drama = 0.7
	music_bitcrush_algae = 0.6
	music_bass_grit = 0.5
	music_pump_gate = 0.6
	music_key_mod = 0.35
	music_breathe_lfo = 0.35
	environment_preset = "void"
	# Fauna behavior.
	auto_respawn_fauna = false
	auto_feed_fauna = false
	fauna_schooling_mult = 1.0
	fauna_separation_mult = 1.0
	fauna_wander_mult = 1.0
	fauna_speed_mult = 1.0
	fauna_school_pulse_enabled = true
	fauna_school_pulse_amplitude = 0.15
	fauna_mourning_enabled = true
	fauna_player_glance_enabled = true
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
	dither_region_aware = true
	palette_bank_lock = true
	outline_strength = 0.0
	crt_strength = 0.0
	integer_upscale = false
	pixel_snap_camera = false
	adaptive_quality = false
	adaptive_quality_target_fps = 55
	palette_enabled = true
	fog_density = 0.02
	fog_anisotropy = 0.3
	fog_ambient_inject = 0.05
	material_hue_shift = 0.0
	material_saturation = 1.0
	material_warmth = 0.0
	material_value = 1.0
	material_weight_fauna = 1.0
	material_weight_foliage = 1.0
	material_weight_substrate = 1.0
	material_weight_hardscape = 1.0
	material_weight_water = 0.75
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
	music_drop_intensity = rng.randf_range(0.35, 1.0)
	music_breakdown_depth = rng.randf_range(0.35, 1.0)
	music_lead_mix = rng.randf_range(0.25, 0.9)
	music_lead_detune = rng.randf_range(0.2, 1.0)
	music_jazziness = rng.randf_range(0.0, 1.0)
	# Lo-fi knobs — most tanks stay subtle, wild leans further into it.
	music_vinyl_crackle = rng.randf_range(0.0, 0.7 if wild else 0.45)
	music_tape_wow = rng.randf_range(0.0, 0.6 if wild else 0.35)
	music_swing = rng.randf_range(0.0, 0.45)
	music_offbeat_hat = rng.randf_range(0.15, 1.0)
	music_reverb_send = rng.randf_range(0.2, 0.85)
	music_humanize = rng.randf_range(0.05, 0.45)
	music_species_palette = rng.randf_range(0.4, 1.0)
	if wild or rng.randf() > 0.35:
		var forms: Array[String] = ["auto", "trance", "loop", "free"]
		music_phrase_form = forms[rng.randi_range(0, forms.size() - 1)]
	music_sub_bass_mix = rng.randf_range(0.25, 0.85)
	music_offbeat_bass_mix = rng.randf_range(0.0, 0.85)
	music_granular_pad = rng.randf_range(0.0, 0.65 if wild else 0.45)
	music_vocoder_pad = rng.randf_range(0.0, 0.55 if wild else 0.35)
	music_shaker_mix = rng.randf_range(0.15, 0.8)
	music_clap_mix = rng.randf_range(0.0, 0.85)
	music_build_drama = rng.randf_range(0.3, 1.0)
	music_bitcrush_algae = rng.randf_range(0.0, 0.9)
	music_bass_grit = rng.randf_range(0.0, 0.85)
	music_pump_gate = rng.randf_range(0.2, 0.95)
	music_key_mod = rng.randf_range(0.0, 0.75)
	music_breathe_lfo = rng.randf_range(0.0, 0.7)


static func logical_screen_size() -> Vector2:
	var win: Vector2i = DisplayServer.window_get_size()
	if win.x > 0 and win.y > 0:
		return Vector2(win)
	var scr: Vector2i = DisplayServer.screen_get_size()
	if scr.x > 0 and scr.y > 0:
		return Vector2(scr)
	return Vector2(1536, 864)


static func is_mobile_platform() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


static func is_desktop_platform() -> bool:
	return not is_mobile_platform() and not OS.has_feature("web")


func apply_screen_fitted_dimensions() -> void:
	var vp: Vector2 = logical_screen_size()
	var portrait: bool = vp.y > vp.x * 1.02
	var desktop: bool = is_desktop_platform()

	if desktop:
		tank_shape = "box"
		tank_half_w = 14.0
		tank_half_d = 10.0
		tank_height = 10.0
		return

	var ref: float = minf(vp.x, vp.y)
	var scale: float = clampf(ref / 400.0, 0.72, 1.28)

	var want_round: bool = false
	match new_tank_fit:
		"round":
			want_round = true
		"rect":
			want_round = false
		_:
			want_round = portrait

	if want_round:
		tank_shape = "cylinder"
		var r: float = clampf(4.6 * scale, 3.4, 7.2)
		tank_half_w = r
		tank_half_d = r
		tank_height = clampf((9.2 if portrait else 7.0) * scale, 5.8, 11.5)
		return

	tank_shape = "box"
	if portrait:
		tank_half_w = clampf(3.6 * scale, 2.8, 5.8)
		tank_half_d = clampf(3.0 * scale, 2.4, 5.0)
		tank_height = clampf(8.8 * scale, 6.2, 11.0)
	else:
		tank_half_w = clampf(6.8 * scale, 4.8, 9.5)
		tank_half_d = clampf(4.2 * scale, 3.0, 7.0)
		tank_height = clampf(6.8 * scale, 5.2, 9.0)
