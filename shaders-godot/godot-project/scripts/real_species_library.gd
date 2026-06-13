extends RefCounted

# class_name intentionally omitted — every caller preloads via
# `const RealSpeciesLibrary = preload(...)`. Keeping a class_name on top
# would fire "constant shadows global class" warnings in the editor.

# Curated catalog of real-world aquarium plants with parameter presets that
# drive Plant.init() to reproduce each species visually + behaviorally.
#
# Each entry is the union of:
#   - identification: id, common_name, latin_name, category, role
#   - care metadata: light, co2, substrate, difficulty, origin
#   - description text shown in the library panel
#   - genome: the Plant.init() params (leaf_form, ramp, growth_rate, etc.)
#
# Used by:
#   - library_panel.gd "Species" tab to render the catalog
#   - world.gd spawn helpers to instantiate a real-species plant by id
#   - species_library.gd match_real_species() to label emergent plants
#     that drift close to one of these genomes ("Looks like Anubias barteri")
#
# Color ramps are 6 entries (light->shade) sampled from real photo references
# of each species. We tune for "reads as this plant at a glance" — pixel-
# perfect matching isn't the goal; recognition + variety is.


# Category id -> human label. Library panel uses this to group entries.
const CATEGORIES: Dictionary = {
	"anubias":    "Anubias",
	"buce":       "Bucephalandra",
	"crypt":      "Cryptocoryne",
	"stem":       "Stem Plants",
	"carpet":     "Carpets",
	"moss":       "Mosses",
	"fern":       "Ferns",
	"sword":      "Echinodorus (Swords)",
	"floating":   "Floating Plants",
	"specialty":  "Specialty",
}


# Short color helper — the table below uses these so it stays readable.
static func _c(r: int, g: int, b: int) -> Color:
	return Color8(r, g, b)


