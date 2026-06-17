# Canonical plant trait schema for walstad loom Plants v2.
# All spawn paths funnel params through enrich() / to_dict() / from_dict().
extends RefCounted
class_name PlantGenome

const DORMANCY_NONE: String = "none"
const DORMANCY_TUBER: String = "tuber"
const DORMANCY_TURION: String = "turion"

const REPRO_SEED: String = "seed"
const REPRO_SPORE: String = "spore"
const REPRO_PLANTLET: String = "plantlet"
const REPRO_FRAGMENT: String = "fragment"
const REPRO_BULBIL: String = "bulbil"

const DEFAULTS: Dictionary = {
	"max_height": 22,
	"growth_rate": 0.18,
	"nutrient_demand": 0.05,
	"sway_amplitude": 0.25,
	"leaf_form": "column",
	"leaf_length": 4,
	"leaf_size_mult": 1.0,
	"max_roots": 5,
	"variegation": 0.0,
	"quilted": false,
	"wavy_edges": false,
	"iridescence": 0.0,
	"underside_tone": null,
	"red_potential": 0.0,
	"co2_demand": 0.3,
	"melt_susceptibility": 0.0,
	"has_plantlets": false,
	"is_carpet": false,
	"whorled_leaves": false,
	"is_epiphyte": false,
	"emergent_growth": true,
	"monocarpic": false,
	"uses_flowering": true,
	"latin_name": "",
	"common_name": "",
	"species_id": "",
	"plant_name": "",
	"generation": 0,
	"parent_lineage": "Founders",
	"parent_keys": [],
	# Plants v2 traits
	"palatability": 0.65,
	"leaf_thickness": 0.5,
	"temp_opt": 0.55,
	"allelopathy_strength": 0.0,
	"emersed_leaf_form": "",
	"dormancy_type": DORMANCY_NONE,
	"repro_mode": REPRO_SEED,
	"asymmetry_seed": 0,
	"ls_angle": 35.0,
	"ls_ratio": 0.72,
	"ls_depth": 2,
}


static func enrich(src: Dictionary) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	for k in src.keys():
		out[k] = src[k]
	if String(out.emersed_leaf_form) == "":
		out.emersed_leaf_form = String(out.leaf_form)
	# Category-based defaults when species_id hints at type
	var sid: String = String(out.species_id)
	if sid.begins_with("anubias") or sid.begins_with("buce"):
		out.palatability = minf(float(out.palatability), 0.18)
		out.leaf_thickness = maxf(float(out.leaf_thickness), 0.85)
		out.repro_mode = REPRO_PLANTLET if bool(out.has_plantlets) else REPRO_SEED
	elif sid.begins_with("fern") or sid.begins_with("moss"):
		out.repro_mode = REPRO_SPORE
		out.leaf_thickness = minf(float(out.leaf_thickness), 0.35)
	elif sid.begins_with("stem"):
		out.palatability = maxf(float(out.palatability), 0.75)
		out.repro_mode = REPRO_FRAGMENT
	elif sid.begins_with("crypt"):
		out.melt_susceptibility = maxf(float(out.melt_susceptibility), 0.55)
		out.dormancy_type = DORMANCY_TUBER
	if bool(out.is_epiphyte):
		out.palatability = minf(float(out.palatability), 0.22)
	if bool(out.is_carpet):
		out.palatability = maxf(float(out.palatability), 0.8)
	if float(out.red_potential) > 0.7:
		out.palatability = maxf(float(out.palatability), 0.7)
	if out.asymmetry_seed == 0:
		out.asymmetry_seed = randi()
	return out


static func from_plant(p: Plant) -> Dictionary:
	return enrich({
		"max_height": p.max_height,
		"growth_rate": p.growth_rate,
		"nutrient_demand": p.nutrient_demand,
		"sway_amplitude": p.sway_amplitude,
		"leaf_form": p.leaf_form,
		"leaf_length": p.leaf_length,
		"leaf_size_mult": p.leaf_size_mult,
		"max_roots": p._max_roots,
		"variegation": p.variegation,
		"quilted": p.quilted,
		"wavy_edges": p.wavy_edges,
		"iridescence": p.iridescence,
		"underside_tone": p.underside_tone,
		"red_potential": p.red_potential,
		"co2_demand": p.co2_demand,
		"melt_susceptibility": p.melt_susceptibility,
		"has_plantlets": p.has_plantlets,
		"is_carpet": p.is_carpet,
		"whorled_leaves": p.whorled_leaves,
		"is_epiphyte": p.is_epiphyte,
		"emergent_growth": p.emergent_growth,
		"monocarpic": p.monocarpic,
		"uses_flowering": p.uses_flowering,
		"latin_name": p.latin_name,
		"common_name": p.common_name,
		"species_id": p.species_id,
		"plant_name": p.plant_name,
		"generation": p.generation,
		"parent_lineage": p.parent_lineage,
		"parent_keys": p._parent_keys.duplicate(),
		"palatability": p.palatability,
		"leaf_thickness": p.leaf_thickness,
		"temp_opt": p.temp_opt,
		"allelopathy_strength": p.allelopathy_strength,
		"emersed_leaf_form": p.emersed_leaf_form,
		"dormancy_type": p.dormancy_type,
		"repro_mode": p.repro_mode,
		"asymmetry_seed": p.asymmetry_seed,
		"ls_angle": p.ls_angle,
		"ls_ratio": p.ls_ratio,
		"ls_depth": p.ls_depth,
	})


