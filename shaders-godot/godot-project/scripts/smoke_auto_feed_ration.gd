extends SceneTree

func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_auto_feed_ration")
	var sim := SimDriver.new()
	var fixtures: Array[Fish] = []
	for i in 48:
		var fish := Fish.new()
		fish.id = "ration_%d" % i
		fish.hunger = 0.3
		fixtures.append(fish)
		sim.fish.append(fish)
	t.equals(sim._automatic_feed_portion_count(), 0, "sated communities do not accumulate unnecessary food")
	fixtures[0].hunger = 0.6
	t.equals(sim._automatic_feed_portion_count(), 1, "one hungry resident receives a small ration")
	for fish in fixtures:
		fish.hunger = 0.6
	t.equals(sim._automatic_feed_portion_count(), 12, "hungry communities get a bounded population-scaled ration")
	var food := WasteParticle.new()
	food.kind = WasteParticle.KIND_FOOD
	sim.waste.append(food)
	t.equals(sim._automatic_feed_portion_count(), 11, "existing meals are credited before adding new food")
	sim.dissolved_o2 = 0.3
	t.equals(sim._automatic_feed_portion_count(), 1, "oxygen pressure limits additional feeding")
	sim.dissolved_o2 = 0.85
	sim.water_chemistry.ammonia = 0.5
	t.equals(sim._automatic_feed_portion_count(), 1, "ammonia pressure limits additional feeding")
	sim.water_chemistry.ammonia = 0.0
	food.free()
	for fish in fixtures:
		fish.free()
	t.equals(sim._automatic_feed_portion_count(), 0, "freed residents and meals are ignored safely")
	sim.fish.clear()
	sim.waste.clear()
	var shrimp := Shrimp.new()
	shrimp.hunger = 0.9
	sim.shrimp.append(shrimp)
	t.equals(sim._automatic_feed_portion_count(), 1, "hungry detritivores receive a small grazing supplement")
	shrimp.hunger = 0.5
	t.equals(sim._automatic_feed_portion_count(), 0, "successful grazers need no automatic supplement")
	shrimp.free()
	sim.free()
	quit(t.finish())
