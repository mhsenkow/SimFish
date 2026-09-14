extends Node

# Application log (BROAD_DIRECTIONS #5).
#
# THE GAP THIS FILLS: across ~136k lines of shipped (non-test) GDScript the
# project had 3 push_error, 32 push_warning and 0 printerr calls, no crash
# reporting, no on-disk log and no player-facing bug-report path. When a
# player said "my tank broke" there was nothing else to go on — and with
# saves carrying no version stamp (#4) the most likely breakage was also the
# most invisible.
#
# This is a diagnostic log, NOT telemetry: nothing leaves the machine. The
# player exports it themselves when they want to file a report.
#
# Three properties it has to have, in priority order:
#   1. **Never blocks** (ENGINEERING_CREED). Every call is cheap and cannot
#      throw. Disk writes are batched off the hot path. A broken log must
#      never break the game.
#   2. **Bounded.** A ring buffer in memory and a byte cap on disk, so a
#      thousand-hour tank cannot fill the player's drive.
#   3. **Self-describing.** A log with no build version, platform or renderer
#      is nearly useless, so every session writes a header.
#
# Usage:
#   AppLog.info("save", "restored slot %d" % slot)
#   AppLog.warn("guardian", "model load skipped: %s" % reason)
#   AppLog.error("save", "refusing future-format save (%d)" % v)
#
# error() and warn() also fan out to push_error/push_warning so editor and
# CI output are unchanged — this adds a record, it does not replace one.

signal entry_logged(entry: Dictionary)

enum Level { DEBUG, INFO, WARN, ERROR }

const LEVEL_NAMES: Array[String] = ["DEBUG", "INFO", "WARN", "ERROR"]

# Default destination. Every Godot process on a machine shares ONE user://
# directory, so these are a machine-wide singleton path, not a per-process one
# — see log_dir below before assuming otherwise.
const LOG_DIR := "user://logs"
const CURRENT_LOG := "user://logs/session.log"
# Sessions kept as session.log.1 ... session.log.N.
const KEEP_SESSIONS: int = 3
# Hard cap on one session's log. Past this, logging continues in memory but
# stops growing the file — a runaway warning loop must not fill the disk.
const MAX_BYTES: int = 2_097_152  # 2 MiB
# In-memory ring, which is what export_report() and the bug-report path read.
const RING_SIZE: int = 400
# Entries are appended to disk in batches this large, or on flush().
const FLUSH_EVERY: int = 16

# Below this level, calls are dropped before any string work.
var min_level: int = Level.INFO

# Where THIS instance writes. The shipping autoload uses the default, but
# user:// is shared by every Godot process for this project — a second process
# booting rotates session.log away and truncates a fresh one at the same path,
# under the first process's feet. Anything that needs a log only it can touch
# (tests under the parallel smoke runner) sets this to a private directory
# BEFORE the node enters the tree, and reads back through current_log().
var log_dir: String = LOG_DIR
var log_name: String = "session.log"

var _ring: Array[Dictionary] = []
var _ring_head: int = 0
var _pending: PackedStringArray = PackedStringArray()
var _bytes_written: int = 0
var _disk_ok: bool = true
var _counts: Dictionary = {}          # level name -> int
var _session_started_unix: int = 0
var _file: FileAccess = null
# Set by main.gd so a report says which tank was open.
var _context: Dictionary = {}


func _ready() -> void:
	_session_started_unix = int(Time.get_unix_time_from_system())
	_ring.resize(RING_SIZE)
	if OS.is_debug_build():
		min_level = Level.DEBUG
	_open_session()
	info("app", "session start — %s" % session_header_line())


func _exit_tree() -> void:
	info("app", "session end")
	flush()
	if _file != null:
		_file.close()
		_file = null


# --- Public API ------------------------------------------------------------

func debug(tag: String, message: String) -> void:
	_log(Level.DEBUG, tag, message)


func info(tag: String, message: String) -> void:
	_log(Level.INFO, tag, message)


func warn(tag: String, message: String) -> void:
	_log(Level.WARN, tag, message)
	# Keep the existing engine-level signal so editor/CI output is unchanged.
	push_warning("[%s] %s" % [tag, message])


func error(tag: String, message: String) -> void:
	_log(Level.ERROR, tag, message)
	push_error("[%s] %s" % [tag, message])


# Facts about the running tank, folded into every exported report. main.gd
# refreshes this; it is deliberately small and cheap to copy.
func set_context(ctx: Dictionary) -> void:
	_context = ctx.duplicate()


# Force pending entries to disk. Called on save, on quit, and before export.
func flush() -> void:
	if _pending.is_empty() or not _disk_ok or _file == null:
		_pending.clear()
		return
	var blob: String = "\n".join(_pending) + "\n"
	_pending.clear()
	if _bytes_written >= MAX_BYTES:
		return
	_file.store_string(blob)
	_file.flush()
	_bytes_written += blob.length()
	if _bytes_written >= MAX_BYTES:
		# Say so in the file itself, so a truncated log is not mistaken for a
		# clean one that simply stopped.
		_file.store_string("--- log size cap (%d bytes) reached; "
			% MAX_BYTES + "further entries are in memory only ---\n")
		_file.flush()


