extends SceneTree

# The learning mind (fish_learned_mind.gd): a fish that learns over its life.
#
#   - repeated keeper feeds at the same time of day consolidate, during sleep,
#     into a belief with confidence ("you come when the light goes gold")
#   - the belief updates with prediction error: a feed in the window confirms
#     it, a missed one weakens it, surprises the fish, sends it to inspect the
#     spot, and is said out loud ("you didn't come today")
#   - the surprise habituates on repetition and recovers after time away
#   - a confident belief biases behaviour: the fish anticipates (gathers at the
#     feeding spot before feeding time) and swims around learned danger
#   - lived experience drifts personality slowly (<= 0.03/night) and within
#     a birth-anchored bound (+-0.25); the per-tick conditioning no longer
#     writes traits directly
#   - identity continuity: "I was small when you first fed me"
#   - the state survives JSON save/load; old saves (no key) and junk migrate
#   - the voice grounds on beliefs; validate_line accepts ordinary
#     sentence-initial words / contractions but rejects invented names
#   - mate grief now fires after a mate's death (the survivor's _mate_id is
#     cleared at death, so the old path never ran), mirrored from FishSocial
#     without a second mood hit

const FishLearnedMind = preload("res://scripts/fish_learned_mind.gd")
const FishMind = preload("res://scripts/fish_mind.gd")
const FishMindScience = preload("res://scripts/fish_mind_science.gd")
const GlobalWorkspace = preload("res://scripts/global_workspace.gd")
const MindNarrator = preload("res://scripts/mind_narrator.gd")
const _MindContext = preload("res://scripts/mind_context.gd")

const FEED_POS := Vector3(2.0, 1.5, 0.0)
const FEED_PHASE: float = 0.42  # bucket 3, "when the light goes gold"


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_mind_sleep_beliefs")
	FishLearnedMind.clear_for_test()
	_test_belief_forms_and_updates(t)
	_test_habituation_curve(t)
	_test_danger_avoidance(t)
	_test_trait_drift(t)
	_test_identity(t)
	_test_save_roundtrip_and_migration(t)
	_test_voice_and_validation(t)
	_test_mate_grief(t)
	quit(t.finish())


func _mk(id: String) -> Fish:
	var f: Fish = Fish.new()
	root.add_child(f)
	f.set_process(false)
	f.set_physics_process(false)
	f.id = id
	f.fish_name = id.capitalize()
	f.personality = {"boldness": 0.5, "curiosity": 0.5, "sociability": 0.5, "calm": 0.5}
	f.position = Vector3(-1.0, 3.0, 0.0)
	return f


# One light cycle. The keeper feeds at FEED_PHASE when `fed`; the fish sleeps
# (and consolidates) at night; the clock then wraps to the next cycle.
func _day(f: Fish, fed: bool) -> void:
	f._asleep = false
	FishLearnedMind.tick_at(f, 0.05, 1.0)
	FishLearnedMind.tick_at(f, 0.2, 1.0)
	if fed:
		FishLearnedMind.observe_at(f, "keeper_feed", f.position, FEED_PHASE)
		FishLearnedMind.observe_at(f, "food", FEED_POS, FEED_PHASE + 0.01)
	FishLearnedMind.tick_at(f, 0.5, 1.0)
	FishLearnedMind.tick_at(f, 0.64, 1.0)  # window + grace closed: the check
	f._asleep = true
	FishLearnedMind.tick_at(f, 0.7, 1.0)   # night pass
	FishLearnedMind.tick_at(f, 0.95, 1.0)
	f._asleep = false


func _feed_belief(f: Fish) -> Dictionary:
	for b in (FishLearnedMind.ensure(f)["beliefs"] as Array):
		if str((b as Dictionary).get("id", "")) == "feed@3":
			return b as Dictionary
	return {}


