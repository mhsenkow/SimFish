extends RefCounted

# SENTIENCE_DEEP_SCIENCE #71 — grammar-constrained decoding, as far as the
# shipped stack allows.
#
# FEASIBILITY (checked 2026-11): the bundled llama.cpp dylibs carry full GBNF /
# json_schema_to_grammar support, but the committed godot_llama GDExtension
# surfaces only sampler params (temperature/top_k/top_p/penalties/seed/stop) —
# it exposes NO `grammar` key. Native GBNF decoding therefore needs a rebuild
# of the committed C++ binaries (out of scope here). godot_llama.gd already
# forwards the whole params dict to the native context, so a future extension
# that reads a `grammar` key will get it for free.
#
# Until then this module is the structural guarantee the game relies on for the
# JSON model paths (bios, narration/intent, chronicle): a single schema owner
# that validates and repairs parsed model output so malformed shapes and
# out-of-vocabulary entities (unknown regions/moods) cannot reach the game.
# `gbnf()` and `ollama_format()` emit the same schema as a GBNF grammar and an
# Ollama structured-output object, ready to wire the moment either tier can
# enforce it at generation time.
#
# Deliberately no class_name (preload it): a new global needs an editor rescan.

const KIND_BIOS: String = "bios"
const KIND_INTENT: String = "intent"
const KIND_CHRONICLE: String = "chronicle"

# These enums MUST match the prompts in ai_director.gd (_build_intent_prompt).
const VALID_REGIONS: PackedStringArray = [
	"top-front", "top-back", "mid-front", "mid-back",
	"bottom-front", "bottom-back", "center",
]
const VALID_MOODS: PackedStringArray = [
	"calm", "curious", "hungry", "restless", "sleepy", "playful", "shy", "alert",
]


# --- Validation / repair ---------------------------------------------------

# Clean a parsed bios payload to a bounded Array of {id, line}. Entries missing
# an id or a line are dropped; lines are trimmed and length-capped.
static func validate_bios(parsed: Variant, max_line_chars: int = 180) -> Array:
	var out: Array = []
	var bios: Variant = parsed.get("bios") if parsed is Dictionary else parsed
	if not (bios is Array):
		return out
	for b in (bios as Array):
		if not (b is Dictionary):
			continue
		var fid: String = String((b as Dictionary).get("id", "")).strip_edges()
		var line: String = String((b as Dictionary).get("line", "")).strip_edges()
		if fid == "" or line == "":
			continue
		if line.length() > max_line_chars:
			line = line.substr(0, max_line_chars).strip_edges()
		out.append({"id": fid, "line": line})
	return out


# Clean a parsed intent payload: drop out-of-vocab regions/moods, keep the
# narration string. Returns {regions:[{region,mood}], fish_moods:[{id,mood}],
# narration:String}.
static func validate_intent(parsed: Variant) -> Dictionary:
	var out: Dictionary = {"regions": [], "fish_moods": [], "narration": ""}
	if not (parsed is Dictionary):
		return out
	var d: Dictionary = parsed
	var regions: Variant = d.get("regions", [])
	if regions is Array:
		for r in (regions as Array):
			if not (r is Dictionary):
				continue
			var region: String = String((r as Dictionary).get("region", "")).to_lower().strip_edges()
			var mood: String = String((r as Dictionary).get("mood", "")).to_lower().strip_edges()
			if VALID_REGIONS.has(region) and VALID_MOODS.has(mood):
				out["regions"].append({"region": region, "mood": mood})
	var fms: Variant = d.get("fish_moods", [])
	if fms is Array:
		for fm in (fms as Array):
			if not (fm is Dictionary):
				continue
			var fid: String = String((fm as Dictionary).get("id", "")).strip_edges()
			var mood2: String = String((fm as Dictionary).get("mood", "")).to_lower().strip_edges()
			if fid != "" and VALID_MOODS.has(mood2):
				out["fish_moods"].append({"id": fid, "mood": mood2})
	out["narration"] = String(d.get("narration", "")).strip_edges()
	return out


# --- GBNF emission (forward-compatible; ready for native decoding) ----------

