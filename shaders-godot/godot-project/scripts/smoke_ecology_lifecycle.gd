extends SceneTree

class QuerySim:
	extends Node3D
	var candidates: Array = []
	var waste: Array = [1]
	func query_plants_in_radius(_pos: Vector3, _radius: float) -> Array:
		return candidates

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_ecology_lifecycle")
	var host := Node3D.new()
	root.add_child(host)
	var query := QuerySim.new()
	host.add_child(query)
	var plant := Plant.new()
	host.add_child(plant)
	plant.set_process(false)
	plant.current_height = 4
	plant._sim_driver_ref = query
	var neighbor := Plant.new()
	host.add_child(neighbor)
	neighbor.set_process(false)
	neighbor.current_height = 20
	neighbor.position = Vector3(0.3, 0.0, 0.0)
	neighbor._world_pos = neighbor.position
	neighbor.flower_stage = Plant.FlowerStage.MATURE
	neighbor._pollen_ready = true
	neighbor.repro_mode = PlantGenome.REPRO_SEED
	plant.repro_mode = PlantGenome.REPRO_SEED
	var removed := Plant.new()
	query.candidates = [removed, null, host, plant, neighbor]
	removed.free()
	plant._recompute_shade()
	t.approx(plant._shade_mult, Plant.SHADE_PENALTY,
		"freed candidates cannot abort shading from a live canopy")
	t.check(plant._find_pollination_partner() == neighbor,
		"freed candidates cannot hide a live pollination partner")

	var sim := SimDriver.new()
	sim.plants.append(neighbor)
	sim._rebuild_plants_grid()
	neighbor.queue_free()
	plant._recompute_shade()
	t.approx(plant._shade_mult, 1.0, "queued canopy stops shading new growth")
	t.check(plant._find_pollination_partner() == null,
		"queued flowers cannot receive pollen")
	t.check(sim.query_plants_in_radius(Vector3.ZERO, 2.0).is_empty(),
		"cached plant queries omit queued removals before frame end")
	await process_frame
	t.check(sim.query_plants_in_radius(Vector3.ZERO, 2.0).is_empty(),
		"cached plant queries omit freed removals before rebuilding")
	sim._rebuild_plants_grid()
	t.check(sim._plants_grid.is_empty(), "grid rebuilding tolerates freed inventory entries")

	var live_algae := Node3D.new()
	var removed_algae := Node3D.new()
	host.add_child(live_algae)
	host.add_child(removed_algae)
	sim.algae = [removed_algae, live_algae]
	sim._rebuild_algae_grid()
	removed_algae.queue_free()
	t.check(sim.query_algae_in_radius(Vector3.ZERO, 2.0) == [live_algae],
		"algae searches preserve live food while omitting queued removals")
	await process_frame
	t.check(sim.query_algae_in_radius(Vector3.ZERO, 2.0) == [live_algae],
		"algae searches omit freed food before rebuilding")
	sim.free()

	# Eating detritus used to leave a plant-owned timer capturing the freed
	# fleck. Fast-forward the real timer rather than waiting 8–18 seconds.
	var previous: Array[Tween] = get_processed_tweens()
	plant._tick_detritus_flecks(100.0, query)
	t.equals(plant._detritus_fleck_nodes.size(), 1, "detritus fixture creates one edible fleck")
	var retirement: Tween = null
	for tween in get_processed_tweens():
		if not previous.has(tween):
			retirement = tween
	t.check(retirement != null, "detritus gets a retirement timer")
	t.check(plant.graze_detritus_fleck(), "grazing removes the fleck immediately")
	await process_frame
	await process_frame
	if retirement != null:
		if retirement.is_valid():
			retirement.custom_step(30.0)
		t.check(not retirement.is_valid(), "grazing cancels the freed fleck's timer")

	plant._tick_detritus_flecks(100.0, query)
	for tween in get_processed_tweens():
		if not previous.has(tween):
			tween.custom_step(30.0)
	t.check(plant._detritus_fleck_nodes.is_empty(), "natural expiration releases the habitat slot")
	await process_frame
	for _i in 3:
		plant._tick_detritus_flecks(100.0, query)
	t.equals(plant._detritus_fleck_nodes.size(), 3, "detritus habitat fills to its cap")
	for fleck in plant._detritus_fleck_nodes:
		fleck.free()
	plant._tick_detritus_flecks(100.0, query)
	t.equals(plant._detritus_fleck_nodes.size(), 1,
		"external cleanup cannot leave dead flecks occupying all habitat slots")
	host.queue_free()
	await process_frame
	await process_frame
	quit(t.finish())
