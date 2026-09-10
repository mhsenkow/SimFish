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
	_assert(failed, q.size() >= 2, "queue has items")
	_assert(failed, String(q[0].get("kind", "")) == "water_alert",
		"critical water first in queue")

	# Soft-cap drops ambient first.
	for i in range(12):
		CommsInbox.enqueue_toast(q, {
			"kind": "discovery", "severity": "info", "body": "x%d" % i
		})
	_assert(failed, q.size() <= CommsInbox.TOAST_QUEUE_SOFT_CAP, "soft cap enforced")
	var has_crit: bool = false
	for item in q:
		if String(item.get("kind", "")) == "water_alert" \
				and String(item.get("severity", "")) == "critical":
			has_crit = true
			break
	_assert(failed, has_crit, "critical survives soft-cap drops")

	# --- Quiet mute (#121) ---
	_assert(failed, CommsInbox.allows_toast("water_alert", "critical", true),
		"quiet allows critical water")
	_assert(failed, not CommsInbox.allows_toast("guardian", "important", true),
		"quiet blocks guardian toast")
	_assert(failed, not CommsInbox.allows_toast("discovery", "info", true),
		"quiet blocks discovery")
	_assert(failed, CommsInbox.allows_toast("residents", "important", true),
		"quiet allows memorial")
	_assert(failed, not CommsInbox.allows_status_toast("Saved", true),
		"quiet hushes autosave status")
	_assert(failed, CommsInbox.allows_status_toast("Photo saved · shot.png", true),
		"quiet keeps photo status")
	_assert(failed, not CommsInbox.allows_caption(true), "quiet blocks captions")

	# --- Return ceremony XOR (#241) ---
	var st: Dictionary = {}
	_assert(failed, CommsInbox.claim_return_ceremony(st, "welcome"), "welcome claim")
	_assert(failed, not CommsInbox.claim_return_ceremony(st, "welcome"), "welcome no double")
	_assert(failed, CommsInbox.claim_return_ceremony(st, "away"), "away steals welcome")
	_assert(failed, CommsInbox.return_ceremony(st) == "away", "away is final")
	_assert(failed, not CommsInbox.claim_return_ceremony(st, "welcome"),
		"welcome cannot steal away")

	# --- Caption budget (#401) ---
	var cap: Dictionary = {}
	_assert(failed, CommsInbox.caption_allowed(cap, 100.0, false), "first caption ok")
	_assert(failed, not CommsInbox.caption_allowed(cap, 110.0, false),
		"caption within 20s blocked")
	_assert(failed, CommsInbox.caption_allowed(cap, 121.0, false),
		"caption after 20s ok")

	# --- Death summary (#361) ---
	var death: Dictionary = {}
	CommsInbox.note_death(death, "A", 1.0)
	CommsInbox.note_death(death, "B", 2.0)
	var summary: Dictionary = CommsInbox.flush_death_summary(death)
	_assert(failed, int(summary.get("count", 0)) == 2, "death count 2")
	_assert(failed, String(summary.get("body", "")).contains("and"),
		"two-name death body")

	CommsInbox.note_death(death, "Only", 50.0)
	var s1: Dictionary = CommsInbox.flush_death_summary(death)
	_assert(failed, int(s1.get("count", 0)) == 1, "single death")
	_assert(failed, String(s1.get("title", "")) == "In memoriam", "single title")

	# --- Consent defer (#281) ---
	_assert(failed, CommsInbox.consent_deferred(0.0, 60.0), "within 5min deferred")
	_assert(failed, not CommsInbox.consent_deferred(0.0, 301.0), "after 5min allowed")

	# --- Kind filters (#41) ---
	var ids: PackedStringArray = PackedStringArray()
	for e in CommsInbox.KIND_FILTER_ENTRIES:
		ids.append(String(e.get("id", "")))
	for need in ["guardian", "care", "fish_thought", "residents", "system",
			"mind_upgrade", "guardian_llm"]:
		_assert(failed, need in ids, "kind filter has %s" % need)

	# --- Tier chip (#161) ---
	_assert(failed, CommsInbox.tier_chip_line("template").begins_with("Voice:"),
		"tier chip templates")
	_assert(failed, CommsInbox.tier_chip_line("inprocess").contains("built-in"),
		"tier chip built-in")
	_assert(failed, CommsInbox.tier_chip_line("ollama").contains("Ollama"),
		"tier chip ollama")

	# --- Wiring presence ---
	var main_src: String = FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(failed, main_src.contains("CommsInbox.enqueue_toast"), "main uses arbiter")
	_assert(failed, main_src.contains("_mark_visible_notifications_read"),
		"mark-as-read on open")
	_assert(failed, main_src.contains("claim_return_ceremony"), "return ceremony API")
	_assert(failed, main_src.contains("_flush_death_summary"), "death summary flush")
	_assert(failed, main_src.contains("request_ambient_caption"), "caption budget API")
	_assert(failed, main_src.contains("_flush_deferred_consent"), "consent defer")

	var sim_src: String = FileAccess.get_file_as_string("res://scripts/sim_driver.gd")
	_assert(failed, sim_src.contains("claim_return_ceremony"), "away claims ceremony")

	var onb_src: String = FileAccess.get_file_as_string("res://scripts/onboarding_runtime.gd")
	_assert(failed, onb_src.contains("request_ambient_caption"), "captions gated")

	if failed.is_empty():
		print("SMOKE_COMMS_INBOX_OK")
		quit(0)
	else:
		for f in failed:
			push_error(f)
		print("SMOKE_COMMS_INBOX_FAIL count=%d" % failed.size())
		quit(1)


func _assert(failed: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		failed.append(msg)
