class_name MindPairCache
extends RefCounted

# PERFORMANCE_UNTHROTTLED #38 — pair-shared geometry for social math.

static var _frame: Dictionary = {}


static func reset_for_test() -> void:
	_frame.clear()


static func begin_tick() -> void:
	_frame.clear()


static func _key(a_id: String, b_id: String) -> String:
	if a_id <= b_id:
		return "%s|%s" % [a_id, b_id]
	return "%s|%s" % [b_id, a_id]


static func get_pair(a: Fish, b: Fish) -> Dictionary:
	if a == null or b == null or a == b:
		return {}
	var aid: String = str(a.id)
	var bid: String = str(b.id)
	if aid == "" or bid == "":
		return _compute(a, b, true)
	var k: String = _key(aid, bid)
	if _frame.has(k):
		var cached: Dictionary = _frame[k] as Dictionary
		if aid > bid:
			return {
				"to_me": -cached.get("to_me", Vector3.ZERO),
				"dist": cached.get("dist", 99.0),
				"heading_dot": -float(cached.get("heading_dot", 0.0)),
			}
		return cached
	var computed: Dictionary = _compute(a, b, aid <= bid)
	_frame[k] = computed
	if aid > bid:
		return {
			"to_me": -computed.get("to_me", Vector3.ZERO),
			"dist": computed.get("dist", 99.0),
			"heading_dot": -float(computed.get("heading_dot", 0.0)),
		}
	return computed


static func _compute(a: Fish, b: Fish, canonical: bool) -> Dictionary:
	var to_b: Vector3 = b.global_position - a.global_position
	var dist: float = to_b.length()
	var to_me: Vector3 = to_b / maxf(dist, 0.001)
	var ha: Vector3 = a.heading if a.heading.length_squared() > 1e-6 else Vector3.FORWARD
	var hb: Vector3 = b.heading if b.heading.length_squared() > 1e-6 else Vector3.FORWARD
	var dot_ab: float = ha.normalized().dot(to_me)
	if not canonical:
		to_me = -to_me
		dot_ab = hb.normalized().dot(-to_me)
	return {"to_me": to_me, "dist": dist, "heading_dot": dot_ab}
