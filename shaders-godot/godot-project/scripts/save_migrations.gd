class_name SaveMigrations
extends RefCounted

# Save schema version stamp + migration chain (BROAD_DIRECTIONS #4).
#
# THE BUG THIS FIXES: tank_saves.gd declared `const STATE_VERSION := 1` and
# never wrote or read it. Saves on disk carried no version at all, so:
#   - a schema change could not be migrated (nothing said what shape a file
#     was in), and
#   - a save written by a NEWER build loaded silently into an older one,
#     with missing fields defaulting quietly. Combined with the near-total
#     absence of runtime diagnostics (#5) that failure was invisible to the
#     player and unreportable to us.
#
# Now every save is stamped, a newer-than-known save is refused rather than
# half-loaded, and schema changes get a migration step.
#
# ADDING A MIGRATION
#   1. Bump CURRENT_VERSION.
#   2. Add a `_migrate_N_to_N_plus_1(d)` static func that mutates and returns d.
#   3. Register it in _STEPS.
#   4. Extend smoke_save_versioning.gd with a fixture of the OLD shape.
# Steps run in order, so a version-1 save walks 1→2→3 to reach current.

# Bump this for any breaking change to the state.json shape.
const CURRENT_VERSION: int = 1

# Key the stamp lives under, at the top level of state.json.
const VERSION_KEY := "save_version"

# Saves written before the stamp existed. They are structurally identical to
# version 1 — the field was simply never written — so they are ASSUMED to be
# version 1 rather than migrated. Do not add a 0→1 step: there is no shape
# difference to fix, and inventing one would corrupt real player tanks.
const UNSTAMPED_ASSUMED_VERSION: int = 1

# Migration steps, in application order: {"from": int, "to": int, "fn": Callable}.
# Empty until CURRENT_VERSION first moves past 1.
static var _STEPS: Array[Dictionary] = []


# --- Reading ---------------------------------------------------------------

# Schema version of a loaded save dict. An unstamped (pre-#4) save reports
# UNSTAMPED_ASSUMED_VERSION. A garbage stamp reports -1 so callers can tell
# "no stamp" from "nonsense stamp".
static func version_of(d: Dictionary) -> int:
	if not d.has(VERSION_KEY):
		return UNSTAMPED_ASSUMED_VERSION
	var raw: Variant = d.get(VERSION_KEY)
	match typeof(raw):
		TYPE_INT:
			return int(raw)
		TYPE_FLOAT:
			# JSON round-trips small ints as floats often enough to allow it,
			# but only when it is actually integral.
			var f: float = float(raw)
			return int(f) if is_equal_approx(f, floorf(f)) else -1
		TYPE_STRING, TYPE_STRING_NAME:
			var s: String = String(raw)
			return int(s) if s.is_valid_int() else -1
		_:
			return -1


static func is_unstamped(d: Dictionary) -> bool:
	return not d.has(VERSION_KEY)


# --- Writing ---------------------------------------------------------------

# Stamp a state dict with the current schema version. Called on every save.
# Mutates and returns the same dict (the save path already owns it).
static func stamp(d: Dictionary) -> Dictionary:
	d[VERSION_KEY] = CURRENT_VERSION
	return d


# --- Migration -------------------------------------------------------------

# Bring a loaded save up to CURRENT_VERSION.
#
# Returns:
#   ok      : bool       — safe to load
#   dict    : Dictionary — the migrated save (unchanged when already current)
#   from    : int        — version as found on disk
#   to      : int        — version after migration
#   reason  : String     — why it was refused; "" when ok
#   refused : String     — machine-readable refusal code, "" when ok
#                          ("future" | "unknown_version" | "no_path")
#
# A save is refused, never partially loaded, when:
#   - its version is newer than this build understands (downgrade), or
#   - its stamp is unparseable, or
#   - no chain of steps reaches CURRENT_VERSION.
static func migrate(d: Dictionary) -> Dictionary:
	var found: int = version_of(d)
	var result: Dictionary = {
		"ok": false, "dict": d, "from": found, "to": found,
		"reason": "", "refused": "",
	}

	if found < 0:
		result["reason"] = "This tank's save has an unreadable version stamp."
		result["refused"] = "unknown_version"
		return result

	if found > CURRENT_VERSION:
		# Downgrade. Loading this would silently drop whatever the newer
		# build added, and the next save would write the loss back to disk.
		result["reason"] = (
			"This tank was saved by a newer version of walstad loom "
			+ "(save format %d; this build understands %d). "
			+ "Update the game to open it."
		) % [found, CURRENT_VERSION]
		result["refused"] = "future"
		return result

	if found == CURRENT_VERSION:
		result["ok"] = true
		return result

	# Walk the chain forward.
	var cur: int = found
	var work: Dictionary = d
	var guard: int = 0
	while cur < CURRENT_VERSION:
		# Guard against a malformed _STEPS table looping forever.
		guard += 1
		if guard > 64:
			result["reason"] = "Save migration did not terminate."
			result["refused"] = "no_path"
			return result
		var step: Dictionary = _step_from(cur)
		if step.is_empty():
			result["reason"] = (
				"No migration path from save format %d to %d."
			) % [cur, CURRENT_VERSION]
			result["refused"] = "no_path"
			result["to"] = cur
			result["dict"] = work
			return result
		var fn: Callable = step.get("fn")
		work = fn.call(work)
		cur = int(step.get("to", cur))

	work[VERSION_KEY] = CURRENT_VERSION
	result["ok"] = true
	result["dict"] = work
	result["to"] = CURRENT_VERSION
	return result


static func _step_from(from_version: int) -> Dictionary:
	for step in _STEPS:
		if int(step.get("from", -1)) == from_version:
			return step
	return {}


# True when a save at this version can be opened by this build at all.
static func can_open(d: Dictionary) -> bool:
	return bool(migrate(d.duplicate(true)).get("ok", false))
