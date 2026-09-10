class_name HardscapeOccluders
extends RefCounted

# Conservative occluder synthesis. Boxes are inset so they never project beyond
# visible hardscape, and only chunky opaque static pieces qualify.

const MIN_AXIS: float = 0.50
const MIN_VOLUME: float = 0.35
const INSET: float = 0.72
const MIN_BENEFIT_SCORE: int = 20


static func eligible(size: Vector3, opaque: bool, moving: bool) -> bool:
	return opaque and not moving and minf(size.x, minf(size.y, size.z)) >= MIN_AXIS \
		and size.x * size.y * size.z >= MIN_VOLUME


static func build(parent: Node3D, candidates: Array, quality_tier: int) -> Dictionary:
	var stats := {"candidates": candidates.size(), "eligible": 0, "built": 0,
		"benefit_score": 0, "enabled": false}
	if parent == null or quality_tier >= 2 \
			or not ProjectSettings.get_setting(
				"rendering/occlusion_culling/use_occlusion_culling", false):
		return stats
	var accepted: Array = []
	for candidate in candidates:
		var size: Vector3 = candidate.get("size", Vector3.ZERO)
		if eligible(size, bool(candidate.get("opaque", false)),
				bool(candidate.get("moving", true))):
			accepted.append(candidate)
	stats.eligible = accepted.size()
	stats.benefit_score = accepted.size() * candidates.size()
	if int(stats.benefit_score) < MIN_BENEFIT_SCORE:
		return stats

	var holder := Node3D.new()
	holder.name = "HardscapeOccluders"
	parent.add_child(holder)
	for candidate in accepted:
		var instance := OccluderInstance3D.new()
		var box := BoxOccluder3D.new()
		box.size = (candidate.size as Vector3) * INSET
		instance.occluder = box
		instance.position = candidate.position
		holder.add_child(instance)
		stats.built = int(stats.built) + 1
	stats.enabled = int(stats.built) > 0
	return stats
