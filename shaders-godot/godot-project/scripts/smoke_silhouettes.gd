extends SceneTree

const FishScript := preload("res://scripts/fish.gd")
const TankConfigScript := preload("res://scripts/tank_config.gd")


func _initialize() -> void:
	await process_frame
	var cfg := get_root().get_node_or_null("TankConfig")
	if cfg == null:
		push_error("[smoke_silhouettes] TankConfig autoload missing")
		quit(1)
		return
	var lib: Dictionary = cfg.SPECIES_LIBRARY
	var fingerprints: Dictionary = {}
	var root_node := Node3D.new()
	root_node.name = "SilhouetteRoot"
	root.add_child(root_node)
	for species_key: String in lib.keys():
		var entry: Dictionary = lib[species_key]
		var genome: Dictionary = entry.get("genome", {}).duplicate(true)
		genome["species"] = species_key
		var fp: String = TankConfigScript.species_silhouette_fingerprint(species_key)
		if fp.is_empty():
			push_error("[smoke_silhouettes] %s: empty silhouette fingerprint" % species_key)
			quit(1)
			return
		if fingerprints.has(fp):
			push_error("[smoke_silhouettes] duplicate fingerprint %s vs %s" % [
				species_key, fingerprints[fp]])
			quit(1)
			return
		fingerprints[fp] = species_key
		var fish: Fish = FishScript.new()
		fish.name = "Sil_" + species_key
		root_node.add_child(fish)
		fish.init_genome(genome)
		await process_frame
		var batches: Array = fish.get("_voxel_builder").get_batches() if fish.get("_voxel_builder") != null else []
		if batches.size() < 8:
			push_error("[smoke_silhouettes] %s: too few voxel batches (%d)" % [
				species_key, batches.size()])
			quit(1)
			return
		fish.queue_free()
	print("[smoke_silhouettes] OK — %d unique species silhouettes" % lib.size())
	quit()
