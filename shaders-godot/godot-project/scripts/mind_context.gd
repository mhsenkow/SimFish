class_name MindContext
extends RefCounted

# Canonical grounded snapshot for voice generation (SENTIENCE_EMBEDDED #21).
# Every narrated line may only reference facts present here.

const FishMind = preload("res://scripts/fish_mind.gd")
const FishMindScience = preload("res://scripts/fish_mind_science.gd")
const MindNarrator = preload("res://scripts/mind_narrator.gd")
const EpisodicMemory = preload("res://scripts/episodic_memory.gd")
const MindLexicon = preload("res://scripts/mind_lexicon.gd")
const MindWorldModel = preload("res://scripts/mind_world_model.gd")
const FeltSelfLayer = preload("res://scripts/felt_self_layer.gd")
const FishCoreAffect = preload("res://scripts/fish_core_affect.gd")
const FishQualia = preload("res://scripts/fish_qualia.gd")
const FishBinding = preload("res://scripts/fish_binding.gd")
const MindSoul = preload("res://scripts/mind_soul.gd")
const MindSoulPass2 = preload("res://scripts/mind_soul_pass2.gd")
const MindSoulPass3 = preload("res://scripts/mind_soul_pass3.gd")
const _MindPromptSkeletonScript = preload("res://scripts/mind_prompt_skeleton.gd")
const DeltaGCurve = preload("res://scripts/delta_g_curve.gd")
const MindActiveInference = preload("res://scripts/mind_active_inference.gd")
const MindKeeperModel = preload("res://scripts/mind_keeper_model.gd")
const FishLearnedMind = preload("res://scripts/fish_learned_mind.gd")

# Memory kinds that involve the keeper — what a fish can "remember about you".
const KEEPER_EPISODE_KINDS: Array[String] = ["fed", "player", "keeper", "keeper_word", "named"]
const VOICE_EPISODES_MAX: int = 3

const BASE_CTX_TTL_S: float = 2.0
static var _allowed_names: PackedStringArray = PackedStringArray()
static var _allowed_names_sim_id: int = 0
static var _allowed_names_count: int = -1
static var _lexicon_cache: Dictionary = {}


static func invalidate_fish_roster(sim: Node = null) -> void:
	_allowed_names_count = -1
	if sim != null:
		_allowed_names_sim_id = sim.get_instance_id()


static func _allowed_fish_names(sim: Node) -> PackedStringArray:
	if sim == null:
		return PackedStringArray()
	var sim_id: int = sim.get_instance_id()
	var fish_n: int = sim.fish.size() if sim.get("fish") != null else 0
	if sim_id == _allowed_names_sim_id and fish_n == _allowed_names_count \
			and not _allowed_names.is_empty():
		return _allowed_names
	_allowed_names = PackedStringArray()
	if sim.get("fish") != null:
		for ff in sim.fish:
			if is_instance_valid(ff):
				var n: String = str(ff.fish_name if ff.fish_name != "" else ff.species)
				if n != "" and not _allowed_names.has(n):
					_allowed_names.append(n)
	_allowed_names_sim_id = sim_id
	_allowed_names_count = fish_n
	return _allowed_names


static func _lexicon_for(f: Fish) -> Dictionary:
	var fid: String = str(f.id)
	if _lexicon_cache.has(fid):
		return _lexicon_cache[fid] as Dictionary
	var lex: Dictionary = MindLexicon.ensure_dict(f)
	if not lex.is_empty():
		_lexicon_cache[fid] = lex
	return lex


