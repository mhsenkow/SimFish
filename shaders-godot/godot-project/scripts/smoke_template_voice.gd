extends SceneTree

# SYSTEMIC #16 — template voice produces text when no LLM is available.

const MindNarrator = preload("res://scripts/mind_narrator.gd")
const MindContext = preload("res://scripts/mind_context.gd")
const MakeItThere = preload("res://scripts/make_it_there.gd")


func _initialize() -> void:
	if not _run_all():
		quit(1)
		return
	print("[smoke_template_voice] OK")
	quit(0)


func _fail(msg: String) -> bool:
	push_error(msg)
	return false


func _run_all() -> bool:
	var f: Fish = Fish.new()
	f.id = "tpl-smoke-1"
	f.fish_name = "Ripple"
	f.mood = 0.1
	f.hunger = 0.4
	f._keeper_pending = {
		"keeper_text": "hello",
		"keeper_felt": "comfort",
		"keeper_intent": "greeting",
	}
	var ctx: Dictionary = MindContext.build_for_keeper_turn(f, null, "keeper_reply")
	var fb: String = MindNarrator.template_fish_reply(ctx)
	if fb.strip_edges() == "":
		return _fail("template_fish_reply empty")
	var gline: String = MakeItThere.away_recap_fallback({
		"away_tier": "short",
		"feel": "calm",
		"keeper_moniker": "keeper",
	})
	if gline.strip_edges() == "":
		return _fail("away_recap_fallback empty")
	var thought: String = MindNarrator.template_fish_thought({
		"feel": "anxious", "species": "neon_tetra", "hunger": 0.3,
	})
	if thought.strip_edges() == "":
		return _fail("template_fish_thought empty")
	var clipped: String = MindNarrator.sanitize_prose(
			"A small body stirs in the water, its presence a reminder of what lies beyond the glass",
			MindNarrator.FISH_THOUGHT_MAX_WORDS)
	if clipped.ends_with(" the") or clipped.ends_with(" beyond"):
		return _fail("sanitize_prose must drop dangling tail words")
	if not clipped.ends_with("…") and not clipped.ends_with("."):
		return _fail("sanitize_prose must end a clipped thought cleanly")
	return true
