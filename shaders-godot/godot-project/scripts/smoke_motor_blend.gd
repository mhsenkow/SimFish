extends SceneTree

# META #9 / Tier-1 — multi-goal motor blending. When the Global Workspace
# co-ignites >1 goal, GlobalWorkspace.blend_behavior_bias synthesizes one
# salience-weighted "skirt" vector instead of steering from the primary alone.
# Verifies: single-winner behavior is preserved, co-ignition blends BOTH goals,
# and broadcast() routes co-ignition through the blend.

const GlobalWorkspace = preload("res://scripts/global_workspace.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	var f: Fish = Fish.new()
	root.add_child(f)
	f.id = "blend"
	f.heading = Vector3(1, 0, 0)   # threat bias = -heading = -X; food bias = +Y

	# --- Single winner: blend reduces exactly to the single-goal bias.
	var food_only := [{"label": "food", "salience": 0.8}]
	var food_bias: Vector3 = GlobalWorkspace._bias_for(f, "food", 0.8)
	GlobalWorkspace.blend_behavior_bias(f, food_only)
	_assert(failed, f._behavior_ws_bias.is_equal_approx(food_bias),
			"single-winner blend == single-goal bias (behavior preserved)")

	# --- Co-ignition (food + threat): the skirt vector carries BOTH goals.
	var threat_bias: Vector3 = GlobalWorkspace._bias_for(f, "threat", 0.6)
	_assert(failed, food_bias.y > 0.0, "food bias pulls toward surface (+Y)")
	_assert(failed, threat_bias.x < 0.0, "threat bias leans away from heading (-X)")

	var coignite := [{"label": "food", "salience": 0.8}, {"label": "threat", "salience": 0.6}]
	GlobalWorkspace.blend_behavior_bias(f, coignite)
	var b: Vector3 = f._behavior_ws_bias
	_assert(failed, _finite(b), "blended bias is finite")
	_assert(failed, b.y > 0.0, "blend keeps the food pull (+Y) — still heading for food")
	_assert(failed, b.x < 0.0, "blend folds in the threat lean (-X) — skirting, not ignoring")
	_assert(failed, not b.is_equal_approx(food_bias) and not b.is_equal_approx(threat_bias),
			"blend is a genuine combination, not just the primary or the secondary")
	# Primary leads: the food component should dominate the threat component.
	_assert(failed, b.y > absf(b.x),
			"primary (food) leads the blend over the secondary (threat)")

	# --- broadcast() routes co-ignition through the blend.
	var ms = MindChannel.for_cycle(f, true)
	GlobalWorkspace.broadcast(f, {"contents": coignite, "ignited": true}, ms)
	var bb: Vector3 = f._behavior_ws_bias
	_assert(failed, bb.y > 0.0 and bb.x < 0.0,
			"broadcast with 2 winners applies the blended skirt vector")
	# ...and a lone winner through broadcast keeps the single-goal bias.
	GlobalWorkspace.broadcast(f, {"contents": food_only, "ignited": true}, ms)
	_assert(failed, f._behavior_ws_bias.is_equal_approx(food_bias),
			"broadcast with 1 winner keeps the single-goal bias")

	if failed.is_empty():
		print("[smoke] motor_blend OK")
		quit(0)
	else:
		for m in failed:
			push_error("[smoke] " + m)
		quit(1)


func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _assert(failed: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		failed.append(msg)
