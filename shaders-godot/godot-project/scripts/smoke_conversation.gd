extends SceneTree

# SENTIENCE_THE_CONVERSATION — keeper reply, session, lexicon, keeper-model, eval.

const CognitiveSchema = preload("res://scripts/cognitive_schema.gd")
const MindConversation = preload("res://scripts/mind_conversation.gd")
const MindDebug = preload("res://scripts/mind_debug.gd")
const MindKeeperModel = preload("res://scripts/mind_keeper_model.gd")
const MindLexicon = preload("res://scripts/mind_lexicon.gd")
const MindNarrator = preload("res://scripts/mind_narrator.gd")
const KeeperInput = preload("res://scripts/keeper_input.gd")
const KeeperCare = preload("res://scripts/keeper_care.gd")


func _initialize() -> void:
	if not _run_all():
		quit(1)
		return
	print("[smoke] conversation OK")
	quit(0)


func _run_all() -> bool:
	_test_reply_template()
	_test_reply_validator()
	_test_session()
	_test_interpret()
	_test_lexicon()
	_test_keeper_model()
	_test_eval_harness()
	_test_determinism()
	_test_slim_context()
	_test_keeper_care()
	return true


func _make_fish() -> Fish:
	var f: Fish = Fish.new()
	f.id = "smoke-conv-1"
	f.fish_name = "Pip"
	f.personality = {"boldness": 0.5, "curiosity": 0.5, "sociability": 0.5,
			"gluttony": 0.5, "calm": 0.5}
	f.familiarity = 0.55
	return f


func _test_reply_template() -> void:
	var ctx: Dictionary = {
		"feel": "content",
		"keeper_intent": "greeting",
		"keeper_comprehension": 0.8,
		"familiarity": 0.6,
		"intimacy": 0.55,
		"stress": 0.1,
		"hunger": 0.2,
	}
	var line: String = MindNarrator.template_fish_reply(ctx)
	assert(line != "", "template reply empty")
	assert(line.split(" ", false).size() <= MindNarrator.FISH_REPLY_MAX_WORDS,
			"template too long")
	ctx["keeper_intent"] = "unknown_sound"
	ctx["keeper_comprehension"] = 0.1
	assert(MindNarrator.template_fish_reply(ctx).contains("don't know"),
			"unknown sound template")


func _test_reply_validator() -> void:
	var ctx: Dictionary = {
		"feel": "anxious",
		"stress": 0.85,
		"allowed_fish_names": PackedStringArray(),
	}
	assert(not bool(MindNarrator.validate_reply_line(ctx, "I am so happy today").get("ok", true)),
			"stress/happy should reject")
	assert(bool(MindNarrator.validate_reply_line(ctx, "water feels heavy").get("ok", false)),
			"grounded stress line ok")
	assert(MindNarrator.is_manipulative("feed me or I'm sad"),
			"coercion blocked")


func _test_session() -> void:
	var f: Fish = _make_fish()
	var result: Dictionary = {"ok": true, "too_wary": false}
	MindConversation.on_keeper_submit(f, "hello", null, result)
	assert(MindConversation.session_active(f), "session should start")
	MindConversation.note_reply(f, "that shape again", null)
	assert(MindConversation.dialogue_snippet(f).size() >= 2, "ring records turns")


func _test_interpret() -> void:
	var f: Fish = _make_fish()
	f._learned_words = {"dinner": {"kind": "food", "pairings": 4, "strength": 0.9, "last_t": 0}}
	var d: Dictionary = KeeperInput._interpret_keeper(f, "dinner")
	assert(str(d.get("keeper_intent", "")) == "food", "food intent")
	var op: Dictionary = CognitiveSchema.template_reply_op({
		"feel": "calm",
		"keeper_intent": "greeting",
		"keeper_comprehension": 0.7,
		"familiarity": 0.6,
		"intimacy": 0.55,
	})
	assert(CognitiveSchema.validate_reply_op(op, {
		"feel": "calm",
		"keeper_intent": "greeting",
		"familiarity": 0.6,
	}), "reply op valid: %s line=%s" % [JSON.stringify(op), str(op.get("line", ""))])
	assert(CognitiveSchema.gbnf_reply_grammar().contains("short_string"), "gbnf reply")


