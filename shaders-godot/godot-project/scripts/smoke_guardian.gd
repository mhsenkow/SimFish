extends SceneTree

# Headless smoke: Guardian mind + journal + active inference.
const GuardianMind = preload("res://scripts/guardian_mind.gd")
const GuardianJournal = preload("res://scripts/guardian_journal.gd")
const GuardianGenerative = preload("res://scripts/guardian_generative.gd")


func _init() -> void:
	var arc: Dictionary = GuardianMind.default_arc()
	assert(arc.has("mind"))
	GuardianMind.record_visit(arc, 1000, 3600)
	GuardianMind.record_player_action(arc, "fed", "pellets")
	GuardianMind.maybe_advance_chapter(arc, 86400.0 * 6.0)
	assert(int(arc.get("chapter", 0)) >= 2)
	assert(arc.has("generative"))
	var g: Fish = Fish.new()
	g.is_guardian = true
	g.fish_name = "Ripple"
	g.familiarity = 0.6
	g.hunger = 0.2
	g.position = Vector3(0, 2, 0)
	var inf: Dictionary = GuardianGenerative.tick(g, null, arc, 0.1)
	assert(inf.has("chosen_policy"))
	assert(str(inf.get("chosen_policy", "")) != "")
	var fe_before: float = float(GuardianGenerative.ensure(arc).get("free_energy", 1.0))
	GuardianGenerative.note_feed(arc)
	assert(float(GuardianGenerative.ensure(arc).get("free_energy", 1.0)) < fe_before)
	var blanket: Dictionary = GuardianGenerative.markov_blanket()
	assert(blanket.has("sense") and blanket.has("act"))
	var ctx: Dictionary = GuardianMind.build_ai_context(g, null, arc, "feed_nudge")
	assert(ctx.has("generative_policy"))
	var woven: String = GuardianJournal.weave_callback(
			[{"text": "...Lazuli seems calm today.", "tags": PackedStringArray(["observe"])}],
			"Still watching.", "daily")
	assert(woven.contains("Lazuli") or woven.contains("Still watching"))
	var quiet: String = GuardianMind.compose_quiet_inner_line(null, arc, 7200)
	assert(quiet != "")
	var journal: Array = []
	GuardianJournal.append_entry(journal, "Test entry.", 0,
			PackedStringArray(["test"]), {"sim_day": "Day 1", "source": "template"})
	assert(journal.size() == 1)
	var pred: Array = [{"sim_day": "Day 0", "text": "Old voice.", "chapter": 1}]
	GuardianJournal.merge_predecessor(journal, pred, "Ripple", "A bold tetra.")
	assert(journal.size() >= 2)
	var bb: String = GuardianJournal.format_bbcode(journal)
	assert(bb.contains("Ripple"))
	print("[smoke_guardian] OK — mind + journal + generative")
	quit()
