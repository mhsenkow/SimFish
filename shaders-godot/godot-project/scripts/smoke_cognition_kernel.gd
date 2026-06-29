extends SceneTree

# META #11 + #15 + #31 — cognition kernel + deterministic mind RNG.

const SimStubScript = preload("res://scripts/smoke_sim_stub.gd")
const FishMind = preload("res://scripts/fish_mind.gd")
const FishScript = preload("res://scripts/fish.gd")


func _initialize() -> void:
	if not _run_all():
		quit(1)
		return
	print("[smoke_cognition_kernel] OK")
	quit(0)


func _fail(msg: String) -> bool:
	push_error(msg)
	return false


func _run_all() -> bool:
	var sim_a: Node = SimStubScript.new()
	sim_a.rng.reset(42)
	var sim_b: Node = SimStubScript.new()
	sim_b.rng.reset(42)
	var f_a: Fish = FishScript.new()
	f_a.id = "golden-fish"
	f_a.sim = sim_a
	var f_b: Fish = FishScript.new()
	f_b.id = "golden-fish"
	f_b.sim = sim_b
	var s_a: PackedFloat32Array = MindRng.golden_sample(f_a, 6)
	var s_b: PackedFloat32Array = MindRng.golden_sample(f_b, 6)
	if s_a.size() != s_b.size():
		return _fail("golden sample size mismatch")
	for i in s_a.size():
		if s_a[i] != s_b[i]:
			return _fail("cognition stream must be deterministic for same seed+id")
	f_a._delib_active = true
	f_a._delib_decided = false
	f_a._delib_ev_approach = 0.0
	f_a._delib_ev_avoid = 0.0
	f_a._delib_phase = 0.0
	FishMind.tick_ddm(f_a, 0.1, 0.6, 0.55, sim_a)
	var f_dup: Fish = FishScript.new()
	f_dup.id = "golden-fish"
	f_dup.sim = sim_b
	f_dup._delib_active = true
	f_dup._delib_decided = false
	f_dup._delib_ev_approach = 0.0
	f_dup._delib_ev_avoid = 0.0
	f_dup._delib_phase = 0.0
	FishMind.tick_ddm(f_dup, 0.1, 0.6, 0.55, sim_a)
	if absf(f_a._delib_ev_approach - f_dup._delib_ev_approach) > 0.0001:
		return _fail("DDM must be deterministic with seeded cognition RNG")
	f_dup.free()
	var ms: MindState = MindState.new()
	ms.sync_from_fish(f_a)
	var percept := CognitionKernel.Percept.new()
	percept.dt = 0.1
	percept.sim = sim_a
	CognitionKernel.tick(f_a, ms, percept)
	sim_a.free()
	sim_b.free()
	return true
