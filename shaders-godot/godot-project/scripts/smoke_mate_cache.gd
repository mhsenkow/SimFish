extends SceneTree

func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_mate_cache")
	var fish := Fish.new()
	fish.sex = 0
	fish._mate_id = "bonded"
	var mate := Fish.new()
	mate.id = "bonded"
	mate.sex = 1
	mate.maturity = Fish.MATURITY_ADULT
	mate.hunger = 0.2
	mate.energy = 0.9
	mate.stress = 0.1
	var neighbors: Array = [mate]
	t.check(fish._find_preferred_mate(neighbors) == mate, "available bonded adults reunite")
	mate.hunger = 0.9
	t.check(fish._find_preferred_mate(neighbors) == null, "hungry bonded fish can recover before courting")
	mate.hunger = 0.2
	mate._dying = true
	t.check(not fish._mate_candidate_available(mate), "a cached dying partner cannot begin courtship")
	mate._dying = false
	mate.position = Vector3(4, 0, 0)
	t.check(not fish._mate_candidate_available(mate), "cached partners are rechecked after moving apart")
	mate.position = Vector3.ZERO
	mate.species = "another_species"
	t.check(not fish._mate_candidate_available(mate), "mate cache respects current species")
	mate.free()
	t.check(fish._find_preferred_mate(neighbors) == null, "freed bonded refs are skipped safely")
	t.check(fish._find_breeding_partner(neighbors) == null, "freed candidate refs are skipped safely")
	var expected: float = 1.0 + sin((float(Time.get_datetime_dict_from_system().month) - 4.0) / 12.0 * TAU) * 0.3
	t.approx(fish._season_breed_mult(), expected, "shared season cache preserves the breeding curve")
	fish.free()
	quit(t.finish())