# A GBNF grammar string for each JSON kind. Every grammar has a `root` symbol,
# the one thing llama.cpp refuses to run without. Intent constrains region/mood
# to the enum, so an out-of-vocab token is structurally unreachable.
static func gbnf(kind: String) -> String:
	var ws: String = "ws ::= [ \\t\\n]*"
	var str_rule: String = "string ::= \"\\\"\" ([^\"\\\\] | \"\\\\\" .)* \"\\\"\""
	match kind:
		KIND_BIOS:
			return "\n".join([
				"root ::= \"{\" ws \"\\\"bios\\\"\" ws \":\" ws bios ws \"}\"",
				"bios ::= \"[\" ws (bio (ws \",\" ws bio)*)? ws \"]\"",
				"bio ::= \"{\" ws \"\\\"id\\\"\" ws \":\" ws string ws \",\" ws \"\\\"line\\\"\" ws \":\" ws string ws \"}\"",
				str_rule, ws,
			])
		KIND_INTENT:
			return "\n".join([
				"root ::= \"{\" ws \"\\\"regions\\\"\" ws \":\" ws regions ws \",\" ws \"\\\"fish_moods\\\"\" ws \":\" ws fishmoods ws \",\" ws \"\\\"narration\\\"\" ws \":\" ws string ws \"}\"",
				"regions ::= \"[\" ws (region (ws \",\" ws region)*)? ws \"]\"",
				"region ::= \"{\" ws \"\\\"region\\\"\" ws \":\" ws regionval ws \",\" ws \"\\\"mood\\\"\" ws \":\" ws moodval ws \"}\"",
				"fishmoods ::= \"[\" ws (fishmood (ws \",\" ws fishmood)*)? ws \"]\"",
				"fishmood ::= \"{\" ws \"\\\"id\\\"\" ws \":\" ws string ws \",\" ws \"\\\"mood\\\"\" ws \":\" ws moodval ws \"}\"",
				"regionval ::= " + _enum_rule(VALID_REGIONS),
				"moodval ::= " + _enum_rule(VALID_MOODS),
				str_rule, ws,
			])
		KIND_CHRONICLE:
			return "\n".join([
				"root ::= \"{\" ws \"\\\"line\\\"\" ws \":\" ws string ws \"}\"",
				str_rule, ws,
			])
		_:
			return ""


static func _enum_rule(values: PackedStringArray) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for v in values:
		parts.append("\"\\\"%s\\\"\"" % v)
	return " | ".join(parts)


# --- Ollama structured-output schema (forward-compatible) -------------------

# A JSON Schema object suitable for Ollama's `format` field (structured
# outputs, Ollama >= 0.5). Not wired into the live request yet to preserve
# compatibility with older servers; the validators above are the live guard.
static func ollama_format(kind: String) -> Variant:
	match kind:
		KIND_BIOS:
			return {
				"type": "object",
				"properties": {
					"bios": {
						"type": "array",
						"items": {
							"type": "object",
							"properties": {
								"id": {"type": "string"},
								"line": {"type": "string"},
							},
							"required": ["id", "line"],
						},
					},
				},
				"required": ["bios"],
			}
		KIND_INTENT:
			return {
				"type": "object",
				"properties": {
					"regions": {
						"type": "array",
						"items": {
							"type": "object",
							"properties": {
								"region": {"type": "string", "enum": Array(VALID_REGIONS)},
								"mood": {"type": "string", "enum": Array(VALID_MOODS)},
							},
							"required": ["region", "mood"],
						},
					},
					"fish_moods": {
						"type": "array",
						"items": {
							"type": "object",
							"properties": {
								"id": {"type": "string"},
								"mood": {"type": "string", "enum": Array(VALID_MOODS)},
							},
							"required": ["id", "mood"],
						},
					},
					"narration": {"type": "string"},
				},
				"required": ["regions", "fish_moods", "narration"],
			}
		KIND_CHRONICLE:
			return {
				"type": "object",
				"properties": {"line": {"type": "string"}},
				"required": ["line"],
			}
		_:
			return null
