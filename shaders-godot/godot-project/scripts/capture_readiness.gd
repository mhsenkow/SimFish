# Capture readiness — wait on World staged construction (HOLISTIC #004).
#
# Captures used to guess a frame count. Slow machines under-settled; fast ones
# over-waited. World now exposes `build_complete` + `build_stage`; harnesses
# wait for completion, then keep a bounded cosmetic settle.
#
# Pure helpers — no scene tree ownership.

class_name CaptureReadiness
extends RefCounted

const DEFAULT_READY_TIMEOUT_S: float = 45.0
const STAGES: PackedStringArray = [
	"init", "structure", "stocking", "fixtures", "complete",
]


## Resolve the World node from a booted main.tscn instance.
static func world_of(main: Node) -> Node:
	if main == null:
		return null
	var w: Variant = main.get("world")
	if w is Node:
		return w as Node
	return main.get_node_or_null("SubViewport/World")


static func is_complete(world: Node) -> bool:
	return world != null and bool(world.get("build_complete"))


static func stage_of(world: Node) -> String:
	if world == null:
		return "missing"
	var s: Variant = world.get("build_stage")
	if s == null:
		return "unknown"
	var out: String = String(s)
	return out if out != "" else "unknown"


## Await until build_complete or timeout. Returns {ok, stage, waited_s, reason}.
static func await_world(tree: SceneTree, main: Node,
		timeout_s: float = DEFAULT_READY_TIMEOUT_S) -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	var limit_ms: int = int(maxf(timeout_s, 1.0) * 1000.0)
	var last_stage: String = "missing"
	while Time.get_ticks_msec() - t0 < limit_ms:
		var world: Node = world_of(main)
		last_stage = stage_of(world)
		if is_complete(world):
			return {
				"ok": true,
				"stage": last_stage,
				"waited_s": float(Time.get_ticks_msec() - t0) / 1000.0,
				"reason": "complete",
			}
		await tree.process_frame
	return {
		"ok": false,
		"stage": last_stage,
		"waited_s": float(Time.get_ticks_msec() - t0) / 1000.0,
		"reason": "timeout waiting for build_complete (stuck at '%s')" % last_stage,
	}
