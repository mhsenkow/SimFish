extends SceneTree

const EpiphyteAttachment = preload("res://scripts/epiphyte_attachment.gd")


func _init() -> void:
	var failed: Array[String] = []
	var surfaces: Array = [
		{"position": Vector3(1, 1, 0), "kind": "rock"},
		{"position": Vector3(3, 2, 0), "kind": "wood"},
		{"position": Vector3(0, 0, 0), "kind": "substrate"},
	]
	var near_rock: Dictionary = EpiphyteAttachment.nearest_valid(Vector3.ZERO, surfaces)
	TestSupport.check(failed, String(near_rock.get("kind", "")) == "rock",
		"nearest rock surface selected")
	var near_wood: Dictionary = EpiphyteAttachment.nearest_valid(Vector3(3, 1.8, 0), surfaces)
	TestSupport.check(failed, String(near_wood.get("kind", "")) == "wood",
		"wood surface selected")
	var absent: Dictionary = EpiphyteAttachment.nearest_valid(
		Vector3(20, 0, 0), surfaces)
	TestSupport.check(failed, absent.is_empty(), "distant hardscape triggers substrate fallback")
	TestSupport.check(failed, EpiphyteAttachment.nearest_valid(
		Vector3.ZERO, [{"position": Vector3.ZERO, "kind": "substrate"}]).is_empty(),
		"substrate is not accepted as attachment")
	quit(TestSupport.report("smoke_plant_reproduction_46", failed))