func _test_belief_forms_and_updates(t: TestSupport.Suite) -> void:
	var f: Fish = _mk("goldie")
	_day(f, true)
	t.check(_feed_belief(f).is_empty(), "one feed is an event, not yet a belief")
	_day(f, true)
	var b: Dictionary = _feed_belief(f)
	t.check(not b.is_empty(), "two evenings of feeding consolidate into a belief overnight")
	var c_formed: float = float(b.get("conf", 0.0))
	t.in_range(c_formed, 0.3, 0.7, "a new belief starts with moderate confidence")
	t.equals(FishLearnedMind.belief_line(f, b), "you come when the light goes gold",
			"the belief is sayable in the fish's own terms")
	_day(f, true)
	_day(f, true)
	t.check((f.semantic_memory as Array).has("believe: you come when the light goes gold"),
			"a confident belief is voiced and lands in semantic memory")
	var c_conf: float = float(_feed_belief(f).get("conf", 0.0))
	t.check(c_conf > c_formed, "confirmed predictions strengthen it (%.2f -> %.2f)" % [c_formed, c_conf])
	t.check(int(_feed_belief(f).get("ok", 0)) >= 1, "confirmations are counted")

	# Anticipation: just before the learned window the fish wants to be at the spot.
	f._asleep = false
	f.hunger = 0.5
	FishLearnedMind.tick_at(f, 0.05, 1.0)
	FishLearnedMind.tick_at(f, 0.34, 1.0)
	var cue: Dictionary = f._belief_cue
	t.equals(str(cue.get("label", "")), "anticipate", "a confident belief produces anticipation before feeding time")
	t.check(cue.get("pos") is Vector3 and (cue["pos"] as Vector3).distance_to(FEED_POS) < 0.1,
			"anticipation targets where the food usually lands")
	var bid: Dictionary = FishLearnedMind.collect_bid(f)
	t.check(str(bid.get("label", "")) == "anticipate" and float(bid.get("salience", 0.0)) > 0.3,
			"anticipation bids into the workspace (%.2f)" % float(bid.get("salience", 0.0)))
	var bias: Vector3 = GlobalWorkspace._bias_for(f, "anticipate", 0.7)
	var toward: Vector3 = (FEED_POS - f.position).normalized()
	t.check(bias.length() > 0.05 and bias.normalized().dot(toward) > 0.95,
			"the anticipation bias steers toward the feeding spot")
	var ctx: Dictionary = FishLearnedMind.context_for(f)
	t.check(ctx.has("anticipating") and str(ctx.get("belief_line", "")) != "",
			"voice context carries the belief and the anticipation")

	# Prediction error: the keeper does not come today.
	var before: float = float(_feed_belief(f).get("conf", 0.0))
	f.surprise = 0.0
	f._thought_stream = ""
	FishLearnedMind.tick_at(f, 0.5, 1.0)
	FishLearnedMind.tick_at(f, 0.64, 1.0)
	var after: float = float(_feed_belief(f).get("conf", 0.0))
	t.check(after < before, "a missed feed weakens the belief (%.2f -> %.2f)" % [before, after])
	t.check(f.surprise > 0.2, "a violated confident belief is surprising (%.2f)" % f.surprise)
	t.equals(str(f._belief_cue.get("label", "")), "inspect", "surprise sends the fish to inspect the spot")
	t.check(f._thought_stream.contains("didn't come"), "and it says so: '%s'" % f._thought_stream)
	var first_surprise: float = f.surprise
	f._asleep = true
	FishLearnedMind.tick_at(f, 0.7, 1.0)
	FishLearnedMind.tick_at(f, 0.95, 1.0)
	f._asleep = false
	f.surprise = 0.0
	_day(f, false)
	t.check(f.surprise < first_surprise,
			"a second empty evening surprises less (%.2f < %.2f)" % [f.surprise, first_surprise])
	_day(f, false)
	_day(f, false)
	t.check(float(_feed_belief(f).get("conf", 0.0)) < before * 0.6,
			"repeated violations extinguish the belief (%.2f)" % float(_feed_belief(f).get("conf", 0.0)))


func _test_habituation_curve(t: TestSupport.Suite) -> void:
	var f: Fish = _mk("habit")
	FishLearnedMind.tick_at(f, 0.1, 1.0)
	var n0: float = FishLearnedMind.novelty(f, "tap")
	var n1: float = FishLearnedMind.expose(f, "tap")
	FishLearnedMind.expose(f, "tap")
	FishLearnedMind.expose(f, "tap")
	var n3: float = FishLearnedMind.novelty(f, "tap")
	t.approx(n0, 1.0, "an unmet stimulus is fully novel")
	t.approx(n1, 1.0, "expose() reports the novelty it had before this exposure")
	t.check(n3 < 0.35, "novelty falls with repeated exposure (%.2f)" % n3)
	for _i in 5:
		FishLearnedMind.tick_at(f, 0.9, 1.0)
		FishLearnedMind.tick_at(f, 0.1, 1.0)
	var n_rec: float = FishLearnedMind.novelty(f, "tap")
	t.check(n_rec > n3 + 0.3, "and recovers after nights without it (%.2f -> %.2f)" % [n3, n_rec])
	var st: Dictionary = FishLearnedMind.ensure(f)
	for i in 30:
		FishLearnedMind.expose(f, "k%d" % i)
	t.check((st["hab"] as Dictionary).size() <= FishLearnedMind.HAB_MAX, "habituation map is bounded")


