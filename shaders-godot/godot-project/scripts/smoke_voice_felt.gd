extends SceneTree

# LOOM #76 — felt state enters voice_params. Assert the felt snapshot is stored
# on the params and audibly shifts pitch/brightness/tempo/amp, while an empty
# felt leaves the baseline voice untouched (so existing paths are unchanged).

const V = preload("res://scripts/tank_voice_audio.gd")


func _init() -> void:
	var t := TestSupport.Suite.new("smoke_voice_felt")

	var base: Dictionary = V.voice_params("fish", 4242, 40, 0.4, 0.5)
	t.check(not base.has("felt"), "empty felt leaves no felt key (baseline unchanged)")

	var calm := {"valence": 0.0, "arousal": 0.1, "stress": 0.0,
			"fatigue": 0.0, "confidence": 0.8, "surprise": 0.0}
	var aroused := {"valence": 0.2, "arousal": 0.9, "stress": 0.1,
			"fatigue": 0.0, "confidence": 0.7, "surprise": 0.0}
	var tired := {"valence": -0.1, "arousal": 0.1, "stress": 0.0,
			"fatigue": 0.9, "confidence": 0.6, "surprise": 0.0}
	var stressed := {"valence": -0.3, "arousal": 0.6, "stress": 0.9,
			"fatigue": 0.0, "confidence": 0.3, "surprise": 0.0}

	var pc: Dictionary = V.voice_params("fish", 4242, 40, 0.4, 0.5, 0, calm)
	var pa: Dictionary = V.voice_params("fish", 4242, 40, 0.4, 0.5, 0, aroused)
	var pt: Dictionary = V.voice_params("fish", 4242, 40, 0.4, 0.5, 0, tired)
	var ps: Dictionary = V.voice_params("fish", 4242, 40, 0.4, 0.5, 0, stressed)

	t.has_keys(pc, ["felt"], "felt snapshot stored on params")
	t.check(float(pa["base_hz"]) > float(pc["base_hz"]),
			"arousal lifts pitch (%.0f > %.0f)" % [float(pa["base_hz"]), float(pc["base_hz"])])
	t.check(float(pt["base_hz"]) < float(pc["base_hz"]),
			"fatigue lowers pitch (%.0f < %.0f)" % [float(pt["base_hz"]), float(pc["base_hz"])])
	t.check(float(ps["brightness"]) > float(pc["brightness"]),
			"stress brightens timbre (%.3f > %.3f)" % [float(ps["brightness"]), float(pc["brightness"])])
	t.check(float(pt["amp"]) < float(pc["amp"]),
			"fatigue quiets the voice (%.3f < %.3f)" % [float(pt["amp"]), float(pc["amp"])])
	t.check(V.duration_s(pt) > V.duration_s(pa),
			"tired drawls longer than aroused (%.3fs > %.3fs)" % [V.duration_s(pt), V.duration_s(pa)])

	# Determinism and distinct renders per felt state.
	var pa2: Dictionary = V.voice_params("fish", 4242, 40, 0.4, 0.5, 0, aroused)
	t.check(pa == pa2, "same felt is deterministic")
	var va := V.new()
	# Cache keys differ, so calm and aroused do not alias to one sample.
	t.check(va._cache_key(pc) != va._cache_key(pa), "distinct felt -> distinct cache key")
	var smp: PackedFloat32Array = V.render(ps)
	var peak: float = 0.0
	for x in smp:
		peak = maxf(peak, absf(x))
	t.in_range(peak, 0.0, V.PEAK_CEILING + 0.001, "felt render stays under the peak ceiling")
	va.free()

	quit(t.finish())
