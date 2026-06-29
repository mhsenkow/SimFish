extends SceneTree

# 0E (ENGINEERING #14/#15) — MindState is the authority for the Global Workspace
# triplet (workspace / workspace_ignited / attention_focus), and broadcast mirrors
# it onto the fish via MindState.commit_workspace_to(). This pins the contract AND
# guards the latent revert it fixes: broadcast used to update ms.workspace but NOT
# ms.attention_focus, so MindChannel.commit's apply_to_fish reverted attention_focus
# to its stale cycle-start value. Now the triplet moves together through a full
# sync -> broadcast -> commit cycle.

const GlobalWorkspace = preload("res://scripts/global_workspace.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	var f: Fish = Fish.new()
	root.add_child(f)
	f.id = "ws-chan"
	f.attention_focus = "stale"   # prior-frame value the old commit would revert to

	# Cycle-start sync captures the stale value into ms (ms.attention_focus="stale").
	var ms = MindChannel.for_cycle(f, true)
	_assert(failed, ms.attention_focus == "stale", "for_cycle syncs attention_focus off the fish")

	# Broadcast a workspace whose primary content is "food".
	var result := {
		"contents": [{"label": "food", "salience": 0.8, "coalition": "food"}],
		"ignited": true,
	}
	GlobalWorkspace.broadcast(f, result, ms)

	# MindState is now the authority — it carries the new focus, not the stale one.
	_assert(failed, ms.attention_focus == "food", "broadcast sets ms.attention_focus (authority)")
	_assert(failed, ms.workspace.size() == 1, "broadcast sets ms.workspace")
	_assert(failed, ms.workspace_ignited == true, "broadcast sets ms.workspace_ignited")
	# ...and it's mirrored onto the fish for the rest of tick() to read.
	_assert(failed, f.attention_focus == "food", "broadcast mirrors focus onto the fish")
	_assert(failed, f._mind_workspace.size() == 1, "broadcast mirrors workspace onto the fish")
	_assert(failed, f._workspace_ignited == true, "broadcast mirrors ignition onto the fish")

	# THE FIX: commit (apply_to_fish) must keep "food", not revert to "stale".
	MindChannel.commit(f, ms)
	_assert(failed, f.attention_focus == "food",
			"commit keeps the broadcast focus (no revert to stale cycle-start value)")
	_assert(failed, f._mind_workspace.size() == 1, "commit keeps the workspace")

	# Empty workspace: focus clears and the behavior bias resets.
	GlobalWorkspace.broadcast(f, {"contents": [], "ignited": false}, ms)
	_assert(failed, ms.attention_focus == "" and f.attention_focus == "",
			"empty workspace clears focus on ms + fish")
	_assert(failed, f._mind_workspace.is_empty(), "empty workspace clears the fish workspace")
	_assert(failed, f._behavior_ws_bias == Vector3.ZERO, "empty workspace zeroes behavior bias")

	if failed.is_empty():
		print("[smoke] workspace_channel OK")
		quit(0)
	else:
		for m in failed:
			push_error("[smoke] " + m)
		quit(1)


func _assert(failed: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		failed.append(msg)
