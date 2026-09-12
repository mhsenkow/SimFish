extends SceneTree

# COMMS_AI foundations smoke: arbiter priority, quiet mute, return XOR,
# caption budget, death summary, kind filters, consent defer.


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	# --- Priority enqueue (#1) ---
	var q: Array = []
	CommsInbox.enqueue_toast(q, {"kind": "discovery", "severity": "info", "body": "a"})
	CommsInbox.enqueue_toast(q, {"kind": "water_alert", "severity": "critical", "body": "b"})
	CommsInbox.enqueue_toast(q, {"kind": "care", "severity": "important", "body": "c"})
	TestSupport.check(failed, q.size() >= 2, "queue has items")
	TestSupport.check(failed, String(q[0].get("kind", "")) == "water_alert",
		"critical water first in queue")

	# Soft-cap drops ambient first.
	for i in range(12):
		CommsInbox.enqueue_toast(q, {
			"kind": "discovery", "severity": "info", "body": "x%d" % i
		})
	TestSupport.check(failed, q.size() <= CommsInbox.TOAST_QUEUE_SOFT_CAP, "soft cap enforced")
	var has_crit: bool = false
	for item in q:
		if String(item.get("kind", "")) == "water_alert" \
				and String(item.get("severity", "")) == "critical":
			has_crit = true
			break
	TestSupport.check(failed, has_crit, "critical survives soft-cap drops")

	# --- Quiet mute (#121) ---
	TestSupport.check(failed, CommsInbox.allows_toast("water_alert", "critical", true),
		"quiet allows critical water")
	TestSupport.check(failed, not CommsInbox.allows_toast("guardian", "important", true),
		"quiet blocks guardian toast")
	TestSupport.check(failed, not CommsInbox.allows_toast("discovery", "info", true),
		"quiet blocks discovery")
	TestSupport.check(failed, CommsInbox.allows_toast("residents", "important", true),
		"quiet allows memorial")
	TestSupport.check(failed, not CommsInbox.allows_status_toast("Saved", true),
		"quiet hushes autosave status")
	TestSupport.check(failed, CommsInbox.allows_status_toast("Photo saved · shot.png", true),
		"quiet keeps photo status")
	TestSupport.check(failed, not CommsInbox.allows_caption(true), "quiet blocks captions")

	# --- Return ceremony XOR (#241) ---
	var st: Dictionary = {}
	TestSupport.check(failed, CommsInbox.claim_return_ceremony(st, "welcome"), "welcome claim")
	TestSupport.check(failed, not CommsInbox.claim_return_ceremony(st, "welcome"), "welcome no double")
	TestSupport.check(failed, CommsInbox.claim_return_ceremony(st, "away"), "away steals welcome")
	TestSupport.check(failed, CommsInbox.return_ceremony(st) == "away", "away is final")
	TestSupport.check(failed, not CommsInbox.claim_return_ceremony(st, "welcome"),
		"welcome cannot steal away")

	# --- Caption budget (#401) ---
	var cap: Dictionary = {}
	TestSupport.check(failed, CommsInbox.caption_allowed(cap, 100.0, false), "first caption ok")
	TestSupport.check(failed, not CommsInbox.caption_allowed(cap, 110.0, false),
		"caption within 20s blocked")
	TestSupport.check(failed, CommsInbox.caption_allowed(cap, 121.0, false),
		"caption after 20s ok")

	# --- Death summary (#361) ---
	var death: Dictionary = {}
	CommsInbox.note_death(death, "A", 1.0)
	CommsInbox.note_death(death, "B", 2.0)
	var summary: Dictionary = CommsInbox.flush_death_summary(death)
	TestSupport.check(failed, int(summary.get("count", 0)) == 2, "death count 2")
	TestSupport.check(failed, String(summary.get("body", "")).contains("and"),
		"two-name death body")

	CommsInbox.note_death(death, "Only", 50.0)
	var s1: Dictionary = CommsInbox.flush_death_summary(death)
	TestSupport.check(failed, int(s1.get("count", 0)) == 1, "single death")
	TestSupport.check(failed, String(s1.get("title", "")) == "In memoriam", "single title")

	# --- Consent defer (#281) ---
	TestSupport.check(failed, CommsInbox.consent_deferred(0.0, 60.0), "within 5min deferred")
	TestSupport.check(failed, not CommsInbox.consent_deferred(0.0, 301.0), "after 5min allowed")

	# --- Kind filters (#41) ---
	var ids: PackedStringArray = PackedStringArray()
	for e in CommsInbox.KIND_FILTER_ENTRIES:
		ids.append(String(e.get("id", "")))
	for need in ["guardian", "care", "fish_thought", "residents", "system",
			"mind_upgrade", "guardian_llm"]:
		TestSupport.check(failed, need in ids, "kind filter has %s" % need)

	# --- Tier chip (#161) ---
	TestSupport.check(failed, CommsInbox.tier_chip_line("template").begins_with("Voice:"),
		"tier chip templates")
	TestSupport.check(failed, CommsInbox.tier_chip_line("inprocess").contains("built-in"),
		"tier chip built-in")
	TestSupport.check(failed, CommsInbox.tier_chip_line("ollama").contains("Ollama"),
		"tier chip ollama")

	# --- Wiring presence ---
	var main_src: String = FileAccess.get_file_as_string("res://scripts/main.gd")
	TestSupport.check(failed, main_src.contains("CommsInbox.enqueue_toast"), "main uses arbiter")
	TestSupport.check(failed, main_src.contains("_mark_visible_notifications_read"),
		"mark-as-read on open")
	TestSupport.check(failed, main_src.contains("claim_return_ceremony"), "return ceremony API")
	TestSupport.check(failed, main_src.contains("_flush_death_summary"), "death summary flush")
	TestSupport.check(failed, main_src.contains("request_ambient_caption"), "caption budget API")
	TestSupport.check(failed, main_src.contains("_flush_deferred_consent"), "consent defer")

	var sim_src: String = FileAccess.get_file_as_string("res://scripts/sim_driver.gd")
	TestSupport.check(failed, sim_src.contains("claim_return_ceremony"), "away claims ceremony")

	var onb_src: String = FileAccess.get_file_as_string("res://scripts/onboarding_runtime.gd")
	TestSupport.check(failed, onb_src.contains("request_ambient_caption"), "captions gated")

	if failed.is_empty():
		print("SMOKE_COMMS_INBOX_OK")
		quit(0)
	else:
		for f in failed:
			push_error(f)
		print("SMOKE_COMMS_INBOX_FAIL count=%d" % failed.size())
		quit(1)
