class_name SimGate
extends RefCounted

# Typed service accessors for the sim/world boundary (BROAD_DIRECTIONS #8).
#
# THE PROBLEM. `world` and the SimDriver are reached as bare `Node` from 99
# of ~400 scripts, so every call site defends itself:
#
#     var dl: float = float(sim.daylight()) if sim.has_method("daylight") else 1.0
#
# There were 1,077 such `has_method()` guards, and `has_method("daylight")`
# alone appeared 77 times. Typing is excellent *inside* a file and evaporates
# at every module seam.
#
# The real cost is not verbosity. Rename `SimDriver.daylight()` and nothing
# fails at parse time — all 77 sites quietly take their fallback branch and
# the tank just behaves as if it were permanently noon. A silent, uniform,
# plausible wrongness is the worst failure mode available.
#
# WHAT THIS DOES. GDScript has no interfaces, so the fix is three-part:
#
#   1. **One guard, not 77.** Each accessor here is the single place the
#      duck-check lives, with the caller's fallback passed in (the fallbacks
#      genuinely differ — some default to daylight 1.0, others to 0.5).
#   2. **A violated contract is LOUD.** A missing method logs once per
#      method per session (not per call — this is hot-path code), so a
#      rename shows up in the log instead of nowhere.
#   3. **The contract is asserted at test time.** CONTRACT below declares
#      what each provider must expose; `smoke_service_contracts.gd` checks it
#      against the real classes. That is the compile-time check GDScript
#      cannot give us, moved to CI.
#
# ADDING A METHOD: add it to CONTRACT, add a typed accessor, and the smoke
# will start enforcing it.

# provider -> { method: arg_count }. arg_count is the REQUIRED arity (the
# smoke allows extra optional params, since several of these have defaults).
const CONTRACT: Dictionary = {
	"SimDriver": {
		"daylight": 0,
		"query_plants_in_radius": 2,
	},
	"World": {
		"clamp_xyz_in_tank": 1,
		"column_surface_y": 2,
		"sample_flow": 1,
		"effective_warmth_at": 1,
		"is_inside_tank": 2,
	},
}

# Methods already reported missing this session, so the log gets one line per
# broken contract rather than one per frame.
static var _reported: Dictionary = {}


# --- SimDriver -------------------------------------------------------------

# Day/night light multiplier, 0..1. `fallback` matters: some callers want
# 1.0 (assume full day) and others 0.5 (assume neutral), and that choice is
# the caller's, not ours.
static func daylight(sim: Object, fallback: float = 1.0) -> float:
	if not _has(sim, "daylight"):
		return fallback
	return float(sim.call("daylight"))


static func query_plants_in_radius(sim: Object, pos: Vector3, max_dist: float) -> Array:
	if not _has(sim, "query_plants_in_radius"):
		return []
	return sim.call("query_plants_in_radius", pos, max_dist)


# --- World -----------------------------------------------------------------

# Clamp a position inside the tank walls. Falls back to the input point:
# returning ZERO instead would teleport creatures to the tank centre, which
# is far more visible than leaving them momentarily out of bounds.
static func clamp_xyz_in_tank(world: Object, p: Vector3, margin: float = 0.25,
		body_radius: float = 0.0) -> Vector3:
	if not _has(world, "clamp_xyz_in_tank"):
		return p
	return world.call("clamp_xyz_in_tank", p, margin, body_radius)


static func column_surface_y(world: Object, x: float, z: float,
		fallback: float = 0.0) -> float:
	if not _has(world, "column_surface_y"):
		return fallback
	return float(world.call("column_surface_y", x, z))


static func sample_flow(world: Object, pos: Vector3) -> Vector3:
	if not _has(world, "sample_flow"):
		return Vector3.ZERO
	return world.call("sample_flow", pos)


static func effective_warmth_at(world: Object, world_pos: Vector3,
		fallback: float = 0.5) -> float:
	if not _has(world, "effective_warmth_at"):
		return fallback
	return float(world.call("effective_warmth_at", world_pos))


# Defaults to true: a missing tank-bounds provider should not make every
# position read as "outside the tank", which would strand the whole
# population against invisible walls.
static func is_inside_tank(world: Object, x: float, z: float,
		margin: float = 0.0, world_y: float = NAN) -> bool:
	if not _has(world, "is_inside_tank"):
		return true
	return bool(world.call("is_inside_tank", x, z, margin, world_y))


# --- Internals -------------------------------------------------------------

# The single duck-check. A null provider is normal (headless tests, teardown,
# a panel built before the world exists) and is silent. A NON-null provider
# that lacks the method is a broken contract and says so, once.
static func _has(provider: Object, method: String) -> bool:
	if provider == null:
		return false
	if provider is Node and not is_instance_valid(provider):
		return false
	if provider.has_method(method):
		return true
	_report_once(provider, method)
	return false


static func _report_once(provider: Object, method: String) -> void:
	var key: String = "%s.%s" % [provider.get_class(), method]
	if _reported.has(key):
		return
	_reported[key] = true
	var msg: String = (
		"broken service contract: %s has no %s() — callers are silently "
		+ "falling back. Check SimGate.CONTRACT and smoke_service_contracts.gd."
	) % [provider.get_class(), method]
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree:
		var lg: Node = (ml as SceneTree).root.get_node_or_null("AppLog")
		if lg != null and lg.has_method("error"):
			lg.error("contract", msg)
			return
	push_error("[contract] %s" % msg)


# Test hook: clear the once-only report set between smoke cases.
static func reset_reports() -> void:
	_reported.clear()
