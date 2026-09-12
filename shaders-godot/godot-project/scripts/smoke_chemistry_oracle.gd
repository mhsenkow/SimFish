extends SceneTree

# Chemistry oracle — the GDScript half (docs/CHEMISTRY_ORACLE.md).
#
# `sim-rust/` is an independent implementation of this tank's water chemistry.
# The two are NOT numerically comparable — GDScript is well-mixed and
# game-tuned, Rust is a 2D grid in lumped mg/L — so nothing here compares
# values against the crate. What both must agree on is CURVE SHAPE, and the
# invariant IDs below are the same IDs asserted in
# `sim-rust/src/chemistry.rs`. A failure on either side points at one claim.
#
# This exists because writing the Rust half found that the crate had silently
# stopped reproducing its own documented nitrogen cycle. An invariant nobody
# checks is a comment (ADR 003).

const DAY_S: float = 864.0   # WaterChemistry.SIM_DAY_S
# Sim-seconds between cycle samples. The nitrite peak lands around t=16 s, so
# this has to be fine or the spike is missed entirely.
const SAMPLE_INTERVAL_S: float = 2.0
const CYCLE_SAMPLES: int = 40


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_chemistry_oracle")

	# ---- N1 / N2 / N3 / N4 : the nitrogen cycle ----
	var series: Array[Dictionary] = _run_cycle(CYCLE_SAMPLES)
	t.check(series.size() == CYCLE_SAMPLES, "cycle sampler produced its samples")

	var nh4: Array[float] = []
	var no2: Array[float] = []
	var no3: Array[float] = []
	for row in series:
		nh4.append(float(row["ammonia"]))
		no2.append(float(row["nitrite"]))
		no3.append(float(row["nitrate"]))

	# N1 — ammonia introduced into a cycling tank is consumed.
	var nh4_peak: float = _max(nh4)
	t.check(nh4[nh4.size() - 1] < nh4_peak * 0.5,
		"N1: ammonia must be consumed — peak %.4f, final %.4f"
			% [nh4_peak, nh4[nh4.size() - 1]])

	# N2 — nitrite rises THEN falls: a peak strictly inside the window.
	var no2_peak_i: int = _argmax(no2)
	var no2_peak: float = no2[no2_peak_i]
	t.check(no2_peak_i > 0 and no2_peak_i < no2.size() - 1,
		"N2: nitrite peaked at the window edge (day %d) — that is a ramp, "
			% no2_peak_i + "not a spike")
	t.check(no2_peak > no2[0],
		"N2: nitrite peak %.5f must exceed its start %.5f" % [no2_peak, no2[0]])
	t.check(no2[no2.size() - 1] < no2_peak * 0.8,
		"N2: nitrite must come back down — peak %.5f, final %.5f"
			% [no2_peak, no2[no2.size() - 1]])

	# N3 — nitrate accumulates while nitrification runs.
	t.check(no3[no3.size() - 1] > no3[0],
		"N3: nitrate must accumulate — %.4f -> %.4f" % [no3[0], no3[no3.size() - 1]])

	# N4 — the nitrite peak comes after the ammonia peak. Ordering is what
	# makes this a cycle rather than three unrelated curves.
	t.check(no2_peak_i >= _argmax(nh4),
		"N4: nitrite peaked on day %d but ammonia peaked on day %d — "
			% [no2_peak_i, _argmax(nh4)] + "nitrite must not lead ammonia")

	# ---- O1 / O2 : oxygen ----
	# O1 — aeration raises dissolved O2. GDScript keeps O2 on SimDriver as a
	# normalised 0..1 level rather than mg/L, so this is the same claim in
	# different units.
	var still: float = _run_o2(0.0)
	var bubbled: float = _run_o2(1.0)
	t.check(bubbled >= still,
		"O1: aeration must not lower oxygen — still %.4f, aerated %.4f"
			% [still, bubbled])
	# NB: dissolved_o2 is NOT normalised 0..1 despite reading like a fraction
	# elsewhere — it settles above 1.0 under aeration. Assert it stays sane
	# rather than inventing a range the model does not hold to.
	t.check(bubbled > 0.0 and bubbled < 10.0,
		"O1: oxygen must stay in a sane range, got %.4f" % bubbled)

	# O2 — an ammonia load must not RAISE oxygen. (The GDScript model couples
	# these loosely, so this is deliberately the weak form of the Rust claim.)
	var o2_clean: float = _run_o2_under_load(0.0)
	var o2_loaded: float = _run_o2_under_load(1.5)
	t.check(o2_loaded <= o2_clean + 0.02,
		"O2: an ammonia load must not raise oxygen — clean %.4f, loaded %.4f"
			% [o2_clean, o2_loaded])

	# ---- P1 / P2 : pH ----
	# P1 — pH falls as CO2 rises, at fixed KH.
	var ph_low_co2: float = _settle_ph(4.0, 0.1)
	var ph_high_co2: float = _settle_ph(4.0, 1.2)
	t.check(ph_high_co2 < ph_low_co2,
		"P1: more CO2 must mean lower pH — low-CO2 %.3f, high-CO2 %.3f"
			% [ph_low_co2, ph_high_co2])

	# P2 — KH buffers: soft water swings more for the same CO2 change.
	var soft_swing: float = absf(_settle_ph(1.0, 0.1) - _settle_ph(1.0, 1.2))
	var hard_swing: float = absf(_settle_ph(12.0, 0.1) - _settle_ph(12.0, 1.2))
	t.check(soft_swing >= hard_swing,
		"P2: soft water (KH 1) must swing at least as much as hard (KH 12) — "
			+ "soft %.4f, hard %.4f" % [soft_swing, hard_swing])

	quit(t.finish())


