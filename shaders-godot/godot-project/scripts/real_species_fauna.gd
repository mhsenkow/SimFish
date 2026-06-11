# Real-species fauna catalog + fingerprint matcher.
#
# Mirrors real_species_library.gd (which catalogs plants) for the animals:
# fish, shrimp and snails. species_library.gd calls match_genome() when an
# organism is discovered so the library card can show "Looks like: Hillstream
# loach" and fire a discovery story-event the first time a lineage drifts close
# to a real species.
#
# class_name intentionally omitted — preloaded as a const elsewhere.
extends RefCounted


static func _c(r: int, g: int, b: int) -> Color:
	return Color8(r, g, b)


# Coerce a genome colour value (Color, [r,g,b,a] array, or "(r,g,b,a)" string)
# to a Color. Returns a neutral grey on failure so a missing colour doesn't
# blow up the distance metric.
static func _to_color(v: Variant) -> Color:
	if v is Color:
		return v
	if v is Array and (v as Array).size() >= 3:
		var a: Array = v
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return Color(0.5, 0.5, 0.5)


# Master fauna catalog. Each entry's `genome` lists only the discriminating
# morphology fields — match_genome() skips fields an entry omits, so sparse
# entries still match on the traits that matter for that species.
#
# organism: "fish" | "shrimp" | "snail". The matcher only compares an entry
# against a genome of the same organism type.
static func entries() -> Array:
	return [
		# ───────────────────────── FISH ─────────────────────────
		{
			"id": "neon_tetra", "common_name": "Neon / cardinal tetra",
			"latin_name": "Paracheirodon", "organism": "fish",
			"role": "Mid-water schooler", "origin": "South America",
			"description": "Slim torpedo body split by a neon lateral band, deep-forked tail, tetra adipose fin.",
			"genome": {
				"body_shape": "fusiform", "tail_shape": 0, "pattern_type": 4,
				"body_elongation": 1.1, "body_depth_factor": 0.85,
				"adipose_fin": true, "base_color": _c(50, 180, 210),
			},
		},
		{
			"id": "angelfish", "common_name": "Angelfish",
			"latin_name": "Pterophyllum scalare", "organism": "fish",
			"role": "Cichlid centerpiece", "origin": "Amazon",
			"description": "Tall laterally-compressed disc with long trailing dorsal + anal fins and dark vertical bars.",
			"genome": {
				"body_shape": "compressed", "tail_shape": 2, "pattern_type": 3,
				"body_depth_factor": 1.7, "anal_fin_length_factor": 1.5,
				"base_color": _c(220, 220, 230),
			},
		},
		{
			"id": "betta", "common_name": "Betta / Siamese fighting fish",
			"latin_name": "Betta splendens", "organism": "fish",
			"role": "Labyrinth apex", "origin": "Southeast Asia",
			"description": "Billowing veil finnage on a stocky body; lyre tail, long anal fin, atmospheric breather.",
			"genome": {
				"body_shape": "fusiform", "tail_shape": 2, "finnage": 1.6,
				"anal_fin_length_factor": 1.5, "base_color": _c(40, 90, 235),
			},
		},
		{
			"id": "pufferfish", "common_name": "Pufferfish",
			"latin_name": "Tetraodontidae", "organism": "fish",
			"role": "Globiform grazer", "origin": "Worldwide",
			"description": "Rounded near-spherical body, big eyes, small fins, often a snail-crushing beak.",
			"genome": {
				"body_shape": "globiform", "eye_size_factor": 1.5,
				"snail_predator": true, "base_color": _c(200, 190, 120),
			},
		},
		{
			"id": "corydoras", "common_name": "Corydoras catfish",
			"latin_name": "Corydoras", "organism": "fish",
			"role": "Armored bottom dweller", "origin": "South America",
			"description": "Stout armored body, downturned barbelled mouth, flat belly, beady eyes.",
			"genome": {
				"body_shape": "fusiform", "armor_plates": true, "has_barbels": true,
				"mouth_orientation": 1, "eye_size_factor": 0.8, "ventral_profile": 0.75,
				"base_color": _c(170, 170, 150),
			},
		},
		{
			"id": "kuhli_loach", "common_name": "Kuhli loach",
			"latin_name": "Pangio kuhlii", "organism": "fish",
			"role": "Eel-like sifter", "origin": "Southeast Asia",
			"description": "Long banded eel-like body, barbels, downturned mouth; sifts the substrate.",
			"genome": {
				"body_shape": "anguilliform", "has_barbels": true, "mouth_orientation": 1,
				"body_elongation": 1.45, "body_depth_factor": 0.75, "pattern_type": 3,
				"base_color": _c(225, 130, 50),
			},
		},
		{
			"id": "pleco", "common_name": "Pleco / suckermouth catfish",
			"latin_name": "Loricariidae", "organism": "fish",
			"role": "Algae/wood grazer", "origin": "South America",
			"description": "Flattened armored body with a ventral sucker mouth and a tall long-based dorsal sail.",
			"genome": {
				"body_shape": "depressed", "ventral_sucker": true, "armor_plates": true,
				"dorsal_length_factor": 1.8, "body_width_factor": 1.3, "has_barbels": true,
				"wood_grazer": true, "base_color": _c(90, 80, 60),
			},
		},
		{
			"id": "hillstream_loach", "common_name": "Hillstream loach",
			"latin_name": "Sewellia / Beaufortia", "organism": "fish",
			"role": "Torrent clinger", "origin": "Asia",
			"description": "Dorsoventrally flattened with broad ray-like pectorals and a sucker belly; grazes biofilm.",
			"genome": {
				"body_shape": "depressed", "ventral_sucker": true, "body_width_factor": 1.55,
				"body_depth_factor": 0.6, "pattern_type": 7, "algae_grazer": true,
				"base_color": _c(120, 105, 70),
			},
		},
		{
			"id": "gar", "common_name": "Gar / needlefish",
			"latin_name": "Lepisosteus / Belonidae", "organism": "fish",
			"role": "Surface ambush predator", "origin": "Worldwide",
			"description": "Very long body with a needle snout; hangs near the surface and lunges.",
			"genome": {
				"body_shape": "sagittiform", "snout_length_factor": 2.2, "snout_pointed": true,
				"body_elongation": 1.5, "shrimp_predator": true, "base_color": _c(95, 110, 70),
			},
		},
		{
			"id": "discus", "common_name": "Discus / severum",
			"latin_name": "Symphysodon / Heros", "organism": "fish",
			"role": "Disc cichlid", "origin": "Amazon",
			"description": "Very deep round disc body; dominant males swell a forehead hump.",
			"genome": {
				"body_shape": "compressed", "body_depth_factor": 1.6, "nuchal_hump": 0.7,
				"pattern_type": 9, "base_color": _c(150, 170, 90),
			},
		},
		{
			"id": "goby", "common_name": "Goby",
			"latin_name": "Gobiidae", "organism": "fish",
			"role": "Benthic percher", "origin": "Worldwide",
			"description": "Small bottom-percher with two distinct dorsal fins and a fused pelvic sucker.",
			"genome": {
				"body_shape": "fusiform", "second_dorsal": true, "ventral_sucker": true,
				"pattern_type": 3, "base_color": _c(235, 195, 60),
			},
		},
		{
			"id": "guppy", "common_name": "Guppy / fancy livebearer",
			"latin_name": "Poecilia reticulata", "organism": "fish",
			"role": "Surface livebearer", "origin": "South America",
			"description": "Small fish with an oversized colorful fan tail and trailing finnage.",
			"genome": {
				"body_shape": "fusiform", "tail_shape": 1, "finnage": 1.4,
				"is_livebearer": true, "base_color": _c(245, 120, 60),
			},
		},
		{
			"id": "clownfish", "common_name": "Clownfish",
			"latin_name": "Amphiprion", "organism": "fish",
			"role": "Reef anemone symbiont", "origin": "Indo-Pacific",
			"description": "Orange body crossed by crisp white black-edged bars; rounded fins.",
			"genome": {
				"body_shape": "compressed", "tail_shape": 1, "pattern_type": 3,
				"bar_edged": true, "second_dorsal": true, "base_color": _c(245, 110, 30),
			},
		},
		{
			"id": "ribbon_eel", "common_name": "Ribbon eel / knifefish",
			"latin_name": "Rhinomuraena / Gymnotus", "organism": "fish",
			"role": "Elongate undulator", "origin": "Worldwide",
			"description": "Extremely long thin body with a continuous fin ridge instead of discrete fins.",
			"genome": {
				"body_shape": "ribbon", "body_elongation": 1.5, "body_depth_factor": 0.7,
				"base_color": _c(40, 90, 200),
			},
		},
		# ──────────────────────── SHRIMP ────────────────────────
		{
			"id": "cherry_shrimp", "common_name": "Cherry shrimp",
			"latin_name": "Neocaridina davidi", "organism": "shrimp",
			"role": "Dwarf grazer", "origin": "Taiwan",
			"description": "Small solid-red caridean shrimp with tiny claws.",
			"genome": {
				"body_shape": "caridean", "pattern_type": 0, "claw_size": 0.25,
				"base_color": _c(195, 65, 55),
			},
		},
		{
			"id": "crystal_shrimp", "common_name": "Crystal / bee shrimp",
			"latin_name": "Caridina cantonensis", "organism": "shrimp",
			"role": "Dwarf grazer", "origin": "Asia",
			"description": "Caridean shrimp banded in crisp white and red rings.",
			"genome": {
				"body_shape": "caridean", "pattern_type": 1, "rostrum_length": 0.7,
				"base_color": _c(235, 235, 240),
			},
		},
		{
			"id": "amano_shrimp", "common_name": "Amano shrimp",
			"latin_name": "Caridina multidentata", "organism": "shrimp",
			"role": "Algae cleaner", "origin": "Japan",
			"description": "Larger translucent grey caridean with a dashed lateral stripe.",
			"genome": {
				"body_shape": "caridean", "pattern_type": 3, "body_length_factor": 1.3,
				"base_color": _c(160, 165, 160),
			},
		},
		{
			"id": "bamboo_shrimp", "common_name": "Bamboo / wood shrimp",
			"latin_name": "Atyopsis moluccensis", "organism": "shrimp",
			"role": "Filter feeder", "origin": "Southeast Asia",
			"description": "Large shrimp that fans the current with feathery feeding hands.",
			"genome": {
				"body_shape": "caridean", "filter_fans": true, "body_length_factor": 1.4,
				"base_color": _c(150, 110, 80),
			},
		},
		{
			"id": "crayfish", "common_name": "Crayfish / dwarf lobster",
			"latin_name": "Cambarellus / Procambarus", "organism": "shrimp",
			"role": "Benthic forager", "origin": "Worldwide",
			"description": "Long straight-bodied crustacean with big forward claws.",
			"genome": {
				"body_shape": "lobster", "claw_size": 0.9, "abdomen_curl": 0.1,
				"base_color": _c(120, 90, 160),
			},
		},
		{
			"id": "fiddler_crab", "common_name": "Fiddler crab",
			"latin_name": "Uca", "organism": "shrimp",
			"role": "Brackish scavenger", "origin": "Worldwide",
			"description": "Wide flat crab with stalked eyes and one greatly enlarged claw.",
			"genome": {
				"body_shape": "crab", "claw_asymmetry": 0.8, "eye_stalk_length": 0.7,
				"claw_size": 0.7, "base_color": _c(200, 140, 70),
			},
		},
		{
			"id": "mantis_shrimp", "common_name": "Mantis shrimp",
			"latin_name": "Stomatopoda", "organism": "shrimp",
			"role": "Raptorial predator", "origin": "Indo-Pacific",
			"description": "Elongate segmented body with folded raptorial arms and stalked eyes.",
			"genome": {
				"body_shape": "mantis", "eye_stalk_length": 0.7, "claw_size": 0.6,
				"base_color": _c(60, 180, 120),
			},
		},
		{
			"id": "cleaner_shrimp", "common_name": "Skunk cleaner shrimp",
			"latin_name": "Lysmata amboinensis", "organism": "shrimp",
			"role": "Cleaning symbiont", "origin": "Indo-Pacific",
			"description": "Red caridean shrimp with a white dorsal stripe and long white antennae.",
			"genome": {
				"body_shape": "caridean", "is_cleaner": true, "antenna_length_factor": 1.8,
				"base_color": _c(195, 50, 45),
			},
		},
		# ───────────────────────── SNAIL ─────────────────────────
		{
			"id": "nerite", "common_name": "Nerite snail",
			"latin_name": "Neritina", "organism": "snail",
			"role": "Algae grazer", "origin": "Worldwide",
			"description": "Round operculate shell patterned with dark zigzag markings.",
			"genome": {
				"shell_shape": "turbo", "shell_pattern": 3, "operculum": true,
				"shell_color": _c(60, 50, 30),
			},
		},
		{
			"id": "ramshorn", "common_name": "Ramshorn snail",
			"latin_name": "Planorbidae", "organism": "snail",
			"role": "Detritivore", "origin": "Worldwide",
			"description": "Flat planispiral coil shell wound in a single plane.",
			"genome": {
				"shell_shape": "ramshorn", "shell_color": _c(170, 70, 50),
			},
		},
		{
			"id": "mystery_apple", "common_name": "Mystery / apple snail",
			"latin_name": "Pomacea", "organism": "snail",
			"role": "Large grazer", "origin": "South America",
			"description": "Big rounded globose shell, often gold; broad foot.",
			"genome": {
				"shell_shape": "apple", "shell_size": 1.3, "shell_color": _c(210, 170, 60),
			},
		},
		{
			"id": "malaysian_trumpet", "common_name": "Malaysian trumpet snail",
			"latin_name": "Melanoides tuberculata", "organism": "snail",
			"role": "Substrate burrower", "origin": "Asia/Africa",
			"description": "Tall narrow cone of many whorls; burrows in the substrate.",
			"genome": {
				"shell_shape": "tower", "spire_height": 1.6, "whorl_count": 7,
				"shell_color": _c(120, 95, 60),
			},
		},
		{
			"id": "rabbit_snail", "common_name": "Rabbit snail",
			"latin_name": "Tylomelania", "organism": "snail",
			"role": "Large grazer", "origin": "Sulawesi",
			"description": "Large elongate conical shell with a long wrinkled body.",
			"genome": {
				"shell_shape": "tower", "spire_height": 1.4, "shell_size": 1.3,
				"shell_color": _c(180, 140, 50),
			},
		},
		{
			"id": "trochus_marine", "common_name": "Trochus / turban snail",
			"latin_name": "Trochus / Turbo", "organism": "snail",
			"role": "Reef algae grazer", "origin": "Indo-Pacific",
			"description": "Pointed conical shell, banded, with an operculum.",
			"genome": {
				"shell_shape": "trochus", "operculum": true, "shell_color": _c(225, 210, 175),
			},
		},
		{
			"id": "nassarius", "common_name": "Nassarius snail",
			"latin_name": "Nassarius", "organism": "snail",
			"role": "Sand scavenger", "origin": "Worldwide",
			"description": "Small low oval shell; lives in the sand and emerges to scavenge.",
			"genome": {
				"shell_shape": "nassarius", "shell_color": _c(200, 185, 150),
			},
		},
		{
			"id": "limpet", "common_name": "Limpet / abalone",
			"latin_name": "Patellidae / Haliotis", "organism": "snail",
			"role": "Rock grazer", "origin": "Worldwide",
			"description": "Low conical cap shell with no spire, clamped to rock.",
			"genome": {
				"shell_shape": "limpet", "shell_color": _c(140, 130, 120),
			},
		},
		{
			"id": "conch", "common_name": "Conch",
			"latin_name": "Strombidae", "organism": "snail",
			"role": "Sand sifter", "origin": "Tropical seas",
			"description": "Large globose shell with a broad flared aperture lip.",
			"genome": {
				"shell_shape": "conch", "aperture_flare": 0.8, "shell_size": 1.3,
				"shell_color": _c(235, 215, 180),
			},
		},
	]


