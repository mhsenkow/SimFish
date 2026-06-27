extends SceneTree

# Headless smoke: Guardian mind + journal + arc defaults compile and run.
const GuardianMind = preload("res://scripts/guardian_mind.gd")
const GuardianJournal = preload("res://scripts/guardian_journal.gd")


func _init() -> void:
	var arc: Dictionary = GuardianMind.default_arc()
	assert(arc.has("mind"))
	GuardianMind.record_visit(arc, 1000, 3600)
	GuardianMind.record_player_action(arc, "fed", "pellets")
	var journal: Array = []
	GuardianJournal.append_entry(journal, "Test entry.", 0,
			PackedStringArray(["test"]), {"sim_day": "Day 1", "source": "template"})
	assert(journal.size() == 1)
	var pred: Array = [{"sim_day": "Day 0", "text": "Old voice.", "chapter": 1}]
	GuardianJournal.merge_predecessor(journal, pred, "Ripple", "A bold tetra.")
	assert(journal.size() >= 2)
	var bb: String = GuardianJournal.format_bbcode(journal)
	assert(bb.contains("Ripple"))
	print("[smoke_guardian] OK — mind + journal")
	quit()
