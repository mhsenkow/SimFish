extends SceneTree

# MindState channel smoke — ENGINEERING_EXCELLENCE §14–15.


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	var f: Fish = Fish.new()
	f.fish_name = "Test"
	f.familiarity = 0.8
	f._mind_workspace = [{"label": "hunger", "salience": 0.7, "coalition": ["body"]}]
	f._workspace_ignited = true
	f._prediction_error = 0.42
	f._life_stance = "wary"
	f._keeper_pending = {"keeper_text": "hello"}
	var ms: MindState = MindChannel.for_cycle(f, true)
	if ms.workspace.is_empty():
		failed.append("workspace should sync from fish")
	if ms.prediction_error < 0.4:
		failed.append("prediction_error should sync")
	if MindChannel.workspace_label(ms) != "hunger":
		failed.append("workspace_label should read primary bid")
	ms.prediction_error = 0.1
	ms.life_stance = "calm"
	MindChannel.commit(f, ms)
	if float(f._prediction_error) > 0.15:
		failed.append("commit should write back prediction_error")
	if str(f._life_stance) != "calm":
		failed.append("commit should write back life_stance")
	var ctx: Dictionary = MindContext.build_for_fish(f, null, "inspect", ms)
	if not bool(ctx.get("workspace_ignited", false)):
		failed.append("build_for_fish should use MindState workspace_ignited")
	if str(ctx.get("life_stance", "")) != "calm":
		failed.append("build_for_fish should use MindState life_stance")
	var d: Dictionary = ms.to_dict()
	var ms2: MindState = MindState.new()
	ms2.from_dict(d)
	if ms2.schema_version < 3:
		failed.append("schema_version should be 3+")
	if ms2.prediction_error > 0.15:
		failed.append("round-trip prediction_error")
	if failed.is_empty():
		print("[smoke] mind_channel OK")
		quit(0)
	else:
		for msg in failed:
			push_error("[smoke] " + msg)
		quit(1)
