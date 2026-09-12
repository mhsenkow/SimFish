extends SceneTree

# Localization contract (BROAD_DIRECTIONS #14).
#
# The project had zero `tr()` calls and ~510 UI strings hardcoded in English.
# The retrofit is partial by nature, so the load-bearing assertion here is a
# **coverage ratchet**: the count of still-unwrapped player-facing literals
# may fall, never rise. Without it, every future feature quietly adds English
# and the debt grows exactly the way it grew to 510 in the first place.

const LocalizationScript = preload("res://scripts/localization.gd")

# Player-facing literals not yet wrapped in tr(). MUST NOT INCREASE.
# Lower it whenever you wrap more; the test tells you the new number.
#
# NB: this was 305 while the counter flagged any `.text = "` line, including
# `"\n".join(...)` separators and format fragments. With the prose check the
# real figure is 105 — i.e. coverage was ~67%, not the ~40% first reported.
const UNWRAPPED_BUDGET: int = 105

# Wrapped keys currently extracted. A floor, so wrapping cannot be undone.
const MIN_WRAPPED_KEYS: int = 195


func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_localization")

	# --- Pseudolocale transform ---
	var p: String = LocalizationScript.pseudo("Adopt fish")
	t.check(LocalizationScript.looks_pseudo(p),
		"pseudo() output must be recognisable as pseudolocale: %s" % p)
	t.check(p.contains("Å") and p.contains("ï"),
		"pseudo() must accent ASCII letters: %s" % p)
	t.check(p.length() > "Adopt fish".length(),
		"pseudo() must pad — the point is to surface clipping: %s" % p)
	# Still readable: a pseudolocale nobody can read is a pseudolocale nobody
	# uses. Non-letters must survive untouched.
	var punct: String = LocalizationScript.pseudo("Feed (F) — 3 items, 50%")
	for ch in ["(", ")", "—", "3", "5", "0", "%", ","]:
		t.check(punct.contains(ch),
			"pseudo() must preserve '%s': %s" % [ch, punct])

	# Padding scales with LETTERS, so short labels do not sprout absurd tails.
	var ok_p: String = LocalizationScript.pseudo("OK")
	t.check(ok_p.length() <= 6,
		"a 2-letter label must not balloon: %s (%d chars)" % [ok_p, ok_p.length()])
	# Empty in, empty out — never bracket nothing.
	t.equals(LocalizationScript.pseudo(""), "", "pseudo('') stays empty")
	t.check(not LocalizationScript.looks_pseudo("Adopt fish"),
		"plain English must NOT look pseudo — that is the detection signal")

	# Deterministic: the same string always renders the same way, or
	# screenshots are not comparable between runs.
	t.equals(LocalizationScript.pseudo("Settings"),
		LocalizationScript.pseudo("Settings"), "pseudo() is deterministic")

	# --- THE LEAK TEST ---
	# Godot's TranslationServer matches locales by PREFIX. The pseudolocale
	# was originally "en_XA", which Godot treats as a match for "en" — so
	# every wrapped string rendered as ⟦…⟧ for real English players. Caught by
	# running the thing rather than trusting it.
	t.check(not LocalizationScript.LOCALE_PSEUDO.begins_with(
			LocalizationScript.LOCALE_SOURCE),
		"pseudolocale '%s' prefix-matches the source locale '%s' — it will "
			% [LocalizationScript.LOCALE_PSEUDO, LocalizationScript.LOCALE_SOURCE]
		+ "leak into the shipping build")
	for l in LocalizationScript.LOCALES:
		var code: String = String(l["code"])
		if code == LocalizationScript.LOCALE_PSEUDO:
			continue
		t.check(not LocalizationScript.LOCALE_PSEUDO.begins_with(code)
				and not code.begins_with(LocalizationScript.LOCALE_PSEUDO),
			"pseudolocale must share no prefix with shipping locale '%s'" % code)

	# End-to-end: a live TranslationServer must keep them apart.
	var svc: Node = LocalizationScript.new()
	svc.name = "LocalizationTest"
	root.add_child(svc)
	await process_frame
	svc.register_key("Adopt fish")
	svc.set_locale(LocalizationScript.LOCALE_SOURCE)
	t.equals(tr("Adopt fish"), "Adopt fish",
		"English must render plainly — a pseudolocale leak here ships to players")
	svc.set_locale(LocalizationScript.LOCALE_PSEUDO)
	t.check(LocalizationScript.looks_pseudo(tr("Adopt fish")),
		"the pseudolocale must actually transform, got: %s" % tr("Adopt fish"))
	svc.set_locale(LocalizationScript.LOCALE_SOURCE)
	t.equals(tr("Adopt fish"), "Adopt fish", "switching back must restore English")
	# An unknown locale must fall back, not leave the UI undefined.
	svc.set_locale("not-a-locale")
	t.equals(svc.current_locale(), LocalizationScript.LOCALE_SOURCE,
		"an unknown locale must fall back to the source language")
	svc.free()

	# --- Locale registry ---
	t.check(LocalizationScript.LOCALES.size() >= 2,
		"at least the source locale and the pseudolocale must be offered")
	var codes: Array[String] = []
	for l in LocalizationScript.LOCALES:
		var code: String = String(l["code"])
		t.check(not code.is_empty(), "every locale needs a code")
		t.check(not String(l["label"]).is_empty(),
			"locale %s needs a display label" % code)
		t.check(not codes.has(code), "duplicate locale code %s" % code)
		codes.append(code)
	t.check(codes.has(LocalizationScript.LOCALE_SOURCE),
		"the source locale must be offered")
	t.check(codes.has(LocalizationScript.LOCALE_PSEUDO),
		"the pseudolocale must be offered — it is the extraction tool")

	# --- The locale knob is curated and persisted ---
	t.check(ConfigCuration.is_curated("locale"),
		"locale must be triaged in ConfigCuration")
	t.check(ConfigCuration.is_setting("locale"),
		"locale must be a real setting, not persisted state")
	var cfg_src: String = FileAccess.get_file_as_string("res://scripts/tank_config.gd")
	t.check(cfg_src.contains('cfg.set_value("ui", "locale"'),
		"locale must be WRITTEN to disk — it was reachable from Settings but "
			+ "not persisted, so it reset on every restart")
	t.check(cfg_src.contains('cfg.get_value("ui", "locale"'),
		"locale must be READ back from disk")
	t.check(cfg_src.contains('cfg.set_value("ui", "settings_mode"'),
		"settings_mode must be persisted too (same bug)")

	# --- Coverage ratchet ---
	var wrapped: int = _count_wrapped()
	var unwrapped: int = _count_unwrapped()
	print("[i18n] wrapped=%d unwrapped=%d (budget %d)"
		% [wrapped, unwrapped, UNWRAPPED_BUDGET])

	t.check(wrapped >= MIN_WRAPPED_KEYS,
		"wrapped key count fell to %d, below the floor of %d — strings were "
			% [wrapped, MIN_WRAPPED_KEYS] + "un-wrapped")
	t.check(unwrapped <= UNWRAPPED_BUDGET,
		"unwrapped player-facing literals rose to %d (budget %d). New UI text "
			% [unwrapped, UNWRAPPED_BUDGET]
		+ "must go through tr(); see docs/CHEMISTRY_ORACLE.md's sibling, "
		+ "assets/i18n/README.md")
	# Ratchet down: if coverage improved, the budget is stale.
	t.check(unwrapped >= UNWRAPPED_BUDGET - 25,
		"unwrapped dropped to %d, well under the %d budget — lower "
			% [unwrapped, UNWRAPPED_BUDGET]
		+ "UNWRAPPED_BUDGET in this file so the ratchet keeps biting")

	quit(t.finish())


