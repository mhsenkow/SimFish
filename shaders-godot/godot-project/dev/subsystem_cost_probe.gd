# Subsystem cost probe: where a frame's CPU goes, by knockout.
#
#   scripts/dev_run.sh --path shaders-godot/godot-project --headless \
#       --fixed-fps 60 res://dev/subsystem_cost_probe.tscn
#
# Boots main.tscn the way perf_workload_probe does (first-launch aesthetics,
# beginner_sandbox, established cycle), lets it settle, then measures the mean
# wall time of a frame with everything on, and again with each script group's
# _process/_physics_process switched off (one group at a time, restored after).
# Run it with --fixed-fps 60 so every frame advances exactly one physics tick
# and the frame wall time is the whole CPU cost of one 60 Hz frame.
#
# The difference "all on" minus "group off" is that group's per-frame cost.
# Self-contained on purpose: it runs unchanged against older checkouts so two
# releases can be compared like for like.
#
# Env: SUBSYS_SCENARIO (beginner_sandbox), SUBSYS_SETTLE (600 frames),
#      SUBSYS_FRAMES (180 per measurement), SUBSYS_OUT (report path),
#      SUBSYS_TOP (14 script groups by node count, plus the singletons),
#      SUBSYS_ONLY (comma list of script files to knock out, e.g. fish.gd).

extends Node

const ScenarioPickerScript = preload("res://scripts/scenario_picker.gd")
const AestheticsScript = preload("res://scripts/aesthetics_runtime.gd")

var _main: Node = null
var _settle: int = 600
var _frames: int = 180
var _out: String = "user://subsystem_cost.txt"
var _top: int = 14


static func _env(key: String, fallback: String) -> String:
	var v: String = OS.get_environment(key).strip_edges()
	return fallback if v.is_empty() else v


func _ready() -> void:
	var cfg: Node = get_node_or_null("/root/TankConfig")
	cfg.set("capture_mode", true)
	if cfg.has_method("reset_to_defaults"):
		cfg.call("reset_to_defaults")
	AestheticsScript.apply_first_launch_defaults(cfg)
	cfg.set("capture_mode", true)
	var id: String = _env("SUBSYS_SCENARIO", "beginner_sandbox")
	for sc in ScenarioPickerScript.SCENARIOS:
		if String(sc.get("id", "")) == id:
			ScenarioPickerScript.apply_scenario(sc, cfg)
	cfg.set("cycle_start_mode", "established")
	cfg.set("start_matured", true)
	_settle = _env("SUBSYS_SETTLE", "600").to_int()
	_frames = _env("SUBSYS_FRAMES", "180").to_int()
	_out = _env("SUBSYS_OUT", _out)
	_top = _env("SUBSYS_TOP", "14").to_int()
	process_priority = 1000
	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	_run.call_deferred()


func _keep_awake() -> void:
	if bool(_main.get("_focus_paused")) and _main.has_method("_on_focus_in"):
		_main.call("_on_focus_in")
	_main.set("_hud_idle_seconds", 0.0)


