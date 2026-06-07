extends RefCounted

# class_name intentionally omitted — every caller preloads this script as
# `const CreatureNaming = preload(...)`, and a class_name on top of that
# fires "constant shadows global class" warnings in the editor.

# Offline name generator + epithet helper for fish / shrimp / snails.
# Used as the always-available fallback when AIDirector is disabled or
# unreachable; AIDirector itself pulls from the same epithet table so
# LLM names get a personality-flavored title without a second round-trip.
#
# Names are intentionally short (1-3 syllables), evocative, gender-neutral.
# The pool is wide enough that ~50-fish tanks rarely collide, but caller
# can pass an already_used set to enforce hard uniqueness.


const FIRST_NAMES: Array = [
	# Mythic
	"Atlas", "Mira", "Orion", "Lyra", "Iris", "Nyx", "Selene", "Helios",
	"Persephone", "Calliope", "Echo", "Juno", "Hermes", "Vesta", "Rhea",
	"Castor", "Pollux", "Andromeda", "Cassia", "Eros", "Phoebe",
	# Nature
	"River", "Coral", "Reef", "Tide", "Marsh", "Brook", "Cove", "Bay",
	"Lagoon", "Delta", "Pearl", "Opal", "Jade", "Amber", "Ash", "Sage",
	"Fern", "Moss", "Willow", "Dune", "Cinder", "Ember", "Storm", "Rain",
	# Playful / pet
	"Bubbles", "Pip", "Pixel", "Quark", "Zippy", "Doodle", "Mochi", "Pebble",
	"Whisker", "Twig", "Sprout", "Biscuit", "Marble", "Tuffet", "Noodle",
	"Pickle", "Bean", "Tater", "Squish", "Gummy", "Pudding", "Tofu", "Wasabi",
	# Classic
	"Otis", "Mabel", "Cleo", "Eli", "Hugo", "Ruby", "Ozzie", "Stella",
	"Felix", "Olive", "Theo", "Nora", "Milo", "Hazel", "Arlo", "Iris",
	"Ezra", "Lila", "Wren", "June", "Cyrus", "Vera", "Asher", "Maeve",
	# Cosmic / abstract
	"Nova", "Vega", "Rigel", "Sirius", "Lumen", "Solis", "Aria", "Eclipse",
	"Cosmo", "Nebula", "Comet", "Halley", "Quasar", "Pulsar", "Zenith",
	# Aquatic legacy
	"Finley", "Marlin", "Coral", "Kelpie", "Tidal", "Pisces", "Aqua",
	"Nereo", "Nerida", "Triton", "Marina", "Murex", "Cassia", "Caspian",
	"Salish", "Lagan", "Brine", "Foam", "Salt", "Spray", "Surge",
]

# Epithets keyed off personality. Caller passes the 5-trait personality
# vector and we pick the strongest. Used for "Mira the Bold", "Atlas the
# Curious". When all traits are average we omit the epithet entirely so
# unremarkable fish stay just-a-name (which is also fine — most don't
# need a title).
const EPITHETS_BOLD: Array = ["the Bold", "the Brave", "the Fearless", "the Daring"]
const EPITHETS_CURIOUS: Array = ["the Curious", "the Wanderer", "the Seeker", "the Inquisitive"]
const EPITHETS_SOCIAL: Array = ["the Friendly", "the Gentle", "the Companion", "the Sociable"]
const EPITHETS_GLUTTONOUS: Array = ["the Hungry", "the Glutton", "the Famished", "the Insatiable"]
const EPITHETS_CALM: Array = ["the Calm", "the Serene", "the Steady", "the Patient"]
const EPITHETS_SHY: Array = ["the Shy", "the Hidden", "the Quiet", "the Bashful"]

# Species-flavored extra names (added to the base pool for that organism).
const FISH_FLAVOR: Array = ["Glide", "Dart", "Shimmer", "Veil", "Wisp", "Lance", "Crest"]
const SHRIMP_FLAVOR: Array = ["Skitter", "Tickle", "Snip", "Wiggle", "Tinker", "Scoot"]
const SNAIL_FLAVOR: Array = ["Slowpoke", "Mossy", "Drift", "Patience", "Linger", "Petra"]


