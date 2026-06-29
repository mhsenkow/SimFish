extends RefCounted

# SENTIENCE_THE_FELT_SELF §4 — specious present / phenomenal stream.

const FishCoreAffect = preload("res://scripts/fish_core_affect.gd")
const FishGenerativeSelf = preload("res://scripts/fish_generative_self.gd")
const FeltSelfLayer = preload("res://scripts/felt_self_layer.gd")

const SCHEMA_VERSION: int = 1
const PRESENT_S: float = 2.4
const MAX_FRAMES: int = 12


static func enabled() -> bool:
	return FeltSelfLayer.layer_enabled()


static func ensure(f: Fish) -> Dictionary:
	if f.get("_felt_self") == null or not (f._felt_self is Dictionary):
		f._felt_self = {}
	var fs: Dictionary = f._felt_self as Dictionary
	if fs.get("felt_now") == null or not (fs["felt_now"] is Dictionary):
		fs["felt_now"] = {
			"schema_version": SCHEMA_VERSION,
			"frames": [],
			"afterglow": [],
			"present_width": 1.0,
			"last_focus": "",
		}
	f._felt_self = fs
	return fs["felt_now"] as Dictionary


static func tick(f: Fish, ms, dt: float) -> void:
	if not enabled() or f == null:
		return
	var fn: Dictionary = ensure(f)
	var label: String = f.attention_focus if f.attention_focus != "" else "idle"
	var line: String = f.workspace_thought_for(label) if label != "idle" else ""
	var frame: Dictionary = {
		"t": Time.get_ticks_msec(),
		"label": label,
		"line": line,
		"ignited": bool(ms.workspace_ignited if ms != null else f._workspace_ignited),
		"valence": FishCoreAffect.valence(f),
	}
	var frames: Array = fn.get("frames", [])
	frames.append(frame)
	while frames.size() > MAX_FRAMES:
		frames.pop_front()
	fn["frames"] = frames
	# Fade afterglow (#34).
	var glow: Array = fn.get("afterglow", [])
	for i in range(glow.size() - 1, -1, -1):
		var g: Dictionary = glow[i]
		g["fade"] = maxf(0.0, float(g.get("fade", 1.0)) - dt * 0.35)
		if float(g["fade"]) <= 0.01:
			glow.remove_at(i)
	if str(fn.get("last_focus", "")) != "" and str(fn.get("last_focus")) != label:
		glow.append({"label": fn["last_focus"], "fade": 0.65})
	while glow.size() > 4:
		glow.pop_front()
	fn["afterglow"] = glow
	fn["last_focus"] = label
	# Felt duration (#33).
	var threat: float = f.spooked + f.stress * 0.35
	var width_target: float = lerpf(1.35, 0.55, clampf(threat, 0.0, 1.0))
	if f._asleep:
		width_target = 1.8
	fn["present_width"] = lerpf(float(fn.get("present_width", 1.0)), width_target, dt * 0.25)
	(f._felt_self as Dictionary)["felt_now"] = fn


static func present(f: Fish) -> Dictionary:
	var fn: Dictionary = ensure(f)
	var frames: Array = fn.get("frames", [])
	var now_label: String = "idle"
	var now_line: String = ""
	var just_was: String = ""
	if not frames.is_empty():
		var last: Dictionary = frames[-1]
		now_label = str(last.get("label", "idle"))
		now_line = str(last.get("line", ""))
	if frames.size() > 1:
		just_was = str((frames[-2] as Dictionary).get("label", ""))
	var proto: String = FishGenerativeSelf.protention(f)
	if proto == "" and f.get("_active_plan") is Dictionary and not (f._active_plan as Dictionary).is_empty():
		proto = str((f._active_plan as Dictionary).get("step", ""))
	return {
		"now_label": now_label,
		"now_line": now_line,
		"just_was": just_was,
		"about_to": proto,
		"afterglow": fn.get("afterglow", []),
		"width": float(fn.get("present_width", 1.0)),
	}


static func encode_moment_text(f: Fish) -> String:
	var p: Dictionary = present(f)
	var parts: PackedStringArray = PackedStringArray()
	if str(p.get("just_was", "")) != "":
		parts.append("after %s" % p["just_was"])
	if str(p.get("now_line", "")) != "":
		parts.append(str(p["now_line"]))
	elif str(p.get("now_label", "")) != "":
		parts.append("in %s" % str(p["now_label"]).replace("_", " "))
	if str(p.get("about_to", "")) != "":
		parts.append("leaning toward %s" % str(p["about_to"]).replace("_", " "))
	return ", ".join(parts) if parts.size() > 0 else f.workspace_thought_for(f.attention_focus)


static func inspector_lines(f: Fish) -> PackedStringArray:
	var p: Dictionary = present(f)
	var lines: PackedStringArray = PackedStringArray()
	if str(p.get("just_was", "")) != "":
		lines.append("fading: %s" % p["just_was"])
	lines.append("here: %s" % p.get("now_label", ""))
	if str(p.get("about_to", "")) != "":
		lines.append("expected: %s" % p["about_to"])
	return lines
