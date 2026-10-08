extends SceneTree

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_mind_nearest_selection")
	var science: Script = load("res://scripts/fish_mind_science.gd")
	var observer := Fish.new()
	observer.id = "observer"
	var neighbors: Array = [observer, null]
	var fixtures: Array[Fish] = []
	for i in range(100, 0, -1):
		var other := Fish.new()
		other.id = "neighbor_%d" % i
		other.position = Vector3(i, 0, 0)
		fixtures.append(other)
		neighbors.append(other)
	var unregistered := Fish.new()
	unregistered.position = Vector3(0.01, 0, 0)
	neighbors.append(unregistered)
	var selected: Array = science._tom_nearest(observer, neighbors)
	t.equals(selected.size(), 4, "selection remains bounded to four neighbors")
	for i in 4:
		t.equals((selected[i] as Fish).id, "neighbor_%d" % (i + 1), "nearest ranking survives reversed input")
	t.equals(science._tom_nearest(observer, [null, observer, unregistered]).size(), 0, "self and unregistered fish are ignored")
	var tie := Fish.new()
	tie.id = "tie"
	tie.position = Vector3(-1, 0, 0)
	var nearest: Fish = fixtures.back()
	var tied: Array = science._tom_nearest(observer, [nearest, tie])
	t.check(tied[0] == nearest and tied[1] == tie, "equal-distance neighbors retain stable input order")
	for other in fixtures:
		other.free()
	observer.free()
	unregistered.free()
	tie.free()
	quit(t.finish())
