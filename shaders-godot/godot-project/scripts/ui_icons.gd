# HUD marks. Buttons show one basic emoji; the tooltip carries the name.
# The font is the system emoji face, with a symbol fallback, so iPad is not
# stuck with IBM Plex's empty boxes.
class_name UiIcons
extends RefCounted

const MARKS: Dictionary = {
	"menu": "🏠",
	"immersive": "👁️",
	"create": "➕",
	"world": "🐠",
	"appearance": "☀️",
	"system": "⚙️",
	"alerts": "🔔",
	"help": "❓",
	"portal": "🔍",
	"aquascape": "🪨",
	"creator": "✨",
	"adopt": "🐠",
	"library": "📚",
	"notifications": "🔔",
	"render": "🎨",
	"sound": "🔊",
	"settings": "⚙️",
	"light": "💡",
	"pause": "⏸️",
	"play": "▶️",
	"photo": "📷",
	"undo": "↩️",
	"camera": "🎥",
	"residents": "🐟",
	"block": "🧱",
	"eraser": "❌",
	"line": "✏️",
	"object": "🌿",
	"paste": "📋",
	"up": "⬆️",
	"down": "⬇️",
}

const MARK_TIPS: Dictionary = {
	"pause": "Pause or resume the tank (P)",
	"play": "Resume the tank (P)",
	"photo": "Photo mode — frame a shot",
	"undo": "Undo the last change",
	"camera": "Camera views",
	"residents": "Residents — follow and favorite creatures",
	"block": "Place a block",
	"eraser": "Erase",
	"line": "Draw a line",
	"object": "Place an object",
	"paste": "Paste",
	"up": "Raise the build plane",
	"down": "Lower the build plane",
}

static var _mark_font: Font

const RAIL: Dictionary = {
	"portal": {"emoji": "◉", "text": "◉", "tip": "Follow portal (creature PiP)"},
	"aquascape": {"emoji": "▣", "text": "▣", "tip": "Aquascape — sculpt substrate & hardscape"},
	"creator": {"emoji": "✦", "text": "✦", "tip": "Creature creator"},
	"adopt": {"emoji": "◇", "text": "◇", "tip": "Adopt fish (free)"},
	"library": {"emoji": "☰", "text": "☰", "tip": "Species library"},
	"notifications": {"emoji": "◔", "text": "◔", "tip": "Notification center"},
	"render": {"emoji": "▦", "text": "▦", "tip": "Rendering panel"},
	"sound": {"emoji": "♪", "text": "♪", "tip": "Sound studio"},
	"settings": {"emoji": "⚙", "text": "⚙", "tip": "Settings"},
	"menu": {"emoji": "≡", "text": "≡", "tip": "Save and return to tank menu"},
	"immersive": {"emoji": "⛶", "text": "⛶", "tip": "Focus mode — hide menus"},
	"light": {"emoji": "☼", "text": "☼", "tip": "Light settings — tank lights, intensity, warmth, caustics"},
	"create": {"emoji": "✦", "text": "✦", "tip": "Create — creature designer, fish adoption, life library"},
	"world": {"emoji": "▣", "text": "▣", "tip": "World — aquascape sculpting and follow portal"},
	"appearance": {"emoji": "▦", "text": "▦", "tip": "Look & feel — lighting, rendering, sound"},
	"system": {"emoji": "⚙", "text": "⚙", "tip": "System — tank settings and stocking"},
	"alerts": {"emoji": "⚠", "text": "⚠", "tip": "Alerts — notifications and discoveries"},
	"help": {"emoji": "?", "text": "?", "tip": "Help — controls, glossary, tank tells"},
}

const CHIPS: Dictionary = {
	"state": {"emoji": "◷", "text": "◷"},
	"mood": {"emoji": "♥", "text": "♥"},
	"fish": {"emoji": "◇", "text": "◇"},
	"shrimp": {"emoji": "›", "text": "›"},
	"snails": {"emoji": "◎", "text": "◎"},
	"flora": {"emoji": "⁂", "text": "⁂"},
	"water": {"emoji": "≈", "text": "≈"},
	"morphs": {"emoji": "✦", "text": "✦"},
	"alert": {"emoji": "⚠", "text": "⚠"},
}

const MOBILE_HUD: Dictionary = {
	"pause": {"emoji": "❚❚", "text": "❚❚"},
	"play": {"emoji": "▶", "text": "▶"},
	"photo": {"emoji": "▣", "text": "▣"},
	"undo": {"emoji": "↩", "text": "↩"},
}

