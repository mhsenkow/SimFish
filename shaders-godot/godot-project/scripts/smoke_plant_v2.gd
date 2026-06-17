# Headless smoke: spawn one plant per leaf_form, tick 60 sim-seconds, assert alive.
extends SceneTree

const FORMS: Array[String] = [
	"column", "paddle", "ribbon", "lance", "needle", "spade", "cordate",
	"pinnate", "starburst", "four_leaf", "fingered", "downy", "round", "lobed",
]

var _substrate: SubstrateGrid
var _plants: Array = []
var _elapsed: float = 0.0
const DURATION: float = 60.0


func _initialize() -> void:
	_substrate = SubstrateGrid.new()
	_substrate.init(4.0, 2.0, 1.0)
	for form in FORMS:
		var p := Plant.new()
		root.add_child(p)
		p.global_position = Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-1.0, 1.0))
		p.water_surface_y = 5.0
		p.init(2, PlantGenome.enrich({
			"leaf_form": form,
			"max_height": 12,
			"growth_rate": 0.22,
		}))
		_plants.append(p)
	print("[smoke_plant_v2] spawned %d plants" % _plants.size())


func _process(delta: float) -> bool:
	_elapsed += delta
	var dt: float = 0.1
	for p in _plants:
		if is_instance_valid(p):
			p.tick(dt, _substrate)
	if _elapsed >= DURATION:
		var total_biomass: int = 0
		for p in _plants:
			if is_instance_valid(p):
				total_biomass += p.biomass()
		if total_biomass <= 0:
			push_error("[smoke_plant_v2] FAIL: zero biomass after tick")
			quit(1)
			return false
		print("[smoke_plant_v2] OK biomass=%d" % total_biomass)
		quit(0)
		return false
	return true
