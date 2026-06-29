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


static func build_for_fish(f: Fish, sim: Node = null, situation: String = "", ms: MindState = null) -> Dictionary:
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
	var allowed_fish: PackedStringArray = PackedStringArray()
	if sim != null and sim.get("fish") != null:
		for ff in sim.fish:
			if is_instance_valid(ff):
				var n: String = str(ff.fish_name if ff.fish_name != "" else ff.species)
				if n != "" and not allowed_fish.has(n):
					allowed_fish.append(n)
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
		"self_model": state.self_model.duplicate(true),
		"thought_stream": state.thought_stream,
		"voice_seed": MindNarrator.voice_style_seed(str(f.id), f.personality),
		"meals_eaten": int(f.bio.get("meals_eaten", 0)) if f.bio is Dictionary else 0,
		"age_days": snappedf(f.age / maxf(f.max_age_s, 1.0) * 365.0, 0.1),
		"generation": f.generation,
		"is_guardian": f.is_guardian,
		"voiced": f.is_voiced_individual(),
	}
	if not f.inferred_states.is_empty():
		ctx["inferred_others"] = f.inferred_states.duplicate()
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
	var lex: Dictionary = MindLexicon.ensure_dict(f)
	if not lex.is_empty():
		ctx["learned_words"] = lex.duplicate(true)
	if not state.keeper_pending.is_empty():
		ctx.merge(state.keeper_pending.duplicate(true))
	ctx["life_stance"] = state.life_stance
	ctx["prediction_error"] = snappedf(state.prediction_error, 0.01)
	ctx["thought_tense"] = FishMind.stream_tense_tag(f)
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
		var ql: String = FishQualia.report_line(f)
		if ql != "":
			ctx["qualia_report"] = ql
		var glimpse: String = FishBinding.first_person_glimpse(f)
		if glimpse != "":
			ctx["felt_glimpse"] = glimpse
	return ctx


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
			"keeper_absence_days", "deliberation_hint", "greeting_ritual"]:
		if full.has(k):
			slim[k] = full[k]
	return slim


static func _autoload(name: String) -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return null
	var st: SceneTree = ml as SceneTree
	if st == null or st.root == null or not st.root.is_inside_tree():
		return null
	return st.root.get_node_or_null("/root/" + name)