# Master catalog. Each entry: {
#   id, common_name, latin_name, category, role, origin,
#   light: "low"|"med"|"high", co2: "no"|"opt"|"yes",
#   substrate: "yes"|"epi"|"surface", difficulty: "easy"|"med"|"hard",
#   description: short paragraph,
#   genome: { max_height, growth_rate, sway_amplitude, leaf_form, leaf_length,
#             leaf_size_mult, is_epiphyte, is_carpet, whorled_leaves,
#             variegation, quilted, wavy_edges, iridescence,
#             red_potential, co2_demand, melt_susceptibility, has_plantlets,
#             ramp_override }
# }
static func entries() -> Array:
	return [
		# ─── ANUBIAS (rhizome epiphytes, slow, low light, no CO2) ────────────
		{
			"id": "anubias_barteri",
			"common_name": "Anubias barteri",
			"latin_name": "Anubias barteri",
			"category": "anubias",
			"role": "Epiphyte / Midground",
			"origin": "West Africa",
			"light": "low", "co2": "no", "substrate": "epi", "difficulty": "easy",
			"description": "Classic broad-spade anubias. Thick waxy dark green leaves on a horizontal rhizome attached to wood or rock. The most forgiving aquarium plant — survives anything except buried rhizomes.",
			"genome": {
				"leaf_form": "spade", "max_height": 8, "leaf_length": 5,
				"leaf_size_mult": 1.2, "growth_rate": 0.06,
				"is_epiphyte": true, "sway_amplitude": 0.18,
				"quilted": true,
				"red_potential": 0.0, "co2_demand": 0.1,
				"ramp_override": [
					_c(18, 42, 22), _c(28, 60, 32), _c(40, 86, 44),
					_c(56, 112, 58), _c(78, 138, 76), _c(102, 162, 90),
				],
			},
		},
		{
			"id": "anubias_nana",
			"common_name": "Anubias nana",
			"latin_name": "Anubias barteri var. nana",
			"category": "anubias",
			"role": "Epiphyte / Midground",
			"origin": "West Africa",
			"light": "low", "co2": "no", "substrate": "epi", "difficulty": "easy",
			"description": "Smaller-leafed sibling of barteri. The workhorse epiphyte for mid-to-foreground attachment — small enough to fit on driftwood crooks and rock crevices.",
			"genome": {
				"leaf_form": "spade", "max_height": 5, "leaf_length": 3,
				"leaf_size_mult": 0.85, "growth_rate": 0.06,
				"is_epiphyte": true, "sway_amplitude": 0.16,
				"ramp_override": [
					_c(20, 46, 24), _c(30, 64, 34), _c(46, 92, 50),
					_c(62, 120, 64), _c(82, 145, 80), _c(108, 168, 96),
				],
			},
		},
		{
			"id": "anubias_petite",
			"common_name": "Anubias nana 'Petite'",
			"latin_name": "Anubias barteri var. nana 'Petite'",
			"category": "anubias",
			"role": "Foreground Epiphyte",
			"origin": "West Africa",
			"light": "low", "co2": "no", "substrate": "epi", "difficulty": "easy",
			"description": "Miniature anubias with thumbnail-sized leaves. Foreground epiphyte — small enough to dot across hardscape like sculpture.",
			"genome": {
				"leaf_form": "spade", "max_height": 3, "leaf_length": 2,
				"leaf_size_mult": 0.6, "growth_rate": 0.05,
				"is_epiphyte": true, "sway_amplitude": 0.14,
				"ramp_override": [
					_c(22, 50, 26), _c(32, 68, 36), _c(48, 96, 52),
					_c(66, 124, 68), _c(86, 150, 84), _c(112, 172, 98),
				],
			},
		},
		{
			"id": "anubias_coffeefolia",
			"common_name": "Anubias 'Coffeefolia'",
			"latin_name": "Anubias barteri 'Coffeefolia'",
			"category": "anubias",
			"role": "Epiphyte / Midground",
			"origin": "West Africa",
			"light": "low", "co2": "no", "substrate": "epi", "difficulty": "easy",
			"description": "Distinctive bullate (hammered) leaf texture with bronze-to-coffee new growth that matures to green. The quilted surface is the visual signature.",
			"genome": {
				"leaf_form": "spade", "max_height": 7, "leaf_length": 4,
				"leaf_size_mult": 1.0, "growth_rate": 0.05,
				"is_epiphyte": true, "sway_amplitude": 0.16,
				"quilted": true, "red_potential": 0.18,
				"ramp_override": [
					_c(34, 28, 14), _c(58, 46, 22), _c(72, 76, 38),
					_c(76, 118, 58), _c(96, 146, 78), _c(120, 168, 96),
				],
			},
		},
		{
			"id": "anubias_stardust",
			"common_name": "Anubias 'Stardust'",
			"latin_name": "Anubias barteri 'Stardust'",
			"category": "anubias",
			"role": "Accent Epiphyte",
			"origin": "Cultivar",
			"light": "low", "co2": "no", "substrate": "epi", "difficulty": "med",
			"description": "Variegated cultivar with white speckles dusted across the dark green leaves. Slow grower; the variegation stabilizes with maturity.",
			"genome": {
				"leaf_form": "spade", "max_height": 4, "leaf_length": 3,
				"leaf_size_mult": 0.7, "growth_rate": 0.04,
				"is_epiphyte": true, "variegation": 0.18, "sway_amplitude": 0.14,
				"ramp_override": [
					_c(20, 44, 24), _c(30, 60, 32), _c(46, 88, 50),
					_c(64, 116, 66), _c(86, 140, 82), _c(112, 162, 100),
				],
			},
		},

		# ─── BUCEPHALANDRA (rhizome epiphytes, iridescent) ───────────────────
		{
			"id": "buce_kedagang",
			"common_name": "Bucephalandra 'Kedagang'",
			"latin_name": "Bucephalandra sp. 'Kedagang'",
			"category": "buce",
			"role": "Epiphyte / Foreground Accent",
			"origin": "Borneo",
			"light": "low", "co2": "opt", "substrate": "epi", "difficulty": "easy",
			"description": "Long, slightly wavy dark-green leaves with subtle iridescent sheen. Iconic buce — the one most hobbyists meet first. White root hairs visible on rhizome.",
			"genome": {
				"leaf_form": "lance", "max_height": 5, "leaf_length": 4,
				"leaf_size_mult": 0.95, "growth_rate": 0.05,
				"is_epiphyte": true, "wavy_edges": true, "iridescence": 0.35,
				"red_potential": 0.15, "sway_amplitude": 0.18,
				"ramp_override": [
					_c(16, 32, 22), _c(26, 50, 32), _c(40, 76, 44),
					_c(58, 108, 60), _c(80, 138, 82), _c(108, 162, 102),
				],
			},
		},
		{
			"id": "buce_brownie_ghost",
			"common_name": "Bucephalandra 'Brownie Ghost'",
			"latin_name": "Bucephalandra sp. 'Brownie Ghost'",
			"category": "buce",
			"role": "Epiphyte / Foreground Accent",
			"origin": "Borneo",
			"light": "low", "co2": "opt", "substrate": "epi", "difficulty": "med",
			"description": "Small elongated leaves in deep brown-green that ghost toward purple-iridescent under good light. Slow, compact, premium.",
			"genome": {
				"leaf_form": "lance", "max_height": 4, "leaf_length": 3,
				"leaf_size_mult": 0.75, "growth_rate": 0.04,
				"is_epiphyte": true, "iridescence": 0.55,
				"red_potential": 0.35, "sway_amplitude": 0.14,
				"ramp_override": [
					_c(28, 22, 18), _c(48, 36, 26), _c(60, 56, 38),
					_c(72, 84, 56), _c(90, 116, 78), _c(120, 144, 100),
				],
			},
		},
		{
			"id": "buce_wavy_green",
			"common_name": "Bucephalandra 'Wavy Green'",
			"latin_name": "Bucephalandra sp. 'Wavy Green'",
			"category": "buce",
			"role": "Epiphyte / Midground Accent",
			"origin": "Borneo",
			"light": "low", "co2": "opt", "substrate": "epi", "difficulty": "easy",
			"description": "Ruffled emerald margins — the wave is in the leaf edge itself, not the sway. Reads as movement even in still water.",
			"genome": {
				"leaf_form": "lance", "max_height": 5, "leaf_length": 4,
				"leaf_size_mult": 1.0, "growth_rate": 0.05,
				"is_epiphyte": true, "wavy_edges": true, "iridescence": 0.25,
				"sway_amplitude": 0.20,
				"ramp_override": [
					_c(22, 50, 30), _c(34, 72, 40), _c(50, 104, 56),
					_c(72, 138, 76), _c(98, 168, 96), _c(126, 192, 118),
				],
			},
		},
		{
			"id": "buce_theia",
			"common_name": "Bucephalandra 'Theia'",
			"latin_name": "Bucephalandra sp. 'Theia'",
			"category": "buce",
			"role": "Accent Epiphyte",
			"origin": "Borneo",
			"light": "low", "co2": "opt", "substrate": "epi", "difficulty": "med",
			"description": "Deep purple-iridescent flat oval leaves. The most dramatic color shift under high light — looks black at angles, electric purple head-on.",
			"genome": {
				"leaf_form": "oval", "max_height": 4, "leaf_length": 3,
				"leaf_size_mult": 0.85, "growth_rate": 0.04,
				"is_epiphyte": true, "iridescence": 0.75,
				"red_potential": 0.55, "sway_amplitude": 0.14,
				"ramp_override": [
					_c(36, 18, 38), _c(52, 28, 56), _c(64, 46, 76),
					_c(76, 70, 96), _c(94, 100, 122), _c(120, 132, 148),
				],
			},
		},

		# ─── CRYPTOCORYNE (substrate rosettes with runners) ─────────────────
		{
			"id": "crypt_wendtii_green",
			"common_name": "Cryptocoryne wendtii (Green)",
			"latin_name": "Cryptocoryne wendtii 'green'",
			"category": "crypt",
			"role": "Midground rosette",
			"origin": "Sri Lanka",
			"light": "low", "co2": "no", "substrate": "yes", "difficulty": "easy",
			"description": "Ruffled lance leaves emerging from a basal crown. Spreads slowly via runners. Famous for 'melt' — drops all leaves when relocated, regrows from roots over days.",
			"genome": {
				"leaf_form": "paddle", "max_height": 8, "leaf_length": 5,
				"leaf_size_mult": 1.0, "growth_rate": 0.10,
				"wavy_edges": true, "melt_susceptibility": 0.7,
				"sway_amplitude": 0.22,
				"ramp_override": [
					_c(22, 48, 26), _c(34, 70, 36), _c(52, 100, 52),
					_c(76, 132, 74), _c(102, 156, 96), _c(130, 180, 116),
				],
			},
		},
		{
			"id": "crypt_wendtii_brown",
			"common_name": "Cryptocoryne wendtii (Brown)",
			"latin_name": "Cryptocoryne wendtii 'brown'",
			"category": "crypt",
			"role": "Midground rosette",
			"origin": "Sri Lanka",
			"light": "low", "co2": "no", "substrate": "yes", "difficulty": "easy",
			"description": "Bronze-brown wavy lance leaves. The most popular wendtii variant — new growth comes in distinctly red-brown before maturing.",
			"genome": {
				"leaf_form": "paddle", "max_height": 8, "leaf_length": 5,
				"leaf_size_mult": 1.0, "growth_rate": 0.10,
				"wavy_edges": true, "melt_susceptibility": 0.7,
				"red_potential": 0.4, "sway_amplitude": 0.22,
				"ramp_override": [
					_c(38, 24, 18), _c(60, 42, 28), _c(82, 66, 40),
					_c(96, 96, 58), _c(118, 130, 84), _c(150, 162, 110),
				],
			},
		},
		{
			"id": "crypt_parva",
			"common_name": "Cryptocoryne parva",
			"latin_name": "Cryptocoryne parva",
			"category": "crypt",
			"role": "Foreground rosette",
			"origin": "Sri Lanka",
			"light": "med", "co2": "opt", "substrate": "yes", "difficulty": "med",
			"description": "True dwarf crypt — 2 inches max. Tiny grass-like rosettes that spread slowly into a foreground mat. The only crypt small enough for true foreground use.",
			"genome": {
				"leaf_form": "ribbon", "max_height": 3, "leaf_length": 3,
				"leaf_size_mult": 0.7, "growth_rate": 0.08,
				"melt_susceptibility": 0.5, "sway_amplitude": 0.16,
				"ramp_override": [
					_c(24, 56, 28), _c(38, 80, 40), _c(58, 110, 56),
					_c(82, 140, 76), _c(108, 162, 96), _c(134, 184, 116),
				],
			},
		},
		{
			"id": "crypt_spiralis",
			"common_name": "Cryptocoryne spiralis",
			"latin_name": "Cryptocoryne spiralis",
			"category": "crypt",
			"role": "Background rosette",
			"origin": "India",
			"light": "low", "co2": "no", "substrate": "yes", "difficulty": "easy",
			"description": "Long twisted ribbon leaves spiral upward from a single crown. Background statement plant; reads as 'spiral grass' from any angle.",
			"genome": {
				"leaf_form": "ribbon", "max_height": 16, "leaf_length": 12,
				"leaf_size_mult": 1.1, "growth_rate": 0.13,
				"melt_susceptibility": 0.6, "sway_amplitude": 0.36,
				"wavy_edges": true,
				"ramp_override": [
					_c(28, 48, 22), _c(40, 76, 32), _c(60, 108, 50),
					_c(84, 138, 72), _c(108, 162, 90), _c(134, 184, 110),
				],
			},
		},

		# ─── STEM PLANTS (vertical, branching, the red ones) ────────────────
		{
			"id": "rotala_rotundifolia",
			"common_name": "Rotala rotundifolia",
			"latin_name": "Rotala rotundifolia",
			"category": "stem",
			"role": "Background stem",
			"origin": "Southeast Asia",
			"light": "med", "co2": "opt", "substrate": "yes", "difficulty": "easy",
			"description": "Narrow needle leaves in whorls along a branching stem. Green at low light, blushes orange-pink at the tips under high light + CO2.",
			"genome": {
				"leaf_form": "lance", "max_height": 18, "leaf_length": 3,
				"leaf_size_mult": 0.7, "growth_rate": 0.20,
				"whorled_leaves": true, "red_potential": 0.55,
				"co2_demand": 0.5, "sway_amplitude": 0.30,
				"iridescence": 0.12,
				"ramp_override": [
					_c(22, 58, 26), _c(40, 88, 42), _c(78, 124, 64),
					_c(132, 138, 78), _c(176, 130, 80), _c(208, 122, 92),
				],
			},
		},
		{
			"id": "rotala_hra",
			"common_name": "Rotala 'H'ra'",
			"latin_name": "Rotala rotundifolia 'H'ra'",
			"category": "stem",
			"role": "Background stem",
			"origin": "Vietnam",
			"light": "high", "co2": "yes", "substrate": "yes", "difficulty": "med",
			"description": "Intense orange-red whorls under strong light + CO2 + lean N. The standard 'fire' stem in aquascaping competitions.",
			"genome": {
				"leaf_form": "lance", "max_height": 18, "leaf_length": 3,
				"leaf_size_mult": 0.65, "growth_rate": 0.22,
				"whorled_leaves": true, "red_potential": 0.95,
				"co2_demand": 0.85, "sway_amplitude": 0.32,
				"ramp_override": [
					_c(48, 28, 18), _c(96, 48, 28), _c(150, 70, 42),
					_c(196, 100, 60), _c(228, 132, 88), _c(242, 168, 122),
				],
			},
		},
		{
			"id": "rotala_macrandra",
			"common_name": "Rotala macrandra",
			"latin_name": "Rotala macrandra",
			"category": "stem",
			"role": "Background stem",
			"origin": "India",
			"light": "high", "co2": "yes", "substrate": "yes", "difficulty": "hard",
			"description": "The deepest blood-red in the planted hobby. Broad oval whorls. Demanding — needs strong light, dosing, CO2. Melts if conditions slip.",
			"genome": {
				"leaf_form": "oval", "max_height": 16, "leaf_length": 4,
				"leaf_size_mult": 0.9, "growth_rate": 0.18,
				"whorled_leaves": true, "red_potential": 1.0,
				"co2_demand": 0.95, "melt_susceptibility": 0.5,
				"sway_amplitude": 0.28,
				"ramp_override": [
					_c(48, 14, 18), _c(92, 28, 32), _c(146, 52, 56),
					_c(186, 78, 84), _c(214, 108, 116), _c(232, 142, 152),
				],
			},
		},
		{
			"id": "ludwigia_repens",
			"common_name": "Ludwigia repens",
			"latin_name": "Ludwigia repens",
			"category": "stem",
			"role": "Background stem",
			"origin": "North + Central America",
			"light": "med", "co2": "opt", "substrate": "yes", "difficulty": "easy",
			"description": "Oval leaves with copper-red undersides. Easier than Rotala; reds reliably under medium light. Topside green, flips copper on every leaf.",
			"genome": {
				"leaf_form": "oval", "max_height": 18, "leaf_length": 4,
				"leaf_size_mult": 1.0, "growth_rate": 0.20,
				"red_potential": 0.7, "co2_demand": 0.5,
				"underside_tone": _c(168, 88, 56),
				"sway_amplitude": 0.32,
				"ramp_override": [
					_c(40, 60, 26), _c(70, 96, 42), _c(112, 124, 62),
					_c(156, 132, 78), _c(192, 138, 96), _c(218, 156, 124),
				],
			},
		},
		{
			"id": "ludwigia_super_red",
			"common_name": "Ludwigia 'Super Red'",
			"latin_name": "Ludwigia natans 'Super Red'",
			"category": "stem",
			"role": "Background stem",
			"origin": "Cultivar",
			"light": "med", "co2": "opt", "substrate": "yes", "difficulty": "easy",
			"description": "Solid red leaves even at moderate light — the most beginner-friendly red plant. Small rounded leaves on slim stems.",
			"genome": {
				"leaf_form": "oval", "max_height": 16, "leaf_length": 3,
				"leaf_size_mult": 0.85, "growth_rate": 0.18,
				"red_potential": 0.9, "co2_demand": 0.4,
				"sway_amplitude": 0.30,
				"ramp_override": [
					_c(72, 22, 20), _c(122, 40, 36), _c(168, 64, 56),
					_c(202, 92, 80), _c(224, 124, 108), _c(238, 156, 140),
				],
			},
		},
		{
			"id": "alternanthera_reineckii",
			"common_name": "Alternanthera reineckii",
			"latin_name": "Alternanthera reineckii",
			"category": "stem",
			"role": "Midground / background stem",
			"origin": "South America",
			"light": "med", "co2": "opt", "substrate": "yes", "difficulty": "med",
			"description": "Broad pointed leaves with magenta-pink topside, deep purple underside. The classic 'pink plant' in nature-style aquascapes.",
			"genome": {
				"leaf_form": "lance", "max_height": 14, "leaf_length": 5,
				"leaf_size_mult": 1.05, "growth_rate": 0.16,
				"red_potential": 0.85, "co2_demand": 0.55,
				"underside_tone": _c(96, 32, 84),
				"sway_amplitude": 0.30,
				"ramp_override": [
					_c(72, 26, 56), _c(122, 48, 92), _c(170, 78, 124),
					_c(204, 110, 152), _c(226, 140, 174), _c(240, 168, 196),
				],
			},
		},
		{
			"id": "hygrophila_pinnatifida",
			"common_name": "Hygrophila pinnatifida",
			"latin_name": "Hygrophila pinnatifida",
			"category": "stem",
			"role": "Midground epiphyte / stem",
			"origin": "India",
			"light": "med", "co2": "opt", "substrate": "epi", "difficulty": "med",
			"description": "Lobed fern-like leaves with red-brown undersides. Uniquely can attach to wood as an epiphyte OR root as a stem. The lobed silhouette is the signature.",
			"genome": {
				"leaf_form": "pinnate", "max_height": 12, "leaf_length": 5,
				"leaf_size_mult": 1.0, "growth_rate": 0.13,
				"is_epiphyte": true, "red_potential": 0.55,
				"co2_demand": 0.5, "underside_tone": _c(126, 64, 36),
				"sway_amplitude": 0.24,
				"ramp_override": [
					_c(38, 56, 30), _c(64, 86, 40), _c(102, 116, 56),
					_c(146, 130, 80), _c(180, 144, 108), _c(206, 162, 132),
				],
			},
		},

		# ─── CARPETS (foreground, runner-spreading) ─────────────────────────
		{
			"id": "monte_carlo",
			"common_name": "Monte Carlo",
			"latin_name": "Micranthemum 'Monte Carlo'",
			"category": "carpet",
			"role": "Foreground carpet",
			"origin": "Argentina",
			"light": "high", "co2": "opt", "substrate": "yes", "difficulty": "easy",
			"description": "Tiny round leaves spreading horizontally via runners. The easiest tight carpet — needs less CO2 than HC and forms a denser mat than glosso.",
			"genome": {
				"leaf_form": "oval", "max_height": 2, "leaf_length": 2,
				"leaf_size_mult": 0.55, "growth_rate": 0.18,
				"is_carpet": true, "co2_demand": 0.45,
				"sway_amplitude": 0.10,
				"ramp_override": [
					_c(46, 86, 36), _c(64, 110, 48), _c(86, 138, 64),
					_c(112, 162, 82), _c(140, 184, 104), _c(168, 204, 128),
				],
			},
		},
		{
			"id": "hc_cuba",
			"common_name": "HC Cuba",
			"latin_name": "Hemianthus callitrichoides 'Cuba'",
			"category": "carpet",
			"role": "Foreground carpet",
			"origin": "Cuba",
			"light": "high", "co2": "yes", "substrate": "yes", "difficulty": "hard",
			"description": "Sub-millimeter round leaves. The finest carpet in the hobby — looks like green velvet from across the room. Demands strong CO2 and intense light.",
			"genome": {
				"leaf_form": "oval", "max_height": 2, "leaf_length": 2,
				"leaf_size_mult": 0.4, "growth_rate": 0.15,
				"is_carpet": true, "co2_demand": 0.85,
				"sway_amplitude": 0.08,
				"ramp_override": [
					_c(52, 100, 42), _c(70, 126, 56), _c(94, 156, 74),
					_c(120, 184, 94), _c(148, 208, 116), _c(178, 226, 140),
				],
			},
		},
		{
			"id": "dwarf_hairgrass",
			"common_name": "Dwarf Hairgrass",
			"latin_name": "Eleocharis parvula",
			"category": "carpet",
			"role": "Foreground carpet",
			"origin": "Cosmopolitan",
			"light": "med", "co2": "opt", "substrate": "yes", "difficulty": "easy",
			"description": "Fine grass blades spreading via runners. Reads as 'manicured lawn' once filled in. Easier than HC; tolerates lower light.",
			"genome": {
				"leaf_form": "needle", "max_height": 3, "leaf_length": 4,
				"leaf_size_mult": 0.85, "growth_rate": 0.16,
				"is_carpet": true, "co2_demand": 0.4,
				"sway_amplitude": 0.20,
				"ramp_override": [
					_c(50, 90, 38), _c(72, 116, 54), _c(96, 144, 72),
					_c(122, 168, 92), _c(150, 192, 116), _c(180, 216, 142),
				],
			},
		},
		{
			"id": "glossostigma",
			"common_name": "Glossostigma elatinoides",
			"latin_name": "Glossostigma elatinoides",
			"category": "carpet",
			"role": "Foreground carpet",
			"origin": "Australia / New Zealand",
			"light": "high", "co2": "yes", "substrate": "yes", "difficulty": "hard",
			"description": "Tiny paddle-shaped leaves on creeping stems. The classic Amano carpet — predates Monte Carlo as the iaquascaping foreground standard.",
			"genome": {
				"leaf_form": "paddle", "max_height": 2, "leaf_length": 2,
				"leaf_size_mult": 0.5, "growth_rate": 0.16,
				"is_carpet": true, "co2_demand": 0.8,
				"sway_amplitude": 0.10,
				"ramp_override": [
					_c(44, 90, 40), _c(64, 116, 54), _c(88, 142, 72),
					_c(116, 168, 92), _c(144, 192, 116), _c(174, 216, 140),
				],
			},
		},
		{
			"id": "dwarf_sag",
			"common_name": "Dwarf Sagittaria",
			"latin_name": "Sagittaria subulata",
			"category": "carpet",
			"role": "Foreground / Midground",
			"origin": "Americas",
			"light": "low", "co2": "no", "substrate": "yes", "difficulty": "easy",
			"description": "Short grass-like ribbons spreading by runners. Tolerates low light; the hardiest foreground option for beginner tanks.",
			"genome": {
				"leaf_form": "ribbon", "max_height": 4, "leaf_length": 4,
				"leaf_size_mult": 0.8, "growth_rate": 0.14,
				"is_carpet": true, "co2_demand": 0.2,
				"sway_amplitude": 0.22,
				"ramp_override": [
					_c(40, 80, 36), _c(60, 108, 52), _c(84, 138, 72),
					_c(112, 164, 92), _c(140, 188, 116), _c(170, 212, 140),
				],
			},
		},
		{
			"id": "marsilea",
			"common_name": "Marsilea hirsuta",
			"latin_name": "Marsilea hirsuta",
			"category": "carpet",
			"role": "Foreground carpet",
			"origin": "Australia",
			"light": "med", "co2": "no", "substrate": "yes", "difficulty": "easy",
			"description": "Four-leaf-clover shape on a creeping rhizome. Lucky-clover carpet for low-light tanks. Slow but reliable.",
			"genome": {
				"leaf_form": "four_leaf", "max_height": 2, "leaf_length": 2,
				"leaf_size_mult": 0.8, "growth_rate": 0.10,
				"is_carpet": true, "co2_demand": 0.2,
				"sway_amplitude": 0.10,
				"ramp_override": [
					_c(48, 88, 36), _c(68, 114, 52), _c(92, 142, 72),
					_c(118, 168, 92), _c(146, 192, 116), _c(176, 216, 140),
				],
			},
		},
		{
			"id": "pogostemon_helferi",
			"common_name": "Pogostemon helferi 'Downoi'",
			"latin_name": "Pogostemon helferi",
			"category": "carpet",
			"role": "Foreground / Midground",
			"origin": "Thailand",
			"light": "med", "co2": "opt", "substrate": "yes", "difficulty": "med",
			"description": "Crinkled curly rosette — looks like a tiny downy mound. Each plant stays compact; clusters read as moss-like texture.",
			"genome": {
				"leaf_form": "downy", "max_height": 3, "leaf_length": 2,
				"leaf_size_mult": 0.85, "growth_rate": 0.10,
				"co2_demand": 0.55, "sway_amplitude": 0.14,
				"ramp_override": [
					_c(36, 76, 32), _c(56, 104, 50), _c(80, 132, 70),
					_c(106, 158, 92), _c(134, 184, 116), _c(164, 208, 142),
				],
			},
		},

		# ─── MOSSES (hardscape-attached, no roots) ──────────────────────────
		{
			"id": "java_moss",
			"common_name": "Java Moss",
			"latin_name": "Taxiphyllum barbieri",
			"category": "moss",
			"role": "Epiphyte / Hardscape carpet",
			"origin": "Southeast Asia",
			"light": "low", "co2": "no", "substrate": "epi", "difficulty": "easy",
			"description": "Irregular tangled fronds. The easiest moss — clips to anything, grows in everything. Foundation moss for shrimp tanks.",
			"genome": {
				"leaf_form": "downy", "max_height": 3, "leaf_length": 2,
				"leaf_size_mult": 0.7, "growth_rate": 0.10,
				"is_epiphyte": true, "sway_amplitude": 0.16,
				"ramp_override": [
					_c(28, 56, 26), _c(46, 84, 42), _c(70, 116, 60),
					_c(96, 144, 80), _c(126, 168, 104), _c(156, 192, 128),
				],
			},
		},
		{
			"id": "christmas_moss",
			"common_name": "Christmas Moss",
			"latin_name": "Vesicularia montagnei",
			"category": "moss",
			"role": "Epiphyte / Hardscape carpet",
			"origin": "South America",
			"light": "low", "co2": "no", "substrate": "epi", "difficulty": "easy",
			"description": "Flat triangular branching pattern — actually resembles tiny pine boughs. The most visually distinct moss.",
			"genome": {
				"leaf_form": "fingered", "max_height": 4, "leaf_length": 3,
				"leaf_size_mult": 0.6, "growth_rate": 0.09,
				"is_epiphyte": true, "sway_amplitude": 0.18,
				"ramp_override": [
					_c(30, 60, 30), _c(50, 88, 46), _c(74, 120, 66),
					_c(100, 150, 88), _c(130, 176, 112), _c(160, 200, 136),
				],
			},
		},
		{
			"id": "weeping_moss",
			"common_name": "Weeping Moss",
			"latin_name": "Vesicularia ferriei",
			"category": "moss",
			"role": "Epiphyte (drooping)",
			"origin": "China",
			"light": "low", "co2": "no", "substrate": "epi", "difficulty": "easy",
			"description": "Drooping downward strands like a tiny willow. Best on driftwood tops where it can cascade. Slow-growing, dramatic silhouette.",
			"genome": {
				"leaf_form": "downy", "max_height": 5, "leaf_length": 2,
				"leaf_size_mult": 0.65, "growth_rate": 0.08,
				"is_epiphyte": true, "sway_amplitude": 0.32,
				"ramp_override": [
					_c(28, 58, 28), _c(46, 84, 44), _c(68, 114, 62),
					_c(92, 142, 82), _c(120, 168, 106), _c(150, 192, 130),
				],
			},
		},

		# ─── FERNS (rhizome epiphytes) ──────────────────────────────────────
		{
			"id": "java_fern",
			"common_name": "Java Fern",
			"latin_name": "Microsorum pteropus",
			"category": "fern",
			"role": "Epiphyte / Background",
			"origin": "Southeast Asia",
			"light": "low", "co2": "no", "substrate": "epi", "difficulty": "easy",
			"description": "Broad lance fronds on a horizontal rhizome attached to wood. Slow, indestructible. Produces baby plantlets on leaf tips.",
			"genome": {
				"leaf_form": "lobed", "max_height": 12, "leaf_length": 8,
				"leaf_size_mult": 1.15, "growth_rate": 0.07,
				"is_epiphyte": true, "has_plantlets": true,
				"sway_amplitude": 0.22,
				"ramp_override": [
					_c(22, 50, 24), _c(38, 80, 38), _c(60, 112, 58),
					_c(86, 142, 80), _c(112, 168, 102), _c(142, 192, 126),
				],
			},
		},
		{
			"id": "java_fern_windelov",
			"common_name": "Java Fern 'Windelov'",
			"latin_name": "Microsorum pteropus 'Windelov'",
			"category": "fern",
			"role": "Epiphyte / Background",
			"origin": "Cultivar",
			"light": "low", "co2": "no", "substrate": "epi", "difficulty": "easy",
			"description": "Lacy fingered tips — each frond splays at the top like coral fingers. Slower than standard java fern but visually striking.",
			"genome": {
				"leaf_form": "fingered", "max_height": 10, "leaf_length": 7,
				"leaf_size_mult": 1.0, "growth_rate": 0.06,
				"is_epiphyte": true, "has_plantlets": true,
				"sway_amplitude": 0.20,
				"ramp_override": [
					_c(24, 52, 26), _c(40, 82, 40), _c(62, 114, 60),
					_c(88, 144, 82), _c(114, 170, 104), _c(144, 194, 128),
				],
			},
		},
		{
			"id": "java_fern_trident",
			"common_name": "Java Fern 'Trident'",
			"latin_name": "Microsorum pteropus 'Trident'",
			"category": "fern",
			"role": "Epiphyte / Background",
			"origin": "Cultivar",
			"light": "low", "co2": "no", "substrate": "epi", "difficulty": "easy",
			"description": "Deeply lobed/serrated narrow fronds. The most interesting java fern silhouette — reads as 3-pronged from a distance.",
			"genome": {
				"leaf_form": "pinnate", "max_height": 12, "leaf_length": 7,
				"leaf_size_mult": 0.95, "growth_rate": 0.07,
				"is_epiphyte": true, "has_plantlets": true,
				"sway_amplitude": 0.22,
				"ramp_override": [
					_c(22, 48, 24), _c(38, 78, 38), _c(60, 110, 58),
					_c(84, 140, 80), _c(110, 166, 100), _c(140, 188, 124),
				],
			},
		},
		{
			"id": "bolbitis",
			"common_name": "Bolbitis heudelotii",
			"latin_name": "Bolbitis heudelotii",
			"category": "fern",
			"role": "Epiphyte / Midground",
			"origin": "West Africa",
			"light": "low", "co2": "opt", "substrate": "epi", "difficulty": "med",
			"description": "Finely divided dark-green fronds — looks like an underwater fern out of a primordial swamp. Slow grower, premium look.",
			"genome": {
				"leaf_form": "pinnate", "max_height": 10, "leaf_length": 6,
				"leaf_size_mult": 1.0, "growth_rate": 0.06,
				"is_epiphyte": true, "sway_amplitude": 0.24,
				"ramp_override": [
					_c(20, 44, 22), _c(36, 72, 36), _c(56, 102, 54),
					_c(80, 132, 74), _c(106, 156, 96), _c(134, 178, 118),
				],
			},
		},

		# ─── ECHINODORUS (swords) ───────────────────────────────────────────
		{
			"id": "amazon_sword",
			"common_name": "Amazon Sword",
			"latin_name": "Echinodorus bleheri",
			"category": "sword",
			"role": "Background statement",
			"origin": "Brazil",
			"light": "med", "co2": "opt", "substrate": "yes", "difficulty": "easy",
			"description": "Broad lance leaves from a central crown — the classic 'centerpiece plant' for large tanks. Heavy root feeder; needs deep substrate.",
			"genome": {
				"leaf_form": "paddle", "max_height": 22, "leaf_length": 8,
				"leaf_size_mult": 1.4, "growth_rate": 0.13,
				"has_plantlets": true, "sway_amplitude": 0.28,
				"variegation": 0.10,
				"ramp_override": [
					_c(28, 58, 28), _c(46, 92, 44), _c(70, 124, 62),
					_c(96, 154, 82), _c(124, 178, 104), _c(154, 200, 128),
				],
			},
		},

		# ─── SPECIALTY ─────────────────────────────────────────────────────
		{
			"id": "blyxa_japonica",
			"common_name": "Blyxa japonica",
			"latin_name": "Blyxa japonica",
			"category": "specialty",
			"role": "Midground bush",
			"origin": "East Asia",
			"light": "med", "co2": "opt", "substrate": "yes", "difficulty": "med",
			"description": "Grass-tuft from a stem base — looks like a sea-anemone of green/red blades. Tips redden under high light. Midground bush with personality.",
			"genome": {
				"leaf_form": "starburst", "max_height": 5, "leaf_length": 5,
				"leaf_size_mult": 1.0, "growth_rate": 0.13,
				"red_potential": 0.5, "co2_demand": 0.55,
				"sway_amplitude": 0.20,
				"ramp_override": [
					_c(40, 70, 30), _c(64, 102, 46), _c(92, 132, 68),
					_c(128, 152, 88), _c(170, 156, 100), _c(204, 158, 116),
				],
			},
		},
		{
			"id": "eriocaulon_vietnam",
			"common_name": "Eriocaulon Vietnam",
			"latin_name": "Eriocaulon cinereum 'Vietnam'",
			"category": "specialty",
			"role": "Midground rosette",
			"origin": "Vietnam",
			"light": "high", "co2": "yes", "substrate": "yes", "difficulty": "hard",
			"description": "Radial starburst rosette of fine grass leaves. One of the most visually distinct planted-tank plants — looks like a green sea urchin. Demanding.",
			"genome": {
				"leaf_form": "starburst", "max_height": 4, "leaf_length": 5,
				"leaf_size_mult": 1.05, "growth_rate": 0.08,
				"co2_demand": 0.85, "sway_amplitude": 0.16,
				"ramp_override": [
					_c(48, 92, 38), _c(70, 122, 56), _c(94, 150, 76),
					_c(122, 176, 98), _c(150, 200, 122), _c(180, 222, 148),
				],
			},
		},
		{
			"id": "vallisneria_spiralis",
			"common_name": "Vallisneria spiralis",
			"latin_name": "Vallisneria spiralis",
			"category": "specialty",
			"role": "Background curtain",
			"origin": "Cosmopolitan",
			"light": "low", "co2": "no", "substrate": "yes", "difficulty": "easy",
			"description": "Long ribbon 'tape grass' background. Spreads aggressively via runners — creates a curtain effect at the back wall in weeks.",
			"genome": {
				"leaf_form": "ribbon", "max_height": 22, "leaf_length": 18,
				"leaf_size_mult": 1.2, "growth_rate": 0.20,
				"is_carpet": false, "sway_amplitude": 0.42,
				"wavy_edges": true,
				"ramp_override": [
					_c(30, 60, 26), _c(48, 90, 42), _c(72, 122, 64),
					_c(100, 152, 88), _c(130, 178, 112), _c(160, 200, 134),
				],
			},
		},
	]


