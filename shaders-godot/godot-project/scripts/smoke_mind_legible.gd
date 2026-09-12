extends SceneTree

# Mind legibility (BROAD_DIRECTIONS #17).
#
# The contract is about PHRASING, not plumbing: a player should read a
# sentence about a creature, never a scalar. So the assertions here are
# mostly "does this say the right thing, and never leak a number".


# Stand-in for a MindState snapshot. Plain properties, so the same reader
# works against a live Fish, a MindState, or this.
class FakeMind:
	extends RefCounted
	var mood: float = 0.0
	var arousal: float = 0.0
	var vigilance: float = 0.0
	var stress: float = 0.0
	var hunger: float = 0.0
	var surprise: float = 0.0
	var curiosity_drive: float = 0.0
	var sleep_depth: float = 0.0
	var dream_wisp: String = ""
	var attention_focus: String = ""
	var current_intention: String = ""
	var current_thought: String = ""
	var goal_kind: String = ""
	var thought_stream: String = ""
	var prediction_error: float = 0.0
	var life_stance: String = ""
	var self_summary: String = ""
	var workspace: Array = []
	var workspace_ignited: bool = false
	var meta_states: PackedStringArray = PackedStringArray()
	var emotional_state: String = ""
	var dominant_need: String = ""


func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_mind_legible")

	# --- Null safety: every entry point must survive a missing subject ---
	t.check(MindLegible.headline(null) != "", "headline(null) returns something printable")
	t.check(MindLegible.mood_label(null) != "", "mood_label(null) returns something")
	t.equals(MindLegible.detail_lines(null).size(), 0, "detail_lines(null) is empty")
	t.equals(MindLegible.drives(null).size(), 0, "drives(null) is empty")
	t.equals(MindLegible.workings(null).size(), 0, "workings(null) is empty")

	# --- Mood words are player-facing, not enum tokens ---
	var m := FakeMind.new()
	m.emotional_state = "cozy"
	t.equals(MindLegible.mood_label(m), "Asleep",
		"'cozy' must read as 'Asleep', not the raw token")
	m.emotional_state = "anxious"
	t.equals(MindLegible.mood_label(m), "Uneasy", "'anxious' must read as 'Uneasy'")
	# An unknown state degrades to its capitalised name rather than vanishing.
	m.emotional_state = "brand_new_state"
	t.check(MindLegible.mood_label(m).length() > 0,
		"an unrecognised mood still produces a label")
	t.check(not MindLegible.mood_label(m).contains("_"),
		"a label must never leak snake_case: %s" % MindLegible.mood_label(m))

	# --- Derived mood when the snapshot carries no emotional_state ---
	var d := FakeMind.new()
	d.sleep_depth = 0.5
	t.equals(MindLegible.mood_label(d), "Asleep",
		"a sleeping snapshot reads as Asleep without emotional_state")
	var d2 := FakeMind.new()
	d2.vigilance = 0.8
	t.equals(MindLegible.mood_label(d2), "Uneasy", "high vigilance derives Uneasy")
	var d3 := FakeMind.new()
	d3.arousal = 0.8
	d3.mood = 0.5
	t.equals(MindLegible.mood_label(d3), "Excited", "high arousal + good mood derives Excited")

	# --- Headline: sleep overrides need ---
	# A sleeping fish must never read as "searching for food".
	var sleeper := FakeMind.new()
	sleeper.sleep_depth = 0.6
	sleeper.hunger = 0.9
	sleeper.dominant_need = "food"
	var sh: String = MindLegible.headline(sleeper)
	t.check(not sh.contains("searching for food"),
		"a sleeping fish must not read as foraging: %s" % sh)
	t.check(sh.contains("settled in"), "a sleeping fish reads as settled: %s" % sh)
	# A dream, when there is one, is the better line.
	sleeper.dream_wisp = "warm shallows"
	t.check(MindLegible.headline(sleeper).contains("warm shallows"),
		"a dream wisp must appear in the headline")

	# --- Headline: need and focus combine, and read as English ---
	var busy := FakeMind.new()
	busy.emotional_state = "anxious"
	busy.dominant_need = "safety"
	busy.attention_focus = "predator"
	var bh: String = MindLegible.headline(busy)
	t.check(bh.begins_with("Uneasy"), "headline leads with the mood: %s" % bh)
	t.check(bh.contains("hide"), "a safety need reads as looking to hide: %s" % bh)
	t.check(bh.contains("something bigger"),
		"a predator focus reads as 'something bigger': %s" % bh)
	t.check(bh.ends_with("."), "a headline is a sentence: %s" % bh)
	# Focus alone still produces a sentence.
	var focused := FakeMind.new()
	focused.attention_focus = "keeper"
	t.check(MindLegible.headline(focused).contains("you"),
		"a keeper focus should read as 'you'")

	# --- THE RULE: no raw numbers in any player-facing string ---
	var loud := FakeMind.new()
	loud.emotional_state = "excited"
	loud.dominant_need = "explore"
	loud.attention_focus = "novelty"
	loud.stress = 0.8123
	loud.hunger = 0.7777
	loud.curiosity_drive = 0.6543
	loud.surprise = 0.9
	loud.vigilance = 0.71
	loud.current_thought = "what is that"
	var strings: Array[String] = [MindLegible.headline(loud), MindLegible.mood_label(loud)]
	strings.append_array(MindLegible.detail_lines(loud))
	for row in MindLegible.workings(loud):
		strings.append(String(row.get("value", "")))
	for line in strings:
		# A decimal point between digits is the tell for a leaked scalar.
		var leaked: bool = false
		for i in range(1, line.length() - 1):
			if line[i] == "." and line[i - 1].is_valid_int() and line[i + 1].is_valid_int():
				leaked = true
		t.check(not leaked, "player-facing text must not contain a raw value: '%s'" % line)

	# --- Detail lines: only notable things, strongest phrasing at extremes ---
	var calm := FakeMind.new()
	t.equals(MindLegible.detail_lines(calm).size(), 0,
		"an unremarkable fish produces no detail lines (no padding)")
	var stressed := FakeMind.new()
	stressed.stress = 0.9
	var sl: Array[String] = MindLegible.detail_lines(stressed)
	t.check(sl.size() >= 1, "high stress produces a detail line")
	t.check(sl[0].contains("water"),
		"severe stress should point the player at the water: %s" % sl[0])
	var peckish := FakeMind.new()
	peckish.hunger = 0.5
	var pl: Array[String] = MindLegible.detail_lines(peckish)
	t.check(pl.size() == 1 and pl[0].contains("Getting hungry"),
		"moderate hunger reads as 'Getting hungry'")
	# Below the notability threshold nothing is said.
	var faint := FakeMind.new()
	faint.hunger = 0.2
	faint.stress = 0.2
	t.equals(MindLegible.detail_lines(faint).size(), 0,
		"faint drives must not be mentioned")

	# --- A thought is quoted and comes last ---
	var thinker := FakeMind.new()
	thinker.current_thought = "the light moved"
	var tl: Array[String] = MindLegible.detail_lines(thinker)
	t.check(tl.size() == 1, "a thought produces exactly one line")
	t.check(tl[tl.size() - 1].contains("the light moved"),
		"the thought is the last line")
	t.check(tl[0].contains("“"), "a thought is quoted: %s" % tl[0])
	# thought_stream is the fallback source.
	var streamer := FakeMind.new()
	streamer.thought_stream = "cold near the glass"
	t.check(MindLegible.detail_lines(streamer)[0].contains("cold near the glass"),
		"thought_stream is used when current_thought is empty")

	# --- Drives: sorted strongest-first, weak ones dropped ---
	var dr := FakeMind.new()
	dr.hunger = 0.9
	dr.stress = 0.3
	dr.curiosity_drive = 0.6
	dr.vigilance = 0.01
	var rows: Array[Dictionary] = MindLegible.drives(dr)
	t.check(rows.size() >= 3, "notable drives are returned")
	t.equals(String(rows[0]["label"]), "Hunger", "the strongest drive sorts first")
	var labels: Array[String] = []
	for r in rows:
		labels.append(String(r["label"]))
		t.in_range(float(r["value"]), 0.0, 1.0,
			"%s must be a 0..1 magnitude" % String(r["label"]))
	t.check(not labels.has("Alertness"),
		"a negligible drive (0.01) must be dropped, got: %s" % ", ".join(labels))
	# Descending order throughout.
	for i in range(1, rows.size()):
		t.check(float(rows[i - 1]["value"]) >= float(rows[i]["value"]),
			"drives must be sorted descending")

	# --- Workings: the machinery, still phrased ---
	var w := FakeMind.new()
	w.current_intention = "find_cover"
	w.workspace_ignited = true
	w.prediction_error = 0.8
	w.life_stance = "cautious_explorer"
	w.meta_states = PackedStringArray(["self_aware", "second_guessing"])
	var wr: Array[Dictionary] = MindLegible.workings(w)
	var by_label: Dictionary = {}
	for r in wr:
		by_label[String(r["label"])] = String(r["value"])
	t.check(by_label.has("Trying to"), "an intention is surfaced")
	t.equals(String(by_label.get("Trying to", "")), "find cover",
		"snake_case intentions are humanised")
	t.check(String(by_label.get("Mind", "")).contains("taken over"),
		"workspace ignition reads as one thing taking over")
	t.check(String(by_label.get("Expectations", "")).contains("surprising"),
		"high prediction error reads as the tank surprising them")
	t.equals(String(by_label.get("Outlook", "")), "cautious explorer",
		"life stance is humanised")
	t.check(String(by_label.get("Also", "")).contains("second guessing"),
		"meta-states are listed and humanised")
	# No underscores anywhere in the rendered values.
	for label in by_label.keys():
		t.check(not String(by_label[label]).contains("_"),
			"workings value must not leak snake_case: %s" % String(by_label[label]))

	# Competing impulses, when not yet ignited.
	var comp := FakeMind.new()
	comp.workspace = ["a", "b", "c"]
	var cr: Array[Dictionary] = MindLegible.workings(comp)
	var found: bool = false
	for r in cr:
		if String(r["label"]) == "Mind" and String(r["value"]).contains("competing"):
			found = true
	t.check(found, "multiple un-ignited workspace bids read as competing impulses")

	# A quiet mind reports nothing rather than empty rows.
	t.equals(MindLegible.workings(FakeMind.new()).size(), 0,
		"a quiet mind produces no workings rows")

	quit(t.finish())
