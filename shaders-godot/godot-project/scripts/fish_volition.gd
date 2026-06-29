extends RefCounted

# SENTIENCE_THE_FELT_SELF §9 — felt volition / endogenous agency.

const FeltSelfLayer = preload("res://scripts/felt_self_layer.gd")

const SCHEMA_VERSION: int = 1


static func enabled() -> bool:
	return FeltSelfLayer.layer_enabled()


static func ensure(f: Fish) -> Dictionary:
	if f.get("_felt_self") == null or not (f._felt_self is Dictionary):
		f._felt_self = {}
	var fs: Dictionary = f._felt_self as Dictionary
	if fs.get("volition") == null or not (fs["volition"] is Dictionary):
		fs["volition"] = {
			"schema_version": SCHEMA_VERSION,
			"authorship": 0.0,
			"effort": 0.0,
			"will_pool": 1.0,
			"veto_cd": 0.0,
			"intention_hold": "",
			"willed_focus": "",
			"last_initiated": "",
		}
	f._felt_self = fs
	return fs["volition"] as Dictionary


static func tick(f: Fish, _sim: Node, dt: float) -> void:
	if not enabled() or f == null:
		return
	var v: Dictionary = ensure(f)
	v["will_pool"] = clampf(float(v.get("will_pool", 1.0))
			- float(f.get("_rest_debt") if f.get("_rest_debt") != null else 0.0) * dt * 0.02
			+ (1.0 - f.energy) * dt * 0.015, 0.05, 1.0)
	v["veto_cd"] = maxf(0.0, float(v.get("veto_cd", 0.0)) - dt)
	# Endogenous initiation (#80).
	if f.current_intention != "" and str(v.get("intention_hold", "")) == "":
		v["intention_hold"] = f.current_intention
	elif f.current_intention == "" and str(v.get("intention_hold", "")) != "":
		if randf() < dt * 0.08:
			f.current_intention = str(v["intention_hold"])
	# Mend will (#88).
	if bool(f.get("_mend_pending")) and float(v.get("will_pool", 1.0)) > 0.35:
		v["authorship"] = clampf(float(v.get("authorship", 0.0)) + dt * 0.02, 0.0, 1.0)
		v["last_initiated"] = "risk trust again"
	# Effort against drive (#82).
	if f.stress > 0.5 and f.speed > 0.4:
		v["effort"] = clampf(float(v.get("effort", 0.0)) + dt * 0.03, 0.0, 1.0)
	else:
		v["effort"] = maxf(0.0, float(v.get("effort", 0.0)) - dt * 0.02)
	(f._felt_self as Dictionary)["volition"] = v


static func try_veto(f: Fish) -> bool:
	if not enabled() or float(ensure(f).get("veto_cd", 0.0)) > 0.0:
		return false
	if f.burst_remaining > 0.1 and f.stress > 0.45:
		f.burst_remaining = 0.0
		var v: Dictionary = ensure(f)
		v["veto_cd"] = 1.2
		v["authorship"] = clampf(float(v.get("authorship", 0.0)) + 0.08, 0.0, 1.0)
		(f._felt_self as Dictionary)["volition"] = v
		return true
	return false


static func willed_attention(f: Fish, label: String) -> void:
	if not enabled() or label == "":
		return
	var v: Dictionary = ensure(f)
	v["willed_focus"] = label
	f.attention_focus = label
	v["authorship"] = clampf(float(v.get("authorship", 0.0)) + 0.05, 0.0, 1.0)
	(f._felt_self as Dictionary)["volition"] = v


static func inspector_lines(f: Fish) -> PackedStringArray:
	var v: Dictionary = ensure(f)
	return PackedStringArray([
		"authorship %.2f · effort %.2f · will %.2f" % [
			float(v.get("authorship", 0.0)), float(v.get("effort", 0.0)),
			float(v.get("will_pool", 1.0))],
		"hold: %s" % str(v.get("intention_hold", "")),
	])
