extends RefCounted
class_name ProceduralPlantSpecies

const RealSpeciesLibrary := preload("res://scripts/real_species_library.gd")
const MAX_REJECTIONS: int = 8
const ARCHETYPES: Array[Dictionary] = [
	{"category": "stem", "height": 1.15, "rate": 1.18, "thickness": 0.82, "co2": 1.2},
	{"category": "anubias", "height": 0.82, "rate": 0.72, "thickness": 1.2, "co2": 0.75},
	{"category": "carpet", "height": 0.62, "rate": 1.12, "thickness": 0.72, "co2": 1.0},
	{"category": "crypt", "height": 0.95, "rate": 0.86, "thickness": 1.05, "co2": 0.88},
]


static func sample(seed: int = -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed >= 0 else randi()
	for _attempt in MAX_REJECTIONS:
		var archetype: Dictionary = ARCHETYPES[rng.randi_range(0, ARCHETYPES.size() - 1)]
		var anchors: Array = RealSpeciesLibrary.in_category(String(archetype.category))
		if anchors.is_empty():
			continue
		var entry: Dictionary = anchors[rng.randi_range(0, anchors.size() - 1)]
		var g: Dictionary = PlantGenome.enrich(
			(entry.get("genome", {}) as Dictionary).duplicate(true))
		g.parent_lineage = "Procedural — %s" % String(entry.get("common_name", "wild anchor"))
		g.species_id = ""
		g.common_name = ""
		g.latin_name = ""
		g.asymmetry_seed = rng.randi()
		g.max_height = clampi(int(round(float(g.max_height) * float(archetype.height)
			+ rng.randfn(0.0, 1.5))), 2, 48)
		g.growth_rate = clampf(float(g.growth_rate) * float(archetype.rate)
			+ rng.randfn(0.0, 0.008), 0.04, 0.48)
		g.leaf_thickness = clampf(float(g.leaf_thickness) * float(archetype.thickness)
			+ rng.randfn(0.0, 0.025), 0.1, 1.0)
		g.co2_demand = clampf(float(g.co2_demand) * float(archetype.co2)
			+ rng.randfn(0.0, 0.02), 0.05, 1.0)
		if _valid(g):
			return g
	# Catalog data is trusted; deterministic fallback still has a real anchor.
	return PlantGenome.enrich(
		(RealSpeciesLibrary.entries()[0].get("genome", {}) as Dictionary).duplicate(true))


static func _valid(g: Dictionary) -> bool:
	if bool(g.is_carpet) and int(g.max_height) > 14:
		return false
	if bool(g.is_epiphyte) and int(g.max_roots) > 8:
		return false
	if float(g.leaf_thickness) > 0.8 and float(g.growth_rate) > 0.28:
		return false
	if float(g.red_potential) > 0.7 and float(g.co2_demand) < 0.2:
		return false
	return int(g.max_height) >= 2 and float(g.growth_rate) > 0.0
