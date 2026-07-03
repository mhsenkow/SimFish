extends SceneTree

const MindReplayParity = preload("res://scripts/mind_replay_parity.gd")


func _initialize() -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	var f := Fish.new()
	parent.add_child(f)
	f.id = "golden_fish"
	f.species = "glassdart"
	f.swim_pattern = "school"
	f.schooling_strength = 1.2
	seed(424242)
	var h: int = MindReplayParity.golden_digest_hash(f, null, 16)
	print("[golden_hash] %d" % h)
	parent.queue_free()
	quit(0)
