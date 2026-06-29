extends RefCounted

# SENTIENCE_THE_FELT_SELF §6 — emergent concept formation.

const EpisodicMemory = preload("res://scripts/episodic_memory.gd")
const FishCoreAffect = preload("res://scripts/fish_core_affect.gd")
const MindLexicon = preload("res://scripts/mind_lexicon.gd")
const FeltSelfLayer = preload("res://scripts/felt_self_layer.gd")

const SCHEMA_VERSION: int = 1
const MAX_CONCEPTS: int = 16


static func enabled() -> bool:
	return FeltSelfLayer.layer_enabled()


static func ensure(f: Fish) -> Dictionary:
	if f.get("_felt_self") == null or not (f._felt_self is Dictionary):
		f._felt_self = {}
	var fs: Dictionary = f._felt_self as Dictionary
	if fs.get("concepts") == null or not (fs["concepts"] is Dictionary):
		fs["concepts"] = {
			"schema_version": SCHEMA_VERSION,
			"kinds": [],
			"proto": [],
		}
	f._felt_self = fs
	return fs["concepts"] as Dictionary


static func tick(f: Fish, _sim: Node, dt: float) -> void:
	if not enabled() or f == null:
		return
	var c: Dictionary = ensure(f)
	var store: Array = EpisodicMemory.ensure_store(f)
	if store.is_empty() or randf() >= dt * 0.08:
		return
	var kinds: Array = c.get("kinds", [])
	var last: Dictionary = store[-1]
	var kind: String = str(last.get("kind", "moment"))
	var key: String = "%s@%d" % [kind, int(last.get("cell", -1)) if last.has("cell") else hash(str(last.get("text", "")))]
	var found: Dictionary = {}
	for k in kinds:
		if str((k as Dictionary).get("key", "")) == key:
			found = k
			break
	if found.is_empty():
		found = {
			"key": key,
			"label": "kind-of-%s" % kind,
			"count": 0,
			"affect": FishCoreAffect.valence(f),
			"weight": float(last.get("weight", 0.5)),
		}
		kinds.append(found)
	found["count"] = int(found.get("count", 0)) + 1
	found["weight"] = clampf(float(found.get("weight", 0.5)) + 0.04, 0.0, 1.0)
	found["affect"] = lerpf(float(found.get("affect", 0.0)), FishCoreAffect.valence(f), 0.15)
	while kinds.size() > MAX_CONCEPTS:
		kinds.pop_front()
	c["kinds"] = kinds
	# Proto-abstractions (#56).
	var proto: Array = c.get("proto", [])
	if f.hunger > 0.55 and not proto.has("scarcity"):
		proto.append("scarcity")
	if f.stress < 0.25 and f.mood > 0.2 and not proto.has("safety"):
		proto.append("safety")
	while proto.size() > 6:
		proto.pop_front()
	c["proto"] = proto
	(f._felt_self as Dictionary)["concepts"] = c


static func nearest_label(f: Fish, situation: String) -> String:
	var kinds: Array = ensure(f).get("kinds", [])
	for k in kinds:
		var kd: Dictionary = k
		if str(kd.get("label", "")).contains(situation):
			return str(kd.get("label", ""))
	return ""


static func inspector_lines(f: Fish) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for k in ensure(f).get("kinds", []):
		var kd: Dictionary = k
		lines.append("%s (×%d)" % [kd.get("label", ""), int(kd.get("count", 0))])
	for p in ensure(f).get("proto", []):
		lines.append("proto: %s" % str(p))
	return lines
