class_name CognitionKernel
extends RefCounted

# META_ENGINEERING #11 — host-agnostic cognition tick entry (Fish adapter today).
# perceive → attend → bind → encode → learn; MindState in/out.

const MindCycleScript = preload("res://scripts/mind_cycle.gd")


class Percept:
	var dt: float = 0.0
	var sim: Node = null
	var neighbors: Array = []
	var conspecifics_nearby: int = 0


static func tick(host: Node, state: MindState, percept: Percept) -> MindState:
	if host == null or state == null or percept == null:
		return state
	run_cycle(host, state, percept.sim, percept.dt)
	return state


static func run_cycle(host: Node, ms: MindState, sim: Node, dt: float) -> void:
	MindCycleScript.run_attention_phase(host, sim, ms, dt)
	run_bind_encode_learn(host, ms, sim, dt)


static func run_bind_encode_learn(host: Node, ms: MindState, sim: Node, dt: float) -> void:
	MindCycleScript.run_bind_phase(host, sim, ms, dt)
	MindCycleScript.run_encode_phase(host, ms)
	MindCycleScript.tick_post_cycle(host, sim, dt)