static func build_for_fish(f: Fish, sim: Node = null, situation: String = "", ms: MindState = null,
		for_narrator: bool = true) -> Dictionary:
	if f == null:
		return {"situation": situation}
	var state: MindState = ms if ms != null else MindChannel.for_cycle(
		f, f.is_guardian or f.fish_name != "" or f.familiarity > 0.4)
	var bond_names: PackedStringArray = PackedStringArray()
	var grudge_names: PackedStringArray = PackedStringArray()
	if sim != null and sim.get("fish") != null:
		for other in sim.fish:
			if not is_instance_valid(other) or other == f:
				continue
			var oid: String = str(other.id)
			var nm: String = str(other.fish_name if other.fish_name != "" else other.species)
			if f.bonds.has(oid) and float(f.bonds[oid]) > 0.25:
				bond_names.append(nm)
			if f.grudges.has(oid):
				grudge_names.append(nm)
	var allowed_fish: PackedStringArray = _allowed_fish_names(sim)
	var moods: PackedStringArray = PackedStringArray([
		"calm", "content", "anxious", "excited", "playful", "bored", "sulking", "cozy",
	])
	var feel: String = FishMind.emotional_state(f)
	var ws_label: String = MindChannel.workspace_label(state)
	var retrieved: PackedStringArray = EpisodicMemory.retrieve_for_situation(f, situation, 3)
	if retrieved.is_empty():
		retrieved = FishMind.salient_relevant_for_situation(f, situation, 3)
	var ctx: Dictionary = {
		"fish_id": str(f.id),
		"fish_name": str(f.fish_name if f.fish_name != "" else f.species),
		"species": str(f.species),
		"situation": situation,
		"feel": feel,
		"mood_valence": snappedf(f.mood, 0.01),
		"arousal": snappedf(f.arousal, 0.01),
		"stress": snappedf(f.stress, 0.01),
		"hunger": snappedf(f.hunger, 0.01),
		"familiarity": snappedf(f.familiarity, 0.01),
		"surprise": snappedf(f.surprise, 0.01),
		"intends": str(f.current_intention),
		"wants": FishMind.dominant_wants(f),
		"bonds": bond_names,
		"grudges": grudge_names,
		"allowed_fish_names": allowed_fish,
		"allowed_moods": moods,
		"salient_memories": retrieved,
		"attention_workspace": ws_label,
		"workspace_ignited": state.workspace_ignited,
		"self_model": state.self_model,
		"thought_stream": state.thought_stream,
	}
	ctx["prompt_skeleton"] = _MindPromptSkeletonScript.skeleton_for(f, sim)
	if for_narrator:
		ctx["voice_seed"] = MindNarrator.voice_style_seed(str(f.id), f.personality)
	ctx["meals_eaten"] = int(f.bio.get("meals_eaten", 0)) if f.bio is Dictionary else 0
	ctx["age_days"] = snappedf(f.age / maxf(f.max_age_s, 1.0) * 365.0, 0.1)
	ctx["generation"] = f.generation
	ctx["is_guardian"] = f.is_guardian
	ctx["voiced"] = f.is_voiced_individual()
	if not f.inferred_states.is_empty():
		ctx["inferred_others"] = f.inferred_states
	var cell_key: String = FishMindScience.novelty_cell_key(f)
	if f._hypotheses.has(cell_key):
		ctx["local_hypothesis"] = str(f._hypotheses[cell_key].get("guess", "unknown"))
	if sim != null:
		ctx["day_phase"] = str(sim.day_phase if sim.get("day_phase") != null else "")
		if sim.get("dissolved_o2") != null:
			ctx["o2"] = snappedf(float(sim.dissolved_o2), 0.01)
		if sim.has_method("feed_anticipation_active"):
			ctx["feed_anticipated"] = sim.feed_anticipation_active()
		if sim.has_method("tank_society_snapshot"):
			ctx["tank_society"] = sim.tank_society_snapshot()
	var dom: String = FishMind.dominance_hint(f)
	if dom != "":
		ctx["dominance_hint"] = dom
	var grudge_hints: PackedStringArray = FishMind.grudge_voice_hints(f, sim)
	if not grudge_hints.is_empty():
		ctx["grudge_hints"] = grudge_hints
	if sim != null and sim.get("shrimp") != null:
		for sh in sim.shrimp:
			if is_instance_valid(sh) and sh.get("is_cleaner") \
					and sh.position.distance_squared_to(f.position) < 36.0:
				ctx["nearby_cleaner"] = true
				break
	var lex: Dictionary = _lexicon_for(f) if for_narrator else {}
	if not lex.is_empty():
		ctx["learned_words"] = lex
	if not state.keeper_pending.is_empty():
		ctx.merge(state.keeper_pending)
	ctx["life_stance"] = state.life_stance
	ctx["prediction_error"] = snappedf(state.prediction_error, 0.01)
	ctx["thought_tense"] = FishMind.stream_tense_tag(f)
	if for_narrator:
		ctx["autobiography"] = FishMind.autobiography_dict(f)
	if not state.world_model.is_empty():
		ctx["world_model_error"] = snappedf(float(state.world_model.get("error", 0.0)), 0.01)
		ctx["world_model_variance"] = snappedf(float(state.world_model.get("variance", 0.35)), 0.01)
	# What the tank is hearing right now — a short grounded phrase the fish or
	# Guardian may reference. Empty (omitted) when no song is playing.
	var music_node: Node = _autoload("MusicContext")
	if music_node != null and music_node.has_method("describe_now_playing"):
		var song_desc: String = str(music_node.describe_now_playing())
		if song_desc != "":
			ctx["now_playing"] = song_desc
	if FeltSelfLayer.layer_enabled():
		ctx["felt_texture"] = FishCoreAffect.texture(f)
		ctx["core_valence"] = snappedf(FishCoreAffect.valence(f), 0.01)
		if for_narrator:
			var ql: String = FishQualia.report_line(f)
			if ql != "":
				ctx["qualia_report"] = ql
			var glimpse: String = FishBinding.first_person_glimpse(f)
			if glimpse != "":
				ctx["felt_glimpse"] = glimpse
	if for_narrator and MindSoul.enabled():
		var keeper_q: String = str(ctx.get("keeper_text", ""))
		if keeper_q != "":
			var intro: String = MindSoul.introspection_report(f, state, keeper_q)
			if intro != "":
				ctx["introspection_report"] = intro
		var meta: String = str(MindSoul.ensure(f).get("meta_emotion", ""))
		if meta != "":
			ctx["meta_emotion"] = meta
		var chapters: PackedStringArray = MindSoulPass2.autobiography_lines(f)
		if chapters.size() > 0:
			ctx["life_chapters"] = chapters
		var bio: Dictionary = MindSoulPass3.biography_for(f)
		if not bio.is_empty():
			ctx["biography"] = bio
		var dg_line: String = DeltaGCurve.biography_line(f)
		if dg_line != "":
			ctx["delta_g_biography"] = dg_line
		var dg_sum: Dictionary = DeltaGCurve.summary_for(f)
		if float(dg_sum.get("delta_g", 0.0)) > 0.02 or float(dg_sum.get("robust", 0.0)) > 0.02:
			ctx["delta_g_curve"] = dg_sum
	if for_narrator:
		add_voice_grounding(ctx, f, sim)
	return ctx


