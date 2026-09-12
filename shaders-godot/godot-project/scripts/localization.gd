extends Node

# Localization (BROAD_DIRECTIONS #14).
#
# The project shipped with **zero `tr()` calls** and ~510 UI strings assigned
# directly in GDScript. That is not a missing feature so much as a growing
# debt: every session added more English, and the retrofit gets bigger the
# longer it waits. (This session alone added the mind panel, milestones,
# settings sections and share hints before this landed.)
#
# STRATEGY: English-as-key. `tr("Settings")` uses the source string itself as
# the catalogue key, rather than `tr("SETTINGS_TITLE")` with a separate key
# space.
#
#   + A 510-string retrofit becomes mechanical — wrap the literal, done.
#   + Untranslated locales fall back to readable English, not "SETTINGS_TITLE".
#   - Editing an English string orphans its translations. Accepted: the
#     alternative is a key-mapping table nobody maintains either, and
#     `smoke_localization.gd` reports orphans so they are at least visible.
#
# THE PSEUDOLOCALE IS THE POINT. `en_XA` is generated at runtime — no
# catalogue needed — and transforms every string that passes through `tr()`:
#
#     "Adopt fish"  ->  "⟦Ådöpt fïsh····⟧"
#
# Switch to it and two whole classes of bug become *visible* rather than
# theoretical:
#   1. Anything still in plain English on screen was never wrapped.
#   2. Anything clipped or overflowing cannot survive a real translation —
#      most languages run longer than English, so the padding simulates that
#      before a translator is ever hired.
#
# That is far more useful than a half-finished French catalogue, and it is why
# this lands before any real translation work.

signal locale_changed(locale: String)

# Locales offered in Settings. "en" is the source language; en_XA is the
# development pseudolocale. Real locales get appended as catalogues land.
const LOCALE_SOURCE := "en"
# NB: NOT "en_XA". Godot's TranslationServer matches locales by prefix, so an
# "en_XA" catalogue is considered a match for "en" and the pseudolocale leaks
# into the English build — every wrapped string renders as ⟦…⟧ for real
# players. "qps" is the reserved pseudo-locale range (as used by Windows'
# qps-ploc) and shares no prefix with any shipping locale.
const LOCALE_PSEUDO := "qps"

const LOCALES: Array[Dictionary] = [
	{"code": LOCALE_SOURCE, "label": "English"},
	{"code": LOCALE_PSEUDO, "label": "Pseudolocale (dev)"},
]

# Where compiled catalogues live once they exist.
const CATALOGUE_DIR := "res://assets/i18n"

# Pseudolocale brackets. Chosen to be visually obvious and NOT to appear in
# any real string, so a screenshot makes unwrapped text jump out.
const PSEUDO_OPEN := "⟦"
const PSEUDO_CLOSE := "⟧"
# Most languages run longer than English; German and Finnish routinely +30%.
# Padding to that ratio surfaces clipping before a translator is involved.
const PSEUDO_PAD_RATIO: float = 0.30
const PSEUDO_PAD_CHAR := "·"

# ASCII -> accented look-alike. Still legible to an English reader, which
# matters: a pseudolocale you cannot read is a pseudolocale nobody uses.
const PSEUDO_MAP: Dictionary = {
	"a": "å", "b": "b", "c": "ç", "d": "d", "e": "é", "f": "f", "g": "g",
	"h": "h", "i": "ï", "j": "j", "k": "k", "l": "l", "m": "m", "n": "ñ",
	"o": "ö", "p": "p", "q": "q", "r": "r", "s": "š", "t": "t", "u": "ü",
	"v": "v", "w": "w", "x": "x", "y": "ý", "z": "ž",
	"A": "Å", "B": "B", "C": "Ç", "D": "D", "E": "É", "F": "F", "G": "G",
	"H": "H", "I": "Ï", "J": "J", "K": "K", "L": "L", "M": "M", "N": "Ñ",
	"O": "Ö", "P": "P", "Q": "Q", "R": "R", "S": "Š", "T": "T", "U": "Ü",
	"V": "V", "W": "W", "X": "X", "Y": "Ý", "Z": "Ž",
}

