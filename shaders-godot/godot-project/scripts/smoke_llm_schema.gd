extends SceneTree

# DEEP_SCIENCE #71 — structural validation of the model's JSON output. Assert
# the schema owner drops malformed/out-of-vocab entities, keeps valid ones, and
# that the GBNF grammars and Ollama format objects are well-formed (every
# grammar has a root; the intent schema enumerates regions and moods).

const S = preload("res://scripts/llm_schema.gd")


func _init() -> void:
	var t := TestSupport.Suite.new("smoke_llm_schema")

	# Bios: valid kept, missing id/line dropped, over-long trimmed.
	var bios_in := {"bios": [
		{"id": "a", "line": "A calm little drifter."},
		{"id": "", "line": "no id"},
		{"id": "b", "line": ""},
		{"id": "c", "line": "x".repeat(400)},
		"garbage",
	]}
	var bios: Array = S.validate_bios(bios_in)
	t.equals(bios.size(), 2, "only the two well-formed bios survive")
	t.equals(String(bios[0].get("id", "")), "a", "first valid bio id kept")
	t.check(String(bios[1].get("line", "")).length() <= 180, "over-long line trimmed")

	# Intent: out-of-vocab region/mood dropped; valid kept and lowercased.
	var intent_in := {
		"regions": [
			{"region": "Top-Front", "mood": "Calm"},
			{"region": "ceiling", "mood": "calm"},
			{"region": "center", "mood": "ecstatic"},
		],
		"fish_moods": [
			{"id": "f1", "mood": "hungry"},
			{"id": "f2", "mood": "nonsense"},
			{"id": "", "mood": "calm"},
		],
		"narration": "The tank settles into evening.",
	}
	var clean: Dictionary = S.validate_intent(intent_in)
	t.equals((clean["regions"] as Array).size(), 1, "only the in-vocab region survives")
	t.equals(String((clean["regions"] as Array)[0].get("region", "")), "top-front", "region lowercased")
	t.equals((clean["fish_moods"] as Array).size(), 1, "only the in-vocab fish mood survives")
	t.equals(String(clean["narration"]), "The tank settles into evening.", "narration kept")

	var empty: Dictionary = S.validate_intent("not a dict")
	t.equals((empty["regions"] as Array).size(), 0, "non-dict intent yields empty regions")

	# GBNF grammars: each kind has a root symbol (llama.cpp requires one).
	for kind in [S.KIND_BIOS, S.KIND_INTENT, S.KIND_CHRONICLE]:
		var g: String = S.gbnf(kind)
		t.check(g.contains("root ::="), "%s grammar has a root symbol" % kind)
	t.check(S.gbnf(S.KIND_INTENT).contains("top-front"), "intent grammar enumerates regions")
	t.check(S.gbnf(S.KIND_INTENT).contains("curious"), "intent grammar enumerates moods")

	# Ollama structured-output format objects.
	var fmt: Variant = S.ollama_format(S.KIND_INTENT)
	t.check(fmt is Dictionary, "intent format is a schema object")
	if fmt is Dictionary:
		t.has_keys(fmt as Dictionary, ["type", "properties", "required"], "intent format shape")

	quit(t.finish())
