extends SceneTree

# PLANT_SYSTEMS_50 #25 — conservative static opaque hardscape occluders.

const Occluders := preload("res://scripts/hardscape_occluders.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	_assert(failed, Occluders.eligible(Vector3(1.1, 0.7, 1.0), true, false),
		"large opaque static rock qualifies")
	_assert(failed, not Occluders.eligible(Vector3(2.0, 0.12, 0.12), true, false),
		"thin branch never qualifies")
	_assert(failed, not Occluders.eligible(Vector3.ONE, true, true),
		"moving hardscape never qualifies")
	_assert(failed, not Occluders.eligible(Vector3.ONE, false, false),
		"transparent hardscape never qualifies")

	var candidates: Array = []
	for i in 6:
		candidates.append({"position": Vector3(i * 1.5, 1, 0),
			"size": Vector3(1.0, 0.7, 1.0), "opaque": true,
			"moving": false, "kind": "rock"})
	var host := Node3D.new()
	root.add_child(host)
	var stats: Dictionary = Occluders.build(host, candidates, 0)
	_assert(failed, bool(stats.enabled) and int(stats.built) == 6,
		"benefit gate builds accepted volumes")
	var holder := host.get_node_or_null("HardscapeOccluders")
	_assert(failed, holder != null and holder.get_child_count() == 6,
		"occluder instances are world-owned")
	if holder != null:
		var box := (holder.get_child(0) as OccluderInstance3D).occluder as BoxOccluder3D
		_assert(failed, box != null and box.size.is_equal_approx(
			Vector3(1.0, 0.7, 1.0) * Occluders.INSET),
			"volume is conservatively inset")

	var potato_host := Node3D.new()
	root.add_child(potato_host)
	var potato: Dictionary = Occluders.build(potato_host, candidates, 2)
	_assert(failed, not bool(potato.enabled) and int(potato.built) == 0,
		"potato quality gate disables occluders")
	host.free()
	potato_host.free()
	await process_frame
	if failed.is_empty():
		print("[smoke] hardscape_occluders OK built=%d benefit=%d inset=%.2f"
			% [int(stats.built), int(stats.benefit_score), Occluders.INSET])
		quit(0)
	else:
		for message in failed:
			push_error("[smoke] FAIL: %s" % message)
		quit(1)


func _assert(failed: Array[String], condition: bool, label: String) -> void:
	if not condition:
		failed.append(label)
