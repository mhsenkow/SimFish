extends SceneTree

# FISH_ALIVE foundations smoke — habit kit, posture, fear arc, lateral,
# fin nicks, home loiter, miracle budget, wiring presence.


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	# Habit kit (#761)
	var school: Dictionary = FishAlive.habit_kit("school")
	var shuffle: Dictionary = FishAlive.habit_kit("shuffle")
	_assert(failed, float(school.get("home_radius", 0)) > 0.0, "school kit")
	_assert(failed, float(shuffle.get("night_active", 0)) > float(school.get("night_active", 0)),
		"shuffle more nocturnal than school")

	# Posture (#41)
	var bold := Fish.new()
	bold.personality = {"boldness": 0.95, "calm": 0.5, "sociability": 0.5}
	var timid := Fish.new()
	timid.personality = {"boldness": 0.05, "calm": 0.5, "sociability": 0.5}
	_assert(failed, FishAlive.posture_y_offset(bold) > FishAlive.posture_y_offset(timid),
		"bold hangs higher than timid")
	_assert(failed, FishAlive.posture_sep_mult(timid) > FishAlive.posture_sep_mult(bold),
		"timid wants more space")

	# Home loiter (#481)
	var loaf := Fish.new()
	loaf.personality = {"calm": 0.9}
	loaf.hunger = 0.1
	loaf.stress = 0.1
	loaf.spooked = 0.0
	loaf.current_mode = Fish.Mode.CRUISE
	_assert(failed, FishAlive.home_loiter_mult(loaf) > 1.0, "calm sated loiter boost")
	_assert(failed, FishAlive.home_soft_attract(loaf, 0.5, 3.0) > 0.0, "soft attract inside home")
	loaf.hunger = 0.9
	_assert(failed, FishAlive.home_soft_attract(loaf, 0.5, 3.0) <= 0.0, "hungry skips soft attract")

	# Fear arc (#521)
	var scared := Fish.new()
	scared.personality = {"boldness": 0.4}
	FishAlive.begin_fear_freeze(scared, 0.1)
	_assert(failed, int(scared._fear_phase) == FishAlive.FEAR_FREEZE, "freeze phase")
	scared._fear_phase_t = 0.0
	FishAlive.tick_fear_arc(scared, 0.05, false)
	_assert(failed, int(scared._fear_phase) == FishAlive.FEAR_FLEE, "freeze→flee")
	scared.stress = 0.8
	FishAlive.tick_fear_arc(scared, 0.05, true)
	_assert(failed, int(scared._fear_phase) == FishAlive.FEAR_HIDE, "flee→hide in cover")

	# Miracle budget (#961/#999)
	var st: Dictionary = {}
	_assert(failed, FishAlive.miracle_allowed(st), "miracle allowed initially")
	FishAlive.note_miracle(st)
	FishAlive.note_miracle(st)
	_assert(failed, not FishAlive.miracle_allowed(st), "miracle budget exhausted")

	# Velocity floor (#1)
	var idle := Fish.new()
	idle.max_speed = 1.8
	idle.swim_pattern = "cruise"
	idle.current_mode = Fish.Mode.CRUISE
	idle._asleep = false
	idle.motion_freeze_t = 0.0
	_assert(failed, FishAlive.velocity_floor(idle, 0.0) > 0.0, "never-zero floor")

	# Micro idle advances phase (#121)
	idle._breath_load = 1.2
	idle._breath_phase = 0.0
	var y1: float = FishAlive.micro_idle_y(idle, 0.05)
	var y2: float = FishAlive.micro_idle_y(idle, 0.05)
	_assert(failed, float(idle._breath_phase) > 0.0, "breath phase advances")
	_assert(failed, is_finite(y1) and is_finite(y2), "breath bob finite")

	# Wiring presence
	var fish_src: String = FileAccess.get_file_as_string("res://scripts/fish.gd")
	_assert(failed, fish_src.contains("FishAlive.apply_habit_kit"), "habit kit wired")
	_assert(failed, fish_src.contains("FishAlive.lateral_line_flinch"), "lateral wired")
	_assert(failed, fish_src.contains("FishAlive.tick_fear_arc"), "fear arc wired")
	_assert(failed, fish_src.contains("FishAlive.apply_fin_nicks_visual"), "fin nicks wired")
	_assert(failed, fish_src.contains("FishAlive.home_soft_attract"), "home loiter wired")
	_assert(failed, fish_src.contains("FishAlive.micro_idle_y"), "micro idle wired")
	_assert(failed, fish_src.contains("FishAlive.world_answer"), "world answer wired")
	_assert(failed, fish_src.contains("FishAlive.posture_y_offset"), "posture wired")

	bold.free()
	timid.free()
	loaf.free()
	scared.free()
	idle.free()

	if failed.is_empty():
		print("SMOKE_FISH_ALIVE_OK")
		quit(0)
	else:
		for f in failed:
			push_error(f)
		print("SMOKE_FISH_ALIVE_FAIL count=%d" % failed.size())
		quit(1)


func _assert(failed: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		failed.append(msg)
