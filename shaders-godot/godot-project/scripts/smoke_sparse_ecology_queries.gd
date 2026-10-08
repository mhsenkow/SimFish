extends SceneTree

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_sparse_ecology_queries")
	var grid: Dictionary = {}
	for x in range(-5, 6):
		for z in range(-5, 6):
			if (x * x + z * z) % 4 == 0:
				grid[Vector2i(x, z)] = [x * 100 + z, x * 100 + z + 1]
	var cells: Array[Vector2i] = []
	cells.assign(grid.keys())
	cells.sort_custom(SimDriver._grid_cell_less)
	for center in [Vector2i.ZERO, Vector2i(-3, 4), Vector2i(20, 20)]:
		for reach in [1, 2, 5, 8, 20]:
			var expected: Array = _reference(grid, center, reach)
			t.equals(SimDriver._grid_candidates(grid, cells, center, reach), expected,
				"adaptive query preserves candidates and order at %s radius %d" % [center, reach])
	t.equals(SimDriver._grid_candidates({}, [], Vector2i.ZERO, 10), [], "empty habitat returns no candidates")
	var sparse: Dictionary = {Vector2i.ZERO: [1], Vector2i(2, 2): [2]}
	var sparse_cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i(2, 2)]
	var start: int = Time.get_ticks_usec()
	for i in 1000:
		_reference(sparse, Vector2i.ZERO, 8)
	var before: int = Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	for i in 1000:
		SimDriver._grid_candidates(sparse, sparse_cells, Vector2i.ZERO, 8)
	print("[sparse_query] 1000 broad searches: reference=%dus adaptive=%dus" % [before, Time.get_ticks_usec() - start])
	var sim := SimDriver.new()
	var plant := Plant.new()
	plant._world_pos = Vector3(2, 0, -2)
	sim.plants.append(plant)
	sim._rebuild_plants_grid()
	t.equals(sim._plants_grid_cells.size(), 1, "real grid rebuild exposes occupied plant cells")
	t.equals(sim.query_plants_in_radius(Vector3.ZERO, 16.0), [plant], "real broad query retains the plant")
	sim.plants.clear()
	sim._rebuild_plants_grid()
	t.check(sim._plants_grid_cells.is_empty(), "removing all plants clears the occupied-cell index")
	plant.free()
	sim.free()
	quit(t.finish())

func _reference(grid: Dictionary, center: Vector2i, reach: int) -> Array:
	var result: Array = []
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var bucket: Array = grid.get(center + Vector2i(dx, dz), [])
			result.append_array(bucket)
	return result
