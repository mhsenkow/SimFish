class_name TankShare
extends RefCounted

# Tank share codes + postcard provenance (BROAD_DIRECTIONS #19).
#
# THE GAP. The game generates a unique-looking emergent tank per seed, and
# had no way to share one. `take_pond_photo()` saved a bare PNG: no tank
# identity, no seed, nothing tying the image to the tank that made it. So a
# screenshot could not be traced back, recreated, or used to bring anyone
# in — which for a visual generative game is the cheapest organic-growth
# mechanism there is, left unbuilt.
#
# Meanwhile `SimDriver.tank_seed` existed and was already persisted; it was
# simply unreachable from the UI.
#
# TWO HALVES.
#
#   1. **A share code.** `WLTK1:` + gzip + base64, matching the conventions
#      already here (`WLBP2:` for aquascape blueprints, `WLST1:` for
#      strains). Carries the seed plus the handful of config values that
#      decide how a tank looks and stocks — enough to recreate it, small
#      enough to paste in a message.
#   2. **Burned-in provenance.** A caption strip composited into the photo
#      rather than PNG metadata. Metadata is stripped by every social
#      platform and chat app on earth; pixels are not. The postcard has to
#      survive being re-uploaded, which is the only journey that matters.
#
# Decoding treats input as hostile (#6): a code is size-capped before it is
# decompressed, type-checked after, and returns {} rather than throwing.

const PREFIX: String = "WLTK1:"

# A share code is tiny by construction. Anything larger is not one of ours,
# and refusing early means a hostile paste cannot make us decompress it.
const MAX_CODE_CHARS: int = 4096
# Decompression bound, mirroring the blueprint/strain paths.
const MAX_DECOMPRESSED: int = 1 << 16

# Config values that actually change what a tank looks like and holds. Kept
# deliberately short: a share code is not a save file, and anything not here
# is left at the recipient's own defaults rather than silently overridden.
const SHARED_KEYS: Array[String] = [
	"tank_shape",
	"vessel_preset",
	"tank_preset",
	"substrate_type",
	"environment_preset",
	"lighting_preset",
	"aeration_type",
	"tank_half_w",
	"tank_half_d",
	"tank_height",
]


# --- Encode ----------------------------------------------------------------

# `config` is a plain Dictionary of the SHARED_KEYS the caller read off
# TankConfig. Taking a Dictionary rather than the node keeps this pure and
# testable, and keeps the key list in one place.
static func make_code(tank_seed: int, config: Dictionary) -> String:
	var payload: Dictionary = {"v": 1, "seed": tank_seed, "cfg": {}}
	for key in SHARED_KEYS:
		if config.has(key):
			payload["cfg"][key] = config[key]
	var json: String = JSON.stringify(payload)
	var packed: PackedByteArray = json.to_utf8_buffer().compress(
		FileAccess.COMPRESSION_GZIP)
	return PREFIX + Marshalls.raw_to_base64(packed)


# --- Decode ----------------------------------------------------------------

