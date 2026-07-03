extends RefCounted

# SENTIENCE_THE_FELT_SELF §2 — integrated valence core from the felt body.

const FishProtoself = preload("res://scripts/fish_protoself.gd")
const FeltSelfLayer = preload("res://scripts/felt_self_layer.gd")

const SCHEMA_VERSION: int = 1


static func enabled() -> bool:
	return FeltSelfLayer.layer_enabled()


static func ensure(f) -> Dictionary:
	var fs_v: Variant = f.get("_felt_self")
	var fs: Dictionary = {}
	if fs_v is Dictionary:
		fs = (fs_v as Dictionary).duplicate(true)
	if fs.get("core_affect") == null or not (fs["core_affect"] is Dictionary):
		fs["core_affect"] = {
			"schema_version": SCHEMA_VERSION,
			"valence": 0.0,
			"arousal_core": 0.2,
			"texture": "neutral",
			"residue": 0.0,
			"tonic": 0.0,
		}
	if f is Object:
		(f as Object).set("_felt_self", fs)
	return fs["core_affect"] as Dictionary


static func tick(f, _sim: Node, dt: float) -> void:
	if not enabled() or f == null:
		return
	var pb: Dictionary = FishProtoself.ensure(f)
	var ca: Dictionary = ensure(f)
	# Homeostasis from body (#10).
	var needs_met: float = float(pb.get("comfort", 0.5)) * 0.45 \
		+ (1.0 - float(pb.get("gut_fullness", 0.3))) * 0.25 \
		+ (1.0 - float(pb.get("pain", 0.0))) * 0.3
	var target_val: float = clampf(needs_met * 2.0 - 1.0, -1.0, 1.0)
	# Neuromodulators move the core (#12).
	target_val += (f.dopamine - 0.45) * 0.35
	target_val += (f.serotonin - 0.5) * 0.25
	target_val -= (f.cortisol - 0.2) * 0.45
	target_val -= (f.noradrenaline - 0.25) * 0.3
	ca["tonic"] = f.mood_disposition
	ca["valence"] = lerpf(float(ca.get("valence", 0.0)),
			lerpf(target_val, float(ca.get("tonic", 0.0)), 0.35), clampf(dt * 1.4, 0.0, 1.0))
	ca["arousal_core"] = lerpf(float(ca.get("arousal_core", 0.2)),
			clampf(float(pb.get("gill_rhythm", 0.5)) * 0.4 + f.arousal * 0.35, 0.0, 1.0),
			clampf(dt * 1.6, 0.0, 1.0))
	ca["texture"] = _texture_label(FishProtoself.dominant_source(f), f)
	# Honest residue (#18).
	if f.stress > 0.55:
		ca["residue"] = clampf(float(ca.get("residue", 0.0)) + dt * 0.015, 0.0, 1.0)
	else:
		ca["residue"] = maxf(0.0, float(ca.get("residue", 0.0)) - dt * 0.004)
	# Body loop (#15): valence nudges fin tension back.
	pb["fin_tension"] = clampf(float(pb.get("fin_tension", 0.2))
			- float(ca.get("valence", 0.0)) * dt * 0.08, 0.0, 1.0)
	(f._felt_self as Dictionary)["core_affect"] = ca
	(f._felt_self as Dictionary)["protoself"] = pb
	# Soft sync to legacy scalars so the rest of the sim reads the core.
	f.mood = lerpf(f.mood, float(ca.get("valence", 0.0)), clampf(dt * 0.35, 0.0, 1.0))


static func _texture_label(source: String, f: Fish) -> String:
	var pb: Dictionary = FishProtoself.ensure(f)
	if float(pb.get("vitality_decline", 0.0)) > 0.45:
		return "slow fade"
	if f.spooked > 0.55 and float(pb.get("vitality_decline", 0.0)) < 0.25:
		return "sharp fright"
	match source:
		"gut_fullness":
			return "hollow ache"
		"gill_rhythm":
			return "thin breath"
		"fin_tension":
			return "clamped fins"
		"fatigue":
			return "heavy body"
		"pain":
			return "soreness"
		_:
			if f.stress > 0.5:
				return "unease"
			if f.mood > 0.25:
				return "ease"
			return "neutral"


static func valence(f) -> float:
	return float(ensure(f).get("valence", 0.0))


static func texture(f) -> String:
	return str(ensure(f).get("texture", "neutral"))


static func tone_for_label(f, label: String) -> float:
	var v: float = valence(f)
	if label in ["threat", "gills", "vibration"]:
		return clampf(v - 0.25, -1.0, 0.5)
	if label in ["food", "player", "mate"]:
		return clampf(v + 0.15, -0.5, 1.0)
	return v * 0.5


static func narrator_hint(f) -> String:
	return str(ensure(f).get("texture", ""))


static func to_dict(f) -> Dictionary:
	return ensure(f).duplicate(true)


static func from_dict(f, d: Variant) -> void:
	if d is not Dictionary:
		return
	if f.get("_felt_self") == null or not (f._felt_self is Dictionary):
		f._felt_self = {}
	(f._felt_self as Dictionary)["core_affect"] = (d as Dictionary).duplicate(true)