# Build a fast id -> entry map for O(1) lookup.
static func by_id() -> Dictionary:
	var out: Dictionary = {}
	for e in entries():
		out[String(e.get("id", ""))] = e
	return out


# Convenience: return entries in a given category (anubias, buce, etc.)
static func in_category(cat: String) -> Array:
	var out: Array = []
	for e in entries():
		if String(e.get("category", "")) == cat:
			out.append(e)
	return out


# Find the closest real species to a given emergent plant genome by simple
# trait distance. Returns {"id": "...", "distance": float} where distance
# < 0.35 reads as "looks like" and < 0.18 reads as "is essentially" — the
# caller decides the threshold. Empty dict if no entries.
#
# Distance metric (each weighted): leaf_form (exact match = 0, mismatch = 1),
# max_height (1.0 = 20-voxel delta), color-ramp midpoint distance (0..1),
# is_epiphyte / is_carpet (booleans, 0.4 weight each), leaf_size_mult (0..1).
static func match_genome(genome: Dictionary) -> Dictionary:
	if genome.is_empty():
		return {}
	var best_id: String = ""
	var best_d: float = INF
	var g_form: String = String(genome.get("leaf_form", ""))
	var g_height: int = int(genome.get("max_height", 0))
	var g_epi: bool = bool(genome.get("is_epiphyte", false))
	var g_carp: bool = bool(genome.get("is_carpet", false))
	var g_lsm: float = float(genome.get("leaf_size_mult", 1.0))
	var g_ramp: Array = genome.get("ramp_override", [])
	var g_mid: Color = (g_ramp[3] as Color) if g_ramp.size() >= 4 else Color8(80, 130, 70)
	for e in entries():
		var eg: Dictionary = e.get("genome", {})
		var d: float = 0.0
		d += 0.0 if String(eg.get("leaf_form", "")) == g_form else 1.0
		d += clampf(absf(int(eg.get("max_height", 0)) - g_height) / 20.0, 0.0, 1.0) * 0.6
		d += clampf(absf(float(eg.get("leaf_size_mult", 1.0)) - g_lsm), 0.0, 1.0) * 0.4
		if bool(eg.get("is_epiphyte", false)) != g_epi:
			d += 0.4
		if bool(eg.get("is_carpet", false)) != g_carp:
			d += 0.3
		var er: Array = eg.get("ramp_override", [])
		if er.size() >= 4:
			var em: Color = er[3] as Color
			d += (Vector3(em.r, em.g, em.b) - Vector3(g_mid.r, g_mid.g, g_mid.b)).length() * 0.8
		if d < best_d:
			best_d = d
			best_id = String(e.get("id", ""))
	if best_id == "":
		return {}
	return {"id": best_id, "distance": best_d}


