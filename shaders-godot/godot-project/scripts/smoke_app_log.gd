extends SceneTree

# Application log (BROAD_DIRECTIONS #5).
#
# The log's whole job is to still be there when something has gone wrong, so
# these assertions are mostly about it being unbreakable: bounded memory,
# bounded disk, no throw on a bad call, and a report that actually carries
# the build identity a bug report needs.
#
# WHY THIS WRITES TO A PRIVATE DIRECTORY.
#
# user:// is one directory per PROJECT, not per process: every Godot run for
# "walstad loom" resolves it to the same path, whatever checkout it booted
# from. AppLog is an autoload, and autoloads DO register under `--script`, so
# each of the ~175 smokes opens a session on the shared
# user://logs/session.log at boot — and _open_session() both rotates the
# previous file to .1 and truncates a fresh one at the same name.
#
# Under scripts/run_smokes.sh, which runs 8 of them at once, this smoke used
# to write to that shared path and then re-open it BY NAME to assert on it. A
# sibling process booting in between swapped the file out, so the read landed
# on a newly-truncated file and "the session log must not be empty" failed.
# It passed as often as it did only because the window is narrow.
#
# So the instance under test gets a directory named after this process, which
# no other process can collide with, and every assertion reads back through
# lg.current_log() rather than the AppLogScript.CURRENT_LOG const. That makes
# the smoke independent instead of merely serialised, and — because the file
# is now stable while we look at it — lets us assert its CONTENTS, its
# rotation and its size cap for real, which the shared path never allowed.

const AppLogScript = preload("res://scripts/app_log.gd")


# A directory only this process can name. Same project, same user://, but
# concurrent smokes are separate processes with distinct pids.
static func _private_dir(suffix: String) -> String:
	return "user://logs_smoke_app_log_%d_%s" % [OS.get_process_id(), suffix]