static func by_id() -> Dictionary:
	var out: Dictionary = {}
	for e in entries():
		out[String(e.get("id", ""))] = e
	return out


# Distance between a genome and a same-organism catalog entry. Only fields the
# entry specifies contribute, so sparse entries match on what defines them.
static func _string_term(eg: Dictionary, g: Dictionary, key: String, weight: float) -> float:
	if not eg.has(key):
		return 0.0
	return 0.0 if String(eg[key]) == String(g.get(key, "")) else weight


static func _int_term(eg: Dictionary, g: Dictionary, key: String, weight: float) -> float:
	if not eg.has(key):
		return 0.0
	return 0.0 if int(eg[key]) == int(g.get(key, -999)) else weight


static func _bool_term(eg: Dictionary, g: Dictionary, key: String, weight: float) -> float:
	if not eg.has(key):
		return 0.0
	return 0.0 if bool(eg[key]) == bool(g.get(key, false)) else weight


static func _float_term(eg: Dictionary, g: Dictionary, key: String, scale: float, weight: float) -> float:
	if not eg.has(key):
		return 0.0
	var diff: float = absf(float(eg[key]) - float(g.get(key, eg[key])))
	return clampf(diff / scale, 0.0, 1.0) * weight


static func _color_term(eg: Dictionary, g: Dictionary, key: String, weight: float) -> float:
	if not eg.has(key):
		return 0.0
	var ec: Color = _to_color(eg[key])
	var gc: Color = _to_color(g.get(key, eg[key]))
	return (Vector3(ec.r, ec.g, ec.b) - Vector3(gc.r, gc.g, gc.b)).length() * weight


