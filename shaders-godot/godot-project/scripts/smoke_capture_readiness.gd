extends SceneTree

# CaptureReadiness + World.build_stage contract (HOLISTIC #004).


const Ready = preload("res://scripts/capture_readiness.gd")


class StubWorld extends Node:
	var build_complete: bool = false
	var build_stage: String = "stocking"


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_capture_readiness")
	t.check(Ready.STAGES.has("structure"), "structure is a known stage")
	t.check(Ready.STAGES.has("complete"), "complete is a known stage")
	t.check(not Ready.is_complete(null), "null world is not complete")
	t.equals(Ready.stage_of(null), "missing", "null world stage is missing")

	var stub := StubWorld.new()
	t.check(not Ready.is_complete(stub), "incomplete stub")
	t.equals(Ready.stage_of(stub), "stocking", "reads build_stage")
	stub.build_complete = true
	stub.build_stage = "complete"
	t.check(Ready.is_complete(stub), "complete stub")
	t.equals(Ready.stage_of(stub), "complete", "complete stage name")

	var host := Node.new()
	var sv := Node.new()
	sv.name = "SubViewport"
	host.add_child(sv)
	var world := StubWorld.new()
	world.name = "World"
	world.build_complete = true
	world.build_stage = "complete"
	sv.add_child(world)
	t.check(Ready.world_of(host) == world, "world_of finds SubViewport/World")
	host.free()

	quit(t.finish())
