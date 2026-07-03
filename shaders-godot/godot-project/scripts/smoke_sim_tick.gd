extends SceneTree

# Headless multi-tick sim with brain pool + felt-self (main + worker threads).


func _initialize() -> void:
	await process_frame
	var sim: SimDriver = SimDriver.new()
	root.add_child(sim)
	for i in 12:
		var f: Fish = Fish.new()
		root.add_child(f)
		f.id = "sim-tick-%d" % i
		f.fish_name = "TickSmoke" if i == 0 else ""
		f.familiarity = 0.3 + float(i) * 0.04
		f.personality = {"boldness": 0.5, "curiosity": 0.5, "calm": 0.5, "sociability": 0.5}
		f.position = Vector3(randf_range(-4.0, 4.0), randf_range(2.0, 5.0), randf_range(-2.0, 2.0))
		f.maturity = Fish.MATURITY_ADULT
		sim.register_fish(f)
	for _w in 3:
		sim._tick(SimDriver.SIM_DT)
	for step in 80:
		sim._tick(SimDriver.SIM_DT)
		if step % 4 == 0:
			await process_frame
	print("[smoke_sim_tick] OK steps=80 fish=12")
	quit(0)