func _test_danger_avoidance(t: TestSupport.Suite) -> void:
	var f: Fish = _mk("wary")
	var spot := Vector3(-5.0, 1.0, 0.0)
	FishLearnedMind.tick_at(f, 0.1, 1.0)
	FishLearnedMind.observe_at(f, "startled", spot, 0.2)
	FishLearnedMind.observe_at(f, "startled", spot + Vector3(0.5, 0, 0), 0.3)
	f._asleep = true
	FishLearnedMind.tick_at(f, 0.7, 1.0)
	f._asleep = false
	var found: Dictionary = {}
	for b in (FishLearnedMind.ensure(f)["beliefs"] as Array):
		if str((b as Dictionary).get("kind", "")) == "danger":
			found = b
	t.check(not found.is_empty(), "two frights in one place become a learned danger zone")
	t.check(FishLearnedMind.belief_line(f, found).ends_with("isn't safe"),
			"the zone is named: '%s'" % FishLearnedMind.belief_line(f, found))
	FishLearnedMind.tick_at(f, 0.8, 1.0)
	var at := spot + Vector3(1.0, 0.0, 0.0)
	var steer: Vector3 = FishMind.salient_avoid_steer(f, at)
	t.check(steer.x > 0.5, "steering pushes away from the learned danger (%s)" % str(steer))
	# Extinction: calm time inside the zone weakens the fear, once per cycle.
	f.position = at
	f.stress = 0.1
	var c0: float = float(found.get("conf", 0.0))
	for _i in 25:
		FishLearnedMind.tick_at(f, 0.85, 1.0)
	t.check(float(found.get("conf", 0.0)) < c0, "calm visits to a feared place extinguish the fear")


func _test_trait_drift(t: TestSupport.Suite) -> void:
	var f: Fish = _mk("bully_target")
	FishLearnedMind.tick_at(f, 0.1, 1.0)  # captures the birth personality
	# The per-tick conditioning now only accumulates.
	f.familiarity = 0.8
	f._cached_glance_strength = 0.9
	for _i in 600:
		FishMind.tick_personality_conditioning(f, 1.0)
	t.approx(float(f.personality["boldness"]), 0.5, "10 minutes of attention no longer rewrites boldness per tick")
	var gained: Dictionary = FishLearnedMind.apply_night_drift(f)
	var db: float = float(gained.get("boldness", 0.0))
	t.check(db > 0.0 and db <= FishLearnedMind.DRIFT_NIGHT_MAX + 1e-6,
			"...it becomes one bounded night step (+%.3f)" % db)
	var prev: float = float(f.personality["boldness"])
	var max_step: float = 0.0
	for _n in 40:
		for _c in 3:
			FishLearnedMind.observe_at(f, "chased", Vector3.ZERO, 0.3 + randf() * 0.1, "rex", "Rex")
			FishLearnedMind.ensure(f)["events"] = []  # avoid dedup: drift is what's under test
		FishLearnedMind.apply_night_drift(f)
		var now_b: float = float(f.personality["boldness"])
		max_step = maxf(max_step, absf(now_b - prev))
		prev = now_b
	var birth: float = float((FishLearnedMind.ensure(f)["birth"] as Dictionary)["boldness"])
	t.check(max_step <= FishLearnedMind.DRIFT_NIGHT_MAX + 1e-6, "drift is slow (max %.3f / night)" % max_step)
	t.check(prev < birth - 0.1, "a repeatedly chased fish becomes warier (%.2f)" % prev)
	t.check(prev >= birth - FishLearnedMind.DRIFT_TOTAL_MAX - 1e-6,
			"drift is bounded around the birth self (%.2f >= %.2f)" % [prev, birth - FishLearnedMind.DRIFT_TOTAL_MAX])
	t.check(FishLearnedMind.self_change_line(f).contains("warier"),
			"and knows it: '%s'" % FishLearnedMind.self_change_line(f))
	t.check((FishLearnedMind.ensure(f)["drift_log"] as Array).size() <= FishLearnedMind.DRIFT_LOG_MAX,
			"drift log is bounded")
	# A hand-fed, gently spoken-to fish grows bolder toward the keeper.
	var g: Fish = _mk("pet")
	FishLearnedMind.tick_at(g, 0.1, 1.0)
	g._cached_glance_strength = 0.9
	for _n in 5:
		FishLearnedMind.accumulate(g, "hand_fed", 2.0)
		FishLearnedMind.accumulate(g, "kind", 2.0)
		FishLearnedMind.apply_night_drift(g)
	t.check(float(g.personality["boldness"]) > 0.55 and float(g.personality["sociability"]) > 0.52,
			"hand-feeding and kind words make it bolder and more social")


