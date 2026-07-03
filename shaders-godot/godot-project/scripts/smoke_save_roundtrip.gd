extends SceneTree

# REFINEMENT_II #39 — fish mind fields survive save/load without stale digests.

const MindCacheRegistry = preload("res://scripts/mind_cache_registry.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	var parent := Node3D.new()
	root.add_child(parent)

	var a := Fish.new()
	parent.add_child(a)
	a.id = "rt_fish"
	a.species = "glassdart"
	a.swim_pattern = "school"
	a.schooling_strength = 1.2
	a.position = Vector3(1.0, 1.0, 0.5)
	a.heading = Vector3(1.0, 0.0, 0.0)
	a.hunger = 0.42
	a._ws_broadcast_digest = 99
	a._ws_bids_digest = 77
	a._episodic_retrieval_hint = {"kind": "food", "salience": 0.8}

	var saved: Dictionary = a.to_save_dict()
	var b := Fish.new()
	parent.add_child(b)
	b.global_position = a.global_position
	b.apply_save_dict(saved)

	_assert(failed, b.id == a.id, "id round-trips")
	_assert(failed, absf(b.hunger - 0.42) < 0.01, "hunger round-trips")
	_assert(failed, int(b._ws_broadcast_digest) == -2,
		"transient broadcast digest cleared on load (got %d)" % int(b._ws_broadcast_digest))
	_assert(failed, int(b._ws_bids_digest) == -1, "transient bids digest cleared on load")
	_assert(failed, b._episodic_retrieval_hint.is_empty(), "retrieval hint cleared on load")

	var saved2: Dictionary = b.to_save_dict()
	_assert(failed, not saved2.has("_ws_broadcast_digest"),
		"mind digests not serialized in save dict")

	var alg := Algae.new()
	parent.add_child(alg)
	alg.init(Color8(90, 140, 50), Algae.AlgaeKind.CLUSTER)
	alg._add_voxel(Vector3(0.1, 0.0, 0.05), 0.8)
	alg._add_voxel(Vector3(-0.08, 0.02, 0.12), 0.7)
	var alg_saved: Dictionary = alg.to_save_dict()
	var alg2 := Algae.new()
	parent.add_child(alg2)
	alg2.apply_save_dict(alg_saved)
	_assert(failed, alg2._voxels.size() == alg._voxels.size(),
		"algae voxel count round-trips (got %d want %d)" % [alg2._voxels.size(), alg._voxels.size()])
	if alg._voxels.size() > 0:
		var d0: float = (alg._voxels[0] as VoxelBatch.Handle).local_pos.distance_to(
			(alg2._voxels[0] as VoxelBatch.Handle).local_pos)
		_assert(failed, d0 < 0.02, "algae voxel layout round-trips")

	parent.queue_free()
	if failed.is_empty():
		print("[smoke] save_roundtrip OK")
		quit(0)
	else:
		for msg in failed:
			push_error("[smoke] save_roundtrip FAIL: %s" % msg)
		quit(1)


func _assert(failed: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		failed.append(msg)
