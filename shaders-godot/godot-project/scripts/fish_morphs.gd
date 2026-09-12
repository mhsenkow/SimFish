extends RefCounted
class_name FishMorphs

# Per-individual colour morphs.
#
# WHY A SECOND PALETTE. mixed_morphs existed but rolled from one hardcoded
# REEF palette baked into fish.gd - clownfish orange, blue tang, anthias
# pink. Fine for a reef cube, wrong for anything else, and unreachable from
# a genome. Meanwhile guppies - the single most colour-variable fish anyone
# keeps - had ONE fixed body colour, so a tank of thirty of them rendered
# thirty identical charcoal fish with identical red tails.
#
# Palettes are named so a genome can pick one: "reef" keeps the old
# behaviour exactly, "guppy" is the fancy-guppy spread.

# Each entry is [base, accent]. Accent doubles as marking + tail colour.
const REEF: Array = [
	[Color8(245, 110, 30), Color8(255, 255, 255)],  # clownfish orange + white
	[Color8(255, 215, 40), Color8(45, 35, 25)],     # yellow tang + dark mask
	[Color8(35, 95, 220), Color8(255, 230, 30)],    # blue tang + yellow tail
	[Color8(60, 170, 215), Color8(245, 245, 245)],  # chromis blue-cyan + white
	[Color8(230, 70, 130), Color8(255, 235, 90)],   # anthias pink + amber
	[Color8(110, 60, 180), Color8(255, 220, 70)],   # royal gramma purple + yellow
	[Color8(245, 245, 245), Color8(35, 35, 50)],    # damselfish pearl + black
	[Color8(220, 60, 50), Color8(255, 245, 180)],   # squirrelfish red + cream
	[Color8(40, 80, 60), Color8(255, 200, 90)],     # moorish idol dark + yellow
]

# Fancy guppies, read off photographs of a real mixed colony. The point of
# this list is its RANGE: a real guppy tank is orange next to black next to
# drab olive next to snakeskin, all at once, and the drab ones matter as
# much as the bright ones - they are what make the bright ones read as
# bright. Weighted toward muted bodies with one hot fin, which is what a
# mixed colony actually looks like once it has bred a few generations.
const GUPPY: Array = [
	[Color8(72, 68, 54), Color8(255, 140, 40)],     # olive body, tangerine tail
	[Color8(38, 36, 42), Color8(235, 225, 200)],    # black body, cream head
	[Color8(190, 160, 110), Color8(62, 52, 40)],    # snakeskin tan + dark net
	[Color8(150, 150, 135), Color8(192, 192, 176)], # plain silver female
	[Color8(78, 70, 148), Color8(150, 190, 235)],   # blue-purple + pale blue
	[Color8(198, 62, 44), Color8(255, 198, 118)],   # red body + amber fin
	[Color8(232, 226, 202), Color8(255, 168, 88)],  # cream albino + orange
	[Color8(50, 48, 52), Color8(250, 214, 70)],     # half-black + yellow
	[Color8(108, 120, 70), Color8(228, 148, 58)],   # bronze-green + copper
	[Color8(120, 112, 96), Color8(214, 96, 64)],    # drab khaki + rust
]


static func palette(name: String) -> Array:
	match name:
		"guppy":
			return GUPPY
		_:
			return REEF


# Roll one morph index. `roll` is 0..1 so the caller keeps ownership of its
# RNG (fish.gd seeds a per-individual genetics stream). Index is returned
# separately because the reef path special-cases entry 0 (clownfish bars).
static func index_for(name: String, roll: float) -> int:
	var p: Array = palette(name)
	if p.is_empty():
		return 0
	return clampi(int(clampf(roll, 0.0, 0.99999) * float(p.size())),
		0, p.size() - 1)


static func entry(name: String, idx: int) -> Array:
	var p: Array = palette(name)
	if p.is_empty():
		return [Color.WHITE, Color.WHITE]
	return p[clampi(idx, 0, p.size() - 1)]


static func pick(name: String, roll: float) -> Array:
	return entry(name, index_for(name, roll))


# Does this palette also restyle the BODY, or only its colours?
#
# The reef path rerolls body plan too - depth, elongation, size potential -
# because a reef morph is meant to read as a different species. A guppy
# morph is the same fish in a different colour: rerolling its skeleton
# would turn half a guppy colony into disc-shaped tangs.
static func restyles_body(name: String) -> bool:
	return name != "guppy"
