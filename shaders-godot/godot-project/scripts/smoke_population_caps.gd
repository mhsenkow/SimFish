# Headless check on the population density budget (TankConfig).
#
# Two things must hold no matter what the ecology hands us:
#   1. The density dial scales soft capacities, and
#   2. the hard per-kind ceiling is never exceeded — that is the whole
#      point of the ceiling, so a tank left breeding overnight can't
#      grind the frame budget down.
#
# Run headless:
#   ./scripts/godot.sh --headless --path shaders-godot/godot-project \
#       --script res://scripts/smoke_population_caps.gd
#
# Instantiates the TankConfig script directly rather than reading the
# autoload — `extends SceneTree` scripts run before autoloads register.

extends SceneTree

const TankConfigScript = preload("res://scripts/tank_config.gd")


func _fail(msg: String) -> void:
	push_error("[smoke_population_caps] " + msg)
	quit(1)


func _init() -> void:
	var cfg: Node = TankConfigScript.new()

	# Reference-sized tank: volume ratio should sit at 1.0 so the shipped
	# ceilings mean what the Settings panel says they mean.
	cfg.tank_half_w = 8.0
	cfg.tank_half_d = 4.0
	cfg.tank_height = 7.0
	if not is_equal_approx(cfg.tank_volume_ratio(), 1.0):
		_fail("reference tank ratio should be 1.0, got %f" % cfg.tank_volume_ratio())
		return

	# Every kind in the table must resolve to a positive ceiling, and an
	# absurd soft capacity must be clamped to exactly that ceiling.
	for kind in TankConfigScript.POP_CAP_DEFAULTS.keys():
		var hard: int = cfg.population_hard_cap(String(kind))
		if hard <= 0:
			_fail("kind '%s' has no hard cap" % kind)
			return
		var capped: int = cfg.population_cap(String(kind), 100000)
		if capped != hard:
			_fail("kind '%s': runaway soft cap gave %d, expected ceiling %d"
				% [kind, capped, hard])
			return

	# Density dial scales soft capacities without ever breaching the ceiling.
	cfg.density_budget = 0.5
	if cfg.population_cap("fish", 20) != 10:
		_fail("density 0.5 on soft 20 should give 10, got %d"
			% cfg.population_cap("fish", 20))
		return
	cfg.density_budget = 1.6
	if cfg.population_cap("fish", 20) != 32:
		_fail("density 1.6 on soft 20 should give 32, got %d"
			% cfg.population_cap("fish", 20))
		return
	if cfg.population_cap("fish", 500) > cfg.population_hard_cap("fish"):
		_fail("density 1.6 breached the fish ceiling")
		return
	cfg.density_budget = 1.0

	# A tiny vessel must get a proportionally smaller ceiling than the
	# reference tank — a nano cube holding 60 fish is the exact failure
	# this system exists to prevent.
	cfg.tank_half_w = 4.0
	cfg.tank_half_d = 4.0
	cfg.tank_height = 4.5
	var nano_fish: int = cfg.population_hard_cap("fish")
	if nano_fish >= int(TankConfigScript.POP_CAP_DEFAULTS["fish"]["cap"]):
		_fail("nano cube ceiling (%d) should be below the reference ceiling"
			% nano_fish)
		return
	# ...but never below the per-kind floor, or a small tank becomes unplayable.
	for kind2 in TankConfigScript.POP_CAP_DEFAULTS.keys():
		var row: Dictionary = TankConfigScript.POP_CAP_DEFAULTS[kind2]
		var floor_n: int = int(row.get("floor", 1))
		if cfg.population_hard_cap(String(kind2)) < floor_n:
			_fail("kind '%s' fell below its floor of %d in a nano tank"
				% [kind2, floor_n])
			return

	# Scaling off = raw numbers everywhere, regardless of vessel size.
	cfg.pop_scale_with_tank = false
	if cfg.population_hard_cap("fish") != cfg.pop_cap_fish:
		_fail("scaling disabled should return the raw cap, got %d"
			% cfg.population_hard_cap("fish"))
		return
	cfg.pop_scale_with_tank = true

	# An unknown kind must degrade to "no ceiling" rather than freezing
	# spawns at zero — a typo should never stop the sim dead.
	if cfg.population_cap("gribbly", 37) != 37:
		_fail("unknown kind should pass the soft cap through unchanged")
		return

	cfg.free()
	print("[smoke_population_caps] OK — %d kinds, ceilings + density dial hold"
		% TankConfigScript.POP_CAP_DEFAULTS.size())
	quit()