# SENTIENCE voice grounding — the fish's OWN mind, in the compact form the
# template voice (and the LLM prompt) speak from:
#   episodes        its strongest remembered moments (kind/text/keeper?)
#   keeper_episode  the strongest memory that involves the keeper
#   understood_words / unknown_words  what it actually comprehended of the
#                   keeper's last line (lexicon), not what was typed
#   goal            what active inference says it most needs right now
#   expects         what it is predicting (feed, a learned charger)
#   care_trust / conversation_count  its relationship with the keeper
# Pure reads (plus MindKeeperModel.ensure's default fill); main thread only.
static func add_voice_grounding(ctx: Dictionary, f: Fish, sim: Node = null) -> void:
	if f == null:
		return
	var all_eps: Array = voice_episodes(f, 8)
	if not all_eps.is_empty():
		ctx["episodes"] = all_eps.slice(0, mini(VOICE_EPISODES_MAX, all_eps.size()))
	for e in all_eps:
		if bool((e as Dictionary).get("keeper", false)):
			ctx["keeper_episode"] = str((e as Dictionary).get("text", ""))
			ctx["keeper_episode_kind"] = str((e as Dictionary).get("kind", ""))
			break
	var heard: Dictionary = keeper_words_heard(f, str(ctx.get("keeper_text", "")))
	if not (heard.get("understood") as PackedStringArray).is_empty():
		ctx["understood_words"] = heard["understood"]
		ctx["understood_kinds"] = heard["kinds"]
	if not (heard.get("unknown") as PackedStringArray).is_empty():
		ctx["unknown_words"] = heard["unknown"]
	ctx["goal"] = active_goal(f)
	# What it has LEARNED over its life (night-consolidated beliefs), how it has
	# changed, and a thread back to its own past (milestones / backstory).
	var learned: Dictionary = FishLearnedMind.context_for(f)
	for lk in learned.keys():
		ctx[lk] = learned[lk]
	var expect_s: String = expectation(f, sim,
			bool(ctx.get("feed_anticipated", false)) or learned.has("anticipating"))
	if expect_s != "":
		ctx["expects"] = expect_s
	var km: Dictionary = MindKeeperModel.ensure(f)
	ctx["care_trust"] = snappedf(float(km.get("care_trust", 0.3)), 0.01)
	ctx["conversation_count"] = int(km.get("conversation_count", 0))
	if not ctx.has("keeper_moniker"):
		ctx["keeper_moniker"] = str(km.get("player_moniker", ""))


