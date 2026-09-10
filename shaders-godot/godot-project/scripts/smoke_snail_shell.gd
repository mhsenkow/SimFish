extends SceneTree

# Pins the snail shell-condition contract.
#
# The tank already simulated KH and pH and nothing consumed them. A snail
# shell is aragonite sitting in that water: below ~KH 3, and worse below pH 7,
# it dissolves apex-first. This is the one care signal that reads on the
# animals themselves before you open a panel, so the numbers, the visuals and
# the one-way scar all need holding still.

const SnailScript := preload("res://scripts/snail.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	var host := Node3D.new()
	host.name = "SnailShellHost"
	root.add_child(host)

	# ---- Dissolution pressure curve -----------------------------------------
	var safe: float = SnailScript.shell_dissolution_pressure(6.0, 7.6)
	var soft: float = SnailScript.shell_dissolution_pressure(1.5, 7.4)
	var acid: float = SnailScript.shell_dissolution_pressure(5.0, 6.4)
	var both: float = SnailScript.shell_dissolution_pressure(0.8, 6.0)
	_assert(failed, is_equal_approx(safe, 0.0),
		"hard, alkaline water does not touch the shell (got %.3f)" % safe)
	_assert(failed, soft > 0.2, "soft water dissolves shell (got %.3f)" % soft)
	_assert(failed, acid > 0.2, "acid water dissolves shell (got %.3f)" % acid)
	_assert(failed, both > soft and both > acid,
		"soft AND acid compounds — the blackwater failure mode (%.2f vs %.2f/%.2f)"
			% [both, soft, acid])
	_assert(failed, both <= 1.0 and soft <= 1.0, "pressure is normalised")
	# Monotonic in both axes.
	var prev: float = -1.0
	for i in 10:
		var kh: float = 6.0 - float(i) * 0.6
		var p: float = SnailScript.shell_dissolution_pressure(kh, 7.4)
		_assert(failed, p >= prev - 0.0001, "pressure rises as KH falls")
		prev = p

	# ---- Thickness by shape --------------------------------------------------
	var trochus: float = SnailScript._default_shell_thickness("trochus")
	var ramshorn: float = SnailScript._default_shell_thickness("ramshorn")
	_assert(failed, trochus > ramshorn,
		"trochus builds heavier than ramshorn (%.2f vs %.2f)" % [trochus, ramshorn])
	_assert(failed, SnailScript._default_shell_thickness("unknown_shape") > 0.0,
		"unknown shapes still get a usable thickness")

	# A thin shell must erode faster than a thick one in the same water.
	var thin: Node3D = _make(host, "ramshorn")
	var thick: Node3D = _make(host, "trochus")
	var bad: Node = _fake_sim(1.0, 6.2)
	for i in 40:
		thin._tick_shell_condition(3.0, bad)
		thick._tick_shell_condition(3.0, bad)
	_assert(failed, thin.shell_condition < thick.shell_condition,
		"thin shells go first (%.3f vs %.3f)" % [thin.shell_condition, thick.shell_condition])
	_assert(failed, thin.shell_condition < 0.95, "bad water actually erodes")
	_assert(failed, thin.shell_condition >= 0.0, "condition never goes negative")

	# ---- Good water does not erode ------------------------------------------
	var healthy: Node3D = _make(host, "turbo")
	var good: Node = _fake_sim(6.0, 7.6)
	for i in 40:
		healthy._tick_shell_condition(3.0, good)
	_assert(failed, is_equal_approx(healthy.shell_condition, 1.0),
		"a pristine shell in good water stays pristine")

	# ---- Recovery is partial and the scar is permanent -----------------------
	var scarred: Node3D = _make(host, "turbo")
	for i in 60:
		scarred._tick_shell_condition(3.0, bad)
	var worst: float = scarred.shell_condition
	var scar: float = scarred._shell_scar
	_assert(failed, worst < 0.9 and scar > 0.1, "damage accumulated")
	for i in 400:
		scarred._tick_shell_condition(3.0, good)
	_assert(failed, scarred.shell_condition > worst,
		"fixing the water lets the shell re-deposit (%.3f -> %.3f)"
			% [worst, scarred.shell_condition])
	_assert(failed, scarred.shell_condition < 1.0,
		"but it never returns to pristine — neglect leaves a mark (%.3f)"
			% scarred.shell_condition)
	_assert(failed, is_equal_approx(scarred._shell_scar, scar),
		"the scar high-water mark does not heal")

	# ---- The carbonate loop closes -------------------------------------------
	# Shells are made of the water they sit in. A colony has to draw the buffer
	# down, or "too many snails" is a free lunch and nothing self-limits.
	var draw_sim: Node = _fake_sim(6.0, 7.6)
	var wc: WaterChemistry = draw_sim.get("water_chemistry")
	var kh0: float = wc.kh
	var gh0: float = wc.gh
	var colony: Array[Node3D] = []
	for i in 10:
		var s2: Node3D = _make(host, "apple")
		s2.shell_size = 1.3
		colony.append(s2)
	for i in 60:
		for s3 in colony:
			s3._tick_shell_condition(3.0, draw_sim)
	_assert(failed, wc.kh < kh0 and wc.gh < gh0,
		"a snail colony draws the buffer down (kh %.2f -> %.2f)" % [kh0, wc.kh])
	_assert(failed, wc.kh > 0.4 and wc.gh > 0.4,
		"the draw is floored, never negative")
	# A big-shelled snail must cost more than a small one.
	var big_sim: Node = _fake_sim(6.0, 7.6)
	var small_sim: Node = _fake_sim(6.0, 7.6)
	var big: Node3D = _make(host, "apple")
	big.shell_size = 1.5
	var small: Node3D = _make(host, "apple")
	small.shell_size = 0.7
	for i in 60:
		big._tick_shell_condition(3.0, big_sim)
		small._tick_shell_condition(3.0, small_sim)
	_assert(failed, (big_sim.get("water_chemistry") as WaterChemistry).kh
			< (small_sim.get("water_chemistry") as WaterChemistry).kh,
		"a bigger shell costs more carbonate")
	# draw_carbonate must be floored and monotonic.
	var wc2: WaterChemistry = WaterChemistry.new()
	wc2.kh = 1.0
	wc2.gh = 1.0
	wc2.draw_carbonate(99.0)
	_assert(failed, wc2.kh >= 0.5 and wc2.gh >= 0.5,
		"draw_carbonate floors at the minimum, it cannot go negative")

	# ---- Breeding gate -------------------------------------------------------
	_assert(failed, healthy.shell_breeding_ok(), "a sound snail can breed")
	var wrecked: Node3D = _make(host, "ramshorn")
	wrecked.shell_condition = 0.2
	_assert(failed, not wrecked.shell_breeding_ok(),
		"a badly eroded snail does not breed")

	# ---- Visuals: chalk the oldest whorls, and never touch shared materials --
	var vis: Node3D = _make(host, "trochus")
	var shared_mat: ShaderMaterial = VoxelMat.make_fauna(Color8(120, 90, 60))
	var voxels: Array = []
	for i in 8:
		var mi := MeshInstance3D.new()
		# Ascending size: the smallest boxes are the oldest whorls.
		var e: float = 0.03 + 0.02 * float(i)
		mi.mesh = VoxelMat.get_box(Vector3(e, e, e))
		mi.material_override = shared_mat
		vis.add_child(mi)
		voxels.append(mi)
	vis.register_shell_voxels(voxels)
	var before_shared: Color = shared_mat.get_shader_parameter("albedo")
	vis.shell_condition = 0.25
	vis._shell_visual_step = -1
	vis._apply_shell_visual()
	var after_shared: Color = shared_mat.get_shader_parameter("albedo")
	_assert(failed, before_shared.is_equal_approx(after_shared),
		"eroding one snail must NOT recolour the shared cached material")
	# The apex (smallest voxel) is hit; the aperture (largest) is untouched.
	var apex: MeshInstance3D = voxels[0]
	var lip: MeshInstance3D = voxels[7]
	_assert(failed, apex.material_override != shared_mat,
		"the eroded voxel took a private material copy")
	_assert(failed, lip.material_override == shared_mat,
		"an untouched voxel keeps the shared material (no needless copies)")
	_assert(failed, apex.scale.x < 1.0, "the worst-hit whorl pits inward")
	_assert(failed, lip.scale.is_equal_approx(Vector3.ONE),
		"new growth at the lip stays full size")
	# A pristine snail restyles back to no damage at all.
	vis.shell_condition = 1.0
	vis._apply_shell_visual()
	for v in voxels:
		_assert(failed, (v as MeshInstance3D).visible, "recovered shell is fully visible")
		_assert(failed, (v as MeshInstance3D).scale.is_equal_approx(Vector3.ONE),
			"recovered shell has no pitting")

	# ---- Save / load ---------------------------------------------------------
	var saver: Node3D = _make(host, "apple")
	saver.shell_condition = 0.42
	saver._shell_scar = 0.58
	var d: Dictionary = saver.to_save_dict()
	_assert(failed, d.has("shell_condition") and d.has("shell_scar")
			and d.has("shell_thickness"),
		"shell state is saved")
	var loader: Node3D = _make(host, "apple")
	loader.apply_save_dict(d)
	_assert(failed, is_equal_approx(loader.shell_condition, 0.42)
			and is_equal_approx(loader._shell_scar, 0.58),
		"shell state round-trips")

	# ---- Genome ---------------------------------------------------------------
	var g: Dictionary = saver.get_saved_genome()
	_assert(failed, g.has("shell_thickness"), "thickness is part of the genome")
	var child: Node3D = _make(host, "turbo")
	child.apply_genome_metadata({"shell_thickness": 0.83})
	_assert(failed, is_equal_approx(child.shell_thickness, 0.83)
			and child._shell_thickness_explicit,
		"an explicit thickness overrides the shape default")

	if failed.is_empty():
		print("[smoke] snail_shell OK")
		quit(0)
	else:
		for f in failed:
			push_error("[smoke] FAIL: %s" % f)
		print("[smoke] snail_shell FAILED (%d)" % failed.size())
		quit(1)


func _make(host: Node3D, shape: String) -> Node3D:
	var sn := Node3D.new()
	sn.set_script(SnailScript)
	sn.set("shell_shape", shape)
	host.add_child(sn)
	return sn


# Minimal stand-in for SimDriver: the shell tick only reads water_chemistry.
# WaterChemistry is a RefCounted, so it is constructed, not script-attached.
func _fake_sim(kh: float, ph: float) -> Node:
	var wc: WaterChemistry = WaterChemistry.new()
	wc.kh = kh
	wc.ph = ph
	var sim := Node.new()
	sim.set_script(load("res://scripts/snail_shell_sim_stub.gd"))
	sim.set("water_chemistry", wc)
	root.add_child(sim)
	return sim


func _assert(failed: Array[String], cond: bool, label: String) -> void:
	if not cond:
		failed.append(label)
