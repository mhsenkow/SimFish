extends SceneTree

# Repeats fold; they do not stack (VISUAL_DIRECTIONS #19).
#
# The toast lane was already well policed — TOAST_MAX_VISIBLE 2, a soft cap of
# 8, a 20 s caption floor, death batching. The notification badge still read 53
# inside the first twenty seconds of a boot, because every one of those rules
# governs presentation and none of them governs the record: each push appended
# a row.
#
# The visible half was two toasts on screen both headed "Population collapse".
# The old dedup key was kind|severity|BODY, so two sentences under one headline
# counted as two events. A player does not experience that as two events.

const Inbox = preload("res://scripts/comms_inbox.gd")


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_notification_coalescing")

	# --- A repeat folds into its predecessor ---
	var hist: Array = []
	Inbox.coalesce_into(hist, _n("population", "warning", "Population collapse",
		"Fish extirpated"), 1000)
	Inbox.coalesce_into(hist, _n("population", "warning", "Population collapse",
		"Shrimp colony collapsed"), 1005)
	t.equals(hist.size(), 1,
		"two events under one headline are one row, not two")
	t.equals(int((hist[0] as Dictionary).get("repeat", 1)), 2, "the row counts them")
	t.equals(String((hist[0] as Dictionary).get("body", "")), "Shrimp colony collapsed",
		"the folded row keeps the newest body")
	t.equals(int((hist[0] as Dictionary).get("ts", 0)), 1005,
		"the folded row carries the newest timestamp")
	t.check(not bool((hist[0] as Dictionary).get("read", true)),
		"a repeat marks the row unread again — a second occurrence is news")

	# --- Different titles stay separate ---
	Inbox.coalesce_into(hist, _n("population", "warning", "Fry hatched", "6 fry"), 1010)
	t.equals(hist.size(), 2, "a different title is a different row")
	# …and so does a different kind under the same title.
	Inbox.coalesce_into(hist, _n("care", "warning", "Population collapse", "x"), 1012)
	t.equals(hist.size(), 3, "same title, different kind, different row")

	# --- Past the window it is a new event ---
	var far: Array = []
	Inbox.coalesce_into(far, _n("care", "info", "Water change", "20%"), 0)
	Inbox.coalesce_into(far, _n("care", "info", "Water change", "20%"),
		Inbox.COALESCE_WINDOW_S + 1)
	t.equals(far.size(), 2,
		"a repeat outside the window is genuinely a second event")

	# --- Critical repeats sooner, but not always ---
	t.check(Inbox.coalesce_window_for("critical") < Inbox.coalesce_window_for("info"),
		"critical may repeat sooner than ambient")
	t.check(Inbox.coalesce_window_for("critical") > 0,
		"critical must still have a window — an unbounded bypass is how the "
			+ "same alarm lands twice")
	var crit: Array = []
	Inbox.coalesce_into(crit, _n("water_alert", "critical", "Oxygen low", "42%"), 0)
	Inbox.coalesce_into(crit, _n("water_alert", "critical", "Oxygen low", "38%"), 10)
	t.equals(crit.size(), 1, "a critical repeat 10 s later still folds")
	# The window runs from the LAST occurrence, not the first — a slow drip of
	# repeats keeps one row alive rather than starting a new one every window.
	Inbox.coalesce_into(crit, _n("water_alert", "critical", "Oxygen low", "30%"),
		10 + Inbox.COALESCE_WINDOW_CRITICAL_S + 5)
	t.equals(crit.size(), 2, "a critical repeat past its window is a new alarm")

	# --- Only the most recent match is considered ---
	# An old row of the same title must not resurrect when a fresh one exists.
	var chain: Array = []
	Inbox.coalesce_into(chain, _n("care", "info", "Filter rinsed", "a"), 0)
	Inbox.coalesce_into(chain, _n("care", "info", "Filter rinsed", "b"),
		Inbox.COALESCE_WINDOW_S + 10)
	Inbox.coalesce_into(chain, _n("care", "info", "Filter rinsed", "c"),
		Inbox.COALESCE_WINDOW_S + 20)
	t.equals(chain.size(), 2, "the fresh row absorbs, the stale one does not")
	t.equals(int((chain[1] as Dictionary).get("repeat", 1)), 2,
		"the absorbing row is the recent one")

	# --- The count is rendered ---
	t.equals(Inbox.display_title({"title": "Algae bloom"}), "Algae bloom",
		"a single event shows its plain title")
	t.equals(Inbox.display_title({"title": "Algae bloom", "repeat": 3}),
		"Algae bloom (x3)", "a folded row shows its count")
	t.equals(Inbox.display_title({"title": "Algae bloom", "repeat": 1}),
		"Algae bloom", "a repeat of 1 is not a count")
	t.equals(Inbox.display_title({}), "", "a title-less row does not crash")

	# --- Empty history appends ---
	var fresh: Array = []
	t.equals(Inbox.coalesce_into(fresh, _n("system", "info", "Hello", "hi"), 5), 0,
		"the first row lands at index 0")
	t.equals(fresh.size(), 1, "and is appended")

	# --- The flood is actually bounded ---
	# 60 alternating collapse messages, the shape the badge was seeing.
	var flood: Array = []
	for i in 60:
		var body: String = "Fish extirpated" if i % 2 == 0 else "Shrimp colony collapsed"
		Inbox.coalesce_into(flood,
			_n("population", "warning", "Population collapse", body), 100 + i)
	t.equals(flood.size(), 1,
		"60 repeats of one headline are one row, got %d" % flood.size())
	t.equals(int((flood[0] as Dictionary).get("repeat", 0)), 60,
		"and the row remembers how many")

	quit(t.finish())


func _n(kind: String, severity: String, title: String, body: String) -> Dictionary:
	return {
		"kind": kind, "severity": severity, "title": title, "body": body,
		"read": false, "repeat": 1, "ts": 0,
	}
