extends RefCounted

# SENTIENCE_THE_FELT_SELF §10 — integration capstone + layer toggle.

const FeltSelfLayer = preload("res://scripts/felt_self_layer.gd")
const FishProtoself = preload("res://scripts/fish_protoself.gd")
const FishCoreAffect = preload("res://scripts/fish_core_affect.gd")
const FishRelevance = preload("res://scripts/fish_relevance.gd")
const FishFeltNow = preload("res://scripts/fish_felt_now.gd")
const FishGenerativeSelf = preload("res://scripts/fish_generative_self.gd")
const FishConcepts = preload("res://scripts/fish_concepts.gd")
const FishContinuity = preload("res://scripts/fish_continuity.gd")
const FishQualia = preload("res://scripts/fish_qualia.gd")
const FishVolition = preload("res://scripts/fish_volition.gd")

const HONEST_FRAME: String = FeltSelfLayer.HONEST_FRAME
const CAPSTONE_LINE: String = "a small body, feeling its water, in its now, still itself"

const SCHEMA_VERSION: int = 1


static func layer_enabled() -> bool:
	return FeltSelfLayer.layer_enabled()


static func ensure(f: Fish) -> Dictionary:
	if f.get("_felt_self") == null or not (f._felt_self is Dictionary):
		f._felt_self = {}
	var fs: Dictionary = f._felt_self as Dictionary
	if fs.get("binding") == null or not (fs["binding"] is Dictionary):
		fs["binding"] = {
			"schema_version": SCHEMA_VERSION,
			"phi_proxy": 0.0,
			"presence": 0.0,
			"fragmented": false,
			"moment_label": "",
			"moment_line": "",
			"bound_at_ms": 0,
		}
	f._felt_self = fs
	return fs["binding"] as Dictionary


static func bind_moment(f: Fish, _ms, dt: float) -> Dictionary:
	if not layer_enabled() or f == null:
		return {}
	var bd: Dictionary = ensure(f)
	var modules_ok: int = 0
	if not FishProtoself.ensure(f).is_empty():
		modules_ok += 1
	if not FishCoreAffect.ensure(f).is_empty():
		modules_ok += 1
	if not FishFeltNow.ensure(f).is_empty():
		modules_ok += 1
	if not FishRelevance.ensure(f).is_empty():
		modules_ok += 1
	var phi: float = clampf(float(modules_ok) / 4.0, 0.0, 1.0)
	if f.is_guardian or f.fish_name != "":
		phi = clampf(phi + 0.12, 0.0, 1.0)
	if f.familiarity > 0.45:
		phi = clampf(phi + f.familiarity * 0.08, 0.0, 1.0)
	# Graded consciousness (#94).
	if f._asleep:
		phi *= lerpf(0.35, 0.65, float(f.get("_sleep_depth") if f.get("_sleep_depth") != null else 0.0))
	# Disintegration under extremis (#93).
	var fragmented: bool = f.stress > 0.88 or f.hunger > 0.92
	if fragmented:
		phi *= 0.45
	bd["phi_proxy"] = lerpf(float(bd.get("phi_proxy", 0.0)), phi, clampf(dt * 2.0, 0.0, 1.0))
	bd["presence"] = bd["phi_proxy"]
	bd["fragmented"] = fragmented
	var fn: Dictionary = FishFeltNow.present(f)
	bd["moment_label"] = str(fn.get("now_label", f.attention_focus))
	bd["moment_line"] = str(fn.get("now_line", ""))
	if bd["moment_line"] == "":
		bd["moment_line"] = f.workspace_thought_for(str(bd["moment_label"]))
	bd["bound_at_ms"] = Time.get_ticks_msec()
	(f._felt_self as Dictionary)["binding"] = bd
	FishContinuity.note_bound_moment(f, bd)
	return bd.duplicate(true)


static func integration_score(f: Fish) -> float:
	return float(ensure(f).get("phi_proxy", 0.0))


static func first_person_glimpse(f: Fish) -> String:
	if not layer_enabled() or f == null:
		return ""
	var tex: String = FishCoreAffect.texture(f)
	var line: String = str(ensure(f).get("moment_line", ""))
	if line == "":
		return CAPSTONE_LINE
	return "%s — %s" % [tex, line]


static func integration_test(f: Fish) -> Dictionary:
	var missing: PackedStringArray = PackedStringArray()
	if FishProtoself.ensure(f).is_empty():
		missing.append("protoself")
	if FishCoreAffect.ensure(f).is_empty():
		missing.append("core_affect")
	if FishFeltNow.ensure(f).is_empty():
		missing.append("felt_now")
	if integration_score(f) < 0.15:
		missing.append("binding")
	return {"ok": missing.is_empty(), "missing": missing, "phi": integration_score(f)}


static func to_dict(f: Fish) -> Dictionary:
	if f.get("_felt_self") is Dictionary:
		return (f._felt_self as Dictionary).duplicate(true)
	return {}


static func from_dict(f: Fish, d: Variant) -> void:
	if d is Dictionary:
		f._felt_self = (d as Dictionary).duplicate(true)