func _test_identity(t: TestSupport.Suite) -> void:
	var f: Fish = _mk("sprout")
	f.maturity = Fish.MATURITY_FRY
	FishLearnedMind.tick_at(f, 0.1, 1.0)
	FishLearnedMind.observe_at(f, "keeper_feed", f.position, 0.3)
	f.maturity = Fish.MATURITY_ADULT
	FishLearnedMind.tick_at(f, 0.2, 1.0)
	var ll: String = FishLearnedMind.life_line(f)
	t.equals(ll, "I was small when you first fed me", "the fish references its own past")
	var tags: Array = []
	for m in (FishLearnedMind.ensure(f)["milestones"] as Array):
		tags.append(str((m as Dictionary).get("tag", "")))
	t.check(tags.has("grown"), "growing up is a milestone (%s)" % str(tags))


func _json(v: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(SaveHelpers.sanitize_for_json(v)))


func _test_save_roundtrip_and_migration(t: TestSupport.Suite) -> void:
	var f: Fish = _mk("saver")
	_day(f, true)
	_day(f, true)
	FishLearnedMind.expose(f, "tap")
	var d: Dictionary = FishMind.mind_to_dict(f)
	t.check(d.has("learned_mind"), "mind save includes the learned mind")
	var back: Variant = _json(d)
	t.check(back is Dictionary, "mind save survives JSON")
	var g: Fish = _mk("loader")
	FishMind.apply_mind_dict(g, back as Dictionary)
	var bf: Dictionary = _feed_belief(f)
	var bg: Dictionary = _feed_belief(g)
	t.check(not bg.is_empty(), "the belief survives save/load")
	t.approx(float(bg.get("conf", 0.0)), float(bf.get("conf", -1.0)), "with its confidence", 0.002)
	t.equals(int(FishLearnedMind.ensure(g)["cycle"]), int(FishLearnedMind.ensure(f)["cycle"]), "and its life clock")
	t.check(not (FishLearnedMind.ensure(g)["birth"] as Dictionary).is_empty(), "and its birth self")
	t.check(FishLearnedMind.novelty(g, "tap") < 1.0, "and its habituation")
	# The loaded fish keeps predicting: tomorrow's missed feed still surprises it.
	g.surprise = 0.0
	FishLearnedMind.tick_at(g, 0.05, 1.0)
	FishLearnedMind.tick_at(g, 0.5, 1.0)
	FishLearnedMind.tick_at(g, 0.64, 1.0)
	t.check(float(_feed_belief(g).get("conf", 1.0)) < float(bg.get("conf", 0.0)) + 1e-6 and g.surprise > 0.0,
			"a loaded belief is still tested against the world")
	# Migration: a pre-learned-mind save, then a corrupt one.
	var old: Dictionary = (back as Dictionary).duplicate(true)
	old.erase("learned_mind")
	var h: Fish = _mk("old_save")
	FishMind.apply_mind_dict(h, old)
	var st: Dictionary = FishLearnedMind.ensure(h)
	t.equals(int(st.get("v", 0)), FishLearnedMind.SCHEMA_VERSION, "an old save migrates to a fresh learned mind")
	t.check((st["beliefs"] as Array).is_empty(), "with no invented beliefs")
	var junk: Dictionary = {"cycle": "x", "beliefs": [{"id": "feed@9", "conf": 7.0, "phase": 99, "p": "bad"},
			"nope", {"no_id": true}], "events": "bad", "hab": {"a": {"n": -3}}, "birth": {"boldness": 9.0}}
	for i in 80:
		(junk["beliefs"] as Array).append({"id": "b%d" % i, "conf": 0.5})
	FishLearnedMind.from_dict(h, junk)
	st = FishLearnedMind.ensure(h)
	t.check((st["beliefs"] as Array).size() <= FishLearnedMind.BELIEFS_MAX, "junk beliefs are capped")
	t.check((st["events"] as Array).is_empty(), "junk events are dropped")
	var ok_bounds: bool = true
	for b in (st["beliefs"] as Array):
		var bd: Dictionary = b as Dictionary
		if float(bd["conf"]) > 0.98 or (bd.has("phase") and int(bd["phase"]) > 7) or bd.has("p"):
			ok_bounds = false
	t.check(ok_bounds, "loaded beliefs are clamped / sanitized")
	t.approx(float((st["birth"] as Dictionary).get("boldness", 0.0)), 1.0, "birth traits are clamped")
	t.approx(float(((st["hab"] as Dictionary)["a"] as Dictionary)["n"]), 0.0, "habituation counts are clamped")