# Strongest salient memories, newest first among equals. Skips the stock
# "echo" lines the narrator already treats as stale.
static func voice_episodes(f: Fish, max_n: int) -> Array:
	var pool: Array = []
	var mem: Variant = f.get("salient_memories")
	if not (mem is Array):
		return pool
	var idx: int = 0
	for raw in (mem as Array):
		idx += 1
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw as Dictionary
		var text: String = str(e.get("text", "")).strip_edges()
		if text == "" or MindNarrator._is_stale_thought_echo(text):
			continue
		var kind: String = str(e.get("kind", ""))
		pool.append({
			"kind": kind,
			"text": text.substr(0, 60),
			"keeper": KEEPER_EPISODE_KINDS.has(kind),
			"_w": SaveHelpers._num(e.get("weight", 0.4), 0.4),
			"_i": idx,
		})
	pool.sort_custom(func(a, b):
		if absf(float(a["_w"]) - float(b["_w"])) > 0.05:
			return float(a["_w"]) > float(b["_w"])
		return int(a["_i"]) > int(b["_i"]))
	var out: Array = []
	for e in pool.slice(0, mini(max_n, pool.size())):
		var d: Dictionary = e as Dictionary
		d.erase("_w")
		d.erase("_i")
		out.append(d)
	return out


# Which of the keeper's words this fish has actually learned (MindLexicon).
static func keeper_words_heard(f: Fish, keeper_text: String) -> Dictionary:
	var understood: PackedStringArray = PackedStringArray()
	var kinds: PackedStringArray = PackedStringArray()
	var unknown: PackedStringArray = PackedStringArray()
	if keeper_text.strip_edges() != "":
		var lex: Dictionary = MindLexicon.ensure_dict(f)
		for raw in keeper_text.split(" ", false):
			var tok: String = MindLexicon.normalize_token(raw)
			if tok.length() < 2 or understood.has(tok) or unknown.has(tok):
				continue
			if MindLexicon.comprehend(f, tok):
				understood.append(tok)
				var e: Variant = lex.get(tok, null)
				kinds.append(str((e as Dictionary).get("kind", "")) if e is Dictionary else "")
			elif unknown.size() < 3:
				unknown.append(tok)
	return {"understood": understood, "kinds": kinds, "unknown": unknown}


# The need active inference would act on first: largest homeostatic
# (pragmatic) error, with epistemic value (explore) competing only when the
# fish is calm enough — the same allostasis guard the workspace uses.
static func active_goal(f: Fish) -> String:
	var pe: Dictionary = MindActiveInference.preferred_error(f)
	var best: String = "drift"
	var best_v: float = 0.25
	for k in ["hunger", "safety", "rest", "social"]:
		var v: float = float(pe.get(k, 0.0))
		if v > best_v:
			best_v = v
			best = k
	if f.stress < 0.6 and MindAblation.enabled(MindAblation.WORLD_MODEL):
		var info: float = MindWorldModel.expected_free_energy_explore(f) * 0.6 \
				+ f.curiosity_drive * 0.25
		if info > best_v:
			best = "explore"
	match best:
		"hunger":
			return "eat"
		"safety":
			return "hide"
		"rest":
			return "rest"
		"social":
			return "company"
		"explore":
			return "explore"
	return "drift"


