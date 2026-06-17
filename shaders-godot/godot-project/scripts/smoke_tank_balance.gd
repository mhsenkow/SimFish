# Long-run ecology soak — moved to dev/balance_soak.tscn (scene entry loads autoloads first).
#
#   godot --headless --path shaders-godot/godot-project res://dev/balance_soak.tscn

extends SceneTree

func _initialize() -> void:
	var packed: PackedScene = load("res://dev/balance_soak.tscn")
	if packed == null:
		push_error("[balance] failed to load dev/balance_soak.tscn")
		quit(1)
		return
	var runner: Node = packed.instantiate()
	runner.name = "BalanceSoakRunner"
	root.add_child(runner)
