# Perf workload probe (HOLISTIC #013).
#
# Boots main.tscn for default / dense / mature / interaction-heavy workloads,
# samples frame times via PerfGovernor, and writes p50/p95/p99 + hardware /
# cap / tier / draw calls / entities / spike report.
#
# Env:
#   PERF_PROBE_OUT            output dir (absolute)
#   PERF_PROBE_WORKLOADS      comma list (default,dense,mature,interaction)
#   PERF_PROBE_SAMPLE_S       seconds to sample after settle (default 8)
#   PERF_PROBE_SETTLE         frames before sample (default 180)
#   PERF_PROBE_SCENARIO       base scenario (default beginner_sandbox)
#
# Prefer: scripts/perf_workload_baseline.sh

extends Node

const ScenarioPickerScript = preload("res://scripts/scenario_picker.gd")
const AestheticsScript = preload("res://scripts/aesthetics_runtime.gd")
const Readiness = preload("res://scripts/capture_readiness.gd")

const WORKLOADS: Dictionary = {
	"default": {"density_budget": 1.0, "cycle": "established", "interact": false},
	"dense": {"density_budget": 1.6, "cycle": "established", "interact": false},
	"mature": {"density_budget": 1.0, "cycle": "established", "start_matured": true, "interact": false},
	"interaction": {"density_budget": 1.2, "cycle": "established", "interact": true},
}

var _main: Node = null
var _cfg: Node = null
var _out: String = ""
var _sample_s: float = 8.0
var _settle: int = 180
var _only: PackedStringArray = PackedStringArray()
var _reports: Array = []


func _ready() -> void:
	_cfg = get_node_or_null("/root/TankConfig")
	if _cfg == null:
		push_error("[perf_probe] TankConfig missing")
		get_tree().quit(1)
		return
	_cfg.set("capture_mode", true)
	if _cfg.has_method("reset_to_defaults"):
		_cfg.call("reset_to_defaults")
	AestheticsScript.apply_first_launch_defaults(_cfg)
	_out = OS.get_environment("PERF_PROBE_OUT").strip_edges()
	if _out == "":
		_out = "user://perf_workloads"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_sample_s = maxf(2.0, float(OS.get_environment("PERF_PROBE_SAMPLE_S")) if OS.get_environment("PERF_PROBE_SAMPLE_S") != "" else 8.0)
	_settle = maxi(60, int(OS.get_environment("PERF_PROBE_SETTLE")) if OS.get_environment("PERF_PROBE_SETTLE") != "" else 180)
	_only = OS.get_environment("PERF_PROBE_WORKLOADS").split(",", false)
	if _only.is_empty():
		_only = PackedStringArray(WORKLOADS.keys())
	process_priority = 1000
	_run.call_deferred()


func _run() -> void:
	for wid in _only:
		var id: String = String(wid).strip_edges()
		if id == "" or not WORKLOADS.has(id):
			push_warning("[perf_probe] skip unknown workload '%s'" % id)
			continue
		await _run_workload(id, WORKLOADS[id])
	_finish()


func _apply_scenario(scenario_id: String) -> void:
	for sc in ScenarioPickerScript.SCENARIOS:
		if String(sc.get("id", "")) == scenario_id:
			ScenarioPickerScript.apply_scenario(sc, _cfg)
			return


