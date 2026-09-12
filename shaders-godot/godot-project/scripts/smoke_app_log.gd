extends SceneTree

# Application log (BROAD_DIRECTIONS #5).
#
# The log's whole job is to still be there when something has gone wrong, so
# these assertions are mostly about it being unbreakable: bounded memory,
# bounded disk, no throw on a bad call, and a report that actually carries
# the build identity a bug report needs.

const AppLogScript = preload("res://scripts/app_log.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	var lg: Node = AppLogScript.new()
	lg.name = "AppLogTest"
	root.add_child(lg)
	await process_frame

	# --- Session header carries the facts a report needs ---
	var header: String = lg.session_header_line()
	for want in [OS.get_name(), "walstad loom"]:
		TestSupport.check(failed, header.contains(want),
			"session header must name '%s': %s" % [want, header])
	TestSupport.check(failed, not lg.build_version().is_empty(),
		"build_version must never be empty")
	TestSupport.check(failed, lg.build_version() != "dev",
		"application/config/version must be set in project.godot, got 'dev'")

	# --- Levels are recorded and counted ---
	lg.min_level = AppLogScript.Level.DEBUG
	var base_counts: Dictionary = lg.level_counts()
	lg.debug("test", "a debug line")
	lg.info("test", "an info line")
	var counts: Dictionary = lg.level_counts()
	TestSupport.check(failed, int(counts.get("DEBUG", 0)) > int(base_counts.get("DEBUG", 0)),
		"debug() must be counted")
	TestSupport.check(failed, int(counts.get("INFO", 0)) > int(base_counts.get("INFO", 0)),
		"info() must be counted")

	# --- min_level actually drops calls ---
	lg.min_level = AppLogScript.Level.WARN
	var before: int = int(lg.level_counts().get("INFO", 0))
	lg.info("test", "should be dropped")
	TestSupport.check(failed, int(lg.level_counts().get("INFO", 0)) == before,
		"info() below min_level must be dropped, not recorded")
	lg.min_level = AppLogScript.Level.INFO

	# --- Entries land in the ring, newest last ---
	lg.info("ringtest", "marker-alpha")
	lg.info("ringtest", "marker-omega")
	var recent: Array[Dictionary] = lg.recent(10)
	TestSupport.check(failed, recent.size() >= 2, "recent() must return the latest entries")
	if recent.size() >= 2:
		TestSupport.check(failed, String(recent[recent.size() - 1].get("msg", "")) == "marker-omega",
			"recent() must be oldest-first (newest last)")

	# --- The ring is BOUNDED: a runaway loop must not grow memory ---
	var overflow: int = AppLogScript.RING_SIZE + 120
	for i in overflow:
		lg.info("flood", "entry %d" % i)
	var after_flood: Array[Dictionary] = lg.recent(AppLogScript.RING_SIZE * 3)
	TestSupport.check(failed, after_flood.size() <= AppLogScript.RING_SIZE,
		"ring must cap at RING_SIZE (%d), got %d"
			% [AppLogScript.RING_SIZE, after_flood.size()])
	# The oldest entries must have been evicted, not the newest.
	var last_msg: String = ""
	if not after_flood.is_empty():
		last_msg = String(after_flood[after_flood.size() - 1].get("msg", ""))
	TestSupport.check(failed, last_msg == "entry %d" % (overflow - 1),
		"the newest entry must survive eviction, got '%s'" % last_msg)
	var flood_has_alpha: bool = false
	for e in after_flood:
		if String(e.get("msg", "")) == "marker-alpha":
			flood_has_alpha = true
	TestSupport.check(failed, not flood_has_alpha,
		"entries older than the ring must be evicted")

	# --- recent(limit) respects its limit ---
	TestSupport.check(failed, lg.recent(5).size() <= 5, "recent(5) must return at most 5")
	TestSupport.check(failed, lg.recent(0).is_empty(), "recent(0) must return nothing")

	# --- warn()/error() must not throw, and must be recorded ---
	# They also fan out to push_warning/push_error, so the engine noise below
	# is expected.
	var err_before: int = int(lg.level_counts().get("ERROR", 0))
	lg.error("test", "deliberate test error — expected in smoke output")
	TestSupport.check(failed, int(lg.level_counts().get("ERROR", 0)) == err_before + 1,
		"error() must be recorded")

	# --- Odd input must not break anything ---
	lg.info("", "")
	lg.info("tag with spaces", "msg with % percent and 'quotes'")
	lg.info("unicode", "ammonia ↑ O₂ ↓ — em-dash")
	TestSupport.check(failed, true, "odd log input must not throw")

	# --- Report is paste-ready and self-describing ---
	# This is what a player hands us in a bug report.
	var report: String = lg.export_report(50)
	for want in ["=== walstad loom diagnostics ===", "save format", "entries:", "--- log"]:
		TestSupport.check(failed, report.contains(want),
			"report must contain '%s'" % want)
	TestSupport.check(failed, report.contains(str(SaveMigrations.CURRENT_VERSION)),
		"report must state the save format version")

	# --- Tank context appears in the report ---
	lg.set_context({"tank_slot": 7, "preset": "community"})
	var ctx_report: String = lg.export_report(5)
	TestSupport.check(failed, ctx_report.contains("--- tank ---"),
		"report must include a tank section once context is set")
	TestSupport.check(failed, ctx_report.contains("tank_slot: 7"),
		"report must include the tank slot")
	TestSupport.check(failed, ctx_report.contains("preset: community"),
		"report must include the preset")
	# set_context must copy, not alias — a later caller mutation must not
	# retroactively rewrite what the log believes.
	var live_ctx: Dictionary = {"tank_slot": 1}
	lg.set_context(live_ctx)
	live_ctx["tank_slot"] = 999
	TestSupport.check(failed, not lg.export_report(1).contains("tank_slot: 999"),
		"set_context must copy its argument")

	# --- format_entry is stable and static ---
	var line: String = AppLogScript.format_entry(
		{"t": 1.5, "level": AppLogScript.Level.WARN, "tag": "x", "msg": "hello"})
	TestSupport.check(failed, line.contains("WARN") and line.contains("hello"),
		"format_entry must render level and message: %s" % line)
	# A malformed entry must not crash the formatter — it runs on the crash path.
	var junk_line: String = AppLogScript.format_entry({})
	TestSupport.check(failed, not junk_line.is_empty(),
		"format_entry must tolerate an empty entry")

	# --- The log file exists and is bounded ---
	lg.flush()
	TestSupport.check(failed, FileAccess.file_exists(AppLogScript.CURRENT_LOG),
		"a session log file must be written at %s" % AppLogScript.CURRENT_LOG)
	var f := FileAccess.open(AppLogScript.CURRENT_LOG, FileAccess.READ)
	if f != null:
		var size: int = f.get_length()
		f.close()
		TestSupport.check(failed, size > 0, "the session log must not be empty")
		# MAX_BYTES plus the one truncation notice line.
		TestSupport.check(failed, size <= AppLogScript.MAX_BYTES + 4096,
			"the session log must respect MAX_BYTES (%d), got %d"
				% [AppLogScript.MAX_BYTES, size])
	else:
		TestSupport.check(failed, false, "the session log must be readable")

	quit(TestSupport.report("smoke_app_log", failed))
