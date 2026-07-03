class_name MindNarratorWorker
extends RefCounted

# PERFORMANCE_UNTHROTTLED #54 — template + lexicon polish fully off main thread.

const MindNarrator = preload("res://scripts/mind_narrator.gd")
const CognitiveSchema = preload("res://scripts/cognitive_schema.gd")


static func build_thought_package(ctx: Dictionary) -> Dictionary:
	var op: Dictionary = CognitiveSchema.template_op(ctx)
	var prompt: String = MindNarrator.build_fish_thought_prompt(ctx)
	var line: String = MindNarrator.template_fish_thought(ctx)
	if line == "":
		line = str(op.get("line", ""))
	else:
		op["line"] = line
	return {"op": op, "prompt": prompt, "line": line}
