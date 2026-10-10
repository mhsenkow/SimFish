extends SceneTree

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_mind_handoff")
	var cfg: Node = root.get_node("TankConfig")
	var original_threads: bool = cfg.mind_brain_threads
	cfg.mind_brain_threads = false
	t.check(not MindBrainPool.enabled(), "headless respects the serial cognition setting")
	cfg.mind_brain_threads = true
	t.check(MindBrainPool.enabled(), "cached config still reads changes immediately")
	cfg.mind_brain_threads = original_threads
	var state := MindState.new()
	state.workspace = [{"label": "food", "nested": {"value": 1}}]
	state.felt_self = {"moments": [{"value": 2}]}
	state.episodic_retrieval_hint = {"kind": "food", "pos": Vector3(2, 1, 3)}
	state.bid_salience_mods = {"food": 0.6}
	state.workspace_ignited = true
	state.system2_pending = true
	state.eligibility_peak = 0.7
	state.writeback_cd = 0.9
	state.sleep_depth = 0.35
	state.dream_wisp = "a familiar corner"
	var exported: Dictionary = state.to_dict()
	exported.workspace[0].nested.value = 9
	exported.felt_self.moments[0].value = 8
	t.equals(state.workspace[0].nested.value, 1, "default export owns nested workspace values")
	t.equals(state.felt_self.moments[0].value, 2, "default export owns felt continuity")
	var restored := MindState.new()
	restored.from_dict(exported)
	exported.workspace[0].nested.value = 10
	t.equals(restored.workspace[0].nested.value, 9, "default import remains detached from the caller")
	var owned: Dictionary = state.to_dict()
	var adopted := MindState.new()
	adopted.from_dict(owned, true)
	t.equals(adopted.to_dict(), state.to_dict(), "owned handoff preserves every serialized field")
	adopted.workspace[0].nested.value = 3
	t.equals(state.workspace[0].nested.value, 1, "worker's owned input cannot mutate the originating mind")
	t.check(adopted.workspace_ignited and adopted.system2_pending, "workspace and deliberation flags survive handoff")
	t.approx(adopted.eligibility_peak, 0.7, "learning trace survives handoff")
	t.equals(adopted.episodic_retrieval_hint, state.episodic_retrieval_hint, "recall cue survives handoff")
	t.equals(adopted.bid_salience_mods, state.bid_salience_mods, "attention modulation survives handoff")
	t.approx(adopted.writeback_cd, 0.9, "writeback cooldown survives handoff")
	t.approx(adopted.sleep_depth, 0.35, "sleep depth survives handoff")
	t.equals(adopted.dream_wisp, state.dream_wisp, "dream continuity survives handoff")
	var legacy: Dictionary = {"schema_version": 1, "workspace": [{"label": "legacy"}]}
	var migrated := MindState.new()
	migrated.from_dict(legacy)
	t.equals(legacy.schema_version, 1, "normal migration leaves the original save intact")
	t.equals(migrated.schema_version, MindState.SCHEMA_VERSION, "legacy saves still migrate")
	var future: Dictionary = {"schema_version": MindState.SCHEMA_VERSION + 1}
	migrated.from_dict(future, true)
	t.equals(migrated.schema_version, MindState.SCHEMA_VERSION + 1, "owned handoff does not downgrade future schemas")
	quit(t.finish())
