extends RefCounted

# SENTIENCE_THE_FELT_SELF §7 — felt continuity of identity.

const FeltSelfLayer = preload("res://scripts/felt_self_layer.gd")

const SCHEMA_VERSION: int = 1


static func enabled() -> bool:
	return FeltSelfLayer.layer_enabled()


static func ensure(f: Fish) -> Dictionary:
	if f.get("_felt_self") == null or not (f._felt_self is Dictionary):
		f._felt_self = {}
	var fs: Dictionary = f._felt_self as Dictionary
	if fs.get("continuity") == null or not (fs["continuity"] is Dictionary):
		fs["continuity"] = {
			"schema_version": SCHEMA_VERSION,
			"thread": 1.0,
			"still_me": true,
			"fractured": false,
			"spine": "",
			"remembered_boldness": -1.0,
			"away_pickup": "",
		}
	f._felt_self = fs
	return fs["continuity"] as Dictionary


static func tick(f: Fish, sim: Node, dt: float) -> void:
	if not enabled() or f == null:
		return
	var ct: Dictionary = ensure(f)
	ct["still_me"] = true
	ct["thread"] = clampf(float(ct.get("thread", 1.0)) - dt * 0.0005, 0.15, 1.0)
	if f.stress > 0.85 or f.hunger > 0.9:
		ct["fractured"] = true
		ct["thread"] = maxf(0.15, float(ct["thread"]) - dt * 0.02)
	elif ct["fractured"] and f.stress < 0.35:
		ct["fractured"] = false
		ct["thread"] = lerpf(float(ct["thread"]), 0.85, dt * 0.01)
	# Change-in-self (#63).
	var rb: float = float(ct.get("remembered_boldness", -1.0))
	if rb < 0.0:
		ct["remembered_boldness"] = f._trait("boldness")
	elif absf(f._trait("boldness") - rb) > 0.12:
		var note: String = "braver now" if f._trait("boldness") > rb else "warier now"
		var spine: String = str(ct.get("spine", ""))
		if not spine.contains(note):
			ct["spine"] = (spine + " · " + note).substr(0, mini((spine + " · " + note).length(), 140))
		ct["remembered_boldness"] = f._trait("boldness")
	# Away gap pickup (#65).
	if sim != null and sim.has_method("night_rt_f"):
		if float(sim.night_rt_f("return_grace_s")) > 0.0 and str(ct.get("away_pickup", "")) == "":
			ct["away_pickup"] = "still here after the quiet"
	(f._felt_self as Dictionary)["continuity"] = ct


static func note_bound_moment(f: Fish, bound: Dictionary) -> void:
	if not enabled():
		return
	var ct: Dictionary = ensure(f)
	ct["thread"] = clampf(float(ct.get("thread", 1.0)) + 0.002, 0.0, 1.0)
	var line: String = str(bound.get("moment_line", ""))
	if line != "":
		var spine: String = str(ct.get("spine", ""))
		if spine == "":
			ct["spine"] = line.substr(0, mini(line.length(), 80))
	(f._felt_self as Dictionary)["continuity"] = ct


static func thread_strength(f: Fish) -> float:
	return float(ensure(f).get("thread", 1.0))


static func on_death_weight(f: Fish) -> float:
	return clampf(thread_strength(f) * (1.2 if f.fish_name != "" else 0.8), 0.3, 2.0)


# SENTIENCE_THE_SPARK #84 — bonded fish approach/settle after load + absence.
static func apply_return_beat(f: Fish, sim: Node) -> void:
	if not enabled() or f == null or sim == null:
		return
	if not sim.has_method("night_rt_f") or float(sim.night_rt_f("return_grace_s")) <= 0.0:
		return
	if f.familiarity < 0.28 and f.fish_name == "":
		return
	var ct: Dictionary = ensure(f)
	ct["away_pickup"] = "still here after the quiet"
	(f._felt_self as Dictionary)["continuity"] = ct
	f._continuity_return_beat = maxf(float(f._continuity_return_beat),
			lerpf(6.0, 12.0, f.familiarity))
	f.arousal = clampf(float(f.arousal) + 0.06 + f.familiarity * 0.08, 0.0, 1.0)
	f.mood = clampf(f.mood + 0.04 + f.familiarity * 0.05, -1.0, 1.0)
	if sim.has_method("get_player_glance"):
		var glance: Dictionary = sim.get_player_glance()
		var pt: Vector3 = glance.get("point", Vector3.ZERO)
		if pt != Vector3.ZERO:
			f._interest_target = pt
			f._interest_remaining = lerpf(2.0, 4.5, f.familiarity)
			if f.current_mode == Fish.Mode.REST and f.familiarity > 0.45:
				f.current_mode = Fish.Mode.CRUISE


static func inspector_lines(f: Fish) -> PackedStringArray:
	var ct: Dictionary = ensure(f)
	var lines: PackedStringArray = PackedStringArray([
		"thread %.2f%s" % [float(ct.get("thread", 0.0)), " (fractured)" if ct.get("fractured") else ""],
	])
	if str(ct.get("spine", "")) != "":
		lines.append("spine: %s" % ct["spine"])
	return lines
