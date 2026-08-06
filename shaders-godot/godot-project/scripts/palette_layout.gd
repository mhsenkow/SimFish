# VISUAL_POLISH #166 — palette index layout for planted_48 / biotope LUTs.
# Banks are 16 contiguous indices when palette_size == 48 (see classify_bank
# in palette_quantize.gdshader). Keep this file in sync when remapping PNGs.
class_name PaletteLayout
extends RefCounted

# Bank IDs returned by classify_bank:
#   0 = cool (water, foliage greens, icy highlights)
#   1 = neutral (substrate, wood, stone, room, desaturated)
#   2 = warm (fauna corals, oranges, reds, yellows)

const BANK_COOL := 0
const BANK_NEUTRAL := 1
const BANK_WARM := 2
const BANK_SIZE := 16

const COOL_RANGE := Vector2i(0, 15)
const NEUTRAL_RANGE := Vector2i(16, 31)
const WARM_RANGE := Vector2i(32, 47)

# Reserved accent slots inside the warm bank for fauna only (#162 intent).
const FAUNA_ACCENT_START := 35
const FAUNA_ACCENT_END := 46
# White + icy highlight slots live at the cool/warm boundary.
const HIGHLIGHT_START := 32
const HIGHLIGHT_END := 34

# Substrate ramp within the neutral bank (earth tones).
const SUBSTRATE_START := 16
const SUBSTRATE_END := 23
# Stone / wood / room neutrals.
const HARDSCAPE_START := 24
const HARDSCAPE_END := 31


static func bank_for_index(i: int) -> int:
	if i < 0 or i >= 48:
		return BANK_NEUTRAL
	return i / BANK_SIZE


static func bank_name(bank: int) -> String:
	match bank:
		BANK_COOL:
			return "cool"
		BANK_WARM:
			return "warm"
		_:
			return "neutral"


static func describe() -> String:
	return (
		"48×1 LUT · cool[0–15] water/foliage · neutral[16–31] substrate/room "
		+ "· warm[32–47] fauna accents (32–34 highlights)"
	)
