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
	"render": {"emoji": "▦", "text": "Rd", "tip": "Rendering panel"},
	"sound": {"emoji": "♪", "text": "Sn", "tip": "Sound studio"},
	"settings": {"emoji": "⚙", "text": "Gt", "tip": "Settings"},
	"menu": {"emoji": "≡", "text": "Mn", "tip": "Save and return to tank menu"},
	"immersive": {"emoji": "⛶", "text": "Fs", "tip": "Focus mode — hide menus"},
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
