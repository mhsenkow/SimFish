class_name MindBrainPool
extends RefCounted

# PERFORMANCE_REALTIME #95 + PERFORMANCE_UNTHROTTLED #45/#46/#47/#48 —
# batched fish cognition on WorkerThreadPool (brain thread spine).

const _MindCycleScript = preload("res://scripts/mind_cycle.gd")
const _FeltSelfLayerScript = preload("res://scripts/felt_self_layer.gd")
const _MindWorkerCfgScript = preload("res://scripts/mind_worker_cfg.gd")

static var _mutex: Mutex = Mutex.new()
static var _pending_jobs: Array = []
static var _results: Dictionary = {}  # fish_id -> {ms, proxy}
static var _task_id: int = -1
static var _snap_banks: Array = [{}, {}]
static var _snap_write_idx: int = 0
static var _worker_cfg: Dictionary = {}
static var _in_worker: bool = false
static var _stats: Dictionary = {
	"queued": 0, "applied": 0, "worker_batches": 0, "worker_jobs": 0,
}


static func reset_for_test() -> void:
	_mutex.lock()
	_pending_jobs.clear()
	_results.clear()
	_task_id = -1
	_snap_banks = [{}, {}]
	_snap_write_idx = 0
	_worker_cfg.clear()
	_in_worker = false
	_stats = {"queued": 0, "applied": 0, "worker_batches": 0, "worker_jobs": 0}
	_mutex.unlock()


static func stats() -> Dictionary:
	return _stats.duplicate()


static func enabled() -> bool:
	if OS.has_feature("web") or OS.has_feature("android"):
		return false
	if DisplayServer.get_name() == "headless":
		return true
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return false
	var st: SceneTree = ml as SceneTree
	if st == null or st.root == null:
		return false
	var cfg: Node = st.root.get_node_or_null("/root/TankConfig")
	if cfg == null:
		return true
	if cfg.get("mind_brain_threads") != null:
		return bool(cfg.mind_brain_threads)
	return true


static func in_worker() -> bool:
	return _in_worker


static func worker_cfg(key: String, default: Variant = true) -> Variant:
	return _worker_cfg.get(key, default)


static func begin_tick(sim: Node) -> void:
	var ws_on: bool = true
	var felt_on: bool = true
	var ai_on: bool = true
	var voice_off: bool = false
	var keeper_ears: bool = true
	var keeper_gaze: bool = true
	var keeper_mic: bool = false
	var episodic_quant: bool = true
	var mind_pressure: float = 0.0
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree and (ml as SceneTree).root != null:
		var cfg: Node = (ml as SceneTree).root.get_node_or_null("/root/TankConfig")
		if cfg != null:
			ws_on = bool(cfg.get("consciousness_workspace_enabled") if cfg.get("consciousness_workspace_enabled") != null else true)
			voice_off = bool(cfg.get("sentience_voice_off"))
			if voice_off:
				felt_on = false
			else:
				felt_on = bool(cfg.get("felt_self_enabled") if cfg.get("felt_self_enabled") != null else true)
			ai_on = bool(cfg.get("consciousness_active_inference") if cfg.get("consciousness_active_inference") != null else true)
			keeper_ears = bool(cfg.get("keeper_ears_enabled") if cfg.get("keeper_ears_enabled") != null else true)
			keeper_gaze = bool(cfg.get("keeper_gaze_enabled") if cfg.get("keeper_gaze_enabled") != null else true)
			keeper_mic = bool(cfg.get("keeper_mic_enabled") if cfg.get("keeper_mic_enabled") != null else false)
			if cfg.get("episodic_quant_8bit") != null:
				episodic_quant = bool(cfg.episodic_quant_8bit)
	if sim.get("_mind_budget_pressure") != null:
		mind_pressure = float(sim._mind_budget_pressure)
	_worker_cfg = {
		"felt_self_enabled": felt_on,
		"workspace_enabled": ws_on,
		"consciousness_active_inference": ai_on,
		"sentience_voice_off": voice_off,
		"keeper_ears_enabled": keeper_ears,
		"keeper_gaze_enabled": keeper_gaze,
		"keeper_mic_enabled": keeper_mic,
		"episodic_quant_8bit": episodic_quant,
		"mind_budget_pressure": mind_pressure,
		"mind_tick_index": int(sim.get("_mind_tick_index") if sim.get("_mind_tick_index") != null else 0),
	}
	var w: int = _snap_write_idx
	_snap_banks[w] = MindSimSnap.capture(sim)
	_snap_banks[w]["worker_cfg"] = _worker_cfg.duplicate(true)


static func apply_pending(f: Fish, ms: MindState) -> bool:
	if f == null:
		return false
	var fid: String = str(f.id)
	_mutex.lock()
	var packed: Variant = _results.get(fid, null)
	if packed is Dictionary:
		_results.erase(fid)
	_mutex.unlock()
	if not (packed is Dictionary):
		return false
	var result: Dictionary = packed as Dictionary
	var proxy: MindFishProxy = MindFishProxy.from_dict(result.get("proxy", {}))
	proxy.apply_mind_to(f)
	var ms_dict: Variant = result.get("ms", null)
	if ms is MindState and ms_dict is Dictionary:
		ms.from_dict(ms_dict as Dictionary)
		ms.apply_to_fish(f)
	_stats["applied"] = int(_stats.get("applied", 0)) + 1
	return true


