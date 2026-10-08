# Actual Fish movement and mesh animation in the Library's isolated preview scene.
# Run via scripts/dev_run.sh. SWIMMING_CAPTURE_OUT chooses the PNG sequence directory.
extends Node

func _ready() -> void:
	_capture.call_deferred()

func _capture() -> void:
	var cfg: Node = get_node("/root/TankConfig")
	cfg.capture_mode = true
	cfg.reset_to_defaults()
	cfg.music_enabled = false
	cfg.music_sync_fish = false
	var library: PanelContainer = load("res://scripts/library_panel.gd").new()
	add_child(library)
	library.set_process(false)
	library.call("_resume_preview_rendering")
	var vp: SubViewport = library.get("_preview_viewport")
	vp.size = Vector2i(768, 512)
	var pivot: Node3D = library.get("_preview_pivot")
	pivot.rotation = Vector3.ZERO
	var camera: Camera3D = library.get("_preview_cam")
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.2
	var out: String = OS.get_environment("SWIMMING_CAPTURE_OUT")
	if out.is_empty():
		out = "user://swimming_capture"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var genome: Dictionary = cfg.SPECIES_LIBRARY["guppy"]["genome"].duplicate(true)
	genome["sex"] = 0
	genome["mixed_morphs"] = false
	library.call("_load_preview_creature", genome, "fish")
	var fish: Fish = library.get("_preview_creature")
	var motion_world: Node3D = load("res://scripts/motion_world_test_stub.gd").new()
	pivot.add_child(motion_world)
	var sim: Node = load("res://scripts/motion_visibility_test_stub.gd").new()
	sim.substrate_top_y = -1.0
	motion_world.add_child(sim)
	fish.sim = sim
	fish.heading = Vector3.FORWARD
	fish._last_yaw = 0.0
	fish._hover_depth = 0.0
	fish.home_y = 0.0
	fish._spawn_settle_remaining = 0.0
	fish._wag_freq_jitter = 1.0
	fish._motor_phase = 0.3
	fish._swim_phase = 0.3
	fish.hunger = 0.8 # preempt decorative bouts for a repeatable manoeuvre
	fish.current_mode = Fish.Mode.FLEE
	var trace := PackedStringArray(["time,speed,yaw,bank,target_x,target_z"])
	for i in 240:
		var time: float = float(i) / 30.0
		var yaw: float = sin(time * 0.8) * 1.2
		var pace: float = 0.48 if time < 5.0 else 0.12
		fish.target_velocity = Vector3(sin(yaw), 0.0, -cos(yaw)) * pace
		fish._motion_substep(1.0 / 30.0)
		trace.append("%.4f,%.4f,%.4f,%.4f,%.4f,%.4f" % [time, fish.speed, atan2(fish.heading.x, -fish.heading.z), fish._bank, fish.target_velocity.x, fish.target_velocity.z])
		camera.position = fish.position + Vector3(1.6, 0.8, -2.2)
		camera.look_at(fish.position, Vector3.UP)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(out.path_join("frame_%04d.png" % i))
	var trace_file := FileAccess.open(out.path_join("motion.csv"), FileAccess.WRITE)
	trace_file.store_string("\n".join(trace))
	trace_file.close()
	print("[swimming_capture] 240 frames at 30 sim fps -> ", ProjectSettings.globalize_path(out))
	library.queue_free()
	await get_tree().process_frame
	get_tree().quit()
