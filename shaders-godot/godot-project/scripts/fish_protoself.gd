extends RefCounted

# SENTIENCE_THE_FELT_SELF §1 — felt body schema (Damasio protoself).

const FeltSelfLayer = preload("res://scripts/felt_self_layer.gd")

const SCHEMA_VERSION: int = 1


static func enabled() -> bool:
	return FeltSelfLayer.layer_enabled()


static func ensure(f: Fish) -> Dictionary:
	if f.get("_felt_self") == null or not (f._felt_self is Dictionary):
		f._felt_self = {}
	var fs: Dictionary = f._felt_self as Dictionary
	if fs.get("protoself") == null or not (fs["protoself"] is Dictionary):
		fs["protoself"] = {
			"schema_version": SCHEMA_VERSION,
			"gill_rhythm": 0.5,
			"gut_fullness": 0.3,
			"fin_tension": 0.2,
			"fatigue": 0.0,
			"orientation": 0.0,
			"comfort": 0.5,
			"pain": 0.0,
			"predicted_hunger": 0.3,
			"body_changed_notice": "",
		}
	f._felt_self = fs
	return fs["protoself"] as Dictionary


static func tick(f: Fish, _sim: Node, dt: float) -> void:
	if not enabled() or f == null:
		return
	var pb: Dictionary = ensure(f)
	var o2_pen: float = float(f.get("_chem_o2_penalty") if f.get("_chem_o2_penalty") != null else 0.0)
	pb["gill_rhythm"] = lerpf(float(pb.get("gill_rhythm", 0.5)),
			clampf(0.35 + f.stress * 0.45 + o2_pen * 0.35, 0.0, 1.0), clampf(dt * 2.0, 0.0, 1.0))
	pb["gut_fullness"] = lerpf(float(pb.get("gut_fullness", 0.3)), f.hunger, clampf(dt * 1.5, 0.0, 1.0))
	pb["fin_tension"] = lerpf(float(pb.get("fin_tension", 0.2)),
			clampf(f.stress * 0.55 + f.vigilance * 0.35, 0.0, 1.0), clampf(dt * 1.8, 0.0, 1.0))
	var fatigue: float = clampf(float(f.get("_rest_debt") if f.get("_rest_debt") != null else 0.0)
			+ (1.0 - f.energy) * 0.35, 0.0, 1.0)
	pb["fatigue"] = lerpf(float(pb.get("fatigue", 0.0)), fatigue, clampf(dt * 0.8, 0.0, 1.0))
	var tilt: float = float(f.get("_sleep_tilt") if f.get("_sleep_tilt") != null else 0.0)
	var bank: float = float(f.get("_bank") if f.get("_bank") != null else 0.0)
	pb["orientation"] = lerpf(float(pb.get("orientation", 0.0)), absf(tilt) + absf(bank) * 0.5,
			clampf(dt * 2.5, 0.0, 1.0))
	var comfort: float = clampf(1.0 - f.stress * 0.55 - f.hunger * 0.25 - o2_pen * 0.3, 0.0, 1.0)
	pb["comfort"] = lerpf(float(pb.get("comfort", 0.5)), comfort, clampf(dt * 1.2, 0.0, 1.0))
	pb["pain"] = lerpf(float(pb.get("pain", 0.0)),
			clampf(f.stress * 0.4 + o2_pen * 0.5, 0.0, 1.0), clampf(dt * 1.5, 0.0, 1.0))
	# Bodily prediction error → surprise (#4).
	var pred_h: float = float(pb.get("predicted_hunger", f.hunger))
	var intero_err: float = absf(f.hunger - pred_h)
	if intero_err > 0.08:
		f.surprise = clampf(f.surprise + intero_err * dt * 0.35, 0.0, 1.0)
	pb["predicted_hunger"] = lerpf(pred_h, f.hunger, clampf(dt * 0.4, 0.0, 1.0))
	# Growth / scar body notice (#8).
	var gv: float = float(f.get("_growth_variance") if f.get("_growth_variance") != null else 1.0)
	if absf(gv - 1.0) > 0.12 and randf() < dt * 0.002:
		pb["body_changed_notice"] = "this body feels different"
	# Sleep: body persists (#7).
	if f._asleep:
		pb["gill_rhythm"] = lerpf(float(pb.get("gill_rhythm", 0.5)), 0.28, dt * 0.5)
	(f._felt_self as Dictionary)["protoself"] = pb


static func baseline_bid(f: Fish) -> Dictionary:
	var pb: Dictionary = ensure(f)
	var hum: float = 0.18 + float(pb.get("gill_rhythm", 0.5)) * 0.12 + float(pb.get("comfort", 0.5)) * 0.08
	return {"label": "body_hum", "salience": hum, "coalition": ["body", "interoception"]}


static func organ_bids(f: Fish) -> Array:
	var pb: Dictionary = ensure(f)
	var out: Array = []
	if float(pb.get("gut_fullness", 0.0)) > 0.42:
		out.append({"label": "gut", "salience": float(pb["gut_fullness"]) * 0.55 + 0.12,
				"coalition": ["body", "hunger"]})
	if float(pb.get("gill_rhythm", 0.0)) > 0.55:
		out.append({"label": "gills", "salience": float(pb["gill_rhythm"]) * 0.48 + 0.1,
				"coalition": ["body", "interoception"]})
	if float(pb.get("fin_tension", 0.0)) > 0.45:
		out.append({"label": "fins", "salience": float(pb["fin_tension"]) * 0.42 + 0.08,
				"coalition": ["body", "stress"]})
	if float(pb.get("fatigue", 0.0)) > 0.35:
		out.append({"label": "fatigue", "salience": float(pb["fatigue"]) * 0.5 + 0.1,
				"coalition": ["body", "rest"]})
	return out


static func dominant_source(f: Fish) -> String:
	var pb: Dictionary = ensure(f)
	var best: String = "comfort"
	var best_v: float = float(pb.get("comfort", 0.5))
	for key in ["gut_fullness", "gill_rhythm", "fin_tension", "fatigue", "pain"]:
		var v: float = float(pb.get(key, 0.0))
		if v > best_v:
			best_v = v
			best = key
	return best


static func inspector_lines(f: Fish) -> PackedStringArray:
	var pb: Dictionary = ensure(f)
	return PackedStringArray([
		"gills %.2f · gut %.2f · fins %.2f" % [
			float(pb.get("gill_rhythm", 0.0)), float(pb.get("gut_fullness", 0.0)),
			float(pb.get("fin_tension", 0.0))],
		"fatigue %.2f · comfort %.2f · posture %.2f" % [
			float(pb.get("fatigue", 0.0)), float(pb.get("comfort", 0.0)),
			float(pb.get("orientation", 0.0))],
	])


static func to_dict(f: Fish) -> Dictionary:
	return ensure(f).duplicate(true)


static func from_dict(f: Fish, d: Variant) -> void:
	if d is not Dictionary:
		return
	if f.get("_felt_self") == null or not (f._felt_self is Dictionary):
		f._felt_self = {}
	(f._felt_self as Dictionary)["protoself"] = (d as Dictionary).duplicate(true)
