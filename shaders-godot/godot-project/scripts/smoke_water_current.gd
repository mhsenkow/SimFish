extends SceneTree

# The tank's water as a fluid (WaterCurrent / TankFlowField, REAL_TANK top-10 #4)
# and the swimming maths that reads it (Hydrodynamics).
#
# The failure modes this guards are all quiet: a solver that compiles and
# returns finite numbers can still be compressible soup, push water through
# rock, or invent a current in a tank with nothing running. A fish that swims
# "relative to the water" can still be steering in the ground frame. Each
# check below is a physical property, not a snapshot of numbers.

const WC := preload("res://scripts/water_current.gd")
const FF := preload("res://scripts/tank_flow_field.gd")


func _init() -> void:
	var t := TestSupport.Suite.new("water_current")

	# --- still water stays still ------------------------------------------
	var still: WaterCurrent = WC.new()
	still.build(6.0, 3.0, 0.0, 5.0)
	for i in 20:
		still.step(0.1)
	t.approx(float(still.stats()["max"]), 0.0, "nothing running: no current", 1e-5)

	# --- a bubble plume drives a circulation cell -------------------------
	var f: WaterCurrent = WC.new()
	f.build(6.0, 3.0, 0.0, 5.0, func(p: Vector3) -> bool: return p.y < 0.6)
	var stone := Vector3(-3.5, 0.8, 0.0)
	f.add_plume(stone, 2.6, 0.35)
	for i in 120:
		f.step_coarse(0.2)
	var up: Vector3 = f.velocity_at(Vector3(stone.x, 3.0, stone.z))
	t.check(up.y > 0.2, "water rises over the stone (v.y %.3f)" % up.y)
	var top_far: Vector3 = f.velocity_at(Vector3(0.0, 4.6, 0.0))
	t.check(top_far.x > 0.02, "the plume spreads along the surface away from the stone (u %.3f)" % top_far.x)
	var down_n: int = 0
	for x in f.nx:
		var v: Vector3 = f.velocity_at(f.cell_center(x, int(f.ny / 2.0), int(f.nz / 2.0)))
		if v.y < -0.01:
			down_n += 1
	t.check(down_n > 0, "and returns downward elsewhere: a closed cell, not a fountain")
	t.in_range(f.residual_divergence(), 0.0, 0.15, "incompressible within tolerance")
	t.check(float(f.stats()["max"]) <= WC.MAX_SPEED + 1e-3, "speed stays within the ceiling")

	# --- solids carry no flow and the current goes round them --------------
	var rock: WaterCurrent = WC.new()
	rock.build(6.0, 3.0, 0.0, 5.0, func(p: Vector3) -> bool:
		return p.y < 0.6 or (absf(p.x) < 0.9 and p.y < 3.0 and absf(p.z) < 1.6))
	rock.add_filter(Vector3(-5.0, 4.2, 0.0), Vector3(1, 0, 0), 2.0,
		Vector3(5.0, 1.2, 0.0), 0.6, 2.0)
	for i in 100:
		rock.step_coarse(0.2)
	var inside: Vector3 = rock.velocity_at(Vector3(0.0, 1.5, 0.0))
	var snap: Array = rock.snapshot()
	var solid_max: float = 0.0
	for z in rock.nz:
		for y in rock.ny:
			for x in rock.nx:
				if rock.is_solid_cell(x, y, z):
					var i: int = x + rock.nx * (y + rock.ny * z)
					solid_max = maxf(solid_max, absf(float(snap[0][i]))
						+ absf(float(snap[1][i])) + absf(float(snap[2][i])))
	t.approx(solid_max, 0.0, "no velocity inside solid cells", 1e-5)
	t.check(inside.length() < 0.3, "the lee of the rock is calmer than open water")
	var jet: Vector3 = rock.velocity_at(Vector3(-4.0, 4.2, 0.0))
	t.check(jet.x > 0.3, "the filter return pushes along its outlet (u %.3f)" % jet.x)

	# --- plant beds slow the water ----------------------------------------
	var open_f: WaterCurrent = WC.new()
	var bed_f: WaterCurrent = WC.new()
	for g in [open_f, bed_f]:
		(g as WaterCurrent).build(6.0, 3.0, 0.0, 5.0)
		(g as WaterCurrent).add_filter(Vector3(-5.0, 2.5, 0.0), Vector3(1, 0, 0), 2.0,
			Vector3(5.0, 2.5, 0.0), 0.6, 2.0)
	var por := PackedFloat32Array()
	por.resize(bed_f.cell_count())
	por.fill(0.0)
	for z in bed_f.nz:
		for y in bed_f.ny:
			for x in bed_f.nx:
				if absf(bed_f.cell_center(x, y, z).x) < 1.5:
					por[x + bed_f.nx * (y + bed_f.ny * z)] = 1.0
	bed_f.set_porosity(por)
	for i in 80:
		open_f.step_coarse(0.2)
		bed_f.step_coarse(0.2)
	var probe := Vector3(0.0, 2.5, 0.0)
	t.check(bed_f.velocity_at(probe).length() < open_f.velocity_at(probe).length() * 0.8,
		"a plant bed slows the current through it")

	# --- the threaded adapter ---------------------------------------------
	var ff: TankFlowField = FF.new()
	ff.setup(6.0, 3.0, 0.0, 5.0, func(p: Vector3) -> bool: return p.y < 0.6)
	ff.set_sources([{"kind": "plume", "pos": stone, "buoyancy": 2.6, "radius": 0.35}])
	ff.prewarm(10.0, 0.25)
	var before: int = ff.snapshot_serial()
	for i in 6:
		ff.tick(0.1)
		OS.delay_msec(15)
	ff.tick(0.1)
	t.check(ff.snapshot_serial() >= before, "ticking publishes snapshots")
	t.check(ff.sample(Vector3(stone.x, 3.0, stone.z)).y > 0.1, "the adapter samples the solved plume")
	var tex: ImageTexture3D = ff.texture()
	var dims: Vector3i = ff.grid_dims()
	t.check(tex != null and tex.get_width() == dims.x and tex.get_depth() == dims.z,
		"the field uploads as a 3D texture of the grid's size")
	ff.set_threaded(false)

	# --- a wake stirs, it does not propel the tank --------------------------
	var wk: TankFlowField = FF.new()
	wk.setup(6.0, 3.0, 0.0, 5.0)
	wk.set_threaded(false)
	for i in 40:
		wk.deposit_wake(Vector3(0.0, 2.5, 0.0), Vector3(1.0, 0.0, 0.0), 0.3)
	var net := Vector3.ZERO
	for i in wk._imp_u.size():
		net += Vector3(wk._imp_u[i], wk._imp_v[i], wk._imp_w[i])
	t.approx(net.length(), 0.0, "a steady swimmer's wake carries no net momentum", 1e-4)

	# --- swimming relative to the water ------------------------------------
	var g := Vector3(0.5, 0.0, 0.0)
	t.check(Hydrodynamics.water_relative_target(g, Vector3(0.005, 0, 0), 1.0) == g,
		"still water: the swim target is the ground target")
	var hold: Vector3 = Hydrodynamics.water_relative_target(Vector3.ZERO, Vector3(0.3, 0, 0), 1.0)
	t.check(hold.x < -0.25, "holding station in a current means swimming into it")
	var swept: Vector3 = Hydrodynamics.water_relative_target(Vector3.ZERO, Vector3(5.0, 0, 0), 0.4)
	t.check(swept.length() <= 0.4 * Hydrodynamics.STATION_SPEED_SHARE + 1e-4,
		"a current faster than the fish can swim wins: it is carried")
	t.check(Hydrodynamics.carry_share(2.0, false) > Hydrodynamics.carry_share(0.05, false),
		"the bed's boundary layer carries less than open water")
	t.check(Hydrodynamics.carry_share(0.05, true) < 0.2, "a fish resting on the bed is not swept off it")
	t.check(Hydrodynamics.shelter_steer(0.05, 0.05, 0.05, 0.05, 0.05, 1.0) == Vector3.ZERO,
		"no shelter-seeking when the current is easy")
	var sh: Vector3 = Hydrodynamics.shelter_steer(0.6, 0.9, 0.2, 0.6, 0.6, 1.0)
	t.check(sh.x < 0.0, "shelter-seeking heads for the calmer side")

	# --- shaders that read the field ----------------------------------------
	var inc: String = FileAccess.get_file_as_string("res://shaders/flow_field.gdshaderinc")
	t.check(inc.contains("global uniform sampler3D iaq_flow_tex"), "the field is a global sampler3D")
	for path in ["res://shaders/foliage_mm.gdshader", "res://shaders/foliage.gdshader",
			"res://shaders/flow_particles.gdshader", "res://shaders/flow_bubbles.gdshader",
			"res://shaders/water.gdshader"]:
		t.check(FileAccess.get_file_as_string(path).contains("flow_field.gdshaderinc"),
			"%s reads the shared current" % path.get_file())
	t.check(FileAccess.get_file_as_string("res://project.godot").contains("iaq_flow_tex"),
		"iaq_flow_tex is registered in project.godot")

	quit(t.finish())