func _test_lexicon() -> void:
	var f: Fish = _make_fish()
	var parent: Fish = _make_fish()
	parent.id = "parent-1"
	parent._learned_words = {"hello": {"kind": "keeper", "pairings": 4, "strength": 0.8, "last_t": 0}}
	var child: Fish = Fish.new()
	child.id = "child-1"
	MindLexicon.inherit_from_parent(child, parent)
	assert(child._learned_words.has("hello"), "generational drift")
	MindLexicon.try_pair_on_keeper_word(f, "dinner", null)
	assert(f._learned_words.has("dinner"), "pair on keeper word")


func _test_keeper_model() -> void:
	var f: Fish = _make_fish()
	var result: Dictionary = {"ok": true, "felt": "greeting", "keeper_valence": 0.3,
			"keeper_arousal": 0.2}
	MindKeeperModel.on_keeper_line(f, "hello hello", result, null)
	var km: Dictionary = MindKeeperModel.ensure(f)
	assert(int(km.get("conversation_count", 0)) >= 1, "conversation counted")
	var ctx: Dictionary = MindKeeperModel.merge_context({}, f, null)
	assert(ctx.has("keeper_moniker"), "moniker in context")


func _test_eval_harness() -> void:
	var ctx: Dictionary = {"feel": "calm", "stress": 0.1, "allowed_fish_names": PackedStringArray()}
	var ev: Dictionary = MindDebug.evaluate_conversation_reply(ctx, "steady here")
	assert(bool(ev.get("ok", false)), "eval pass good line")
	ev = MindDebug.evaluate_conversation_reply(ctx, "feed me or I'm sad")
	assert(not bool(ev.get("ok", true)), "eval fail manipulative")


func _test_determinism() -> void:
	var f: Fish = _make_fish()
	var a: String = MindConversation.reply_cache_key(f, "hi")
	var b: String = MindConversation.reply_cache_key(f, "hello")
	assert(a != b, "message hash differs")
	var a2: String = MindConversation.reply_cache_key(f, "hi")
	assert(a == a2, "replay stable")


func _test_slim_context() -> void:
	var f: Fish = _make_fish()
	f._keeper_pending = {"keeper_text": "hi", "keeper_intent": "greeting"}
	var slim: Dictionary = MindContext.build_for_keeper_turn(f, null, "keeper_reply")
	assert(slim.has("keeper_text"), "slim has keeper text")
	assert(not slim.has("tank_society"), "slim omits society")


func _test_keeper_care() -> void:
	var f: Fish = _make_fish()
	f.spooked = 0.5
	f.stress = 0.6
	f.attention_focus = "threat"
	var stats: Dictionary = {
		"dissolved_o2": 0.38,
		"fish_stocking_ratio": 1.2,
		"ammonia": 0.0,
		"nitrite": 0.0,
		"waste_particles": 40,
		"algae_clusters": 25,
		"plant_total_biomass": 200.0,
		"bloom_intensity": 0.0,
		"is_saltwater": false,
	}
	assert(KeeperCare.tier_from_stats(stats) == KeeperCare.Tier.STRESSED,
			"overstock + low o2 reads stressed")
	var interp: Dictionary = CognitiveSchema.interpret_keeper_heuristic("you're safe", f)
	assert(str(interp.get("keeper_intent", "")) == "comfort", "safe -> comfort intent")
	var fx: Dictionary = KeeperCare.apply_comfort_effects(f, interp, null)
	assert(bool(fx.get("applied", false)), "comfort soothes")
	assert(f.spooked < 0.5, "spook reduced")
	var result: Dictionary = {
		"ok": true,
		"too_wary": false,
		"tank_blocks_words": true,
	}
	assert(not MindConversation.should_reply_words(f, result), "tank blocks words when stressed")
	result["tank_blocks_words"] = false
	assert(MindConversation.should_reply_words(f, result), "words ok when tank open")
	assert(KeeperCare.tier_label(KeeperCare.Tier.THRIVING) == "thriving", "tier label")
