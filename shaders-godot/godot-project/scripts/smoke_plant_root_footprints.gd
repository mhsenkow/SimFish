extends SceneTree


func _init() -> void:
	var failed: Array[String] = []
	var grid := SubstrateGrid.new()
	root.add_child(grid)
	grid.init(3.0, 3.0, 1.0)
	var p := Vector3.ZERO
	grid.add_at(p, 2.0)
	grid.begin_root_footprint_refresh()
	grid.register_root_footprint(101, p, 0, 4.0)
	grid.register_root_footprint(202, p, 0, 4.0)
	grid.end_root_footprint_refresh()
	var a: float = grid.consume_root_uptake(101, p, 1.0)
	var b: float = grid.consume_root_uptake(202, p, 1.0)
	_assert(failed, is_equal_approx(a, 0.5) and is_equal_approx(b, 0.5),
		"equal overlapping root masses split uptake proportionally")

	grid.begin_root_footprint_refresh()
	grid.register_root_footprint(101, p, 2, 6.0)
	grid.end_root_footprint_refresh()
	var footprint: Dictionary = grid.root_footprint_for(101)
	_assert(failed, footprint.size() > 1 and footprint.size() <= 13,
		"coarse footprint is bounded")
	_assert(failed, grid.root_footprint_for(202).is_empty(),
		"coarse refresh removes extinct roots")
	var spread_taken: float = grid.consume_root_uptake(101, p, 0.5)
	_assert(failed, spread_taken > 0.0 and spread_taken <= 0.5,
		"footprint uptake is bounded by demand")

	if failed.is_empty():
		print("[smoke_plant_root_footprints] PASS")
		quit(0)
	else:
		for msg in failed:
			push_error("[smoke_plant_root_footprints] " + msg)
		quit(1)


func _assert(failed: Array[String], condition: bool, label: String) -> void:
	if not condition:
		failed.append(label)
