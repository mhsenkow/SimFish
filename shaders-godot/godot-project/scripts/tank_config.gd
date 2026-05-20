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

# ---- Tank dimensions ----
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
	cfg.set_value("light", "energy", light_energy)
	cfg.set_value("light", "yaw", light_yaw)
	cfg.set_value("light", "pitch", light_pitch)
	cfg.set_value("light", "warmth", light_warmth)
	cfg.set_value("substrate", "type", substrate_type)
	cfg.save(SAVE_PATH)


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		return
	tank_half_w = cfg.get_value("tank", "half_w", tank_half_w)
	tank_half_d = cfg.get_value("tank", "half_d", tank_half_d)
	tank_height = cfg.get_value("tank", "height", tank_height)
	light_energy = cfg.get_value("light", "energy", light_energy)
	light_yaw = cfg.get_value("light", "yaw", light_yaw)
	light_pitch = cfg.get_value("light", "pitch", light_pitch)
	light_warmth = cfg.get_value("light", "warmth", light_warmth)
	substrate_type = cfg.get_value("substrate", "type", substrate_type)


func _ready() -> void:
	load_from_disk()