func _run_workload(wid: String, spec: Dictionary) -> void:
	if _main != null:
		_main.queue_free()
		_main = null
		await get_tree().process_frame
		await get_tree().process_frame
	if _cfg.has_method("reset_to_defaults"):
		_cfg.call("reset_to_defaults")
	AestheticsScript.apply_first_launch_defaults(_cfg)
	_cfg.set("capture_mode", true)
	var scenario_id: String = OS.get_environment("PERF_PROBE_SCENARIO").strip_edges()
	if scenario_id == "":
		scenario_id = "beginner_sandbox"
	_apply_scenario(scenario_id)
	_cfg.density_budget = float(spec.get("density_budget", 1.0))
	_cfg.cycle_start_mode = String(spec.get("cycle", "established"))
	_cfg.start_matured = bool(spec.get("start_matured", _cfg.cycle_start_mode == "established"))
	PerfGovernor.reset_for_test()
	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	print("[perf_probe] workload=%s density=%.2f scenario=%s" % [
		wid, float(_cfg.density_budget), scenario_id])
	var ready_info: Dictionary = await Readiness.await_world(get_tree(), _main, 45.0)
	if not bool(ready_info.get("ok", false)):
		push_error("[perf_probe] %s not ready: %s" % [wid, ready_info.get("reason", "")])
		return
	for _i in _settle:
		await get_tree().process_frame
		if bool(_main.get("_focus_paused")) and _main.has_method("_on_focus_in"):
			_main.call("_on_focus_in")
	var t0: int = Time.get_ticks_msec()
	var interact: bool = bool(spec.get("interact", false))
	var feed_every_ms: int = 1500
	var last_feed: int = t0
	while Time.get_ticks_msec() - t0 < int(_sample_s * 1000.0):
		await get_tree().process_frame
		var dt: float = get_process_delta_time()
		PerfGovernor.scope_begin("frame")
		PerfGovernor.record_frame(dt)
		PerfGovernor.scope_end("frame")
		if interact and Time.get_ticks_msec() - last_feed >= feed_every_ms:
			last_feed = Time.get_ticks_msec()
			var sim: Variant = _main.get("_sim")
			if sim is Node and (sim as Node).has_method("spawn_player_food"):
				(sim as Node).call("spawn_player_food", Vector3(0.0, 6.0, 0.0))
			if _main.has_method("_show_feed_toast"):
				_main.call("_show_feed_toast", "perf interact feed")
	var fish_n: int = 0
	var entity_n: int = 0
	var sim_n: Variant = _main.get("_sim")
	if sim_n is Node:
		fish_n = (sim_n as Node).fish.size() if (sim_n as Node).get("fish") != null else 0
		entity_n = fish_n
		if (sim_n as Node).get("shrimp") != null:
			entity_n += (sim_n as Node).shrimp.size()
		if (sim_n as Node).get("plants") != null:
			entity_n += (sim_n as Node).plants.size()
	var draw_n: int = 0
	if RenderingServer.has_method("get_rendering_info"):
		draw_n = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var tier: String = String(_cfg.get("device_tier")) if _cfg.get("device_tier") != null else ""
	var report: Dictionary = PerfGovernor.workload_report(wid, fish_n, draw_n, entity_n, tier)
	report["scenario"] = scenario_id
	report["density_budget"] = float(_cfg.density_budget)
	report["hud"] = PerfGovernor.hud_line(fish_n, draw_n)
	_reports.append(report)
	var path: String = "%s/%s.json" % [_out, wid]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
	print("[perf_probe] %s p50/p95/p99=%.2f/%.2f/%.2f fish=%d draw=%d entities=%d spikes=%d cap=%d tier=%s" % [
		wid, float(report.p50_ms), float(report.p95_ms), float(report.p99_ms),
		fish_n, draw_n, entity_n, int(report.main_thread_spikes),
		int(report.fps_cap), tier if tier != "" else "default"])


func _finish() -> void:
	var summary: Dictionary = {
		"workloads": _reports,
		"disclaimer": "Review-machine sample — does not represent low-end devices.",
	}
	var jf := FileAccess.open("%s/report.json" % _out, FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify(summary, "\t"))
		jf.close()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Perf workload report")
	lines.append("")
	lines.append("Machine-specific sample — not a low-end guarantee.")
	lines.append("")
	lines.append("| Workload | p50 | p95 | p99 | fish | draw | entities | spikes | cap | tier |")
	lines.append("|---|---|---|---|---|---|---|---|---|---|")
	for r in _reports:
		lines.append("| %s | %.2f | %.2f | %.2f | %d | %d | %d | %d | %d | %s |" % [
			String(r.get("workload", "")),
			float(r.get("p50_ms", 0.0)),
			float(r.get("p95_ms", 0.0)),
			float(r.get("p99_ms", 0.0)),
			int(r.get("fish", 0)),
			int(r.get("draw_calls", 0)),
			int(r.get("entities", 0)),
			int(r.get("main_thread_spikes", 0)),
			int(r.get("fps_cap", 0)),
			String(r.get("tier", "")) if String(r.get("tier", "")) != "" else "default",
		])
	var sf := FileAccess.open("%s/SUMMARY.md" % _out, FileAccess.WRITE)
	if sf != null:
		sf.store_string("\n".join(lines) + "\n")
		sf.close()
	print("[perf_probe] wrote %s (%d workloads)" % [_out, _reports.size()])
	get_tree().quit(0 if not _reports.is_empty() else 1)