func _run() -> void:
	var waited: int = 0
	while true:
		await get_tree().process_frame
		_keep_awake()
		waited += 1
		var sim: Variant = _main.get("_sim")
		if sim is Node and (sim as Node).get("fish") != null and not ((sim as Node).fish as Array).is_empty():
			break
		if waited > 6000:
			push_error("[subsys] no fish after boot")
			get_tree().quit(1)
			return
	for _i in _settle:
		await get_tree().process_frame
		_keep_awake()
	if _env("SUBSYS_SIMONLY", "0") == "1":
		await _sim_stage_report()
		return
	var groups: Dictionary = _script_groups()
	var lines: PackedStringArray = []
	var base: float = await _mean_frame()
	lines.append("all_on  %.3f ms/frame" % base)
	var order: Array = groups.keys()
	order.sort_custom(func(a, b): return (groups[a] as Array).size() > (groups[b] as Array).size())
	var picked: Array = order.slice(0, _top)
	for key in order:
		if picked.has(key):
			continue
		if (groups[key] as Array).size() == 1:
			picked.append(key)
	var only: PackedStringArray = _env("SUBSYS_ONLY", "").split(",", false)
	if not only.is_empty():
		picked = picked.filter(func(k): return only.has(String(k)))
	var rows: Array = []
	for key in picked:
		# The tank keeps evolving, so the frame cost drifts over a run. Bracket
		# every knockout with its own before/after baseline.
		var b1: float = await _mean_frame()
		var nodes: Array = groups[key]
		var saved: Array = []
		for n: Variant in nodes:
			if not is_instance_valid(n):
				saved.append([false, false])
				continue
			saved.append([(n as Node).is_processing(), (n as Node).is_physics_processing()])
			(n as Node).set_process(false)
			(n as Node).set_physics_process(false)
		var off: float = await _mean_frame()
		for i in nodes.size():
			var v: Variant = nodes[i]
			if is_instance_valid(v):
				(v as Node).set_process(bool(saved[i][0]))
				(v as Node).set_physics_process(bool(saved[i][1]))
		var b2: float = await _mean_frame()
		var on_ms: float = (b1 + b2) * 0.5
		rows.append([on_ms - off, String(key), nodes.size(), off, on_ms])
	rows.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	for r in rows:
		lines.append("%7.3f ms  n=%-4d  on=%.3f off=%.3f  %s" % [float(r[0]), int(r[2]),
			float(r[4]), float(r[3]), String(r[1])])
	lines.append("all_on_end  %.3f ms/frame" % await _mean_frame())
	var text: String = "\n".join(lines)
	print(text)
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f != null:
		f.store_string(text + "\n")
		f.close()
	get_tree().quit(0)


# SUBSYS_SIMONLY=1 with SIM_PROFILE=1: SimDriver's own per-stage timers over
# 600 frames, as ms per rendered frame.
func _sim_stage_report() -> void:
	var sim: Node = _main.get("_sim") as Node
	var prof: Dictionary = sim.get("tick_profile")
	prof.clear()
	var n: int = 600
	var t0: int = Time.get_ticks_usec()
	for _i in n:
		await get_tree().process_frame
		_keep_awake()
	var wall: float = float(Time.get_ticks_usec() - t0) / 1000.0 / float(n)
	prof = sim.get("tick_profile")
	var keys: Array = prof.keys()
	keys.sort_custom(func(a, b): return (prof[a] as Vector2i).x > (prof[b] as Vector2i).x)
	var lines: PackedStringArray = ["frame %.3f ms  (sim stages, ms per frame)" % wall]
	var tot: float = 0.0
	for k in keys:
		var v: Vector2i = prof[k]
		var ms: float = float(v.x) / 1000.0 / float(n)
		tot += ms
		lines.append("%7.3f  calls=%-5d %s" % [ms, v.y, String(k)])
	lines.append("%7.3f  TOTAL" % tot)
	var text: String = "\n".join(lines)
	print(text)
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f != null:
		f.store_string(text + "\n")
		f.close()
	get_tree().quit(0)


func _mean_frame() -> float:
	for _w in 20:
		await get_tree().process_frame
		_keep_awake()
	var t0: int = Time.get_ticks_usec()
	for _i in _frames:
		await get_tree().process_frame
		_keep_awake()
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(_frames)


# Every node under main that runs per-frame code, keyed by script path.
func _script_groups() -> Dictionary:
	var out: Dictionary = {}
	var stack: Array = [_main]
	while not stack.is_empty():
		var n: Node = stack.pop_back() as Node
		for c in n.get_children():
			stack.append(c)
		var s: Script = n.get_script() as Script
		if s == null:
			continue
		if not (n.is_processing() or n.is_physics_processing()):
			continue
		var key: String = s.resource_path.get_file()
		if key == "":
			key = "<inline>"
		if not out.has(key):
			out[key] = []
		(out[key] as Array).append(n)
	return out
