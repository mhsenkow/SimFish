extends SceneTree

# WHY THIS EXISTS.
#
# project.godot's [autoload] block was silently missing two entries. A comment
# added above AppLog and Localization survived a Godot re-save, but the
# ConfigFile writer strips whitespace and folds the comment onto the following
# line, so what shipped was:
#
#   #AppLogfirst:everyotherautoloadmaywanttolog...AppLog="*res://scripts/app_log.gd"
#
# One commented-out line. Both autoloads were gone. Nothing failed to compile;
# the game just booted with no logger and no translations, and the first
# symptom was an index-out-of-bounds crash three panels away, in
# settings_panel._sync_locale_option(), because the Language dropdown was
# populated from a service that resolved to null.
#
# So: never put comments in [autoload], and assert the block by contract.

const CONFIG_PATH := "res://project.godot"

# Every autoload the game requires, in load order. Order matters: AppLog is
# first because every other autoload may want to log during _ready, and
# Localization is second so tr() resolves from the first frame.
const REQUIRED: Array[String] = [
	"AppLog",
	"Localization",
	"TankSaves",
	"TankConfig",
	"SpeciesLibrary",
	"SteamService",
	"AIDirector",
	"GuardianLlm",
	"MusicContext",
	"UiTicker",
	"GamepadInput",
]


func _init() -> void:
	var s := TestSupport.Suite.new("autoload_contract")

	var text: String = _read(CONFIG_PATH)
	s.check(not text.is_empty(), "project.godot readable")

	var block: PackedStringArray = _autoload_block(text)
	s.check(block.size() > 0, "[autoload] section found")

	# 1. No comments in the block at all. This is the bug class, not a style
	#    preference: a comment here can eat the assignment next to it.
	for line in block:
		var t: String = line.strip_edges()
		if t.is_empty():
			continue
		s.check(not t.begins_with("#"),
			"no comment lines in [autoload] (found: %s)" % t.left(60))

	# 2. Every required autoload is declared, with a loadable script.
	var found: Dictionary = _parse_assignments(block)
	for name in REQUIRED:
		if not s.check(found.has(name), "autoload declared: %s" % name):
			continue
		var path: String = String(found[name])
		s.check(path.begins_with("*"),
			"%s is a singleton (leading *), got %s" % [name, path])
		var res: String = path.trim_prefix("*")
		s.check(ResourceLoader.exists(res), "%s script exists: %s" % [name, res])
		# Deliberately NOT asserting can_instantiate() here. An autoload script
		# that references another autoload by name (music_context.gd ->
		# TankConfig) only compiles once that other script is in the resource
		# cache, which under --script depends on load order. Compilation is
		# dev/compile_check.gd's job; this smoke owns the [autoload] block.

	# 3. Load order: AppLog first, Localization second.
	var order: Array[String] = []
	for line in block:
		var t: String = line.strip_edges()
		var eq: int = t.find("=")
		if eq > 0 and not t.begins_with("#"):
			order.append(t.substr(0, eq).strip_edges())
	s.check(order.size() >= 2, "at least two autoloads")
	if order.size() >= 2:
		s.check(order[0] == "AppLog",
			"AppLog loads first, got %s" % order[0])
		s.check(order[1] == "Localization",
			"Localization loads second, got %s" % order[1])

	quit(s.finish())


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t: String = f.get_as_text()
	f.close()
	return t


# The lines between [autoload] and the next [section] header.
func _autoload_block(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var inside := false
	for line in text.split("\n"):
		var t: String = line.strip_edges()
		if t.begins_with("["):
			if inside:
				break
			inside = t == "[autoload]"
			continue
		if inside:
			out.append(line)
	return out


func _parse_assignments(block: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for line in block:
		var t: String = line.strip_edges()
		if t.is_empty() or t.begins_with("#"):
			continue
		var eq: int = t.find("=")
		if eq <= 0:
			continue
		out[t.substr(0, eq).strip_edges()] = \
			t.substr(eq + 1).strip_edges().trim_prefix('"').trim_suffix('"')
	return out
