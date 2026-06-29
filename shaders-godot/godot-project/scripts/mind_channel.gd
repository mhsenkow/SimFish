class_name MindChannel
extends RefCounted

# ENGINEERING_EXCELLENCE §14–15 — MindState is the sole mind↔fish channel for
# cognitive modules. Route reads/writes here instead of f.get("_mind_*").

const MindStateScript = preload("res://scripts/mind_state.gd")


static func for_cycle(f: Fish, rich: bool = true) -> MindState:
	assert(f != null, "MindChannel.for_cycle requires a Fish")
	var ms: MindState = MindState.for_fish(f, rich)
	ms.sync_from_fish(f)
	return ms


static func commit(f: Fish, ms: MindState) -> void:
	assert(f != null and ms != null)
	ms.apply_to_fish(f)


static func workspace_label(ms: MindState) -> String:
	if ms.workspace.is_empty():
		return ms.attention_focus
	return str((ms.workspace[0] as Dictionary).get("label", ms.attention_focus))


static func assert_mind_field(f: Fish, field: String) -> void:
	if not OS.is_debug_build():
		return
	assert(f.get(field) != null, "Missing mind field on fish: %s" % field)
