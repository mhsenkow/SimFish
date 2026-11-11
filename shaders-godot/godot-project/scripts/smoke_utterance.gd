extends SceneTree

# LOOM #22 — the one Utterance record. Assert it carries identity/act/intent/
# content/felt/delivery, takes an honest felt snapshot, and emits exactly one
# "utter" event on the motion bus that subscribers can read.

const UtteranceScript = preload("res://scripts/utterance.gd")


func _init() -> void:
	var t := TestSupport.Suite.new("smoke_utterance")

	# A felt snapshot from a bare object with the legacy scalars.
	var fake := _FakeFish.new()
	var felt: Dictionary = UtteranceScript.felt_from_fish(fake)
	t.has_keys(felt, ["valence", "arousal", "stress", "fatigue", "confidence", "surprise"],
			"felt snapshot has all six channels")
	t.in_range(float(felt["confidence"]), 0.0, 1.0, "confidence clamped")
	t.in_range(float(felt["stress"]), 0.0, 1.0, "stress clamped")

	# A tank murmur carries valence/arousal and no text requirement.
	var tank_u = UtteranceScript.for_tank("the water settles", 0.3, 0.4)
	t.equals(tank_u.speaker_kind, &"tank", "tank utterance speaker_kind")
	t.equals(tank_u.act, UtteranceScript.ACT_MURMUR, "tank utterance act is murmur")

	# Subscribe to the motion bus and verify exactly one event with the record.
	MotionEvents.clear()
	MotionEvents.enabled = true
	var seen: Array = []
	var cb := func(ev: Dictionary) -> void: seen.append(ev)
	MotionEvents.subscribe(&"utter", cb)

	var u = UtteranceScript.for_fish(fake, "a small bright thing",
			UtteranceScript.ACT_BABBLE, UtteranceScript.INTENT_REPLY, "fish-1")
	t.equals(u.speaker_id, "fish-1", "speaker_id read from fish")
	t.equals(u.intent, UtteranceScript.INTENT_REPLY, "intent preserved")
	t.check(u.id > 0, "utterance has a positive id")
	t.in_range(u.loudness, 0.0, 1.0, "loudness clamped")

	var emitted: Dictionary = u.emit(null)
	t.equals(seen.size(), 1, "exactly one utter event emitted")
	if not seen.is_empty():
		var got: Dictionary = seen[0]
		t.equals(String(got.get("kind", "")), "utter", "event kind is utter")
		t.check(got.get("utterance") == u, "event carries the Utterance record")
		t.has_keys(got, ["felt", "act", "intent", "text", "loudness"], "event has content keys")
	t.has_keys(emitted, ["utterance", "felt"], "emit returns the extra dict")

	MotionEvents.unsubscribe(&"utter", cb)
	quit(t.finish())


class _FakeFish:
	extends RefCounted
	var id: String = "fish-1"
	var mood: float = 0.2
	var stress: float = 0.3
	var arousal: float = 0.4
	var vigilance: float = 0.1
