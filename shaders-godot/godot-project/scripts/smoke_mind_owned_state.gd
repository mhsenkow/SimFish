extends SceneTree

const Soul = preload("res://scripts/mind_soul.gd")
const Relevance = preload("res://scripts/fish_relevance.gd")
const SoulLearning = preload("res://scripts/mind_soul_pass2.gd")
const Binding = preload("res://scripts/fish_binding.gd")

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("mind_owned_state")
	var cfg: Node = root.get_node("TankConfig")
	var original_felt: bool = cfg.felt_self_enabled
	var original_voice: bool = cfg.sentience_voice_off
	cfg.felt_self_enabled = true
	cfg.sentience_voice_off = false
	var f := Fish.new()
	f.id = "owned_state"
	var ms := MindState.new()
	ms.attention_focus = "food"
	ms.workspace_ignited = true
	# Real nested commit: outer Soul retains its state while pass 2 learns.
	Soul.after_workspace_commit(f, ms, null)
	t.check(not (Soul.ensure(f)["habits"] as Dictionary).is_empty(),
		"outer workspace commit retains nested habit learning")
	var binding: Dictionary = Binding.ensure(f)
	binding["phi_proxy"] = 0.2
	Relevance.ensure(f)
	binding["phi_proxy"] = 0.8
	t.approx(Binding.integration_score(f), 0.8,
		"relevance reads do not orphan another module's held binding state")
	var saved: Dictionary = Soul.to_dict(f)
	(saved["habits"] as Dictionary).clear()
	t.check(not (Soul.ensure(f)["habits"] as Dictionary).is_empty(), "save snapshot is detached")
	var packed: Dictionary = MindFishProxy.capture(f)
	var proxy: MindFishProxy = MindFishProxy.from_dict(packed)
	(Soul.ensure(proxy)["habits"] as Dictionary).clear()
	t.check(not (Soul.ensure(f)["habits"] as Dictionary).is_empty(), "worker proxy owns separate soul state")
	(Relevance.ensure(proxy))["explore"] = 0.99
	t.check(float(Relevance.ensure(f)["explore"]) != 0.99, "worker felt state is detached")
	var incoming: Dictionary = Soul.to_dict(f)
	Soul.from_dict(proxy, incoming)
	(incoming["habits"] as Dictionary).clear()
	t.check(not (Soul.ensure(proxy)["habits"] as Dictionary).is_empty(), "loaded state is detached from its input")
	var clock := MindSimSnap.new()
	f.attention_focus = "food"
	clock.day_phase = 0.2501
	var morning_key: String = SoulLearning.context_key(f, clock)
	clock.day_phase = 0.2512
	t.equals(SoulLearning.context_key(f, clock), morning_key, "nearby clock ticks reuse learned context")
	for phase in [0.0, 0.25, 0.5, 0.75]:
		clock.day_phase = phase
		t.check(SoulLearning.context_key(f, clock).contains(SoulLearning._phase_context(phase)),
			"coarse daily context at %s" % phase)
	clock.day_phase = 0.25
	for _step in 20:
		SoulLearning.after_commit(f, ms, clock, "food")
	t.check(float((Soul.ensure(f)["habits"] as Dictionary)[morning_key]["strength"]) >= 0.68,
		"repeated familiar context can actually compile a habit")
	var legacy: Dictionary = {}
	for i in 300:
		legacy[str(i)] = {"strength": 0.5}
	SoulLearning._store_context(legacy, "299", {"strength": 0.9})
	t.check(legacy.size() <= SoulLearning.MAX_LEARNED_CONTEXTS, "large old context table is bounded")
	t.approx(float(legacy["299"]["strength"]), 0.9, "pruning retains reinforced context")
	for i in 300:
		SoulLearning._store_context(legacy, "new_%d" % i, {"strength": 0.2})
	t.equals(legacy.size(), SoulLearning.MAX_LEARNED_CONTEXTS, "new contexts remain bounded")
	f._soul_mind = {"schema_version": -1, "obsolete": true}
	t.check(not Soul.ensure(f).has("obsolete"), "obsolete schema still resets safely")
	t.check(Soul.enabled(), "cached config keeps the live enabled flag")
	cfg.felt_self_enabled = false
	t.check(not Soul.enabled(), "same-frame disable is visible through cached config")
	cfg.felt_self_enabled = true
	t.check(Soul.enabled(), "same-frame re-enable is visible through cached config")
	cfg.sentience_voice_off = true
	t.check(not Soul.enabled(), "voice-off override remains live")
	cfg.felt_self_enabled = original_felt
	cfg.sentience_voice_off = original_voice
	f.free()
	quit(t.finish())
