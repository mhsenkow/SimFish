# Canonical floating-plant trait schema (Floaters v2).
extends RefCounted
class_name FloaterGenome

const STATE_VERSION: int = 2

const DEFAULTS: Dictionary = {
	"morph": "duckweed",
	"leaf_size": 0.3,
	"leaf_count": 4,
	"root_length": 0.4,
	"base_color": Color8(70, 130, 60),
	"tip_color": Color8(120, 180, 90),
	"spread_rate": 1.0,
	"redroot_response": 0.0,
	"vitality_max": 1.0,
	"palatability": 0.82,
	"root_biofilm_rate": 0.018,
	"shade_radius": 0.35,
	"co2_independence": 0.85,
	"nitrogen_fixer": 0.0,
	"temp_min": 0.38,
	"temp_max": 0.78,
	"generation": 0,
	"parent_lineage": "Founders",
	"species_id": "",
	"plant_name": "",
	"quilted": false,
	"wavy": false,
	"underside_tone": null,
	"spin_rate": 0.0,
}


static func enrich(src: Dictionary) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	for k in src.keys():
		out[k] = src[k]
	var morph: String = String(out.morph)
	match morph:
		"duckweed":
			out.palatability = maxf(float(out.palatability), 0.88)
			out.shade_radius = 0.18
			out.spread_rate = maxf(float(out.spread_rate), 0.82)
		"frogbit", "water_lettuce":
			out.shade_radius = maxf(float(out.shade_radius), 0.55)
			out.root_biofilm_rate = maxf(float(out.root_biofilm_rate), 0.022)
		"salvinia":
			out.shade_radius = 0.42
			out.wavy = true
		"red_root":
			out.redroot_response = maxf(float(out.redroot_response), 0.85)
			out.root_length = maxf(float(out.root_length), 0.55)
		"azolla":
			out.nitrogen_fixer = maxf(float(out.nitrogen_fixer), 0.65)
			out.leaf_size = minf(float(out.leaf_size), 0.22)
		"water_hyacinth":
			out.shade_radius = 0.72
			out.leaf_size = maxf(float(out.leaf_size), 0.38)
		"water_spangle":
			out.palatability = 0.75
			out.shade_radius = 0.38
	out.spread_rate = float(out.spread_rate) * WorldFloaterManager.morph_spread_bias(morph)
	if out.plant_name == "":
		out.plant_name = _default_label(morph)
	return out


static func _default_label(morph: String) -> String:
	match morph:
		"frogbit": return "Frogbit"
		"salvinia": return "Salvinia"
		"water_lettuce": return "Water lettuce"
		"red_root": return "Red Root Floater"
		"azolla": return "Azolla"
		"water_hyacinth": return "Water hyacinth"
		"water_spangle": return "Water spangle"
	return "Duckweed"


static func from_floater(fp: FloatingPlant) -> Dictionary:
	return enrich({
		"morph": fp.morph,
		"leaf_size": fp.leaf_size,
		"leaf_count": fp.leaf_count,
		"root_length": fp.root_length,
		"base_color": fp.base_color,
		"tip_color": fp.tip_color,
		"spread_rate": fp.spread_rate,
		"redroot_response": fp.redroot_response,
		"palatability": fp.palatability,
		"root_biofilm_rate": fp.root_biofilm_rate,
		"shade_radius": fp.shade_radius,
		"co2_independence": fp.co2_independence,
		"nitrogen_fixer": fp.nitrogen_fixer,
		"temp_min": fp.temp_min,
		"temp_max": fp.temp_max,
		"generation": fp.generation,
		"parent_lineage": fp.parent_lineage,
		"species_id": fp.species_id,
		"plant_name": fp.plant_name,
		"quilted": fp.quilted,
		"wavy": fp.wavy,
		"underside_tone": fp.underside_tone,
		"spin_rate": fp.spin_rate,
	})


static func apply_to_floater(fp: FloatingPlant, g: Dictionary) -> void:
	var e: Dictionary = enrich(g)
	fp.morph = String(e.morph)
	fp.leaf_size = float(e.leaf_size)
	fp.leaf_count = int(e.leaf_count)
	fp.root_length = float(e.root_length)
	fp.base_color = FloatingPlant._to_color(e.base_color)
	fp.tip_color = FloatingPlant._to_color(e.tip_color)
	fp.spread_rate = float(e.spread_rate)
	fp.redroot_response = float(e.redroot_response)
	fp.palatability = float(e.palatability)
	fp.root_biofilm_rate = float(e.root_biofilm_rate)
	fp.shade_radius = float(e.shade_radius)
	fp.co2_independence = float(e.co2_independence)
	fp.nitrogen_fixer = float(e.nitrogen_fixer)
	fp.temp_min = float(e.temp_min)
	fp.temp_max = float(e.temp_max)
	fp.generation = int(e.generation)
	fp.parent_lineage = String(e.parent_lineage)
	fp.species_id = String(e.species_id)
	fp.plant_name = String(e.plant_name)
	fp.quilted = bool(e.quilted)
	fp.wavy = bool(e.wavy)
	fp.underside_tone = e.underside_tone
	fp.spin_rate = float(e.spin_rate)


static func duplicate_mutate(src: Dictionary, generation: int) -> Dictionary:
	var out: Dictionary = enrich(src)
	out.generation = generation
	out.leaf_size = clampf(float(out.leaf_size) + randf_range(-0.03, 0.03), 0.12, 0.75)
	out.root_length = clampf(float(out.root_length) + randf_range(-0.05, 0.05), 0.05, 1.5)
	out.spread_rate = clampf(float(out.spread_rate) + randf_range(-0.1, 0.1), 0.2, 2.8)
	out.palatability = clampf(float(out.palatability) + randf_range(-0.06, 0.06), 0.15, 1.0)
	if randf() < 0.04:
		var morphs: Array[String] = [
			"duckweed", "frogbit", "salvinia", "water_lettuce", "red_root",
			"azolla", "water_hyacinth", "water_spangle",
		]
		out.morph = morphs[randi() % morphs.size()]
		out.plant_name = ""
	return out
