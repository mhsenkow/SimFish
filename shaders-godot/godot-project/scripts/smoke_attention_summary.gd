extends SceneTree

const Soul = preload("res://scripts/mind_soul_pass3.gd")

func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_attention_summary")
	var sim := SimDriver.new()
	for focus in ["food", "food", "rest", "rest", "novelty", ""]:
		var fish := Fish.new()
		fish.attention_focus = focus
		sim.fish.append(fish)
	sim._rebuild_attention_summary()
	t.equals(sim.attention_theme_for(sim.fish[0]), "food", "equal counts follow original roster order")
	var labels: Array[String] = ["", "food", "rest", "novelty", "safety"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xA77E
	for change in 120:
		var fish: Fish = sim.fish[rng.randi_range(0, sim.fish.size() - 1)]
		fish.attention_focus = labels[rng.randi_range(0, labels.size() - 1)]
		t.equals(sim.attention_theme_for(fish), _reference(sim.fish),
			"incremental attention census agrees with live roster after change %d" % change)
		sim._refresh_fish_attention(fish)
	var fresh := Fish.new()
	fresh.attention_focus = "food"
	sim.fish.append(fresh)
	sim._attention_summary_ready = false
	t.equals(sim.attention_theme_for(fresh), _reference(sim.fish), "new residents enter the attention census")
	var state: Dictionary = {"tank_theme": "previous moment"}
	for fish: Fish in sim.fish:
		fish.attention_focus = ""
	sim._rebuild_attention_summary()
	Soul._tick_tank_theme(fresh, state, sim)
	t.equals(state.tank_theme, "previous moment", "quiet tanks retain the prior theme")
	sim.fish[0].free()
	sim._rebuild_attention_summary()
	t.equals(sim.attention_theme_for(fresh), _reference(sim.fish), "freed residents do not enter the census")
	for fish in sim.fish:
		if is_instance_valid(fish):
			fish.free()
	sim.free()
	quit(t.finish())


func _reference(fish: Array) -> String:
	var counts: Dictionary = {}
	for f in fish:
		if is_instance_valid(f) and f.attention_focus != "":
			counts[f.attention_focus] = int(counts.get(f.attention_focus, 0)) + 1
	var top: String = ""
	var top_n: int = 1
	for focus in counts:
		if int(counts[focus]) > top_n:
			top_n = counts[focus]
			top = focus
	return top
