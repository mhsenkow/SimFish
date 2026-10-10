extends SceneTree

const WorldModel = preload("res://scripts/mind_world_model.gd")

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_mind_cycle_continuity")
	var cfg: Node = root.get_node("TankConfig")
	var original_felt: bool = cfg.felt_self_enabled
	var original_voice: bool = cfg.sentience_voice_off
	cfg.felt_self_enabled = true
	cfg.sentience_voice_off = false
	var fish := Fish.new()
	fish.id = "continuity"
	fish._mind_lod_tier = MindLOD.T2_WORLD_MODEL
	fish._cycle_lod_tier = MindLOD.T2_WORLD_MODEL
	fish.attention_focus = "food"
	for _cycle in 4:
		var state: MindState = MindChannel.for_cycle(fish)
		CognitionKernel.run_bind_encode_learn(fish, state, null, 0.2)
		MindChannel.commit(fish, state)
	var now: Dictionary = fish._felt_self.get("felt_now", {})
	t.equals((now.get("frames", []) as Array).size(), 4,
		"felt moments accumulate across complete cognitive commits")
	t.equals(fish._world_model.get("updates", 0), 4,
		"world predictions retain their recurrent learning between cycles")
	t.check(float(fish._felt_self.get("binding", {}).get("phi_proxy", 0.0)) > 0.3,
		"integration accumulates rather than restarting each cycle")
	var model: Dictionary = WorldModel.ensure_model(fish)
	var weights: PackedFloat32Array = (model.gw.Wo as PackedFloat32Array).duplicate()
	WorldModel._gru_learn_readout(model, PackedFloat32Array([1, 1, 1]),
		PackedFloat32Array([0, 0, 0]), 0.2)
	t.check(model.gw.Wo != weights, "readout learns from a prediction error using the model's hidden state")
	fish._soul_mind["habits"] = {"food": {"strength": 0.5}}
	fish._soul_mind["biography"] = {"lines": ["a familiar corner"]}
	var proxy: MindFishProxy = MindFishProxy.from_dict(MindFishProxy.capture(fish), true)
	var before: int = int(fish._world_model.updates)
	var next_state: MindState = MindChannel.for_cycle(fish)
	CognitionKernel.run_bind_encode_learn(fish, next_state, null, 0.2)
	MindChannel.commit(fish, next_state, true)
	fish._soul_mind.habits.food.strength = 0.9
	fish._soul_mind.biography.lines.append("a new meal")
	proxy._soul_mind["self_pred_focus"] = "rest"
	proxy._felt_self["relevance"] = {"new_attention": true}
	proxy.apply_mind_to(fish, true)
	t.equals(fish._world_model.updates, before + 1, "late worker preserves newer recurrent predictions")
	t.equals((fish._felt_self.felt_now.frames as Array).size(), 5,
		"late worker preserves newer felt moments")
	t.check(fish._felt_self.relevance.get("new_attention", false),
		"worker can still contribute attention to an unchanged component")
	t.approx(fish._soul_mind.habits.food.strength, 0.9,
		"late worker preserves newly strengthened habits")
	t.equals(fish._soul_mind.biography.lines.size(), 2,
		"late worker preserves new biography moments")
	t.equals(fish._soul_mind.self_pred_focus, "rest",
		"worker still contributes its updated self-prediction")
	cfg.felt_self_enabled = original_felt
	cfg.sentience_voice_off = original_voice
	fish.free()
	quit(t.finish())
