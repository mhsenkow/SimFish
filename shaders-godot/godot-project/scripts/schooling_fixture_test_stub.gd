extends RefCounted

# Deterministic mixed schooling fixtures; no scene construction or brain ticks.
class FishRef extends Node:
	var partner: Node = null

static func prepare(n: int) -> void:
	MindBoidsBuffer.reset_for_test()
	MindBoidsBuffer._trim(n)
	MindBoidsBuffer.count = n
	for i in n:
		var f := FishRef.new()
		MindBoidsBuffer.fish_refs[i] = f
		var p := Vector3(sin(i * 1.37) * 4.0, sin(i * 0.71) * 1.5, cos(i * 2.31) * 4.0)
		MindBoidsBuffer.positions[i] = p
		MindBoidsBuffer.velocities[i] = Vector3(cos(i * 0.71), sin(i * 0.43) * 0.12, sin(i * 0.71)) * (0.2 + (i % 6) * 0.17)
		MindBoidsBuffer.headings[i] = Vector3.ZERO if i % 17 == 0 else MindBoidsBuffer.velocities[i].normalized()
		MindBoidsBuffer.species_hash[i] = i % 3
		MindBoidsBuffer.home_y_radii[i] = 0.3 + (i % 4) * 0.2
		MindBoidsBuffer.separation_radii[i] = 0.45 + (i % 5) * 0.1
		MindBoidsBuffer.swim_topo[i] = 0 if i % 5 == 0 else 1
	for i in n:
		if i % 4 == 0 and i + 3 < n:
			MindBoidsBuffer.fish_refs[i].partner = MindBoidsBuffer.fish_refs[i + 3]
	if n >= 2:
		MindBoidsBuffer.positions[1] = MindBoidsBuffer.positions[0]

static func snapshot() -> Array:
	var result: Array = []
	for i in MindBoidsBuffer.count:
		var row: Array = []
		for v: Vector3 in [MindBoidsBuffer.sep_accum[i], MindBoidsBuffer.ali_accum[i], MindBoidsBuffer.coh_center[i]]:
			row.append_array([v.x, v.y, v.z])
		row.append_array([MindBoidsBuffer.neighbor_counts[i], MindBoidsBuffer.school_speed_milli[i]])
		for slot in MindBoidsBuffer.N_TOPO:
			row.append(MindBoidsBuffer.topo_neighbor_at(i, slot))
		result.append(row)
	return result

static func release() -> void:
	for f: Node in MindBoidsBuffer.fish_refs:
		f.free()
	MindBoidsBuffer.reset_for_test()
