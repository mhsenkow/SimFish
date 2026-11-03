extends SceneTree

# SENTIENCE_THE_LOOM_THAT_THINKS #176–#178 — homeostasis live, breath in EFE, felt O₂.


const MindCycle = preload("res://scripts/mind_cycle.gd")
const MindActiveInference = preload("res://scripts/mind_active_inference.gd")
const FishProtoself = preload("res://scripts/fish_protoself.gd")
const FishHomeostasis = preload("res://scripts/fish_homeostasis.gd")


class FakeChem:
	extends RefCounted
	var ammonia: float = 0.0
	var nitrite: float = 0.0

	func toxic_ammonia_level() -> float:
		return ammonia


class FakeSim:
	extends Node
	var dissolved_o2: float = 1.0
	var water_chemistry: FakeChem = FakeChem.new()


func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_loom_body_awareness")
	var sim := FakeSim.new()
	root.add_child(sim)

	var f: Fish = Fish.new()
	root.add_child(f)
	f.id = "loom-body-1"
	f.sim = sim
	f.hunger = 0.4
	f.energy = 0.9
	f.stress = 0.1
	f._chem_o2_penalty = 0.0

	# --- #176: perceive phase ticks homeostasis ---
	var h0: Dictionary = FishHomeostasis.ensure(f)
	h0["prev_hunger"] = 0.2
	f._homeostasis = h0
	f.hunger = 0.5
	MindCycle.run_perceive_phase(f, sim, null, 0.2)
	var h1: Dictionary = FishHomeostasis.ensure(f)
	t.check(absf(float(h1.get("hunger_trend", 0.0))) > 0.01,
			"homeostasis hunger_trend updates in perceive (#176)")
	t.check(f.get("_homeostatic_feed_point") != null,
			"homeostatic feed point written (#176)")

	# --- #177: breath enters preferred_error / pragmatic value ---
	sim.dissolved_o2 = 0.35
	FishHomeostasis.ensure(f)["o2_set"] = 0.8
	var pe: Dictionary = MindActiveInference.preferred_error(f)
	t.check(pe.has("breath"), "preferred_error includes breath (#177)")
	t.check(float(pe.get("breath", 0.0)) > 0.3,
			"thin water raises breath error (#177)")
	var prag: float = MindActiveInference.pragmatic_value(f, "surface")
	t.check(prag > 0.3, "surface bid has pragmatic breath value (#177)")
	# Rich water → breath near zero.
	sim.dissolved_o2 = 1.0
	var pe_ok: Dictionary = MindActiveInference.preferred_error(f)
	t.check(float(pe_ok.get("breath", 1.0)) < 0.15,
			"rich water keeps breath error low (#177)")

	# --- #178: thin water (no nitrite) moves felt gills via breath hunger ---
	sim.dissolved_o2 = 0.3
	sim.water_chemistry.nitrite = 0.0
	sim.water_chemistry.ammonia = 0.0
	f._chem_o2_penalty = 0.0
	FishProtoself.tick(f, sim, 1.0)
	FishProtoself.tick(f, sim, 1.0)
	t.check(float(f._breath_hunger) > 0.3,
			"thin water sets _breath_hunger without nitrite (#178)")
	t.check(float(f._gill_burn) < 0.1,
			"no chem → gill burn stays quiet (#178)")
	var pb: Dictionary = FishProtoself.ensure(f)
	t.check(float(pb.get("gill_rhythm", 0.0)) > 0.4,
			"felt gill_rhythm rises with breath hunger (#178)")

	# Nitrite sting alone raises gill burn even in oxygenated water.
	sim.dissolved_o2 = 1.0
	f._chem_o2_penalty = 0.2
	sim.water_chemistry.ammonia = 0.15
	FishProtoself.tick(f, sim, 1.0)
	FishProtoself.tick(f, sim, 1.0)
	t.check(float(f._gill_burn) > 0.15,
			"nitrite/ammonia raise _gill_burn (#178)")

	f.queue_free()
	sim.queue_free()
	quit(t.finish())