func _test_voice_and_validation(t: TestSupport.Suite) -> void:
	var f: Fish = _mk("speaker")
	_day(f, true)
	_day(f, true)
	var ctx: Dictionary = {"feel": "calm", "voice_seed": 7}
	_MindContext.add_voice_grounding(ctx, f, null)
	t.equals(str(ctx.get("belief_line", "")), "you come when the light goes gold",
			"voice grounding carries the fish's strongest belief")
	var clauses: Array = MindNarrator._grounded_clauses(ctx, false, false)
	var has_belief: bool = false
	for c in clauses:
		if str((c as Dictionary).get("k", "")) == "belief":
			has_belief = true
	t.check(has_belief, "the template voice can speak from a belief")
	var slim: Dictionary = _MindContext.build_for_keeper_turn(f, null, "")
	t.check(slim.has("belief_line"), "the keeper-turn (LLM) context keeps the belief")
	var names := PackedStringArray(["Mira"])
	var vctx: Dictionary = {"allowed_fish_names": names, "fish_name": "Speaker"}
	t.check(bool(MindNarrator.validate_line(vctx, "It's time to eat.").get("ok", false)),
			"a contraction at sentence start is not a name")
	t.check(bool(MindNarrator.validate_line(vctx, "Something soft near Mira. Soft water.").get("ok", false)),
			"ordinary sentence-initial words and known names pass")
	t.check(bool(MindNarrator.validate_line(vctx, "You came back. Keeper, I waited.").get("ok", false)),
			"common capitalised words pass")
	t.check(not bool(MindNarrator.validate_line(vctx, "Bob swims near me.").get("ok", true)),
			"an invented name at sentence start is still caught")
	t.check(not bool(MindNarrator.validate_line(vctx, "I swam with Bob today.").get("ok", true)),
			"an invented name mid-sentence is caught")


func _test_mate_grief(t: TestSupport.Suite) -> void:
	var f: Fish = _mk("widow")
	f._mate_id = ""  # cleared by _clear_partner_refs_on_death
	f.social = {"rel": {"m1": {"fam": 0.9, "ev": "died", "t": 0, "tags": ["mate", "dead"], "n": "Mira"}},
			"grief": {"id": "m1", "n": "Mira", "lvl": 0.8, "at": [0, 1, 0]}}
	f.mood = 0.2
	f._longing_residue = 0.0
	FishMindScience.tick_mate_grief(f, 0.1, false)
	t.check(f._mate_grief >= 0.79, "mate grief fires after the mate's death (%.2f)" % f._mate_grief)
	t.approx(f.mood, 0.2, "without a second mood hit (FishSocial already applied it)")
	t.check(f._longing_residue > 0.3, "and leaves a longing residue")
	f.social = {"rel": {"x": {"fam": 0.9, "tags": ["friend"], "n": "Pal"}},
			"grief": {"id": "x", "n": "Pal", "lvl": 0.8}}
	f._mate_grief = 0.0
	FishMindScience.tick_mate_grief(f, 0.1, false)
	t.approx(f._mate_grief, 0.0, "grief for a friend is not mate grief")
