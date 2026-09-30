extends SceneTree

# Hair-algae mound renderer (scripts/hair_mound.gd): one batch, strands on a
# dome over the host, deterministic from the seed.

const HairMoundScript := preload("res://scripts/hair_mound.gd")


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_hair_mound")
	var host := Node3D.new()
	root.add_child(host)
	var centers: Array = [Vector3(0.0, 2.0, 0.0), Vector3(3.0, 1.5, -1.0)]
	var radii: Array = [0.9, 0.7]
	var a: Node3D = HairMoundScript.new()
	host.add_child(a)
	a.build(centers, radii, 4242)
	var b: Node3D = HairMoundScript.new()
	host.add_child(b)
	b.build(centers, radii, 4242)
	var n: int = a.instance_count()
	t.in_range(float(n), float(HairMoundScript.STRANDS_PER_MOUND * 2 * 5),
		float(HairMoundScript.STRANDS_PER_MOUND * 2 * 9), "every strand lays 5-9 segments")
	t.equals(b.instance_count(), n, "same seed, same mound")
	var ba: VoxelBatch = a._batch
	var bb: VoxelBatch = b._batch
	var same: bool = true
	var on_dome: bool = true
	var worst: String = ""
	for i in n:
		var oa: Vector3 = (ba._xforms[i] as Transform3D).origin
		if oa.distance_to((bb._xforms[i] as Transform3D).origin) > 1e-5:
			same = false
		var near: float = minf(oa.distance_to(centers[0]), oa.distance_to(centers[1]))
		if near > 2.2 or oa.y < 1.5 - 0.7:
			on_dome = false
			worst = "i=%d origin=%s near=%.2f" % [i, oa, near]
	t.check(same, "strand layout is deterministic")
	t.check(on_dome, "strands stay on their dome, above the host top %s" % worst)
	a.build(centers, radii, 99)
	t.check(a.instance_count() <= HairMoundScript.STRANDS_PER_MOUND * 2 * 9,
		"a rebuild replaces rather than stacks (%d)" % a.instance_count())
	quit(t.finish())
