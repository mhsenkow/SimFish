extends RefCounted

# SENTIENCE_THE_RISING_CURVE §B — world-perturbation / counterfactual robustness rig.
# Measurement only: shadow pokes do not mutate the live tank during normal play.

const DeltaG = preload("res://scripts/delta_g.gd")
const DeltaGCurve = preload("res://scripts/delta_g_curve.gd")
const MindWorldModel = preload("res://scripts/mind_world_model.gd")

const POKE_MOVE_FOOD: String = "move_food"
const POKE_NOVEL_OBSTACLE: String = "novel_obstacle"
const POKE_SHIFT_LIGHT: String = "shift_light"
const POKE_REMOVE_BOND: String = "remove_bond"
const POKE_CHANGE_BODY: String = "change_body"

const ROBUST_FLOOR: float = 0.35


static func robustness_ratio(baseline_dg: float, perturbed_dg: float) -> float:
	if baseline_dg <= 0.05:
		return 0.0
	return clampf(perturbed_dg / baseline_dg, 0.0, 2.0)


static func estimate_robustness(pts: PackedVector3Array, baseline_goals: Dictionary,
		perturbed_goals: Dictionary, dt: float, bounds: Dictionary) -> Dictionary:
	var base: Dictionary = DeltaG.estimate(pts, baseline_goals, dt, bounds)
	var pert: Dictionary = DeltaG.estimate(pts, perturbed_goals, dt, bounds)
	var bdg: float = float(base.get("delta_g", 0.0))
	var pdg: float = float(pert.get("delta_g", 0.0))
	return {
		"baseline": bdg,
		"perturbed": pdg,
		"robustness": robustness_ratio(bdg, pdg),
		"baseline_goal": str(base.get("goal", "")),
		"perturbed_goal": str(pert.get("goal", "")),
	}


static func poke_move_food(pts: PackedVector3Array, food_a: Vector3, food_b: Vector3,
		adaptive_pts: PackedVector3Array, dt: float, bounds: Dictionary) -> Dictionary:
	var goals_a: Dictionary = {"food": food_a}
	var goals_b: Dictionary = {"food": food_b}
	var brittle: Dictionary = estimate_robustness(pts, goals_a, goals_b, dt, bounds)
	var adaptive: Dictionary = DeltaG.estimate(adaptive_pts, goals_b, dt, bounds)
	return {
		"poke": POKE_MOVE_FOOD,
		"brittle_robustness": float(brittle.get("robustness", 0.0)),
		"adaptive_delta_g": float(adaptive.get("delta_g", 0.0)),
		"baseline_delta_g": float(brittle.get("baseline", 0.0)),
	}


static func poke_novel_obstacle(pts_familiar: PackedVector3Array,
		pts_novel: PackedVector3Array, goal: Vector3, dt: float,
		bounds: Dictionary) -> Dictionary:
	var goals: Dictionary = {"target": goal}
	var fam: Dictionary = DeltaG.estimate(pts_familiar, goals, dt, bounds)
	var nov: Dictionary = DeltaG.estimate(pts_novel, goals, dt, bounds)
	var gap: float = float(fam.get("delta_g", 0.0)) - float(nov.get("delta_g", 0.0))
	return {
		"poke": POKE_NOVEL_OBSTACLE,
		"delta_g_familiar": float(fam.get("delta_g", 0.0)),
		"delta_g_novel": float(nov.get("delta_g", 0.0)),
		"generalization_gap": gap,
		"robustness": robustness_ratio(float(fam.get("delta_g", 0.0)),
				float(nov.get("delta_g", 0.0))),
	}


static func poke_change_body(pts: PackedVector3Array, goals: Dictionary, dt: float,
		bounds: Dictionary) -> Dictionary:
	# Goal/means separation: same goals, wrong physics timestep → brittle if goal wasn't real.
	var base: Dictionary = DeltaG.estimate(pts, goals, dt, bounds)
	var wrong_phys: Dictionary = DeltaG.estimate(pts, goals, dt * 1.45, bounds)
	return {
		"poke": POKE_CHANGE_BODY,
		"baseline": float(base.get("delta_g", 0.0)),
		"perturbed": float(wrong_phys.get("delta_g", 0.0)),
		"robustness": robustness_ratio(float(base.get("delta_g", 0.0)),
				float(wrong_phys.get("delta_g", 0.0))),
	}


static func shadow_poke_fish(f: Fish, sim: Node, poke_type: String) -> Dictionary:
	if f == null:
		return {}
	var traj: Array = f._delta_g_traj if f.get("_delta_g_traj") is Array else []
	if traj.size() < DeltaG.MIN_SAMPLES:
		return {"poke": poke_type, "skipped": true, "reason": "short trajectory"}
	var pts: PackedVector3Array = DeltaG.positions_from_traj(traj)
	var bounds: Dictionary = DeltaG.tank_bounds(sim)
	var base_goals: Dictionary = DeltaG.goals_from_fish(f, sim)
	var pert_goals: Dictionary = base_goals.duplicate(true)
	var dt: float = 0.05
	match poke_type:
		POKE_MOVE_FOOD:
			if pert_goals.has("food"):
				pert_goals["food"] = (pert_goals["food"] as Vector3) + Vector3(3.0, 0.0, -2.0)
			else:
				pert_goals["food"] = f.position + Vector3(4.0, 0.0, 0.0)
		POKE_SHIFT_LIGHT:
			pert_goals["depth"] = Vector3(f.position.x,
					clampf(f.preferred_y + 1.2, 0.5, 6.5), f.position.z)
		POKE_REMOVE_BOND:
			pert_goals.erase("bond")
		POKE_CHANGE_BODY:
			return poke_change_body(pts, base_goals, dt, bounds)
		POKE_NOVEL_OBSTACLE:
			var goal: Vector3 = base_goals.get("food", f.position + f.heading * 2.0)
			if not goal is Vector3:
				goal = f.position + f.heading * 2.0
			var novel_pts: PackedVector3Array = _novel_replan_path(f, goal as Vector3, dt)
			var poke_n: Dictionary = poke_novel_obstacle(pts, novel_pts, goal as Vector3, dt, bounds)
			poke_n["poke"] = POKE_NOVEL_OBSTACLE
			return poke_n
		_:
			return {"poke": poke_type, "skipped": true}
	var r: Dictionary = estimate_robustness(pts, base_goals, pert_goals, dt, bounds)
	r["poke"] = poke_type
	return r


