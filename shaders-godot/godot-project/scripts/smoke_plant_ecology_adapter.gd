extends SceneTree

const Adapter = preload("res://scripts/plant_ecology_adapter.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed: Array[String] = []
	var grid := SubstrateGrid.new()
	root.add_child(grid)
	grid.init(3.0, 3.0, 1.0)
	var ramp: Array = [
		Color8(20, 60, 30), Color8(40, 95, 50), Color8(60, 130, 70),
		Color8(90, 170, 95), Color8(140, 210, 130),
	]
	var hosts: Array[Node] = []
	var lily := LilyPad.new()
	root.add_child(lily)
	lily.init_at(Vector3.ZERO, -1.0)
	hosts.append(lily)
	var cattail := CattailPlant.new()
	root.add_child(cattail)
	cattail.init_at(Vector3.ZERO, Color.GREEN, Color.BROWN, Color.GREEN)
	hosts.append(cattail)
	var nautilus := NautilusPlant.new()
	root.add_child(nautilus)
	nautilus.init_at(Vector3.ZERO, ramp)
	hosts.append(nautilus)
	var moss := FractalMoss.new()
	root.add_child(moss)
	moss.init_at(Vector3.ZERO, ramp)
	hosts.append(moss)

	grid.add_at(Vector3.ZERO, 2.0)
	var nutrient_before: float = grid.get_at(Vector3.ZERO)
	for host in hosts:
		var adapter = Adapter.new(host)
		_assert(failed, adapter.biomass() > 0.0,
			"%s reports biomass" % host.get_class())
		_assert(failed, adapter.nutrient_demand() > 0.0,
			"%s reports nutrient demand" % host.get_class())
		adapter.tick(2.1, grid)
		_assert(failed, host.has_method("ecology_graze"),
			"%s exposes grazing" % host.get_class())
	_assert(failed, grid.get_at(Vector3.ZERO) < nutrient_before,
		"adapter ecology consumes substrate nutrients")
	var death_adapter = Adapter.new(moss)
	var mulm_before: float = grid.get_mulm_at(Vector3.ZERO)
	death_adapter.die(grid)
	_assert(failed, grid.get_mulm_at(Vector3.ZERO) > mulm_before,
		"adapter death deposits bounded litter")

	if failed.is_empty():
		print("[smoke_plant_ecology_adapter] PASS")
		quit(0)
	else:
		for msg in failed:
			push_error("[smoke_plant_ecology_adapter] " + msg)
		quit(1)


func _assert(failed: Array[String], condition: bool, label: String) -> void:
	if not condition:
		failed.append(label)