func _count_wrapped() -> int:
	var n: int = 0
	for path in _scripts():
		var src: String = FileAccess.get_file_as_string(path)
		n += src.count('tr("')
	return n


# Player-facing literal assignments that never went through tr().
#
# The literal must contain actual PROSE. An early version counted any line
# with `.text = "` and flagged `_desc.text = "\n".join(lines)` — the literal
# there is a separator, not text a player reads. Requiring two consecutive
# letters is the same rule the wrapping pass used, so the gate and the
# wrapper agree on what counts.
func _count_unwrapped() -> int:
	var n: int = 0
	for path in _scripts():
		var src: String = FileAccess.get_file_as_string(path)
		for line in src.split("\n"):
			if line.contains("tr(") or line.strip_edges().begins_with("#"):
				continue
			for marker in ['.text = "', '.tooltip_text = "']:
				var at: int = line.find(marker)
				if at < 0:
					continue
				if _has_prose(line.substr(at + marker.length())):
					n += 1
				break
	return n


# Does the remainder of the line, up to its closing quote, read as prose?
func _has_prose(rest: String) -> bool:
	var lit := ""
	var i: int = 0
	while i < rest.length():
		var c: String = rest[i]
		if c == "\\":
			i += 2
			continue
		if c == '"':
			break
		lit += c
		i += 1
	var run: int = 0
	for c in lit:
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z"):
			run += 1
			if run >= 2:
				return true
		else:
			run = 0
	return false


func _scripts() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open("res://scripts")
	if dir == null:
		return out
	dir.list_dir_begin()
	var f: String = dir.get_next()
	while f != "":
		if f.ends_with(".gd") and not f.begins_with("smoke_"):
			out.append("res://scripts/" + f)
		f = dir.get_next()
	dir.list_dir_end()
	return out
