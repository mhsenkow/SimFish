extends SceneTree

func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_mind_diff_isolation")
	var state := MindState.new()
	state.workspace = [{"label": "food", "nested": {"value": 1}}]
	state.self_model = {"nested": {"value": 1}}
	var previous: Dictionary = state.snapshot()
	t.check(state.diff(previous).is_empty(), "unchanged state produces no diff")
	state.mood = 0.01
	t.check(state.diff(previous).is_empty(), "small float noise remains suppressed")
	state.mood = 0.1
	state.workspace[0].nested.value = 2
	state.self_model.nested.value = 2
	t.equals(previous.workspace[0].nested.value, 1, "workspace snapshot owns its nested values")
	t.equals(previous.self_model.nested.value, 1, "self-model snapshot owns its nested values")
	var changes: Dictionary = state.diff(previous)
	t.has_keys(changes, ["mood", "workspace", "self_model"], "meaningful changes appear in diff")
	state.workspace[0].nested.value = 3
	state.self_model.nested.value = 3
	previous.workspace[0].nested.value = 4
	previous.self_model.nested.value = 4
	t.equals(changes.workspace.to[0].nested.value, 2, "new workspace diff is detached")
	t.equals(changes.workspace.from[0].nested.value, 1, "old workspace diff is detached")
	t.equals(changes.self_model.to.nested.value, 2, "new self-model diff is detached")
	t.equals(changes.self_model.from.nested.value, 1, "old self-model diff is detached")
	quit(t.finish())