static func apply_to_plant(p: Plant, g: Dictionary) -> void:
	var e: Dictionary = enrich(g)
	p.max_height = int(e.max_height)
	p.growth_rate = float(e.growth_rate)
	p.nutrient_demand = float(e.nutrient_demand)
	p.sway_amplitude = float(e.sway_amplitude)
	p.leaf_form = String(e.leaf_form)
	p.leaf_length = int(e.leaf_length)
	p.leaf_size_mult = float(e.leaf_size_mult)
	p._max_roots = int(e.max_roots)
	p.variegation = float(e.variegation)
	p.quilted = bool(e.quilted)
	p.wavy_edges = bool(e.wavy_edges)
	p.iridescence = float(e.iridescence)
	p.underside_tone = e.underside_tone
	p.red_potential = float(e.red_potential)
	p.co2_demand = float(e.co2_demand)
	p.melt_susceptibility = float(e.melt_susceptibility)
	p.has_plantlets = bool(e.has_plantlets)
	p.is_carpet = bool(e.is_carpet)
	p.whorled_leaves = bool(e.whorled_leaves)
	p.is_epiphyte = bool(e.is_epiphyte)
	p.emergent_growth = bool(e.emergent_growth)
	p.monocarpic = bool(e.monocarpic)
	p.uses_flowering = bool(e.uses_flowering)
	p.latin_name = String(e.latin_name)
	p.common_name = String(e.common_name)
	p.species_id = String(e.species_id)
	p.plant_name = String(e.plant_name)
	p.generation = int(e.generation)
	p.parent_lineage = String(e.parent_lineage)
	p._parent_keys = (e.parent_keys as Array).duplicate() if e.parent_keys is Array else []
	p.palatability = float(e.palatability)
	p.leaf_thickness = float(e.leaf_thickness)
	p.temp_opt = float(e.temp_opt)
	p.allelopathy_strength = float(e.allelopathy_strength)
	p.emersed_leaf_form = String(e.emersed_leaf_form)
	p.dormancy_type = String(e.dormancy_type)
	p.repro_mode = String(e.repro_mode)
	p.asymmetry_seed = int(e.asymmetry_seed)
	p.ls_angle = float(e.ls_angle)
	p.ls_ratio = float(e.ls_ratio)
	p.ls_depth = int(e.ls_depth)


static func duplicate_mutate(src: Dictionary, generation: int) -> Dictionary:
	var out: Dictionary = enrich(src)
	out.generation = generation
	out.max_height = clampi(int(out.max_height) + _rng_range(-2, 2), 4, 48)
	out.growth_rate = clampf(float(out.growth_rate) + randf_range(-0.02, 0.02), 0.04, 0.48)
	out.sway_amplitude = clampf(float(out.sway_amplitude) + randf_range(-0.04, 0.04), 0.06, 0.75)
	out.leaf_length = clampi(int(out.leaf_length) + _rng_range(-1, 1), 2, 16)
	out.leaf_size_mult = clampf(float(out.leaf_size_mult) + randf_range(-0.06, 0.06), 0.5, 1.8)
	out.red_potential = clampf(float(out.red_potential) + randf_range(-0.04, 0.04), 0.0, 1.0)
	out.palatability = clampf(float(out.palatability) + randf_range(-0.05, 0.05), 0.05, 1.0)
	if randf() < 0.04:
		var forms: Array[String] = ["column", "paddle", "ribbon", "lance", "needle"]
		out.leaf_form = forms[randi() % forms.size()]
	# Variegation sport (#22)
	if randf() < 0.003:
		out.variegation = randf_range(0.4, 0.82)
		out.plant_name = ""
	return out


static func blend(a: Dictionary, b: Dictionary, generation: int) -> Dictionary:
	var ea: Dictionary = enrich(a)
	var eb: Dictionary = enrich(b)
	var out: Dictionary = ea.duplicate(true)
	out.generation = generation
	out.species_id = ""
	out.plant_name = ""
	out.max_height = int(lerpf(float(ea.max_height), float(eb.max_height), 0.5))
	out.growth_rate = lerpf(float(ea.growth_rate), float(eb.growth_rate), 0.5)
	out.leaf_length = int(lerpf(float(ea.leaf_length), float(eb.leaf_length), 0.5))
	out.red_potential = lerpf(float(ea.red_potential), float(eb.red_potential), 0.5)
	out.co2_demand = lerpf(float(ea.co2_demand), float(eb.co2_demand), 0.5)
	out.palatability = lerpf(float(ea.palatability), float(eb.palatability), 0.5)
	out.leaf_thickness = lerpf(float(ea.leaf_thickness), float(eb.leaf_thickness), 0.5)
	out.allelopathy_strength = lerpf(float(ea.allelopathy_strength), float(eb.allelopathy_strength), 0.5)
	if randf() < 0.5:
		out.leaf_form = String(ea.leaf_form)
	else:
		out.leaf_form = String(eb.leaf_form)
	if randf() < 0.5:
		out.ramp_override = ea.get("ramp_override", [])
	else:
		out.ramp_override = eb.get("ramp_override", [])
	return out


static func _rng_range(lo: int, hi: int) -> int:
	return lo + randi() % maxi(1, hi - lo + 1)