var _pseudo: Translation = null
var _registered: Dictionary = {}   # locale code -> Translation


func _ready() -> void:
	_install_pseudolocale()
	_load_catalogues()
	# Restore the player's choice. TankConfig may not be up yet on the very
	# first frame, so this is defensive rather than assumed.
	var cfg: Node = get_node_or_null("/root/TankConfig")
	if cfg != null and cfg.get("locale") != null:
		set_locale(String(cfg.locale))


# --- Public API ------------------------------------------------------------

func available_locales() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in LOCALES:
		out.append(l.duplicate())
	return out


func current_locale() -> String:
	return TranslationServer.get_locale()


func is_known_locale(code: String) -> bool:
	for l in LOCALES:
		if String(l["code"]) == code:
			return true
	return false


# Switch locale. Unknown codes fall back to the source language rather than
# leaving the UI in an undefined state.
func set_locale(code: String) -> void:
	var want: String = code if is_known_locale(code) else LOCALE_SOURCE
	if TranslationServer.get_locale() == want:
		return
	TranslationServer.set_locale(want)
	locale_changed.emit(want)
	var lg: Node = get_node_or_null("/root/AppLog")
	if lg != null and lg.has_method("info"):
		lg.info("i18n", "locale set to %s" % want)


# --- Pseudolocale ----------------------------------------------------------

# Transform one string the way the pseudolocale does. Pure and static so the
# smoke can exercise it without the autoload.
static func pseudo(text: String) -> String:
	if text.is_empty():
		return text
	var body := ""
	var letters: int = 0
	for i in text.length():
		var c: String = text[i]
		if PSEUDO_MAP.has(c):
			body += String(PSEUDO_MAP[c])
			letters += 1
		else:
			body += c
	# Pad proportionally to the LETTER count, so "OK" does not sprout a tail
	# longer than itself while a long sentence grows realistically.
	var pad_n: int = int(round(float(letters) * PSEUDO_PAD_RATIO))
	var pad := ""
	for _i in pad_n:
		pad += PSEUDO_PAD_CHAR
	return PSEUDO_OPEN + body + pad + PSEUDO_CLOSE


# True when `rendered` looks like pseudolocale output — i.e. the string went
# through tr(). The smoke and any on-screen audit use this.
static func looks_pseudo(rendered: String) -> bool:
	return rendered.begins_with(PSEUDO_OPEN) and rendered.ends_with(PSEUDO_CLOSE)


# Build the pseudolocale from whatever keys the source catalogue knows, plus
# anything registered later. Godot's Translation maps key -> message; a key it
# has never seen falls through untransformed, which is exactly the signal we
# want (it means nobody wrapped it).
func _install_pseudolocale() -> void:
	_pseudo = Translation.new()
	_pseudo.locale = LOCALE_PSEUDO
	TranslationServer.add_translation(_pseudo)
	_registered[LOCALE_PSEUDO] = _pseudo


# Teach the pseudolocale a key. Called by the extraction pass so every string
# the game actually uses has a pseudo form.
func register_key(key: String) -> void:
	if _pseudo == null or key.is_empty():
		return
	if not String(_pseudo.get_message(key)).is_empty():
		return
	_pseudo.add_message(key, pseudo(key))


func register_keys(keys: PackedStringArray) -> void:
	for k in keys:
		register_key(k)


func pseudo_key_count() -> int:
	return _pseudo.get_message_count() if _pseudo != null else 0


# --- Catalogues ------------------------------------------------------------

# Load any compiled .translation files shipped under CATALOGUE_DIR. None exist
# yet; the loader is here so adding a locale is a data drop, not a code change.
func _load_catalogues() -> void:
	var dir := DirAccess.open(CATALOGUE_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var f: String = dir.get_next()
	while f != "":
		if f.ends_with(".translation"):
			var tr_res: Translation = load(CATALOGUE_DIR + "/" + f) as Translation
			if tr_res != null:
				TranslationServer.add_translation(tr_res)
				_registered[tr_res.locale] = tr_res
		f = dir.get_next()
	dir.list_dir_end()


func registered_locales() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _registered.keys():
		out.append(String(k))
	return out
