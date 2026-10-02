extends SceneTree

# Holistic #121 — one meal through the food web: named transfers, no silent
# duplicate of leftover into produced, no whole-meal "lost" on tiny heat.

const FoodWebTraceScript = preload("res://scripts/food_web_trace.gd")
const SimDriverScript = preload("res://scripts/sim_driver.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var t := TestSupport.Suite.new("smoke_food_web_trace")

	var trace = FoodWebTraceScript.new()
	var chain: int = trace.begin_chain("spawn_player_food", 2.0, 1)
	t.check(chain > 0, "begin_chain returns id")
	trace.record(chain, FoodWebTraceScript.STAGE_CONSUME, 2.0, "guppy")
	trace.record(chain, FoodWebTraceScript.STAGE_ABSORB, 1.2, "eater")
	trace.record(chain, FoodWebTraceScript.STAGE_METABOLIC_WASTE, 0.8, "excrete")
	trace.record(chain, FoodWebTraceScript.STAGE_SETTLE_DEPOSIT, 0.8, "substrate")
	trace.record(chain, FoodWebTraceScript.STAGE_PLANT_UPTAKE, 0.3, "Plant")
	trace.record(chain, FoodWebTraceScript.STAGE_DOCUMENTED_LOSS, 0.0, "none")
	var stages: Dictionary = {}
	for ev in trace.recent_events(20):
		stages[String(ev.get("stage", ""))] = true
	for need in ["spawn", "consume", "absorb", "metabolic_waste",
			"settle_deposit", "plant_uptake"]:
		t.check(stages.has(need), "chain names stage %s" % need)
	var summary: Dictionary = trace.chain_summary(chain)
	t.approx(float(summary.get("spawned", 0.0)), 2.0, "spawned booked once")
	t.approx(float(summary.get("absorbed", 0.0)), 1.2, "absorb booked")
	t.approx(float(summary.get("deposited", 0.0)), 0.8, "deposit booked")
	t.approx(float(summary.get("uptake", 0.0)), 0.3, "uptake booked")
	var gap: float = FoodWebTraceScript.conservation_gap(summary, 0.0)
	t.approx(gap, 0.0, "spawned equals absorbed+deposited+lost (uptake ⊂ deposit)")
	t.check(float(summary.get("uptake", 0.0)) <= float(summary.get("deposited", 0.0)) + 0.001,
		"plant uptake does not exceed deposited pool")

	# Ledger math: leftover must not double-count as produced.
	var sim: SimDriver = SimDriverScript.new()
	root.add_child(sim)
	sim.trophic_ledger = {
		"produced": 0.0, "consumed": 0.0, "absorbed": 0.0,
		"deposited": 0.0, "lost": 0.0,
	}
	sim._record_trophic_produced(1.0)
	sim._record_trophic_consumed(1.0, 0.4)  # leftover will re-enter via spawn
	t.approx(float(sim.trophic_ledger["produced"]), 1.0,
		"consumed leftover is NOT silently re-added to produced")
	t.approx(float(sim.trophic_ledger["absorbed"]), 0.6,
		"absorbed excludes open leftover")
	t.approx(float(sim.trophic_ledger.get("lost", 0.0)), 0.0,
		"open leftover is not marked lost")
	# Tiny heat loss documents only the residue, not the whole meal.
	sim._record_trophic_consumed(1.0, 0.03)
	t.approx(float(sim.trophic_ledger["lost"]), 0.03,
		"documented_loss is the heat residue only")
	t.approx(float(sim.trophic_ledger["absorbed"]), 0.6 + 0.97,
		"absorbed keeps the eaten portion")

	sim.queue_free()
	quit(t.finish())
