extends Plant

# Test-only Plant that records distance-bucket integration without running the
# full biological tick. Deliberately not named smoke_* so aggregate discovery
# never attempts to execute it as a MainLoop.

var tick_calls: int = 0
var integrated_dt: float = 0.0


func tick(dt: float, _substrate: SubstrateGrid) -> void:
	tick_calls += 1
	integrated_dt += dt