# ---- Harness ----

# Run a fresh tank, sampling the cycle.
#
# TIMESTEP MATTERS. This chemistry is tuned for SimDriver.SIM_DT and does not
# sub-step, so ticking it with a big dt saturates every rate in one step and
# the whole curve collapses to its steady state. (The Rust crate had the same
# class of bug in its diffusion — see ADR 003.) Tick at SIM_DT.
#
# SAMPLE FAST. The GDScript model is game-tuned rather than physical: the
# whole cycle completes in ~80 sim SECONDS, not the 60 sim days the Rust
# reference takes. Sampling daily shows a flat line at steady state.
func _run_cycle(samples: int) -> Array[Dictionary]:
	var sim := SimDriver.new()
	root.add_child(sim)
	var chem = sim.water_chemistry
	chem.apply_fresh_start()
	# A fresh ammonia dose — the "ghost feeding" the Rust starter tank does.
	chem.ammonia = 2.0
	var dt: float = SimDriver.SIM_DT
	var per_sample: int = maxi(1, int(SAMPLE_INTERVAL_S / dt))
	var out: Array[Dictionary] = []
	for _s in samples:
		for _i in per_sample:
			sim.tank_age_s += dt
			chem.tick(dt, sim, null, 40, 0.02)
		out.append({
			"ammonia": chem.ammonia,
			"nitrite": chem.nitrite,
			"nitrate": chem.nitrate,
		})
	sim.queue_free()
	return out


func _run_o2(aeration: float) -> float:
	var sim := SimDriver.new()
	root.add_child(sim)
	sim.dissolved_o2 = 0.2
	# Aeration is two rates on SimDriver, not one scalar.
	sim.aeration_air_rate = aeration
	sim.aeration_flow_rate = aeration * 0.25
	for _i in 200:
		sim.tank_age_s += 5.0
		sim._tick(SimDriver.SIM_DT)
	var v: float = sim.dissolved_o2
	sim.queue_free()
	return v


func _run_o2_under_load(ammonia: float) -> float:
	var sim := SimDriver.new()
	root.add_child(sim)
	sim.dissolved_o2 = 0.8
	sim.water_chemistry.ammonia = ammonia
	for _i in 200:
		sim.tank_age_s += 5.0
		sim._tick(SimDriver.SIM_DT)
	var v: float = sim.dissolved_o2
	sim.queue_free()
	return v


# Settle pH for a given KH and CO2 target, then read it.
func _settle_ph(kh: float, co2: float) -> float:
	var sim := SimDriver.new()
	root.add_child(sim)
	var chem = sim.water_chemistry
	chem.apply_established_start()
	chem.kh = kh
	for _i in 400:
		chem.dissolved_co2 = co2
		sim.tank_age_s += 5.0
		chem.tick(5.0, sim, null, 40, 0.0)
	var v: float = chem.ph
	sim.queue_free()
	return v


func _max(a: Array[float]) -> float:
	var m: float = -1e30
	for v in a:
		m = maxf(m, v)
	return m


func _argmax(a: Array[float]) -> int:
	var best: int = 0
	for i in a.size():
		if a[i] > a[best]:
			best = i
	return best
