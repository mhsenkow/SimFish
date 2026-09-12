extends SceneTree

# Established-tank plant height (PlantEstablish) and per-individual colour
# morphs (FishMorphs).
#
# Both exist because a preset was describing something the renderer did not
# produce: "established" gave a cycled filter over 3-voxel stubs, and a
# guppy colony rendered thirty identical charcoal fish.

const P := preload("res://scripts/plant_establish.gd")
const M := preload("res://scripts/fish_morphs.gd")
const Cfg := preload("res://scripts/tank_config.gd")

# Vallisneria's real spec from world.gd: planted at 2-5, mature 14-22.
const VALLI_PLANTED_LO := 2
const VALLI_PLANTED_HI := 5
const VALLI_MATURE_LO := 14
const VALLI_MATURE_HI := 22


func _init() -> void:
	var t := TestSupport.Suite.new("growth_and_morphs")

	# --- fresh tanks are untouched ---------------------------------------
	for h in range(VALLI_PLANTED_LO, VALLI_PLANTED_HI + 1):
		t.equals(P.initial_height(h, 18, false), h,
			"a cycling tank still plants small (%d)" % h)

	# --- established tanks open grown in ---------------------------------
	var grown: int = P.initial_height(3, 18, true, P.ESTABLISHED_FRAC, 0.5)
	t.check(grown >= 10,
		"established valli reaches the background, got %d of 18" % grown)
	t.check(grown > VALLI_PLANTED_HI,
		"established is taller than the old literal (%d vs %d)"
		% [grown, VALLI_PLANTED_HI])

	# Never taller than the plant's own mature height - a plant rendered
	# above max_height has nothing left to grow and clips the surface.
	for roll in [0.0, 0.25, 0.5, 0.75, 1.0]:
		for mature in [3, 6, 14, 18, 22]:
			var v: int = P.initial_height(2, mature, true, 1.0, roll)
			t.check(v <= mature,
				"never exceeds mature height (%d <= %d at roll %.2f)"
				% [v, mature, roll])
			t.check(v >= 1, "always at least one voxel")

	# Never SHORTER than it used to be: this change can only add height.
	for roll in [0.0, 0.5, 1.0]:
		for req in range(1, 8):
			t.check(P.initial_height(req, 18, true, P.ESTABLISHED_FRAC, roll) >= req,
				"established never shrinks a plant (req %d, roll %.1f)" % [req, roll])
	# Even a scale of 0 cannot shrink one.
	t.check(P.initial_height(5, 18, true, 0.0, 0.0) >= 5,
		"scale 0 still respects the legacy height")

	# --- a stand must be ragged, not a hedge ------------------------------
	var heights: Dictionary = {}
	for i in 40:
		heights[P.initial_height(3, 18, true, P.ESTABLISHED_FRAC,
			float(i) / 39.0)] = true
	t.check(heights.size() >= 4,
		"a valli stand has varied heights, got %d distinct" % heights.size())

	# --- the jitter must not consume RNG ----------------------------------
	# Adding an _rng draw inside _spawn_plant shifts the stream and moves
	# every plant placed after it, silently reshuffling every preset's
	# hand-tuned layout. The roll is hashed from position instead.
	for xz in [Vector2(0.0, 0.0), Vector2(1.5, -2.0), Vector2(-3.25, 4.5)]:
		var a: float = P.roll_for_position(xz.x, xz.y)
		var b: float = P.roll_for_position(xz.x, xz.y)
		t.approx(a, b, "position roll is stable at %s" % str(xz))
		t.in_range(a, 0.0, 1.0, "position roll is 0..1 at %s" % str(xz))
	var rolls: Dictionary = {}
	for i in 40:
		rolls[snappedf(P.roll_for_position(float(i) * 0.7, float(i) * -1.3), 0.05)] = true
	t.check(rolls.size() >= 8,
		"neighbouring plants get unrelated rolls, got %d" % rolls.size())
	var w: String = _read("res://scripts/world.gd")
	t.check(w.contains("PlantEstablish.roll_for_position("),
		"world.gd hashes position rather than drawing from _rng")

	# --- carpet plants stay carpets ---------------------------------------
	# max 3-6. Establishing them must not turn a foreground carpet into a
	# hedge that hides everything behind it.
	for roll in [0.0, 0.5, 1.0]:
		var carpet: int = P.initial_height(2, 5, true, P.ESTABLISHED_FRAC, roll)
		t.check(carpet <= 5, "carpet stays low (%d)" % carpet)

	# --- reaching the surface ---------------------------------------------
	# Plant heights were fixed voxel counts while tanks are any size the
	# player picks. In the Night Lamp hex (11 units, 8.25 of water) valli's
	# 22-voxel ceiling is 7.04 units of blade - it finished growing 1.06
	# units short, so the canopy layover that bends ribbon blades over at
	# the waterline and runs them along it could never fire at all.
	var vox := 0.32
	var sub := 2.2
	var water := 10.45
	t.equals(P.surface_reach_voxels(sub, water, vox), 26,
		"the hex tank needs 26 voxels of blade to touch the surface")
	t.check(P.surface_reach_voxels(sub, water, vox) > 22,
		"which is more than valli's old hard-coded maximum - the bug")

	# Height must be derived from the tank, so it holds for any vessel.
	for th in [6.5, 9.0, 11.0, 14.0]:
		var s_y: float = th * 0.20
		var w_y: float = th * 0.95
		var h: int = P.surface_height(s_y, w_y, vox, 22, P.POOL_SURPLUS_VOXELS)
		var top: float = s_y + float(h) * vox
		t.check(top >= w_y,
			"valli reaches the surface in a %.1f tank (top %.2f vs %.2f)"
			% [th, top, w_y])
		# And carries enough surplus for the layover to have something to
		# lay along the surface.
		var surplus: int = h - P.surface_reach_voxels(s_y, w_y, vox)
		t.check(surplus >= P.POOL_SURPLUS_VOXELS - 1,
			"and enough surplus blade to pool (%d voxels)" % surplus)
		t.check(h <= P.MAX_PLANT_VOXELS,
			"without exploding the voxel count (%d)" % h)

	# A plant that only breaks the meniscus gets no surplus.
	var stem_h: int = P.surface_height(sub, water, vox, 18, 0)
	t.equals(stem_h, 26, "a stem plant reaches the surface and stops there")

	# A tiny tank must not STUNT a plant below its own genome.
	var tiny: int = P.surface_height(0.5, 1.5, vox, 22, 0)
	t.check(tiny >= 22, "a shallow tank does not shrink the species")
	# Degenerate spans must not divide by zero or return nonsense.
	t.check(P.surface_reach_voxels(5.0, 5.0, vox) >= 1, "zero span is survivable")
	t.check(P.surface_reach_voxels(5.0, 1.0, vox) >= 1, "inverted span is survivable")
	t.check(P.surface_reach_voxels(0.0, 10.0, 0.0) >= 1, "zero voxel size is survivable")

	# --- the surplus must match the layover length -------------------------
	# Two numbers that have to agree: the layover pins N voxels to the water
	# plane, and the surplus is how much blade exists to be pinned. Drift
	# either way and the blade tears or pokes above the water.
	var pl2: String = _read("res://scripts/plant.gd")
	t.check(pl2.contains("const CANOPY_LAY_RIBBON: int = %d" % P.POOL_SURPLUS_VOXELS),
		"pool surplus equals the ribbon layover count (%d)" % P.POOL_SURPLUS_VOXELS)
	t.check(pl2.contains("var surface_pooling: bool"),
		"plants carry a pooling flag")
	t.check(pl2.contains("if not surface_pooling:\n\t\tmax_height = current_height")
			or pl2.contains("if not surface_pooling:"),
		"entering the canopy no longer freezes a pooling plant's height")
	t.check(pl2.contains("elif surface_pooling and life_phase == LifePhase.CANOPY:"),
		"the layover re-applies as a pooling blade keeps growing")
	var w2: String = _read("res://scripts/world.gd")
	t.check(w2.contains('"surface_pooling": true'),
		"vallisneria is marked as a surface-pooling species")
	t.check(w2.contains("PlantEstablish.surface_height("),
		"world.gd derives surface heights from the tank")

	# --- morph palettes ----------------------------------------------------
	t.check(M.palette("reef").size() >= 8, "reef palette intact")
	t.check(M.palette("guppy").size() >= 8, "guppy palette present")
	t.check(M.palette("nonsense").size() == M.palette("reef").size(),
		"an unknown palette name falls back to reef, not empty")

	# The whole point: one species must produce many colours.
	var seen: Dictionary = {}
	for i in 60:
		var e: Array = M.pick("guppy", float(i) / 60.0)
		seen[str(e[0])] = true
	t.check(seen.size() >= 8,
		"a guppy colony shows many colours, got %d" % seen.size())

	# Index and entry must agree, or the reef clownfish special-case fires
	# on the wrong morph.
	for i in 50:
		var roll: float = float(i) / 50.0
		for name in ["reef", "guppy"]:
			var idx: int = M.index_for(name, roll)
			t.in_range(float(idx), 0.0, float(M.palette(name).size() - 1),
				"%s index in range at %.2f" % [name, roll])
			t.equals(M.entry(name, idx), M.pick(name, roll),
				"%s index and entry agree at %.2f" % [name, roll])
	# Out-of-range rolls must not crash or wrap to a surprising morph.
	for roll in [-5.0, 0.0, 1.0, 99.0]:
		t.check(M.pick("guppy", roll).size() == 2,
			"pick survives roll %.1f" % roll)

	# --- colour-only vs body-restyling ------------------------------------
	# A guppy morph is the same fish in a different colour. If it restyled
	# the body, half a guppy colony would render as disc-shaped reef fish.
	t.check(not M.restyles_body("guppy"), "guppy morphs are colour-only")
	t.check(M.restyles_body("reef"), "reef morphs still restyle the body")

	# --- the guppy species actually opts in --------------------------------
	var guppy: Dictionary = Cfg.SPECIES_LIBRARY["guppy"]["genome"]
	t.check(bool(guppy.get("mixed_morphs", false)), "guppy rolls morphs")
	t.equals(String(guppy.get("morph_palette", "")), "guppy",
		"guppy uses the guppy palette, not the reef one")
	# Its signature silhouette must survive the colour roll.
	t.equals(int(guppy.get("tail_shape", -1)), 1, "guppy keeps its fan tail")
	t.check(bool(guppy.get("is_livebearer", false)), "guppy is still a livebearer")

	# --- damped flower follow --------------------------------------------
	# _stabilize_flower_against_lean assigned the bloom's whole transform
	# from the live stem tip every frame, instantly. That anchor is the sum
	# of stem lean, canopy layover, gust tilt, circumnutation, brush bend
	# and a voxel re-lay on every growth step - individually gentle, but a
	# rigid bloom snapped onto their sum reproduces all of it at full
	# amplitude with zero lag. That is the "chaotic waving".
	var F := preload("res://scripts/flower_motion.gd")
	t.approx(F.follow_factor(0.0, F.FOLLOW_TAU), 0.0, "no time, no movement")
	t.check(F.follow_factor(1.0 / 60.0, F.FOLLOW_TAU) < 0.2,
		"one frame moves the bloom only a fraction of the way")
	t.check(F.follow_factor(1.0, F.FOLLOW_TAU) > 0.95,
		"a full second essentially arrives")
	t.check(F.follow_factor(0.016, F.ROT_TAU) > F.follow_factor(0.016, F.FOLLOW_TAU),
		"rotation settles faster than position, or the bloom shows a gap")

	# Frame-rate independence: the same elapsed time must produce the same
	# settle whether it arrives in one step or many, or the bloom damps
	# differently at 30 and 240 fps.
	var one_step: float = F.follow_factor(0.25, F.FOLLOW_TAU)
	var remaining: float = 1.0
	for i in 15:
		remaining *= (1.0 - F.follow_factor(0.25 / 15.0, F.FOLLOW_TAU))
	t.approx(1.0 - remaining, one_step,
		"damping is frame-rate independent", 0.02)

	# A step must always converge, never overshoot or diverge.
	var cur := Transform3D(Basis(), Vector3(5.0, 0.0, 0.0))
	var tgt := Transform3D(Basis(), Vector3.ZERO)
	var prev_d: float = cur.origin.length()
	for i in 200:
		cur = F.step(cur, tgt, 1.0 / 60.0)
		var d: float = cur.origin.length()
		t.check(d <= prev_d + 1e-6, "bloom converges, never overshoots")
		prev_d = d
	t.check(prev_d < 0.05, "bloom actually arrives (%.4f left)" % prev_d)

	# Creation and dt-less paths must land exactly, not ease in from origin.
	var snapped: Transform3D = F.step(
		Transform3D(Basis(), Vector3(9.0, 9.0, 9.0)), tgt, 0.016, true)
	t.approx(snapped.origin.length(), 0.0, "snap lands exactly on the tip")
	t.approx(F.step(Transform3D(Basis(), Vector3(9.0, 0.0, 0.0)), tgt, 0.0).origin.x,
		0.0, "a dt of zero snaps rather than freezing mid-air")

	# The wiring: the tick path must pass dt, or every call snaps and the
	# damping is dead code that still passes its own unit tests.
	var pl: String = _read("res://scripts/plant.gd")
	t.check(pl.contains("_stabilize_flower_against_lean(dt)"),
		"the per-tick path passes dt so the bloom actually damps")
	t.check(pl.contains("FlowerMotion.step("),
		"the bloom transform goes through the damped follow")

	quit(t.finish())


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt: String = f.get_as_text()
	f.close()
	return txt
