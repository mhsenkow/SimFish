# Headless smoke: spawn one floater per morph, tick 60 sim-seconds, assert alive.
extends SceneTree

const MORPHS: Array[String] = [
	"duckweed", "frogbit", "salvinia", "water_lettuce", "red_root",
	"azolla", "water_hyacinth", "water_spangle",
]

const DURATION: float = 60.0
const WATER_Y: float = 5.0


func _initialize() -> void:
	var floaters: Array = []
	for morph in MORPHS:
		var fp := FloatingPlant.new()
		root.add_child(fp)
		fp.position = Vector3(randf_range(-2.0, 2.0), WATER_Y - 0.05, randf_range(-1.0, 1.0))
		fp.init_genome(FloaterGenome.enrich({
			"morph": morph,
			"leaf_size": 0.28,
			"leaf_count": 4,
			"spread_rate": 1.1,
		}))
		floaters.append(fp)
	print("[smoke_floaters_v2] spawned %d floaters" % floaters.size())
	var elapsed: float = 0.0
	var dt: float = 0.1
	while elapsed < DURATION:
		for fp in floaters:
			if is_instance_valid(fp):
				fp.tick(dt, null, null)
		elapsed += dt
	var live: int = 0
	var total_biomass: float = 0.0
	for fp in floaters:
		if is_instance_valid(fp) and not fp.should_remove():
			live += 1
			total_biomass += fp.biomass()
	if live <= 0 or total_biomass <= 0.0:
		push_error("[smoke_floaters_v2] FAIL: no live floaters after tick")
		quit(1)
		return
	print("[smoke_floaters_v2] OK live=%d biomass=%.2f" % [live, total_biomass])
	quit(0)
