extends SceneTree
const FaunaVoxelBuilder = preload("res://scripts/fauna_voxel_builder.gd")

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_lifelike_motion_development")
	var phase: float = 0.3
	for i in 100:
		phase = Hydrodynamics.advance_phase(phase, 7.2, 0.01)
	t.approx(phase, Hydrodynamics.advance_phase(0.3, 7.2, 1.0), "oscillator is independent of time partition")
	t.in_range(Hydrodynamics.advance_phase(0.3, 18.0, 10000.0), 0.0, TAU, "long sessions keep phase bounded")
	t.approx(Hydrodynamics.advance_phase(0.3, 7.2, -1.0), 0.3, "negative time cannot reverse motion")
	t.check(Hydrodynamics.tailbeat_rate(1.0, 2.0, 2.5, 5.5) < Hydrodynamics.tailbeat_rate(1.0, 0.5, 2.5, 5.5), "larger bodies use fewer strokes at equal speed")
	var effort: Dictionary = {}
	Hydrodynamics.fin_effort_into(0.0, 0.0, 2.0, Vector3.ZERO, Vector3.FORWARD, effort)
	var rest: float = effort["tail_amp"]
	Hydrodynamics.fin_effort_into(1.0, 1.0, 2.0, Vector3.ZERO, Vector3.FORWARD, effort)
	var cruising: float = effort["tail_amp"]
	Hydrodynamics.fin_effort_into(1.0, 1.0, 2.0, Vector3.FORWARD * 0.15, Vector3.FORWARD, effort)
	t.check(rest < cruising and effort["tail_amp"] < cruising, "resting and current-carried fish use less tail effort")
	t.equals(effort.size(), 7, "reused effort dictionary does not accumulate entries")

	var egg := FishEgg.new()
	root.add_child(egg)
	egg.init({"species": "danio", "base_color": Color.CORAL})
	t.equals(egg.get("_wobble_pivot").get_child_count(), 1, "one egg represents one fry")
	t.approx(egg.incubation_s, 24.0, "danio uses its development profile")
	var normal: float = FishEgg.development_rate(0.55, 0.8)
	var hypoxic: float = FishEgg.development_rate(0.55, 0.1)
	t.check(hypoxic < normal, "low oxygen slows development")
	egg.tick(12.0, normal)
	t.approx(egg.development_fraction(), 0.5, "half incubation has half development")
	var saved: Dictionary = egg.to_save_dict()
	var restored := FishEgg.new()
	root.add_child(restored)
	restored.apply_save_dict(saved)
	t.check(saved["genome"]["base_color"] is Array, "loading does not mutate save input")
	t.approx(restored.development_fraction(), egg.development_fraction(), "new save preserves development")
	t.check(not restored.tick(-5.0), "negative delta cannot hatch prematurely")
	t.check(restored.tick(12.0), "saved brood hatches on its remaining deadline")
	var legacy := FishEgg.new()
	root.add_child(legacy)
	legacy.apply_save_dict({"species": "angelfish", "genome": {"species": "angelfish"}, "age": 29.0})
	t.approx(legacy.incubation_s, 30.0, "old broods retain old deadline")
	t.check(legacy.tick(1.0), "old brood retains age-based progress")
	var fish := Fish.new()
	root.add_child(fish)
	fish.set_process(false)
	fish.maturity = Fish.MATURITY_ADULT
	fish.hunger = 0.2
	fish.energy = 0.9
	fish.stress = 0.1
	t.equals(fish.breeding_condition_reason(1.0), "", "healthy adult satisfies real courtship gates")
	fish.hunger = 0.5
	t.equals(fish.breeding_condition_reason(1.0), "Needs food", "hunger boundary explains actual blocker")
	fish.hunger = 0.2
	fish.energy = 0.65
	t.equals(fish.breeding_condition_reason(1.0), "Needs rest", "energy boundary explains actual blocker")
	fish.energy = 0.9
	fish.stress = 0.4
	t.equals(fish.breeding_condition_reason(1.0), "Needs calmer conditions", "stress boundary explains actual blocker")
	fish.init_genome({"species": "guppy", "sex": 0})
	fish.set("_color_maturity", 0.5)
	fish.call("_apply_maturity_color")
	var membranes: int = 0
	for handle in fish.get("_cached_meshes"):
		var original: Color = FaunaVoxelBuilder.handle_orig_color(handle)
		if original.a < 0.98:
			membranes += 1
			var colors: PackedColorArray = handle.batch.get("_colors")
			t.approx(colors[handle.index].a, original.a, "juvenile wash preserves membrane tissue density")
	t.check(membranes > 0, "fish includes thin membrane geometry")
	var fan := Fish.new()
	root.add_child(fan)
	fan.set_process(false)
	fan.init_genome({"tail_shape": 1, "fin_length_factor": 2.4, "finnage": 1.8})
	var fan_handles: Array = []
	for handle in fan.get("_cached_meshes"):
		if handle.batch.mmi.get_parent() == fan.get("_tail_pivot"):
			fan_handles.append(handle)
	t.check(fan_handles.size() <= 10, "elaborate fan uses a bounded membrane instead of ray connectors and veil plates")
	var membrane_strips: int = 0
	for handle in fan_handles:
		if handle.local_pos.z > fan.adult_voxel_scale * 0.5 and is_zero_approx(handle.local_pos.y):
			membrane_strips += 1
	t.equals(membrane_strips, 6, "fan keeps six continuous widening membrane strips")
	fan.free()
	fish.free()
	egg.free()
	restored.free()
	legacy.free()
	quit(t.finish())
