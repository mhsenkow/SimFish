extends SceneTree

# Headless smoke: MAKE_IT_THERE runtime helpers + away/obituary context.
const MakeItThere = preload("res://scripts/make_it_there.gd")
const MindNarrator = preload("res://scripts/mind_narrator.gd")


func _initialize() -> void:
	var session: Dictionary = MakeItThere.fresh_session()
	if session.get("look_back_used", true):
		push_error("fresh session should not have look_back_used")
		quit(1)
		return
	var extras: Dictionary = MakeItThere.away_recap_extras(
			90000, 0.35, 1, 2, {"chapter": 0})
	if not extras.has("away_tier"):
		push_error("away recap extras missing tier")
		quit(1)
		return
	var fb: String = MakeItThere.away_recap_fallback({"away_tier": "long", "away_summary": "steady"})
	if fb == "":
		push_error("away recap fallback empty")
		quit(1)
		return
	var ob: Dictionary = MakeItThere.build_obituary_context(null, null)
	if not ob.is_empty():
		push_error("obituary ctx should be empty for null fish")
		quit(1)
		return
	var tpl: String = MindNarrator.template_obituary({
		"fish_name": "Nix",
		"salient_memories": PackedStringArray(["fed near the glass"]),
	})
	if tpl == "":
		push_error("template obituary empty")
		quit(1)
		return
	print("[smoke_make_it_there] OK")
	quit(0)
