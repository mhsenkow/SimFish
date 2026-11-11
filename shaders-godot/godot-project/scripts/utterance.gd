class_name Utterance
extends RefCounted

# SENTIENCE_THE_LOOM_THAT_THINKS_500 #22 — one voice record, the foundation of
# Part One. Every speech path (fish thought, keeper reply, tank breath, colony,
# guardian) builds one of these and emits it on the motion bus
# (`MotionEvents.emit("utter", …)`). Audio, pose, text, journal and nearby fish
# subscribe to one event instead of four code paths each half-wiring the same
# moment.
#
# This is a plain record plus a felt-state snapshot taken at the instant of
# speaking, so prosody (#76) and the model prompt read the same truth the body
# felt when it chose to speak.

const FishCoreAffect = preload("res://scripts/fish_core_affect.gd")
const FishProtoself = preload("res://scripts/fish_protoself.gd")
const MindSelfModel = preload("res://scripts/mind_self_model.gd")

# Act — how the voice is made, independent of what it means.
const ACT_CALL: StringName = &"call"       # a biological signal (drum/stridulation)
const ACT_MURMUR: StringName = &"murmur"   # the tank's low breath
const ACT_BABBLE: StringName = &"babble"   # a fish answering, syllabic
const ACT_LINE: StringName = &"line"       # a text line with a vocal act under it
const ACT_BREATH: StringName = &"breath"   # a non-verbal exhale / gulp kiss

# Intent — what the voice is for.
const INTENT_THOUGHT: StringName = &"thought"
const INTENT_REPLY: StringName = &"reply"
const INTENT_GREET: StringName = &"greet"
const INTENT_ALARM: StringName = &"alarm"
const INTENT_FOOD: StringName = &"food"
const INTENT_CONTACT: StringName = &"contact"
const INTENT_MURMUR: StringName = &"murmur"

var id: int = 0
var speaker_id: String = ""
var speaker_kind: StringName = &"fish"  # fish / tank / colony / guardian
var act: StringName = ACT_LINE
var intent: StringName = INTENT_THOUGHT
var text: String = ""
var felt: Dictionary = {}               # snapshot: valence/arousal/stress/fatigue/confidence/surprise
var pos: Vector3 = Vector3.ZERO
var loudness: float = 0.5               # 0..1, scaled by act + felt arousal
var addressee_id: String = ""
var t: float = 0.0                      # sim-seconds, or wall seconds for UI-only acts

static var _next_id: int = 1


# The felt snapshot (#22 Content, consumed by #76). Reads the felt-self layer
# where it exists and falls back to the legacy scalars so a fish with the layer
# off still produces an honest (if coarser) reading.
static func felt_from_fish(f) -> Dictionary:
	if f == null:
		return {"valence": 0.0, "arousal": 0.2, "stress": 0.0,
				"fatigue": 0.0, "confidence": 0.5, "surprise": 0.0}
	var valence: float = 0.0
	var arousal: float = float(f.get("arousal")) if f.get("arousal") != null else 0.2
	if FishCoreAffect.enabled():
		var ca: Dictionary = FishCoreAffect.ensure(f)
		valence = float(ca.get("valence", 0.0))
		arousal = float(ca.get("arousal_core", arousal))
	else:
		valence = float(f.get("mood")) if f.get("mood") != null else 0.0
	var stress: float = float(f.get("stress")) if f.get("stress") != null else 0.0
	var fatigue: float = 0.0
	if FishProtoself.enabled():
		fatigue = float(FishProtoself.ensure(f).get("fatigue", 0.0))
	var vigilance: float = float(f.get("vigilance")) if f.get("vigilance") != null else 0.0
	var confidence: float = clampf(1.0 - stress * 0.5 - vigilance * 0.3, 0.0, 1.0)
	var sm: Variant = f.get("_mind_self_model")
	if sm is Dictionary and (sm as Dictionary).has("confidence"):
		confidence = float((sm as Dictionary)["confidence"])
	# Prediction-error surprise, if the mind recorded one this cycle.
	var surprise: float = 0.0
	var pe: Variant = f.get("_last_prediction_error")
	if pe != null and is_finite(float(pe)):
		surprise = clampf(float(pe), 0.0, 1.0)
	return {
		"valence": clampf(valence, -1.0, 1.0),
		"arousal": clampf(arousal, 0.0, 1.0),
		"stress": clampf(stress, 0.0, 1.0),
		"fatigue": clampf(fatigue, 0.0, 1.0),
		"confidence": clampf(confidence, 0.0, 1.0),
		"surprise": clampf(surprise, 0.0, 1.0),
	}


# Build an Utterance for a fish speaking. `t` defaults to a wall clock so UI
# ordering works even with no sim reference.
static func for_fish(f, line: String, p_act: StringName = ACT_LINE,
		p_intent: StringName = INTENT_THOUGHT, addressee: String = "") -> Utterance:
	var u := Utterance.new()
	u.id = _next_id
	_next_id += 1
	u.speaker_kind = &"fish"
	u.speaker_id = String(f.get("id")) if f != null and f.get("id") != null else ""
	u.act = p_act
	u.intent = p_intent
	u.text = line
	u.addressee_id = addressee
	u.felt = felt_from_fish(f)
	if f is Node3D:
		u.pos = (f as Node3D).global_position
	# Loudness rises with arousal and a line being spoken aloud over a murmur.
	var base: float = 0.55 if p_act == ACT_LINE or p_act == ACT_BABBLE else 0.4
	u.loudness = clampf(base + float(u.felt.get("arousal", 0.2)) * 0.4, 0.0, 1.0)
	u.t = float(Time.get_ticks_msec()) * 0.001
	return u


# Build an Utterance for the tank mind's low breath (speaker_kind "tank").
static func for_tank(line: String, valence: float = 0.0, arousal: float = 0.2) -> Utterance:
	var u := Utterance.new()
	u.id = _next_id
	_next_id += 1
	u.speaker_kind = &"tank"
	u.act = ACT_MURMUR
	u.intent = INTENT_MURMUR
	u.text = line
	u.felt = {"valence": clampf(valence, -1.0, 1.0), "arousal": clampf(arousal, 0.0, 1.0),
			"stress": 0.0, "fatigue": 0.0, "confidence": 0.5, "surprise": 0.0}
	u.loudness = clampf(0.35 + arousal * 0.3, 0.0, 1.0)
	u.t = float(Time.get_ticks_msec()) * 0.001
	return u


# Emit on the motion bus. Every subscriber (audio/pose/text/journal/neighbours)
# receives the same record. Returns the event dict for convenience.
func emit(source: Object = null) -> Dictionary:
	var extra: Dictionary = {
		"utterance": self,
		"speaker_id": speaker_id,
		"speaker_kind": speaker_kind,
		"act": act,
		"intent": intent,
		"text": text,
		"felt": felt,
		"loudness": loudness,
		"addressee_id": addressee_id,
		"id": id,
	}
	MotionEvents.emit(&"utter", source, pos, loudness, extra)
	return extra


func to_dict() -> Dictionary:
	return {
		"id": id, "speaker_id": speaker_id, "speaker_kind": String(speaker_kind),
		"act": String(act), "intent": String(intent), "text": text,
		"felt": felt.duplicate(), "pos": pos, "loudness": loudness,
		"addressee_id": addressee_id, "t": t,
	}