# Pick a random library entry, optionally constrained to a category, and
# return its genome with mild color/size jitter so 60% of "randomize"
# clicks land on a plausible plant instead of a uniform-random monster.
# This is the "real-feel random" generator the creator UI uses.
static func random_real_genome(category: String = "") -> Dictionary:
	var pool: Array = entries() if category == "" else in_category(category)
	if pool.is_empty():
		return {}
	var pick: Dictionary = pool[randi() % pool.size()]
	var genome: Dictionary = (pick.get("genome", {}) as Dictionary).duplicate(true)
	# Mild jitter on the ramp colors so the result reads as a slight
	# variant of the picked species rather than an exact clone.
	if genome.has("ramp_override"):
		var ramp: Array = (genome["ramp_override"] as Array).duplicate(true)
		for i in ramp.size():
			var c: Color = ramp[i] as Color
			var j: float = 0.06
			ramp[i] = Color(
				clampf(c.r + randf_range(-j, j), 0.0, 1.0),
				clampf(c.g + randf_range(-j, j), 0.0, 1.0),
				clampf(c.b + randf_range(-j, j), 0.0, 1.0),
			)
		genome["ramp_override"] = ramp
	if genome.has("max_height"):
		genome["max_height"] = clampi(int(genome["max_height"])
			+ randi_range(-2, 2), 2, 30)
	# Stamp the original common name as the parent lineage so discovery
	# / library readouts show provenance.
	genome["parent_lineage"] = "Wild — " + String(pick.get("common_name", ""))
	genome["species_id"] = String(pick.get("id", ""))
	genome["common_name"] = String(pick.get("common_name", ""))
	genome["latin_name"] = String(pick.get("latin_name", ""))
	return genome
