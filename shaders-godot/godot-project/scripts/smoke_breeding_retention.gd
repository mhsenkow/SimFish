extends SceneTree

const Library = preload("res://scripts/species_library.gd")

func _initialize() -> void:
	await process_frame
	root.get_node("TankConfig").capture_mode = true
	var t := TestSupport.Suite.new("smoke_breeding_retention")
	var tank := Node3D.new()
	root.add_child(tank)
	var a := Fish.new()
	var b := Fish.new()
	a.id = "parent-a"
	b.id = "parent-b"
	tank.add_child(a)
	tank.add_child(b)
	a.set_process(false)
	b.set_process(false)
	var s1 := Shrimp.new()
	var s2 := Shrimp.new()
	var before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var fish_keys: Array = Library.parent_keys_for_breeding([a.get_saved_genome(), b.get_saved_genome()])
	var shrimp_keys: Array = Library.parent_keys_for_breeding([s1.get_saved_genome(), s2.get_saved_genome()])
	for _i in 32:
		var fish_child: Dictionary = a.produce_offspring_genome(b)
		var shrimp_child: Dictionary = s1.produce_offspring_genome(s2)
		t.equals(fish_child.parent_keys, fish_keys, "fish offspring retain canonical parent lineage")
		t.equals(shrimp_child.parent_keys, shrimp_keys, "shrimp offspring retain canonical parent lineage")
	t.equals(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), before, "repeated reproduction creates no detached library Nodes")
	var example: Dictionary = {"organism_type": "snail", "shell_color": Color(0.2, 0.4, 0.6)}
	t.equals(Library.parent_keys_for_breeding([{}, example, example, null]).size(), 1, "parent keys ignore empty input and deduplicate")
	s1.free()
	s2.free()
	FloatingPlant.clear_shell_cache()
	var floater := FloatingPlant.new()
	tank.add_child(floater)
	floater.init_genome({"morph": "duckweed", "leaf_count": 2})
	var original_count: int = floater.get_child_count()
	for _i in 12:
		floater._build()
		t.equals(floater.get_child_count(), original_count, "same-frame rebuild replaces old children exactly once")
	var oldest_key: String = floater._shell_cache_key()
	var oldest: Node3D = FloatingPlant._morph_shell_cache[oldest_key]
	for i in FloatingPlant.MORPH_SHELL_CACHE_LIMIT + 3:
		floater._store_shell_cache("test-shape-%d" % i)
	t.equals(FloatingPlant._morph_shell_cache.size(), FloatingPlant.MORPH_SHELL_CACHE_LIMIT, "prototype cache has an explicit lifetime-independent bound")
	t.check(not is_instance_valid(oldest), "prototype eviction frees its detached Node tree")
	var retained: Node3D = FloatingPlant._morph_shell_cache.values()[0]
	FloatingPlant.clear_shell_cache()
	t.check(not is_instance_valid(retained), "cache clearing frees detached prototypes")
	t.check(floater.get_child_count() == original_count, "prototype eviction preserves living floater geometry")
	tank.free()
	await process_frame
	quit(t.finish())
