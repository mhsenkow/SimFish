extends Node

# Test-only feed memory stand-in for rung-1 kill tests.

var feed_pos: Vector3 = Vector3.ZERO


func anticipated_feed_surface_pos() -> Vector3:
	return feed_pos
