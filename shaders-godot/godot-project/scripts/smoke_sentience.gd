extends SceneTree

# Headless smoke: sentience spine — mind narrator fact-check + guardian context.
const MindNarrator = preload("res://scripts/mind_narrator.gd")
const GuardianMind = preload("res://scripts/guardian_mind.gd")


func _init() -> void:
	_test_narrator_fact_check()
	_test_mind_context_shape()
	_test_confidence_gate()
	_test_language_clause()
	_test_milestone()
	print("[smoke_sentience] OK — narrator + context")
	quit()


func _test_narrator_fact_check() -> void:
	var ctx: Dictionary = {
		"feel": "anxious",
		"stress": 0.85,
		"allowed_fish_names": PackedStringArray(["Ripple", "Mira"]),
		"fish_name": "Ripple",
	}
	var bad: Dictionary = MindNarrator.finalize_line(
		ctx, "I am so happy and delighted today!", "fallback line")
	if String(bad.get("line", "")) != "fallback line":
		push_error("expected emotion contradiction fallback")
		quit(1)
	var good: Dictionary = MindNarrator.finalize_line(
		ctx, "The water feels heavy; I keep close to the plants.", "fallback line")
	if not String(good.get("line", "")).contains("water"):
		push_error("expected good line to pass")
		quit(1)
	var invented: Dictionary = MindNarrator.finalize_line(
		ctx, "Zephyr chased me around the tank.", "safe template")
	if String(invented.get("line", "")) != "safe template":
		push_error("expected unknown entity fallback")
		quit(1)


func _test_mind_context_shape() -> void:
	var arc: Dictionary = GuardianMind.default_arc()
	var ctx: Dictionary = GuardianMind.build_ai_context(null, null, arc, "daily")
	if not ctx.has("allowed_fish_names") or not ctx.has("feel"):
		push_error("guardian context missing keys")
		quit(1)


func _test_confidence_gate() -> void:
	if MindNarrator.should_attempt_generation({}):
		push_error("thin context should skip generation")
		quit(1)


func _test_language_clause() -> void:
	var clause: String = MindNarrator.language_prompt_clause("es")
	if not clause.contains("Spanish"):
		push_error("expected Spanish language clause")
		quit(1)


func _test_milestone() -> void:
	var arc: Dictionary = GuardianMind.default_arc()
	GuardianMind.record_milestone(arc, "first feed together")
	var ctx: Dictionary = GuardianMind.build_ai_context(null, null, arc, "daily")
	var ms: Variant = ctx.get("shared_milestones", null)
	if not (ms is PackedStringArray) or (ms as PackedStringArray).is_empty():
		push_error("expected shared milestone in context")
		quit(1)
