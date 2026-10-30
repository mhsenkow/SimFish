class_name MotionCreatureView
extends RefCounted

# One read-only view of any creature's motion (CREATURE_MOTION_700 #70), so
# probes, overlays and smokes can measure fish, shrimp, snails and worms the
# same way instead of each knowing every script's private fields. Never
# writes. Fields that a creature doesn't have come back as their defaults.
#
#   position  world position          forward  world forward (unit)
#   velocity  world velocity          speed    scalar speed
#   kind      "fish" / "shrimp" / "snail" / "other"
#   phase     its locomotor clock (stroke, gait or foot pulse), radians
#   grounded  standing/crawling on a surface


static func of(node: Node3D) -> Dictionary:
	var out: Dictionary = {
		"kind": "other", "position": Vector3.ZERO, "forward": Vector3.FORWARD,
		"velocity": Vector3.ZERO, "speed": 0.0, "phase": 0.0, "grounded": false,
	}
	if node == null or not is_instance_valid(node):
		return out
	out["position"] = node.global_position
	if node is Fish:
		var f: Fish = node
		out["kind"] = "fish"
		out["forward"] = f.heading.normalized() if f.heading.length_squared() > 1e-6 else Vector3.FORWARD
		out["velocity"] = f.velocity
		out["speed"] = f.speed
		out["phase"] = f._motor_phase
		return out
	var script_path: String = ""
	var scr: Variant = node.get_script()
	if scr is Script:
		script_path = (scr as Script).resource_path
	if script_path.ends_with("shrimp.gd"):
		out["kind"] = "shrimp"
		var h: Variant = node.get("heading")
		if h is Vector3 and (h as Vector3).length_squared() > 1e-6:
			out["forward"] = (h as Vector3).normalized()
		out["velocity"] = node.get("velocity") if node.get("velocity") is Vector3 else Vector3.ZERO
		out["speed"] = float(node.get("speed")) if node.get("speed") != null else 0.0
		out["phase"] = float(node.get("_gait_phase")) if node.get("_gait_phase") != null else 0.0
		out["grounded"] = bool(node.get("_floor_gripped")) if node.get("_floor_gripped") != null else false
		return out
	if script_path.ends_with("snail.gd"):
		out["kind"] = "snail"
		# The snail's model faces +X under its MODEL_YAW (CREATURE_MOTION_700 #25).
		out["forward"] = node.global_transform.basis.x.normalized()
		out["phase"] = float(node.get("_pulse_phase")) if node.get("_pulse_phase") != null else 0.0
		out["grounded"] = true
		return out
	out["forward"] = -node.global_transform.basis.z.normalized()
	return out
