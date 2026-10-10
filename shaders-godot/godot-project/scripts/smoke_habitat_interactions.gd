extends SceneTree

const SnailScript = preload("res://scripts/snail.gd")

class Food:
	extends Node3D
	var available: int = 0
	func biomass() -> int:
		return 1
	func nibble(amount: int) -> int:
		var taken: int = mini(amount, available)
		available -= taken
		return taken

class FoodSim:
	extends Node3D
	var waste: Array = []
	var algae: Array = []
	var plants: Array = []
	var pellets: int = 0
	var tank_age_s: float = 0.0
	func daylight() -> float:
		return 0.5
	func _spawn_waste(_at: Vector3, _amount: float, _kind: int) -> void:
		pellets += 1

class EcologyPlant:
	extends Plant
	var fleck_ticks: int = 0
	func _tick_detritus_flecks(_dt: float, _sim: Node) -> void:
		fleck_ticks += 1

class ProbeSnail:
	extends SnailScript
	var food_sim: Node
	func _get_sim() -> Node:
		return food_sim
	func _world_node() -> Node:
		return null

func _initialize() -> void:
	await process_frame
	seed(4141)
	var t := TestSupport.Suite.new("smoke_habitat_interactions")
	var host := Node3D.new()
	root.add_child(host)
	var p := Plant.new()
	host.add_child(p)
	p.init(16, {"leaf_form": "lance", "max_height": 30, "asymmetry_seed": 4141})
	p.set_process(false)
	t.check(not p._leaf_states.is_empty(), "grown plant supplies leaf habitats")
	if not p._leaf_states.is_empty():
		for state in p._leaf_states:
			state["biofilm"] = 0.0
			state["hair"] = 0.0
		p._leaf_states[0]["biofilm"] = 0.35
		var site: Vector3 = p.surface_graze_site(Vector3.ZERO)
		t.check(site.is_finite(), "surface food has a live geometry target")
		t.equals(p.graze_surface_food(1, site + Vector3(5, 0, 0), 0.5), 0,
			"distant food cannot be grazed")
		var stems: int = p.voxels.size()
		var height: int = p.current_height
		t.equals(p.graze_surface_food(1, site, 0.5), 1, "reachable film provides a meal")
		t.equals(p.voxels.size(), stems, "surface cleaning preserves stems")
		t.equals(p.current_height, height, "surface cleaning preserves growth height")
		t.approx(p._lifetime_grazing_pressure, 0.0, "cleaning does not induce tissue defenses")
		t.check(not p.surface_graze_site(Vector3.ZERO).is_finite(), "exhausted leaves stop advertising food")
		p._leaf_states[0]["biofilm"] = 0.35
		t.equals(p.nibble(0), 0, "zero bites leave food untouched")
		t.equals(p.nibble(2), 2, "mixed bite reports film plus tissue")
		t.equals(p.voxels.size(), stems - 1, "film replaces one tissue bite, rather than adding damage")
		var shrimp := Shrimp.new()
		host.add_child(shrimp)
		shrimp.set_process(false)
		t.check(shrimp._is_shelter_plant(p), "healthy ordinary foliage shelters shrimp")
		p.is_dying = true
		t.check(not shrimp._is_shelter_plant(p), "dying foliage is not durable cover")
		p.is_dying = false
		for state in p._leaf_states:
			state["biofilm"] = 0.35
		p.position.y = 4.0
		shrimp.hunger = 0.55
		shrimp.substrate_top_y = 0.0
		shrimp.body_shape = "crab"
		t.check(not shrimp._plant_food_site(p).is_finite(), "bottom crab does not chase high leaves")
		shrimp.body_shape = "caridean"
		t.check(shrimp._plant_food_site(p).is_finite(), "swimming shrimp can reach foliage")
		shrimp.breed_cooldown = 999.0
		shrimp.global_position = p.surface_graze_site(Vector3.ZERO)
		var before_stems: int = p.voxels.size()
		shrimp.tick(0.1, [p], [], [], [], [], [], AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40)))
		t.check(shrimp.hunger < 0.5, "real shrimp behavior eats reachable leaf film")
		t.equals(p.voxels.size(), before_stems, "normal shrimp grazing preserves living structure")
		var film_after: float = 0.0
		for state in p._leaf_states:
			film_after += float(state["biofilm"])
		shrimp.tick(0.1, [p], [], [], [], [], [], AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40)))
		var film_paused: float = 0.0
		for state in p._leaf_states:
			film_paused += float(state["biofilm"])
		t.approx(film_paused, film_after, "shrimp handles its meal before rasping again")
		shrimp._forage_pause_s = 0.0
		shrimp.hunger = 0.55
		var waste := WasteParticle.new()
		host.add_child(waste)
		waste.global_position = shrimp.global_position
		var claim: Dictionary = shrimp.tick(0.1, [], [], [waste], [], [], [], AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40)))
		t.check(claim.has("eat_waste"), "nearby detritus produces a claim")
		t.check(shrimp.hunger >= 0.55, "unsettled claim gives no premature nutrition")
		shrimp.hunger = 0.55
		shrimp.finish_detritus_meal()
		t.approx(shrimp.hunger, 0.25, "settled detritus meal grants nutrition")
		t.check(shrimp._forage_pause_s > 0.0, "successful feeding includes a handling pause")
	var sim := FoodSim.new()
	host.add_child(sim)
	var food := Food.new()
	host.add_child(food)
	sim.algae.append(food)
	var snail := ProbeSnail.new()
	snail.food_sim = sim
	host.add_child(snail)
	snail.set_process(false)
	snail.global_position = food.global_position
	snail.hunger = 0.6
	snail._check_waste_nearby(Vector3.RIGHT, Vector3.FORWARD, 0.1)
	t.approx(snail.hunger, 0.6, "empty bite gives no nutrition")
	t.equals(sim.pellets, 0, "empty bite produces no pellet")
	food.available = 3
	snail._check_waste_nearby(Vector3.RIGHT, Vector3.FORWARD, 0.1)
	t.equals(food.available, 2, "snail rasps one portion instead of destroying the colony")
	t.equals(sim.pellets, 1, "successful rasp returns one pellet to the ecosystem")
	var fed_hunger: float = snail.hunger
	snail._check_waste_nearby(Vector3.RIGHT, Vector3.FORWARD, 0.1)
	t.approx(snail.hunger, fed_hunger, "handling pause prevents duplicate feeding")
	t.equals(food.available, 2, "handling pause preserves the next portion")
	var ecology := EcologyPlant.new()
	host.add_child(ecology)
	ecology.init(16, {"leaf_form": "needle", "max_height": 30})
	ecology.set_process(false)
	var substrate := SubstrateGrid.new()
	host.add_child(substrate)
	substrate.init(10, 10)
	ecology._tick_leaf_ecology(0.1, substrate, sim)
	t.equals(ecology.fleck_ticks, 1, "detritus effects tick once per plant, not once per leaf")
	var broadleaf := Plant.new()
	host.add_child(broadleaf)
	broadleaf.init(12, {"leaf_form": "paddle", "max_height": 30})
	broadleaf.set_process(false)
	for state in broadleaf._leaf_states:
		state["biofilm"] = 0.8
		state["gsa"] = 0.5
	broadleaf._tick_dynamic_blush(sim)
	var tint: float = float(broadleaf._foliage_mat.get_shader_parameter("palette_warmth"))
	for _i in 100:
		broadleaf._tick_dynamic_blush(sim)
	t.approx(float(broadleaf._foliage_mat.get_shader_parameter("palette_warmth")), tint,
		"unchanged ecology does not accumulate tint")
	for state in broadleaf._leaf_states:
		state["biofilm"] = 0.0
		state["gsa"] = 0.0
	broadleaf._tick_dynamic_blush(sim)
	t.check(float(broadleaf._foliage_mat.get_shader_parameter("palette_warmth")) < tint,
		"clean leaves recover their original tint")
	host.queue_free()
	await process_frame
	quit(t.finish())