const FAUNA: Dictionary = {
	"fish": {"emoji": "◇", "text": "fish"},
	"shrimp": {"emoji": "›", "text": "shrimp"},
	"snail": {"emoji": "◎", "text": "snail"},
	"plant": {"emoji": "⁂", "text": "plant"},
}

const MENU: Dictionary = {
	"duplicate": {"emoji": "⧉", "text": "Dup", "tip": "Duplicate tank"},
	"delete": {"emoji": "✕", "text": "Del", "tip": "Delete tank"},
	"edit": {"emoji": "✎", "text": "Ed", "tip": "Rename tank"},
	"more": {"emoji": "⋯", "text": "...", "tip": "More actions"},
}

# Player food picker (footer dock). Buttons always show a readable name; glyph
# is a prefix on desktop only (never icon-only — too tiny in the footer bar).
const FEED: Dictionary = {
	"dock": {
		"emoji": "",
		"text": "Feed",
		"name": "Feed",
		"tip": "Pick a food, then click or tap the water to drop it",
	},
	"flake": {
		"emoji": "✧",
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

# Keeper Care dock (PLAYER_WISH #1) — same footer language as Feed.
const CARE: Dictionary = {
	"dock": {
		"emoji": "",
		"text": "Care",
		"name": "Care",
		"tip": "Keep the tank — change water or rinse the filter",
	},
	"water": {
		"emoji": "≈",
		"text": "H₂O",
		"name": "Water",
		"tip": "Partial water change — dilutes nitrate, refreshes minerals",
	},
	"filter": {
		"emoji": "◎",
		"text": "Fil",
		"name": "Filter",
		"tip": "Rinse the filter — restores flow (keeps most of the good bacteria)",
	},
}


static func use_color_emoji() -> bool:
	# Always monochrome geometric — emoji font gaps caused the mobile ASCII
	# fallback split that made the rail look like two products (#179).
	return false


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


static func mark_font() -> Font:
	if _mark_font != null:
		return _mark_font
	var emoji := SystemFont.new()
	emoji.font_names = PackedStringArray([
		"Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji",
	])
	var symbols := SystemFont.new()
	symbols.font_names = PackedStringArray([
		"Apple Symbols", "Segoe UI Symbol", "Noto Sans Symbols 2", "DejaVu Sans",
	])
	var chain: Array[Font] = [symbols, PanelTheme.FONT_SANS]
	emoji.fallbacks = chain
	_mark_font = emoji
	return _mark_font


static func mark_text(id: String) -> String:
	return String(MARKS.get(id, ""))


static func apply_mark(btn: Button, id: String) -> void:
	if btn == null:
		return
	var mark := mark_text(id)
	if mark == "":
		return
	btn.icon = null
	btn.text = mark
	btn.clip_text = false
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var edge: float = maxf(btn.custom_minimum_size.x, btn.custom_minimum_size.y)
	if edge < 36.0:
		edge = 44.0
	btn.custom_minimum_size = Vector2(edge, edge)
	PanelTheme.apply_font(btn, mark_font(), int(round(edge * 0.46)))
	var fg := Color(0.96, 0.97, 0.99)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_color_override("font_focus_color", Color.WHITE)
	if MARK_TIPS.has(id) and btn.tooltip_text.strip_edges() == "":
		btn.tooltip_text = String(MARK_TIPS[id])


static func apply_rail_button(btn: Button, id: String, force_short: bool = false) -> void:
	if btn == null:
		return
	btn.tooltip_text = rail_tooltip(id)
	if mark_text(id) != "":
		apply_mark(btn, id)
	else:
		btn.icon = null
		btn.text = rail_label(id, force_short)


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


static func feed_button_label(id: String, _force_short: bool = false) -> String:
	var e: Dictionary = FEED.get(id, {})
	return String(e.get("name", e.get("text", id)))


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


static func care_button_label(id: String, _force_short: bool = false) -> String:
	var e: Dictionary = CARE.get(id, {})
	return String(e.get("name", e.get("text", id)))


static func care_tooltip(id: String) -> String:
	var e: Dictionary = CARE.get(id, {})
	return String(e.get("tip", id))


static func apply_care_button(btn: Button, id: String, active: bool = false,
		force_short: bool = false) -> void:
	if btn == null:
		return
	btn.text = care_button_label(id, force_short)
	btn.tooltip_text = care_tooltip(id)
	PanelTheme.style_hud_toggle_button(btn, active)
	PanelTheme.apply_font(btn, PanelTheme.FONT_SANS, PanelTheme.SIZE_SMALL)
	btn.add_theme_constant_override("outline_size", 0)