static func queue_cognition(f: Fish, ms: MindState, dt: float) -> void:
	if f == null or ms == null:
		return
	if not enabled():
		return
	var tier_v: Variant = f.get("_mind_lod_tier")
	var tier: int = int(tier_v) if tier_v != null else MindLOD.T2_WORLD_MODEL
	var job: Dictionary = {
		"fish_id": str(f.id),
		"proxy": MindFishProxy.capture(f),
		"ms": ms.to_dict(),
		"dt": dt,
		"tier": tier,
	}
	_mutex.lock()
	_pending_jobs.append(job)
	_mutex.unlock()
	_stats["queued"] = int(_stats.get("queued", 0)) + 1


static func flush_tick() -> void:
	if not enabled():
		return
	poll()
	_mutex.lock()
	if _pending_jobs.is_empty():
		_mutex.unlock()
		return
	var batch: Array = _pending_jobs.duplicate(true)
	_pending_jobs.clear()
	var read_idx: int = _snap_write_idx
	_snap_write_idx = 1 - _snap_write_idx
	var sim_copy: Dictionary = (_snap_banks[read_idx] as Dictionary).duplicate(true)
	_mutex.unlock()
	batch.sort_custom(_spatial_job_less)
	_task_id = WorkerThreadPool.add_task(_worker_run_batch.bind(batch, sim_copy))
	_stats["worker_batches"] = int(_stats.get("worker_batches", 0)) + 1
	_stats["worker_jobs"] = int(_stats.get("worker_jobs", 0)) + batch.size()
	poll()


static func poll() -> void:
	if _task_id < 0:
		return
	if not WorkerThreadPool.is_task_completed(_task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1


static func wait_for_batch(timeout_ms: int = 5000) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while _task_id >= 0 and Time.get_ticks_msec() < deadline:
		poll()
	return _task_id < 0


static func _worker_run_batch(batch: Array, sim_snap: Dictionary) -> void:
	_in_worker = true
	if sim_snap.get("worker_cfg") is Dictionary:
		_worker_cfg = (sim_snap["worker_cfg"] as Dictionary).duplicate(true)
	_MindWorkerCfgScript.begin_batch(_worker_cfg)
	_FeltSelfLayerScript.set_worker_felt_self_override(_worker_cfg.get("felt_self_enabled", true))
	_MindCycleScript.set_worker_workspace_enabled(_worker_cfg.get("workspace_enabled", true))
	var sim_host: MindSimSnap = MindSimSnap.from_dict(sim_snap)
	var out: Dictionary = {}
	for job_v in batch:
		if not (job_v is Dictionary):
			continue
		var job: Dictionary = job_v as Dictionary
		var fid: String = str(job.get("fish_id", ""))
		if fid == "":
			continue
		var proxy: MindFishProxy = MindFishProxy.from_dict(job.get("proxy", {}))
		var ms: MindState = MindState.new()
		ms.from_dict(job.get("ms", {}))
		var dt: float = float(job.get("dt", 0.1))
		var tier: int = int(job.get("tier", MindLOD.T2_WORLD_MODEL))
		proxy._cycle_lod_tier = tier
		proxy._mind_lod_tier = tier
		_MindCycleScript.begin_cycle(proxy, sim_host)
		_MindCycleScript.run_attention_phase_worker(proxy, sim_host, ms, dt)
		out[fid] = {"proxy": proxy.to_dict(), "ms": ms.to_dict()}
	_FeltSelfLayerScript.set_worker_felt_self_override(null)
	_MindCycleScript.set_worker_workspace_enabled(null)
	_MindWorkerCfgScript.end_batch()
	_in_worker = false
	_mutex.lock()
	for k in out.keys():
		_results[k] = out[k]
	_mutex.unlock()


static func run_roundtrip_smoke(f: Fish) -> bool:
	if f == null:
		return false
	reset_for_test()
	begin_tick(f.sim)
	var ms: MindState = MindChannel.for_cycle(f, true)
	queue_cognition(f, ms, 0.1)
	flush_tick()
	if not wait_for_batch():
		return false
	var ms2: MindState = MindChannel.for_cycle(f, true)
	return apply_pending(f, ms2)


static func _spatial_job_less(a: Variant, b: Variant) -> bool:
	if not (a is Dictionary) or not (b is Dictionary):
		return false
	return _spatial_job_key(a as Dictionary) < _spatial_job_key(b as Dictionary)


static func _spatial_job_key(job: Dictionary) -> int:
	var proxy: Variant = job.get("proxy", null)
	if not (proxy is Dictionary):
		return 0
	var p: Dictionary = proxy as Dictionary
	var pos: Variant = p.get("position", null)
	if pos is Vector3:
		var v: Vector3 = pos as Vector3
		var cx: int = int(floor(v.x * 0.5))
		var cz: int = int(floor(v.z * 0.5))
		return (cx * 73856093) ^ (cz * 19349663)
	if pos is Array and (pos as Array).size() >= 3:
		var pa: Array = pos as Array
		var cx2: int = int(floor(float(pa[0]) * 0.5))
		var cz2: int = int(floor(float(pa[2]) * 0.5))
		return (cx2 * 73856093) ^ (cz2 * 19349663)
	return hash(str(job.get("fish_id", "")))