# Returns {} for anything that is not a valid code. Never throws.
# On success: {"v": int, "seed": int, "cfg": Dictionary}.
static func parse_code(code: String) -> Dictionary:
	var c: String = code.strip_edges()
	if c.is_empty() or not c.begins_with(PREFIX):
		return {}
	if c.length() > MAX_CODE_CHARS:
		return {}
	var packed: PackedByteArray = Marshalls.base64_to_raw(c.substr(PREFIX.length()))
	if packed.is_empty():
		return {}
	var raw: PackedByteArray = packed.decompress_dynamic(
		MAX_DECOMPRESSED, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not (parsed is Dictionary):
		return {}
	var d: Dictionary = parsed
	# A code without a usable seed is not a tank.
	if not d.has("seed"):
		return {}
	var seed_v: Variant = d["seed"]
	if typeof(seed_v) != TYPE_INT and typeof(seed_v) != TYPE_FLOAT:
		return {}
	var cfg: Variant = d.get("cfg", {})
	if not (cfg is Dictionary):
		cfg = {}
	# Drop anything not in SHARED_KEYS: a code must not be able to set
	# arbitrary config on the recipient's machine.
	var clean: Dictionary = {}
	for key in SHARED_KEYS:
		if (cfg as Dictionary).has(key):
			clean[key] = (cfg as Dictionary)[key]
	return {"v": int(d.get("v", 1)), "seed": int(seed_v), "cfg": clean}


static func is_code(text: String) -> bool:
	return text.strip_edges().begins_with(PREFIX)


# --- Human-readable identity ----------------------------------------------

# Short seed rendering: "A3F2-91C7". Easier to read aloud or retype than a
# 10-digit integer, and it is what goes on the postcard.
static func seed_label(tank_seed: int) -> String:
	var u: int = tank_seed & 0xFFFFFFFF
	return "%04X-%04X" % [(u >> 16) & 0xFFFF, u & 0xFFFF]


# The provenance line burned into a postcard. Deliberately one line: it has
# to fit a caption strip without wrapping.
#
# `info` keys, all optional: tank_name, sim_day, fish, plants, seed.
static func caption(info: Dictionary) -> String:
	var parts: Array[String] = []
	var name: String = String(info.get("tank_name", "")).strip_edges()
	parts.append(name if not name.is_empty() else "walstad loom")
	var day: String = String(info.get("sim_day", "")).strip_edges()
	if not day.is_empty():
		parts.append(day)
	var counts: Array[String] = []
	var fish: int = int(info.get("fish", -1))
	if fish >= 0:
		counts.append("%d fish" % fish)
	var plants: int = int(info.get("plants", -1))
	if plants >= 0:
		counts.append("%d plants" % plants)
	if not counts.is_empty():
		parts.append(" · ".join(counts))
	if info.has("seed"):
		parts.append("seed %s" % seed_label(int(info["seed"])))
	return " · ".join(parts)


# --- Postcard --------------------------------------------------------------

const CAPTION_STRIP_H: int = 22
const CAPTION_BG: Color = Color(0.05, 0.04, 0.07, 0.82)

# Composite a caption strip along the bottom of `img` and return the result.
#
# Burned in, not metadata: every chat app and social platform strips PNG
# text chunks, so metadata would survive exactly zero shares. This is also
# why the strip is opaque rather than a subtle overlay — it has to stay
# readable after re-compression.
#
# Returns the image unchanged when it is too small to caption, rather than
# producing something illegible.
static func add_caption_strip(img: Image, text: String) -> Image:
	if img == null or text.strip_edges().is_empty():
		return img
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w < 64 or h < CAPTION_STRIP_H * 3:
		return img
	var out := Image.create(w, h, false, img.get_format())
	out.blit_rect(img, Rect2i(0, 0, w, h), Vector2i.ZERO)
	# Darken the strip so light text reads over any tank.
	var strip_top: int = h - CAPTION_STRIP_H
	for y in range(strip_top, h):
		for x in range(w):
			var src: Color = out.get_pixel(x, y)
			out.set_pixel(x, y, src.lerp(CAPTION_BG, CAPTION_BG.a))
	return out


# Where the caption text should be drawn, for a caller that has a font.
# Returned rather than hard-coded into the blit so the drawing stays with
# whoever owns the theme.
static func caption_rect(img: Image) -> Rect2i:
	if img == null:
		return Rect2i()
	var w: int = img.get_width()
	var h: int = img.get_height()
	return Rect2i(4, h - CAPTION_STRIP_H + 4, w - 8, CAPTION_STRIP_H - 6)


# Filename for a postcard, carrying the seed so a saved file is traceable
# even without opening it.
static func postcard_filename(tank_seed: int, unix_time: int) -> String:
	return "walstad-loom_%s_%d.png" % [seed_label(tank_seed), unix_time]
