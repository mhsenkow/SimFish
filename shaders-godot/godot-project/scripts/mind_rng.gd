class_name MindRng
extends RefCounted

# META_ENGINEERING #15 / #31 — per-entity streams into the sim RNG authority.

const SimRngScript = preload("res://scripts/sim_rng.gd")


static func sim_rng(sim: Node) -> Variant:
	if sim == null:
		return null
	return sim.get("rng")


static func entity_id(entity: Node) -> String:
	if entity == null:
		return "null"
	if entity.get("id") != null:
		var sid: String = String(entity.id)
		if sid.strip_edges() != "":
			return sid
	return "inst_%d" % entity.get_instance_id()


static func stream(sim: Node, entity_id_key: String, base: String) -> RandomNumberGenerator:
	var master: Variant = sim_rng(sim)
	var name: String = SimRngScript.entity_stream_name(base, entity_id_key)
	if master != null:
		return master.stream(name)
	var fb := RandomNumberGenerator.new()
	fb.seed = SimRngScript.stream_seed(0xCAFEF155, name)
	return fb


static func for_fish(f: Node, base: String = SimRngScript.STREAM_COGNITION) -> RandomNumberGenerator:
	if f == null:
		var fb := RandomNumberGenerator.new()
		fb.seed = SimRngScript.stream_seed(0xCAFEF155, base)
		return fb
	var sim: Node = f.get("sim") as Node
	return stream(sim, entity_id(f), base)


static func golden_sample(f: Node, n: int = 4) -> PackedFloat32Array:
	var rng: RandomNumberGenerator = for_fish(f)
	var out: PackedFloat32Array = PackedFloat32Array()
	for _i in n:
		out.append(rng.randf())
	return out
