extends SceneTree

# SENTIENCE_THE_SPARK — expression bridge smoke (compile + signal round-trip).

const FishSparkExpression = preload("res://scripts/fish_spark_expression.gd")
const FishSparkBehavior = preload("res://scripts/fish_spark_behavior.gd")
const MindChannel = preload("res://scripts/mind_channel.gd")


func _init() -> void:
	var failed: PackedStringArray = PackedStringArray()
	var f: Fish = Fish.new()
	f._prediction_error = 0.55
	f._workspace_ignited = false
	f._life_stance = "wary"
	f._longing_residue = 0.4
	var ms = MindChannel.for_cycle(f, true)
	var sig: Dictionary = FishSparkExpression.gather_signals(f, ms, 0.1)
	if float(sig.get("pred_err", 0.0)) < 0.5:
		failed.append("pred_err=%s" % str(sig.get("pred_err", "missing")))
	FishSparkExpression.gather_signals(f, ms, 0.05)
	f._workspace_ignited = true
	sig = FishSparkExpression.gather_signals(f, ms, 0.05)
	if not bool(sig.get("ignition_edge", false)):
		failed.append("ignition_edge=%s prev=%s" % [str(sig.get("ignition_edge")), str(f._spark_state)])
	var mods: Dictionary = FishSparkExpression.motion_modifiers(f, sig)
	if mods.is_empty() or not mods.has("wander_scale"):
		failed.append("motion mods missing wander_scale")
	if failed.is_empty():
		print("smoke_spark_expression: OK")
	else:
		for e in failed:
			push_error("smoke_spark_expression: %s" % e)
	quit(0 if failed.is_empty() else 1)