static func _remove_dir(path: String) -> void:
	var d: DirAccess = DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name: String = d.get_next()
	while not name.is_empty():
		if not d.current_is_dir():
			DirAccess.remove_absolute(
				ProjectSettings.globalize_path("%s/%s" % [path, name]))
		name = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	var lg: Node = AppLogScript.new()
	lg.name = "AppLogTest"
	# Must be set BEFORE the node enters the tree: _ready() opens the session.
	var log_dir: String = _private_dir("main")
	lg.log_dir = log_dir
	root.add_child(lg)
	await process_frame
	TestSupport.check(failed, lg.current_log().begins_with(log_dir),
		"the instance under test must write to its own directory, got %s"
			% lg.current_log())

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

	# --- The log file exists, carries the session, and is bounded ---
	# Read through the instance's own path, never AppLogScript.CURRENT_LOG:
	# the const names a file every other Godot process also rotates.
	lg.info("filetest", "marker-on-disk")
	lg.flush()
	var log_path: String = lg.current_log()
	TestSupport.check(failed, FileAccess.file_exists(log_path),
		"a session log file must be written at %s" % log_path)
	var f := FileAccess.open(log_path, FileAccess.READ)
	if f != null:
		var size: int = f.get_length()
		f.seek(0)
		var text: String = f.get_as_text()
		f.close()
		TestSupport.check(failed, size > 0, "the session log must not be empty")
		# MAX_BYTES plus the one truncation notice line.
		TestSupport.check(failed, size <= AppLogScript.MAX_BYTES + 4096,
			"the session log must respect MAX_BYTES (%d), got %d"
				% [AppLogScript.MAX_BYTES, size])
		# Non-empty is not enough: a log missing its header is the one thing
		# that makes a bug report useless, so assert the header reached DISK
		# and not just the in-memory ring.
		TestSupport.check(failed, text.contains("session start"),
			"the session log must open with a session-start line")
		TestSupport.check(failed, text.contains("walstad loom"),
			"the session log header must name the build")
		TestSupport.check(failed, text.contains(lg.build_version()),
			"the session log header must carry the build version")
		TestSupport.check(failed, text.contains("marker-on-disk"),
			"entries logged before flush() must reach disk")
	else:
		TestSupport.check(failed, false, "the session log must be readable")

	# --- Rotation keeps exactly KEEP_SESSIONS old sessions ---
	# Only testable now that the directory is ours: on the shared path the
	# rotation under test is racing ~150 other processes doing the same thing.
	var rot_dir: String = _private_dir("rot")
	var sessions: int = AppLogScript.KEEP_SESSIONS + 2
	for i in sessions:
		var r: Node = AppLogScript.new()
		r.log_dir = rot_dir
		root.add_child(r)
		await process_frame
		r.info("rot", "rotation-marker-%d" % i)
		r.flush()
		root.remove_child(r)
		r.free()
	var rot_base: String = "%s/session.log" % rot_dir
	TestSupport.check(failed, not FileAccess.file_exists(
			"%s.%d" % [rot_base, AppLogScript.KEEP_SESSIONS + 1]),
		"rotation must cap at KEEP_SESSIONS (%d), found a .%d"
			% [AppLogScript.KEEP_SESSIONS, AppLogScript.KEEP_SESSIONS + 1])
	# Newest session is the live file; each .N is one session older.
	for i in AppLogScript.KEEP_SESSIONS + 1:
		var path: String = rot_base if i == 0 else "%s.%d" % [rot_base, i]
		var want: String = "rotation-marker-%d" % (sessions - 1 - i)
		TestSupport.check(failed, FileAccess.file_exists(path),
			"rotation must keep %s" % path)
		var rf := FileAccess.open(path, FileAccess.READ)
		if rf != null:
			var body: String = rf.get_as_text()
			rf.close()
			TestSupport.check(failed, body.contains(want),
				"%s must hold %s" % [path, want])
	# The oldest session must be GONE, not merely unreferenced.
	var dropped := FileAccess.open(
		"%s.%d" % [rot_base, AppLogScript.KEEP_SESSIONS], FileAccess.READ)
	if dropped != null:
		var tail: String = dropped.get_as_text()
		dropped.close()
		TestSupport.check(failed, not tail.contains("rotation-marker-0"),
			"the session beyond KEEP_SESSIONS must be discarded")

	# --- The byte cap actually stops the file growing ---
	# The old assertion only checked the log was under MAX_BYTES, which a 35 KB
	# file passes without ever exercising the cap. Write past it for real.
	var cap_dir: String = _private_dir("cap")
	var cap: Node = AppLogScript.new()
	cap.log_dir = cap_dir
	root.add_child(cap)
	await process_frame
	# Entries sized so one FLUSH_EVERY batch stays under the 4096 slack below,
	# otherwise the final batch overshoots the cap by more than we allow.
	var filler: String = "x".repeat(200)
	for i in 10000:
		cap.info("cap", filler)
	cap.flush()
	var cap_path: String = cap.current_log()
	var cf := FileAccess.open(cap_path, FileAccess.READ)
	if cf != null:
		var cap_size: int = cf.get_length()
		cf.seek(maxi(0, cap_size - 4096))
		var cap_tail: String = cf.get_as_text()
		cf.close()
		TestSupport.check(failed, cap_size >= AppLogScript.MAX_BYTES,
			"the cap test must actually reach MAX_BYTES (%d), got %d"
				% [AppLogScript.MAX_BYTES, cap_size])
		TestSupport.check(failed, cap_size <= AppLogScript.MAX_BYTES + 4096,
			"writing past the cap must stop the file growing, got %d" % cap_size)
		TestSupport.check(failed, cap_tail.contains("log size cap"),
			"a capped log must say so in the file, so it is not mistaken "
			+ "for one that simply stopped")
	else:
		TestSupport.check(failed, false, "the capped log must be readable")
	# Logging must survive the cap: memory keeps going when disk stops.
	var after_cap: int = int(cap.level_counts().get("INFO", 0))
	cap.info("cap", "still logging after the cap")
	TestSupport.check(failed,
		int(cap.level_counts().get("INFO", 0)) == after_cap + 1,
		"the log must keep recording in memory once the disk cap is hit")
	root.remove_child(cap)
	cap.free()

	# --- Leave no litter: these directories are per-process ---
	root.remove_child(lg)
	lg.free()
	for d in [log_dir, rot_dir, cap_dir]:
		_remove_dir(d)
	for d in [log_dir, rot_dir, cap_dir]:
		TestSupport.check(failed,
			not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(d)),
			"the smoke must clean up its private log dir %s" % d)

	quit(TestSupport.report("smoke_app_log", failed))
