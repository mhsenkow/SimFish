# Cross-platform HUD glyphs. Android often ships without color emoji fonts, so
# rail buttons and stat chips fall back to short ASCII labels on mobile.
class_name UiIcons
extends RefCounted

const RAIL: Dictionary = {
	"portal": {"emoji": "👁", "text": "Pi", "tip": "Follow portal (creature PiP)"},
	"aquascape": {"emoji": "🪨", "text": "Sc", "tip": "Aquascape — sculpt substrate & hardscape"},
	"creator": {"emoji": "✦", "text": "Cr", "tip": "Creature creator"},
	"store": {"emoji": "🐟", "text": "St", "tip": "Fish store"},
	"library": {"emoji": "📚", "text": "Lb", "tip": "Species library"},
	"notifications": {"emoji": "🔔", "text": "Nt", "tip": "Notification center"},
	"render": {"emoji": "▦", "text": "Rd", "tip": "Rendering panel"},
	"sound": {"emoji": "♪", "text": "Sn", "tip": "Sound studio"},
	"settings": {"emoji": "⚙", "text": "Gt", "tip": "Settings"},
	"menu": {"emoji": "≡", "text": "Mn", "tip": "Save and return to tank menu"},
	"immersive": {"emoji": "⛶", "text": "Fs", "tip": "Focus mode — hide menus"},
	"light": {"emoji": "💡", "text": "Lt", "tip": "Light settings — tank lights, intensity, warmth, caustics"},
	"create": {"emoji": "✦", "text": "Mk", "tip": "Create — creature designer, fish store, life library"},
	"world": {"emoji": "🪨", "text": "Wr", "tip": "World — aquascape sculpting and follow portal"},
	"appearance": {"emoji": "▦", "text": "Lk", "tip": "Look & feel — lighting, rendering, sound"},
	"system": {"emoji": "⚙", "text": "Sy", "tip": "System — tank settings and stocking"},
	"alerts": {"emoji": "🔔", "text": "Al", "tip": "Alerts — notifications and discoveries"},
	"help": {"emoji": "❓", "text": "?", "tip": "Help — controls, glossary, tank tells"},
}

const CHIPS: Dictionary = {
	"state": {"emoji": "◴", "text": "T"},
	"mood": {"emoji": "♥", "text": "M"},
	"fish": {"emoji": "🐟", "text": "F"},
	"shrimp": {"emoji": "🦐", "text": "S"},
	"snails": {"emoji": "🐌", "text": "N"},
	"flora": {"emoji": "🌿", "text": "P"},
	"water": {"emoji": "💧", "text": "W"},
	"morphs": {"emoji": "✦", "text": "*"},
	"alert": {"emoji": "⚠", "text": "!"},
}

const MOBILE_HUD: Dictionary = {
	"pause": {"emoji": "⏸", "text": "||"},
	"play": {"emoji": "▶", "text": ">"},
	"photo": {"emoji": "📷", "text": "Ph"},
	"undo": {"emoji": "↩", "text": "Un"},
}

const FAUNA: Dictionary = {
	"fish": {"emoji": "🐟", "text": "fish"},
	"shrimp": {"emoji": "🦐", "text": "shrimp"},
	"snail": {"emoji": "🐌", "text": "snail"},
	"plant": {"emoji": "🌿", "text": "plant"},
}

const MENU: Dictionary = {
	"duplicate": {"emoji": "⧉", "text": "Dup", "tip": "Duplicate tank"},
	"delete": {"emoji": "🗑", "text": "Del", "tip": "Delete tank"},
	"edit": {"emoji": "✎", "text": "Ed", "tip": "Rename tank"},
	"more": {"emoji": "⋯", "text": "...", "tip": "More actions"},
}

# Player food picker (footer dock). Buttons always show a readable name; emoji
# is a prefix on desktop only (never icon-only — too tiny in the footer bar).
const FEED: Dictionary = {
	"dock": {
		"emoji": "",
		"text": "Feed",
		"name": "Feed",
		"tip": "Pick a food, then click or tap the water to drop it",
	},
	"flake": {
		"emoji": "✨",
		"text": "Fl",
		"name": "Flakes",
		"tip": "Flakes — float on the surface. Top & mid feeders rush up.",
	},
	"pellet": {
		"emoji": "●",
		"text": "Pt",
		"name": "Pellets",
		"tip": "Pellets — sink to the bottom. Mid & bottom feeders.",
	},
	"worm": {
		"emoji": "〰",
		"text": "Wm",
		"name": "Worm",
		"tip": "Bloodworm — wriggles mid-water. Carnivores go wild.",
	},
	"wafer": {
		"emoji": "▢",
		"text": "Wf",
		"name": "Wafer",
		"tip": "Algae wafer — slow sink. Herbivores & grazers.",
	},
}

const FEED_SUBTYPE_KEYS: Array[String] = ["flake", "pellet", "worm", "wafer"]


static func use_color_emoji() -> bool:
	return not (OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("mobile"))


static func _pick(entry: Dictionary, force_short: bool = false) -> String:
	if entry.is_empty():
		return "?"
	if force_short or not use_color_emoji():
		return String(entry.get("text", "?"))
	return String(entry.get("emoji", entry.get("text", "?")))


static func rail_label(id: String, force_short: bool = false) -> String:
	return _pick(RAIL.get(id, {}), force_short)


static func rail_tooltip(id: String) -> String:
	var e: Dictionary = RAIL.get(id, {})
	return String(e.get("tip", id))


static func apply_rail_button(btn: Button, id: String, force_short: bool = false) -> void:
	if btn == null:
		return
	btn.text = rail_label(id, force_short)
	btn.tooltip_text = rail_tooltip(id)


static func chip_glyph(key: String) -> String:
	return _pick(CHIPS.get(key, {}))


static func mobile_hud_label(key: String) -> String:
	return _pick(MOBILE_HUD.get(key, {}))


static func fauna_label(kind: String) -> String:
	return _pick(FAUNA.get(kind, {}), true)


static func menu_label(id: String) -> String:
	return _pick(MENU.get(id, {}))


static func menu_tooltip(id: String) -> String:
	var e: Dictionary = MENU.get(id, {})
	return String(e.get("tip", id))


static func feed_subtype_key(subtype: int) -> String:
	return FEED_SUBTYPE_KEYS[clampi(subtype, 0, FEED_SUBTYPE_KEYS.size() - 1)]


static func feed_label(id: String, force_short: bool = false) -> String:
	var e: Dictionary = FEED.get(id, {})
	if force_short:
		return String(e.get("text", e.get("name", id)))
	return String(e.get("name", e.get("text", id)))


static func feed_button_label(id: String, force_short: bool = false) -> String:
	var e: Dictionary = FEED.get(id, {})
	var name: String = String(e.get("name", e.get("text", id)))
	if force_short:
		return String(e.get("text", name))
	if use_color_emoji():
		var em: String = String(e.get("emoji", ""))
		if em.strip_edges() != "":
			return "%s %s" % [em, name]
	return name


static func feed_tooltip(id: String) -> String:
	var e: Dictionary = FEED.get(id, {})
	return String(e.get("tip", id))


static func apply_feed_button(btn: Button, id: String, active: bool = false,
		force_short: bool = false) -> void:
	if btn == null:
		return
	btn.text = feed_button_label(id, force_short)
	btn.tooltip_text = feed_tooltip(id)
	PanelTheme.style_hud_toggle_button(btn, active)
	PanelTheme.apply_font(btn, PanelTheme.FONT_SANS, PanelTheme.SIZE_SMALL)
	btn.add_theme_constant_override("outline_size", 0)
