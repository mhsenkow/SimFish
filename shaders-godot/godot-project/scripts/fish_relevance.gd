extends RefCounted

# SENTIENCE_THE_FELT_SELF §3 — relevance realization (caring engine).

const FishCoreAffect = preload("res://scripts/fish_core_affect.gd")
const FishProtoself = preload("res://scripts/fish_protoself.gd")
const EpisodicMemory = preload("res://scripts/episodic_memory.gd")
const FeltSelfLayer = preload("res://scripts/felt_self_layer.gd")

const SCHEMA_VERSION: int = 1
const ECONOMY_CAP: float = 2.4


static func enabled() -> bool:
	return FeltSelfLayer.layer_enabled()


static func ensure(f: Fish) -> Dictionary:
	if f.get("_felt_self") == null or not (f._felt_self is Dictionary):
		f._felt_self = {}
	var fs: Dictionary = f._felt_self as Dictionary
	if fs.get("relevance") == null or not (fs["relevance"] is Dictionary):
		fs["relevance"] = {
			"schema_version": SCHEMA_VERSION,
			"explore": 0.35,
			"boredom": 0.0,
			"last_surprise_t": 0.0,
		}
	f._felt_self = fs
	return fs["relevance"] as Dictionary


static func realize(f: Fish, _sim: Node, bids: Array, dt: float) -> Array:
	if not enabled() or bids.is_empty():
		return bids
	var rel: Dictionary = ensure(f)
	var val: float = FishCoreAffect.valence(f)
	var bold: float = f._trait("boldness")
	var curious: float = f._trait("curiosity")
	# Opponent explore/exploit (#21).
	rel["explore"] = lerpf(float(rel.get("explore", 0.35)),
			clampf(curious * 0.5 + (1.0 - absf(val)) * 0.2, 0.05, 0.75), dt * 0.08)
	var out: Array = []
	for b in bids:
		var nb: Dictionary = (b as Dictionary).duplicate(true)
		var label: String = str(nb.get("label", ""))
		var sal: float = float(nb.get("salience", 0.0))
		# Caring from core (#20).
		sal *= 0.65 + absf(val) * 0.35 + FishCoreAffect.tone_for_label(f, label) * 0.15 + 0.35
		# Need frames perception (#22).
		if f.hunger > 0.4 and label in ["food", "gut"]:
			sal *= 1.0 + f.hunger * 0.45
		if f.spooked > 0.35 and label in ["threat", "vibration", "gills"]:
			sal *= 1.0 + f.spooked * 0.4
		# Affordance tags (#24).
		if label == "food":
			nb["affordance"] = "edible"
		elif label in ["threat", "vibration"]:
			nb["affordance"] = "hide_from"
		elif label == "mate":
			nb["affordance"] = "mate_with"
		# Personality signature (#28).
		if bold > 0.62 and label == "novelty":
			sal *= 1.18
		if bold < 0.38 and label == "threat":
			sal *= 1.15
		# Surprise hijack (#26).
		if f.surprise > 0.45:
			sal *= 1.0 + f.surprise * 0.35
			rel["last_surprise_t"] = Time.get_ticks_msec()
		# Explore bonus (#21).
		if label in ["novelty", "player"] and float(rel.get("explore", 0.35)) > 0.4:
			sal *= 1.0 + float(rel["explore"]) * 0.25
		# Memory relevance (#25).
		if f.get("_episodic_retrieval_hint") is Dictionary:
			var hk: String = str((f._episodic_retrieval_hint as Dictionary).get("kind", ""))
			if hk != "" and label.contains(hk):
				sal *= 1.12
		nb["salience"] = maxf(0.0, sal)
		nb["felt_tone"] = FishCoreAffect.tone_for_label(f, label)
		out.append(nb)
	out.sort_custom(func(a, b): return float(a.get("salience", 0.0)) > float(b.get("salience", 0.0)))
	# Finite economy (#23).
	var total: float = 0.0
	for b in out:
		total += float(b.get("salience", 0.0))
	if total > ECONOMY_CAP:
		var scale: float = ECONOMY_CAP / total
		for b in out:
			b["salience"] = float(b.get("salience", 0.0)) * scale
	# Boredom (#29).
	var flat: bool = out.is_empty() or float(out[0].get("salience", 0.0)) < 0.28
	if flat:
		rel["boredom"] = clampf(float(rel.get("boredom", 0.0)) + dt * 0.04, 0.0, 1.0)
		if rel["boredom"] > 0.55:
			out.append({"label": "boredom", "salience": 0.32 + float(rel["boredom"]) * 0.2,
					"coalition": ["self", "explore"], "affordance": "manufacture_goal"})
	else:
		rel["boredom"] = maxf(0.0, float(rel.get("boredom", 0.0)) - dt * 0.02)
	(f._felt_self as Dictionary)["relevance"] = rel
	return out
