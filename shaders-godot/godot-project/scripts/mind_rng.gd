class_name MindRng
extends RefCounted

# META_ENGINEERING #15 / #31 — per-entity streams into the sim RNG authority.

const SimRngScript = preload("res://scripts/sim_rng.gd")


static func sim_rng(sim: Node) -> Variant:
	if sim == null:
		return null
	return sim.get("rng")


static func entity_id(entity) -> String:
	if entity == null:
		return "null"
	if entity.get("id") != null:
		var sid: String = str(entity.id)
		if sid.strip_edges() != "":
			return sid
	if entity is Object and (entity as Object).has_method("get_instance_id"):
		return "inst_%d" % (entity as Object).get_instance_id()
	return "anon_%d" % hash(str(entity))


static func stream(sim: Node, entity_id_key: String, base: String) -> RandomNumberGenerator:
	var master: Variant = sim_rng(sim)
	var name: String = SimRngScript.entity_stream_name(base, entity_id_key)
	if master != null:
		return master.stream(name)
	var fb := RandomNumberGenerator.new()
	fb.seed = SimRngScript.stream_seed(0xCAFEF155, name)
	return fb


static func stream_for_tick(sim: Node, entity_id_key: String, base: String, tick_index: int) -> RandomNumberGenerator:
	var keyed: String = "%s|t%d" % [entity_id_key, tick_index]
	return stream(sim, keyed, base)


static func for_fish(f, base: String = SimRngScript.STREAM_COGNITION) -> RandomNumberGenerator:
	if f == null:
		var fb := RandomNumberGenerator.new()
		fb.seed = SimRngScript.stream_seed(0xCAFEF155, base)
		return fb
	var sim: Variant = f.get("sim") if f is Object else null
	var eid: String = entity_id(f)
	if sim is Node:
		return stream(sim as Node, eid, base)
	var local := RandomNumberGenerator.new()
	local.seed = SimRngScript.stream_seed(0xCAFEF155, "%s|%s" % [base, eid])
	return local


static func for_fish_tick(f, base: String = SimRngScript.STREAM_COGNITION) -> RandomNumberGenerator:
	if f == null:
		return for_fish(f, base)
	var sim: Variant = f.get("sim") if f is Object else null
	if sim is Node and sim.get("_mind_tick_index") != null:
		return stream_for_tick(sim as Node, entity_id(f), base, int(sim._mind_tick_index))
	return for_fish(f, base)


static func golden_sample(f: Node, n: int = 4) -> PackedFloat32Array:
	var rng: RandomNumberGenerator = for_fish(f)
	var out: PackedFloat32Array = PackedFloat32Array()
	for _i in n:
		out.append(rng.randf())
	return out