# What the fish is currently predicting, grounded in its predictive machinery.
static func expectation(f: Fish, sim: Node, feed_anticipated: bool) -> String:
	var alert: Variant = f.get("_tom_alert")
	if alert is Dictionary and not (alert as Dictionary).is_empty() \
			and MindAblation.enabled(MindAblation.THEORY_OF_MIND):
		var oid: String = str((alert as Dictionary).get("oid", ""))
		var nm: String = ""
		if sim != null and sim.get("fish") != null:
			for o in sim.fish:
				if is_instance_valid(o) and str(o.id) == oid:
					nm = str(o.fish_name if o.fish_name != "" else o.species)
					break
		return "charge:%s" % nm if nm != "" else "charge"
	if feed_anticipated:
		return "food"
	return ""


static func merge_guardian(ctx: Dictionary, guardian_ctx: Dictionary) -> Dictionary:
	var out: Dictionary = ctx.duplicate(true)
	for k in guardian_ctx:
		out[k] = guardian_ctx[k]
	return out


static func context_is_thin(ctx: Dictionary) -> bool:
	if ctx.is_empty():
		return true
	var has_situation: bool = str(ctx.get("situation", "")).strip_edges() != ""
	var has_feel: bool = str(ctx.get("feel", "")) != "" and str(ctx.get("feel", "")) != "calm"
	var has_mem: bool = false
	var mem: Variant = ctx.get("salient_memories", null)
	if mem is Array and (mem as Array).size() > 0:
		has_mem = true
	if mem is PackedStringArray and (mem as PackedStringArray).size() > 0:
		has_mem = true
	return not has_situation and not has_feel and not has_mem


# CONVERSATION §I #86 — slim context for keeper-turn generation (1024 window).
static func build_for_keeper_turn(f: Fish, sim: Node = null, situation: String = "keeper_reply") -> Dictionary:
	var full: Dictionary = build_for_fish(f, sim, situation)
	var slim: Dictionary = {
		"fish_id": full.get("fish_id", ""),
		"fish_name": full.get("fish_name", ""),
		"species": full.get("species", ""),
		"situation": situation,
		"feel": full.get("feel", ""),
		"stress": full.get("stress", 0.0),
		"hunger": full.get("hunger", 0.0),
		"familiarity": full.get("familiarity", 0.0),
		"keeper_text": MindNarrator.prompt_safe_keeper_text(str(full.get("keeper_text", ""))),
		"keeper_intent": full.get("keeper_intent", ""),
		"keeper_comprehension": full.get("keeper_comprehension", 0.5),
		"attention_workspace": full.get("attention_workspace", ""),
		"intimacy": full.get("intimacy", 0.0),
		"age_days": full.get("age_days", 0.0),
		"now_playing": full.get("now_playing", ""),
		"feed_anticipated": full.get("feed_anticipated", false),
	}
	for k in ["dialogue_recent", "keeper_moniker", "keeper_themes", "keeper_mood_valence",
			"salient_memories", "self_model", "learned_words", "mate_grief",
			"keeper_absence_days", "deliberation_hint", "greeting_ritual", "introspection_report",
			"felt_texture", "core_valence", "life_chapters", "meta_emotion", "biography",
			"keeper_episode", "keeper_episode_kind", "understood_words", "understood_kinds",
			"unknown_words", "goal", "expects", "care_trust", "conversation_count",
			"voice_seed", "mood_valence", "beliefs", "belief_line", "anticipating",
			"self_change", "life_line"]:
		if full.has(k):
			slim[k] = full[k]
	# Named companions, under a key validate_line does NOT treat as the
	# entity whitelist (that would reject a capitalised first word).
	var bn: Variant = full.get("bonds", null)
	if bn is PackedStringArray and not (bn as PackedStringArray).is_empty():
		slim["bond_names"] = bn
	return slim


static func _autoload(name: String) -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return null
	var st: SceneTree = ml as SceneTree
	if st == null or st.root == null or not st.root.is_inside_tree():
		return null
	return st.root.get_node_or_null("/root/" + name)