# --- Reporting -------------------------------------------------------------

# One line identifying the build + machine. The single most useful thing in
# any bug report, and the thing this project previously had nowhere.
func session_header_line() -> String:
	return "walstad loom %s · %s %s · %s · Godot %s" % [
		build_version(),
		OS.get_name(),
		OS.get_version(),
		RenderingServer.get_video_adapter_name(),
		Engine.get_version_info().get("string", "?"),
	]


# The file this instance is writing, which is CURRENT_LOG only while log_dir
# and log_name are left at their defaults. Read through this, never through
# the const, or you are reading whichever file currently sits at that name.
func current_log() -> String:
	return "%s/%s" % [log_dir, log_name]


func build_version() -> String:
	var v: String = String(ProjectSettings.get_setting("application/config/version", ""))
	return v if not v.is_empty() else "dev"


# Entries currently in the ring, oldest first.
func recent(limit: int = RING_SIZE) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n: int = mini(limit, RING_SIZE)
	for i in n:
		# Walk backwards from the head so the newest `n` are returned.
		var idx: int = (_ring_head - n + i + RING_SIZE * 2) % RING_SIZE
		var e: Variant = _ring[idx]
		if e is Dictionary and not (e as Dictionary).is_empty():
			out.append(e)
	return out


func level_counts() -> Dictionary:
	return _counts.duplicate()


# A complete, paste-ready diagnostic report: session header, tank context,
# error/warning tallies, then the recent log. This is what a "Copy
# diagnostics" button hands the player for a bug report.
func export_report(limit: int = RING_SIZE) -> String:
	flush()
	var lines: Array[String] = []
	lines.append("=== walstad loom diagnostics ===")
	lines.append(session_header_line())
	lines.append("session started: %s UTC"
		% Time.get_datetime_string_from_unix_time(_session_started_unix))
	lines.append("uptime: %d s" % (int(Time.get_unix_time_from_system()) - _session_started_unix))
	lines.append("save format: %d" % SaveMigrations.CURRENT_VERSION)
	var tallies: Array[String] = []
	for lv in LEVEL_NAMES:
		tallies.append("%s=%d" % [lv, int(_counts.get(lv, 0))])
	lines.append("entries: %s" % " ".join(tallies))
	if not _context.is_empty():
		lines.append("")
		lines.append("--- tank ---")
		var keys: Array = _context.keys()
		keys.sort()
		for k in keys:
			lines.append("%s: %s" % [String(k), str(_context[k])])
	lines.append("")
	lines.append("--- log (most recent %d) ---" % limit)
	for e in recent(limit):
		lines.append(format_entry(e))
	return "\n".join(lines)


static func format_entry(e: Dictionary) -> String:
	var lv: int = int(e.get("level", Level.INFO))
	var lv_name: String = LEVEL_NAMES[lv] if lv >= 0 and lv < LEVEL_NAMES.size() else "?"
	return "[%8.3f] %-5s %-12s %s" % [
		float(e.get("t", 0.0)), lv_name,
		String(e.get("tag", "")), String(e.get("msg", "")),
	]


# --- Internals -------------------------------------------------------------

func _log(level: int, tag: String, message: String) -> void:
	if level < min_level:
		return
	var entry: Dictionary = {
		"t": float(Time.get_ticks_msec()) / 1000.0,
		"level": level,
		"tag": tag,
		"msg": message,
	}
	_ring[_ring_head] = entry
	_ring_head = (_ring_head + 1) % RING_SIZE
	var lv_name: String = LEVEL_NAMES[level] if level < LEVEL_NAMES.size() else "?"
	_counts[lv_name] = int(_counts.get(lv_name, 0)) + 1
	_pending.append(format_entry(entry))
	# Errors go to disk immediately: the next thing that happens may be a
	# crash, and a batched error entry would be lost with it.
	if level >= Level.ERROR or _pending.size() >= FLUSH_EVERY:
		flush()
	entry_logged.emit(entry)


func _open_session() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(log_dir)):
		var err: Error = DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(log_dir))
		if err != OK:
			_disk_ok = false
			return
	_rotate()
	_file = FileAccess.open(current_log(), FileAccess.WRITE)
	if _file == null:
		# A read-only user dir must not take the game down with it.
		_disk_ok = false
		return
	_bytes_written = 0


# session.log -> .1 -> .2 -> .3, dropping the oldest.
func _rotate() -> void:
	var base: String = current_log()
	var oldest: String = "%s.%d" % [base, KEEP_SESSIONS]
	if FileAccess.file_exists(oldest):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(oldest))
	for i in range(KEEP_SESSIONS, 1, -1):
		var from: String = "%s.%d" % [base, i - 1]
		var to: String = "%s.%d" % [base, i]
		if FileAccess.file_exists(from):
			DirAccess.rename_absolute(
				ProjectSettings.globalize_path(from),
				ProjectSettings.globalize_path(to))
	if FileAccess.file_exists(base):
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path(base),
			ProjectSettings.globalize_path("%s.1" % base))