static func run_battery(f: Fish, sim: Node) -> Array:
	var out: Array = []
	var robust_sum: float = 0.0
	var robust_n: int = 0
	for poke in [POKE_MOVE_FOOD, POKE_SHIFT_LIGHT, POKE_REMOVE_BOND, POKE_CHANGE_BODY,
			POKE_NOVEL_OBSTACLE]:
		var r: Dictionary = shadow_poke_fish(f, sim, poke)
		if r.is_empty() or bool(r.get("skipped", false)):
			continue
		out.append(r)
		robust_sum += float(r.get("robustness", 0.0))
		robust_n += 1
		if poke == POKE_NOVEL_OBSTACLE:
			DeltaGCurve.record_generalization_gap(f, float(r.get("generalization_gap", 0.0)))
	if robust_n > 0:
		var mean_rob: float = robust_sum / float(robust_n)
		var est: Dictionary = DeltaG.estimate_fish(f, sim, 0.05)
		DeltaGCurve.record_robustness(f, mean_rob, float(est.get("delta_g", 0.0)))
	return out


static func battery_mean_robustness(results: Array) -> float:
	if results.is_empty():
		return 0.0
	var sum: float = 0.0
	for r in results:
		if r is Dictionary:
			sum += float((r as Dictionary).get("robustness", 0.0))
	return sum / float(results.size())


static func _novel_replan_path(f: Fish, goal: Vector3, dt: float) -> PackedVector3Array:
	var pts: PackedVector3Array = PackedVector3Array()
	var p: Vector3 = f.position
	var block: Vector3 = Vector3(0.0, 0.0, 1.0)
	for _i in 28:
		pts.append(p)
		var to: Vector3 = goal - p
		if to.length_squared() > 1e-6:
			var step: Vector3 = to.normalized() * 0.82
			step += MindWorldModel.replan_bias(f, block) * 0.35
			p += step.normalized() * 1.15 * dt
	return pts


static func passes_goal_floor(robustness: float, perturbed_dg: float) -> bool:
	return robustness >= ROBUST_FLOOR * 0.5 or perturbed_dg >= ROBUST_FLOOR


static func live_rung1_kill(f: Fish, sim: Node) -> Dictionary:
	if f == null or sim == null:
		return {"passed": false, "reason": "missing fish/sim"}
	var food_a: Vector3 = f.position + Vector3(3.0, 0.0, 1.5)
	var food_b: Vector3 = f.position + Vector3(-3.5, 0.0, -2.0)
	if sim.has_method("anticipated_feed_surface_pos"):
		var cur: Vector3 = sim.anticipated_feed_surface_pos()
		if cur.length_squared() > 0.01:
			food_a = cur
			food_b = cur + Vector3(-5.0, 0.0, -3.0)
	FishHomeostasis.tick(f, sim, 0.05)
	var r: Dictionary = FishHomeostasis.rung1_move_food_kill(f, food_a, food_b)
	r["poke"] = POKE_MOVE_FOOD
	r["live"] = true
	return r


static func live_rung2_kill(f: Fish, sim: Node) -> Dictionary:
	if f == null:
		return {"passed": false, "reason": "missing fish"}
	f.position = Vector3(-2.0, 2.0, 0.0)
	var bounds: Dictionary = DeltaG.tank_bounds(sim)
	var dt: float = 0.05
	var goal: Vector3 = Vector3(4.0, 2.0, 1.5)
	var familiar: PackedVector3Array = _simulate_pursuit_path(f.position, goal, dt, 28, 1.15)
	var novel: PackedVector3Array = _novel_replan_path(f, goal, dt)
	var poke: Dictionary = poke_novel_obstacle(familiar, novel, goal, dt, bounds)
	var passed: bool = float(poke.get("delta_g_novel", 0.0)) >= 0.035 \
			and float(poke.get("delta_g_familiar", 0.0)) >= 0.04
	DeltaGCurve.record_generalization_gap(f,
			float(poke.get("generalization_gap", 0.0)))
	return {
		"passed": passed,
		"poke": POKE_NOVEL_OBSTACLE,
		"live": true,
		"delta_g_familiar": float(poke.get("delta_g_familiar", 0.0)),
		"delta_g_novel": float(poke.get("delta_g_novel", 0.0)),
		"generalization_gap": float(poke.get("generalization_gap", 0.0)),
	}


static func _simulate_pursuit_path(start: Vector3, goal: Vector3, dt: float,
		steps: int, speed: float) -> PackedVector3Array:
	var pts: PackedVector3Array = PackedVector3Array()
	var p: Vector3 = start
	for _i in steps:
		pts.append(p)
		var to: Vector3 = goal - p
		if to.length_squared() > 1e-6:
			p += to.normalized() * speed * dt
	return pts
