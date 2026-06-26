# Headless smoke: spawn one plant per leaf_form, tick 60 sim-seconds, assert alive.
extends SceneTree

const FORMS: Array[String] = [
	"column", "paddle", "ribbon", "lance", "needle", "spade", "cordate",
	"pinnate", "starburst", "four_leaf", "fingered", "downy", "round", "lobed",
]

const DURATION: float = 60.0
const TICK_DT: float = 0.1


func _initialize() -> void:
	await process_frame
	var substrate := SubstrateGrid.new()
	substrate.init(4.0, 2.0, 1.0)
	var plants: Array = []
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
		plants.append(p)
	print("[smoke_plant_v2] spawned %d plants" % plants.size())

	var tick_count: int = int(DURATION / TICK_DT)
	for _i in tick_count:
		await process_frame
		for p in plants:
			if is_instance_valid(p):
				p.tick(TICK_DT, substrate)

	var total_biomass: int = 0
	for p in plants:
		if is_instance_valid(p):
			total_biomass += p.biomass()
	if total_biomass <= 0:
		push_error("[smoke_plant_v2] FAIL: zero biomass after tick")
		quit(1)
		return
	print("[smoke_plant_v2] OK biomass=%d" % total_biomass)
	quit(0)