# Generate a clean first-name (no epithet). Tries up to 8 times to avoid
# collision with `already_used` (case-insensitive). Falls back to a numbered
# variant if every attempt collides — guarantees a string, never empty.
static func generate_name(organism_kind: String, already_used: Dictionary = {}) -> String:
	var pool: Array = FIRST_NAMES.duplicate()
	match organism_kind:
		"fish":  pool.append_array(FISH_FLAVOR)
		"shrimp": pool.append_array(SHRIMP_FLAVOR)
		"snail": pool.append_array(SNAIL_FLAVOR)
	for _i in range(8):
		var pick: String = pool[randi() % pool.size()]
		if not already_used.has(pick.to_lower()):
			return pick
	# Every attempt collided. Numbered fallback so this never returns "".
	var base: String = pool[randi() % pool.size()]
	for n in range(2, 99):
		var candidate: String = "%s %d" % [base, n]
		if not already_used.has(candidate.to_lower()):
			return candidate
	return base


# Pick an epithet from a personality vector. Vector keys (all 0..1):
#   boldness, curiosity, sociability, gluttony, calm
# Returns "" when no trait stands out (max < 0.7). This is intentional —
# epithets should feel earned, not stamped on every creature.
static func epithet_for_personality(personality: Dictionary) -> String:
	if personality.is_empty():
		return ""
	var b: float = float(personality.get("boldness", 0.5))
	var c: float = float(personality.get("curiosity", 0.5))
	var s: float = float(personality.get("sociability", 0.5))
	var g: float = float(personality.get("gluttony", 0.5))
	var k: float = float(personality.get("calm", 0.5))
	var best_trait: String = ""
	var best_val: float = 0.70  # threshold to qualify
	if b > best_val:
		best_val = b
		best_trait = "bold"
	if c > best_val:
		best_val = c
		best_trait = "curious"
	if s > best_val:
		best_val = s
		best_trait = "social"
	if g > best_val:
		best_val = g
		best_trait = "glutton"
	if k > best_val:
		best_val = k
		best_trait = "calm"
	# Low boldness reads as shy — also worth flagging.
	if b < 0.25 and best_trait == "":
		best_trait = "shy"
	match best_trait:
		"bold":    return EPITHETS_BOLD[randi() % EPITHETS_BOLD.size()]
		"curious": return EPITHETS_CURIOUS[randi() % EPITHETS_CURIOUS.size()]
		"social":  return EPITHETS_SOCIAL[randi() % EPITHETS_SOCIAL.size()]
		"glutton": return EPITHETS_GLUTTONOUS[randi() % EPITHETS_GLUTTONOUS.size()]
		"calm":    return EPITHETS_CALM[randi() % EPITHETS_CALM.size()]
		"shy":     return EPITHETS_SHY[randi() % EPITHETS_SHY.size()]
		_:         return ""


# Roll a fresh personality dict. Each trait is gaussian-ish around 0.5
# (sum of three rand floats / 3 — central limit) so most creatures cluster
# near average but tails produce real personalities. Optional `bias` lets
# the caller skew the result (e.g. inherit from parents).
static func roll_personality(bias: Dictionary = {}) -> Dictionary:
	var p: Dictionary = {
		"boldness":    _gauss_clamp(float(bias.get("boldness", 0.5))),
		"curiosity":   _gauss_clamp(float(bias.get("curiosity", 0.5))),
		"sociability": _gauss_clamp(float(bias.get("sociability", 0.5))),
		"gluttony":    _gauss_clamp(float(bias.get("gluttony", 0.5))),
		"calm":        _gauss_clamp(float(bias.get("calm", 0.5))),
	}
	return p


static func _gauss_clamp(center: float, spread: float = 0.35) -> float:
	var r: float = (randf() + randf() + randf()) / 3.0  # ≈ N(0.5, ~0.16)
	var v: float = center + (r - 0.5) * 2.0 * spread
	return clampf(v, 0.0, 1.0)


# Inherit personality from two parents (mean with small mutation). When one
# parent is missing (founder spawn from store), the surviving parent is
# returned slightly nudged. When both are missing, returns a fresh roll.
static func inherit_personality(p1: Dictionary, p2: Dictionary) -> Dictionary:
	if p1.is_empty() and p2.is_empty():
		return roll_personality()
	if p1.is_empty():
		return roll_personality(p2)
	if p2.is_empty():
		return roll_personality(p1)
	var blend: Dictionary = {}
	for k in ["boldness", "curiosity", "sociability", "gluttony", "calm"]:
		var avg: float = (float(p1.get(k, 0.5)) + float(p2.get(k, 0.5))) * 0.5
		blend[k] = avg
	return roll_personality(blend)
