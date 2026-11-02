extends SceneTree

# CREATURE_MOTION_700 §M — exaggeration with restraint (#359–374).


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_motion_exaggeration")

	# #359: cap at 1.3 (music may lift to 1.4).
	t.check(FishExaggeration.CAP <= 1.3 + 1e-6, "hard cap ≤1.3 (#359)")
	var tiny: float = MotionLod.legibility_gain(0.01, 10.0, 2.0, 1.3)
	t.check(tiny <= 1.3 + 1e-4, "legibility_gain respects cap (#359)")

	# #367: realism anchors never gain.
	t.check(FishExaggeration.is_anchor("cruise_tail_amp"), "cruise tail is an anchor (#367)")
	t.check(is_equal_approx(
		FishExaggeration.gain("cruise_tail_amp", 0.01, 10.0), 1.0),
		"cruise tail gain is 1 (#367)")
	t.check(is_equal_approx(
		FishExaggeration.gain("swim_speed", 0.01, 10.0), 1.0),
		"swim speed gain is 1 (#367)")

	# #368: distance mix — macro 0, default ~0.15, wide ~0.30.
	t.approx(FishExaggeration.distance_mix(50.0), 0.0, "macro mix 0 (#368)", 0.01)
	t.in_range(FishExaggeration.distance_mix(22.0), 0.05, 0.2, "default mix ~15% (#368)")
	t.approx(FishExaggeration.distance_mix(4.0), 0.30, "wide mix 30% (#368)", 0.01)

	# #369: music lifts the effective gain ceiling.
	var quiet: float = FishExaggeration.gain("fin_erection", 0.01, 12.0, 0.0)
	var loud: float = FishExaggeration.gain("fin_erection", 0.01, 12.0, 1.0)
	t.check(loud + 1e-4 >= quiet, "dance can lift gain (#369)")

	# #360: C-start angle stays biological (ledger).
	var angle_row: Dictionary = {}
	for row in FishExaggeration.ledger():
		if String(row.get("channel", "")) == "c_start_angle":
			angle_row = row
			break
	t.check(not angle_row.is_empty(), "ledger has c_start_angle (#360/#374)")
	t.approx(float(angle_row.get("game", 0.0)), 1.0, "C-start angle not exaggerated (#360)", 0.01)

	# #361–#364 / #371–#373 helpers.
	t.approx(FishExaggeration.display_fin_mult(1.0), 1.2, "display fin +20% (#361)", 0.01)
	t.approx(FishExaggeration.display_hold_mult(1.0), 1.5, "display hold 1.5× (#361)", 0.01)
	t.approx(FishExaggeration.clamp_fin_scale(1.0, 1.0), 0.6, "clamp fins −40% (#363)", 0.05)
	t.check(FishExaggeration.clamp_darken(1.0, 1.0) > 0.1, "clamp darkens (#363)")
	t.approx(FishExaggeration.gulp_gape_mult(true), 1.3, "gulp gape +30% (#364)", 0.01)
	t.in_range(FishExaggeration.pre_action_hold_seconds(), 0.1, 0.3, "pre-hold 100–300 ms (#365)")
	t.check(FishExaggeration.tail_recoil_mult(1.8) > 1.1, "big-tail recoil (#371)")
	t.approx(FishExaggeration.hypoxia_opercula_mult(0.0), 1.5, "hypoxia opercula ×1.5 (#372)", 0.05)
	t.check(FishExaggeration.hypoxia_gape(0.1) > 0.2, "hypoxia mouth gape (#372)")
	t.check(FishExaggeration.sickness_list_mult(1.0) > 1.1, "sickness list (#373)")

	# #374: ledger covers every exaggerated channel.
	var channels: PackedStringArray = PackedStringArray()
	for row in FishExaggeration.ledger():
		t.has_keys(row, ["channel", "real", "game", "reason"], "ledger row shape (#374)")
		channels.append(String(row.get("channel", "")))
	t.check(channels.size() >= 10, "ledger has the exaggerated channels (#374)")

	# Living path: anticipation pre-hold + strike stretch stay finite.
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true
	var host: Node3D = load("res://scripts/motion_world_test_stub.gd").new()
	root.add_child(host)
	var sim: Node = load("res://scripts/motion_visibility_test_stub.gd").new()
	sim.creature_visible = true
	host.add_child(sim)
	var f := Fish.new()
	host.add_child(f)
	f.set_process(false)
	var g: Dictionary = cfg.SPECIES_LIBRARY["guppy"]["genome"].duplicate(true)
	f.id = "exag_smoke"
	f.init_genome(g)
	f.sim = sim
	f._spawn_settle_remaining = 0.0
	FishPhase2Pose.enabled = true
	f.burst_remaining = 0.4
	f._startle_remaining = 0.0
	f.set_meta("_ant_prev_burst", 0.0)
	FishAnticipation.tick(f, 0.016)
	t.check(float(f.get_meta("_ant_pre_hold", 0.0)) > 0.05, "pre-action hold armed (#365)")
	FishAnticipation.note_bite_intent(f)
	t.check(float(f.get_meta("_ant_strike_stretch", 0.0)) > 0.5, "strike stretch armed (#362)")
	f._spawn_adult_action_smear()
	t.check(int(f.get_meta("_adult_smear_live", 0)) <= 1, "adult smear at most one (#370)")

	f.queue_free()
	host.queue_free()
	await process_frame
	quit(t.finish())
