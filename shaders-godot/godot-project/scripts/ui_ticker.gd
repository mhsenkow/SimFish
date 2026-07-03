extends Node

# PERFORMANCE_REALTIME #92 — central 5 Hz UI refresh clock.

signal tick(delta: float)

const TICK_INTERVAL: float = 0.2

var _accum: float = 0.0


func _process(dt: float) -> void:
	_accum += dt
	if _accum < TICK_INTERVAL:
		return
	var adt: float = _accum
	_accum = 0.0
	tick.emit(adt)
