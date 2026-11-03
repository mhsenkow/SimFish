extends SceneTree

# SENTIENCE_THE_LOOM_THAT_THINKS #1 — global voice cooldown decays with AI off.


const MindNarrator = preload("res://scripts/mind_narrator.gd")


func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_global_voice_cooldown")
	var ai: Node = root.get_node_or_null("AIDirector")
	if not t.check(ai != null, "AIDirector autoload present"):
		quit(t.finish())
		return

	# Default / typical play: AI disabled. Process must still tick the CD.
	ai.set("enabled", false)
	ai.set_process(true)
	ai.set_physics_process(false)

	MindNarrator.mark_voice_spoke()
	t.check(not MindNarrator.global_voice_ready(), "cooldown engaged after reply")

	# Advance wall time past GLOBAL_VOICE_COOLDOWN_S via the always-on owner.
	var step: float = 1.0
	var advanced: float = 0.0
	while advanced < MindNarrator.GLOBAL_VOICE_COOLDOWN_S + 2.0:
		ai._process(step)
		advanced += step
	t.check(MindNarrator.global_voice_ready(),
			"global_voice_ready after 20s with AI off")

	# Exact boundary: one full cooldown of tick clears it.
	MindNarrator.mark_voice_spoke()
	t.check(not MindNarrator.global_voice_ready(), "re-engaged")
	MindNarrator.tick_global_cooldown(MindNarrator.GLOBAL_VOICE_COOLDOWN_S)
	t.check(MindNarrator.global_voice_ready(), "exact cooldown clears")

	quit(t.finish())