# Returns {"id": ..., "distance": ...} for the closest same-organism entry, or
# {} if there are no entries of that organism type. Lower distance = closer;
# the caller decides the "looks like" threshold.
static func match_genome(genome: Dictionary) -> Dictionary:
	if genome.is_empty():
		return {}
	var organism: String = String(genome.get("organism_type", ""))
	if organism == "":
		return {}
	var best_id: String = ""
	var best_d: float = INF
	for e in entries():
		if String(e.get("organism", "")) != organism:
			continue
		var eg: Dictionary = e.get("genome", {})
		var d: float = 0.0
		match organism:
			"fish":
				d += _string_term(eg, genome, "body_shape", 1.5)
				d += _int_term(eg, genome, "tail_shape", 0.5)
				d += _int_term(eg, genome, "pattern_type", 0.5)
				d += _float_term(eg, genome, "body_elongation", 0.6, 0.8)
				d += _float_term(eg, genome, "body_depth_factor", 0.7, 0.8)
				d += _float_term(eg, genome, "body_width_factor", 0.7, 0.6)
				d += _float_term(eg, genome, "snout_length_factor", 1.2, 0.5)
				d += _float_term(eg, genome, "nuchal_hump", 0.8, 0.4)
				d += _float_term(eg, genome, "anal_fin_length_factor", 1.2, 0.3)
				d += _float_term(eg, genome, "finnage", 0.9, 0.3)
				d += _bool_term(eg, genome, "second_dorsal", 0.3)
				d += _bool_term(eg, genome, "ventral_sucker", 0.4)
				d += _bool_term(eg, genome, "has_barbels", 0.3)
				d += _bool_term(eg, genome, "armor_plates", 0.3)
				d += _bool_term(eg, genome, "adipose_fin", 0.3)
				d += _bool_term(eg, genome, "snout_pointed", 0.2)
				d += _bool_term(eg, genome, "bar_edged", 0.2)
				d += _int_term(eg, genome, "mouth_orientation", 0.3)
				d += _color_term(eg, genome, "base_color", 0.6)
			"shrimp":
				d += _string_term(eg, genome, "body_shape", 1.5)
				d += _int_term(eg, genome, "pattern_type", 0.5)
				d += _float_term(eg, genome, "claw_size", 0.8, 0.5)
				d += _float_term(eg, genome, "claw_asymmetry", 0.7, 0.5)
				d += _float_term(eg, genome, "rostrum_length", 1.0, 0.3)
				d += _float_term(eg, genome, "eye_stalk_length", 0.7, 0.4)
				d += _float_term(eg, genome, "abdomen_curl", 0.7, 0.3)
				d += _float_term(eg, genome, "antenna_length_factor", 1.2, 0.3)
				d += _float_term(eg, genome, "body_length_factor", 0.7, 0.4)
				d += _bool_term(eg, genome, "filter_fans", 0.6)
				d += _bool_term(eg, genome, "is_cleaner", 0.5)
				d += _color_term(eg, genome, "base_color", 0.5)
			"snail":
				d += _string_term(eg, genome, "shell_shape", 1.8)
				d += _int_term(eg, genome, "shell_pattern", 0.5)
				d += _float_term(eg, genome, "spire_height", 0.9, 0.5)
				d += _float_term(eg, genome, "aperture_flare", 0.7, 0.4)
				d += _float_term(eg, genome, "shell_size", 0.7, 0.3)
				d += _int_term(eg, genome, "whorl_count", 0.4)
				d += _bool_term(eg, genome, "operculum", 0.3)
				d += _color_term(eg, genome, "shell_color", 0.5)
			_:
				continue
		if d < best_d:
			best_d = d
			best_id = String(e.get("id", ""))
	if best_id == "":
		return {}
	return {"id": best_id, "distance": best_d}
