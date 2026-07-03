extends RefCounted

# SENTIENCE_THE_FELT_SELF §8 — qualia bridge (attendable felt states).

const FishCoreAffect = preload("res://scripts/fish_core_affect.gd")
const FishProtoself = preload("res://scripts/fish_protoself.gd")
const FeltSelfLayer = preload("res://scripts/felt_self_layer.gd")

const HONEST_FRAME: String = FeltSelfLayer.HONEST_FRAME
const SCHEMA_VERSION: int = 1


static func enabled() -> bool:
	return FeltSelfLayer.layer_enabled()


static func ensure(f: Fish) -> Dictionary:
	if f.get("_felt_self") == null or not (f._felt_self is Dictionary):
		f._felt_self = {}
	var fs: Dictionary = f._felt_self as Dictionary
	if fs.get("qualia") == null or not (fs["qualia"] is Dictionary):
		fs["qualia"] = {
			"schema_version": SCHEMA_VERSION,
			"objects": {},
			"baseline_valence": 0.0,
			"keeper_tone": "neutral",
		}
	f._felt_self = fs
	return fs["qualia"] as Dictionary


static func tick(f: Fish, sim: Node, dt: float) -> void:
	if not enabled() or f == null:
		return
	var q: Dictionary = ensure(f)
	var objs: Dictionary = q.get("objects", {})
	var tex: String = FishCoreAffect.texture(f)
	var intensity: float = 0.35 + absf(FishCoreAffect.valence(f)) * 0.45
	if f.attention_focus in ["threat", "gills", "gut", "interoception"]:
		intensity = clampf(intensity + dt * 0.15, 0.0, 1.0)
	objs[tex] = {"intensity": intensity, "attended": f.attention_focus == tex}
	# Sensory character (#72).
	var dl: float = float(sim.daylight()) if sim != null and sim.has_method("daylight") else 0.5
	objs["light"] = {"intensity": dl, "character": "sharp" if dl > 0.6 else "dim"}
	objs["water"] = {"intensity": 1.0 - f.stress * 0.4, "character": "heavy" if f.stress > 0.5 else "easy"}
	# Keeper qualia (#77).
	var keeper: String = "warm" if f.familiarity > 0.45 else ("uncertain" if f.familiarity < 0.2 else "neutral")
	q["keeper_tone"] = keeper
	# Affective contrast (#75).
	var base: float = float(q.get("baseline_valence", 0.0))
	var cv: float = FishCoreAffect.valence(f) - base
	if absf(cv) > 0.15:
		objs["contrast"] = {"delta": cv, "character": "relief" if cv > 0 else "dread"}
	q["baseline_valence"] = lerpf(base, FishCoreAffect.valence(f), dt * 0.05)
	q["objects"] = objs
	(f._felt_self as Dictionary)["qualia"] = q


static func report_line(f: Fish) -> String:
	if not enabled():
		return ""
	var tex: String = FishCoreAffect.texture(f)
	match tex:
		"thin breath":
			return "the water feels thin"
		"hollow ache":
			return "a hollow pull inside"
		"heavy body":
			return "the water feels heavy"
		"ease":
			return "the water feels easy"
		"clamped fins":
			return "fins feel tight"
		"unease":
			return "something feels off inside"
		_:
			return ""


static func higher_order(f) -> String:
	var tex: String = FishCoreAffect.texture(f)
	if tex == "neutral":
		return ""
	return "I am feeling %s" % tex.replace("_", " ")


static func welfare_score(f: Fish) -> float:
	return clampf(FishCoreAffect.valence(f) - float(FishProtoself.ensure(f).get("pain", 0.0)) * 0.5,
			-1.0, 1.0)
