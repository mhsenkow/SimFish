# Tank ↔ Music Sync — plays Spotify previews (or local audio), analyzes the
# spectrum in real time, and exposes drive signals for fauna, lights, and shaders.
extends Node

signal track_changed(meta: Dictionary)
signal sync_state_changed(active: bool)
signal search_results_ready(results: Array)
signal status_message(text: String, is_error: bool)

const BUS_NAME := "MusicSync"
const TOKEN_URL := "https://accounts.spotify.com/api/token"
const API_BASE := "https://api.spotify.com/v1"

const _FAUNA_NEUTRAL: Dictionary = {
	"speed": 1.0,
	"wander": 1.0,
	"home_radius": 1.0,
	"home_pull": 1.0,
	"tightness": 1.0,
	"accel": 1.0,
	"turn": 1.0,
	"dart_chance": 0.0,
	"beat_dart": false,
	"wander_refresh": 1.0,
	"home_drift": 1.0,
	"wander_amp": 1.0,
	"sweep": 0.0,
	"vertical": 0.0,
	"beat_phase": 0.0,
	"scale": 1.0,
}

var _player: AudioStreamPlayer
var _spectrum: AudioEffectSpectrumAnalyzerInstance
var _http_token: HTTPRequest
var _http_api: HTTPRequest
var _http_download: HTTPRequest
var _file_dialog: FileDialog

var _token: String = ""
var _token_expires_at: float = 0.0
var _pending_api: Dictionary = {}  # kind, callback context
var _search_results: Array = []
var _track_meta: Dictionary = {}
var _audio_features: Dictionary = {}

var _enabled: bool = false
var _intensity: float = 0.75
var _beat_serial: int = 0
var _beat_cooldown: float = 0.0
var _phase_beats: float = 0.0
var _last_serial_snap: int = -1
var _clock_confidence: float = 0.45
var _prev_energy_peak: float = 0.0
var _drop_detect_until: float = 0.0
const _LATENCY_SEC: float = 0.08
var _bass_smooth: float = 0.0
var _energy_smooth: float = 0.0
var _bass_peak: float = 0.0
# Rolling peaks per band — auto-gain so bass/mid/high meters read on quiet MP3s.
var _band_peak: Dictionary = {"bass": 0.004, "mid": 0.004, "high": 0.004}
var _session_latency_offset_ms: float = 0.0
var _bubble_accum: float = 0.0
var _analyzer: MusicAnalyzer = MusicAnalyzer.new()
var _analysis: Dictionary = {}

var _drive: Dictionary = {
	"bass": 0.0,
	"mid": 0.0,
	"high": 0.0,
	"energy": 0.0,
	"beat": 0.0,
	"valence": 0.5,
	"danceability": 0.5,
	"tempo": 120.0,
	"active": false,
}


func _ready() -> void:
	add_to_group("music_reactive")
	_setup_audio_bus()
	_player = AudioStreamPlayer.new()
	_player.name = "SyncPlayer"
	_player.bus = BUS_NAME
	_player.finished.connect(_on_track_finished)
	add_child(_player)
	_http_token = _make_http("HttpSpotifyToken", _on_token_response)
	_http_api = _make_http("HttpSpotifyApi", _on_api_response)
	_http_download = _make_http("HttpPreviewDownload", _on_preview_downloaded)
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.mp3,*.ogg,*.wav ; Audio Files"])
	_file_dialog.title = "Pick a track for tank sync"
	_file_dialog.file_selected.connect(_on_local_file_selected)
	add_child(_file_dialog)
	_pull_config()
	set_process(true)


func _pull_config() -> void:
	_enabled = bool(TankConfig.music_sync_enabled)
	_intensity = clampf(float(TankConfig.music_sync_intensity), 0.0, 1.0)
	_emit_sync_state()


func apply_config() -> void:
	_pull_config()
	if not _enabled:
		stop()


func set_enabled(on: bool) -> void:
	_enabled = on
	TankConfig.music_sync_enabled = on
	if not on:
		stop()
	_emit_sync_state()


func is_active() -> bool:
	return _enabled and bool(_drive.get("active", false))


func is_external_playing() -> bool:
	return _player != null and _player.playing


func get_drive() -> Dictionary:
	var d: Dictionary = _drive.duplicate()
	d["beat_phase"] = _beat_phase()
	return d


func get_meter_levels() -> Dictionary:
	return {
		"bass": float(_drive.bass),
		"mid": float(_drive.mid),
		"high": float(_drive.high),
		"beat": float(_drive.beat),
		"energy": float(_drive.energy),
	}


func session_latency_ms() -> float:
	return clampf(float(TankConfig.music_sync_latency_ms) + _session_latency_offset_ms, 0.0, 200.0)


func session_latency_offset_ms() -> float:
	return _session_latency_offset_ms


func nudge_session_latency(delta_ms: float) -> void:
	_session_latency_offset_ms = clampf(_session_latency_offset_ms + delta_ms, -80.0, 80.0)


func reset_meter_calibration() -> void:
	_band_peak = {"bass": 0.004, "mid": 0.004, "high": 0.004}


func reset_session_calibration() -> void:
	_session_latency_offset_ms = 0.0
	reset_meter_calibration()


func reset_session_latency() -> void:
	_session_latency_offset_ms = 0.0


func get_music_clock() -> Dictionary:
	if not _analysis.is_empty():
		return _analysis.duplicate()
	var beat_phase: float = _beat_phase()
	var bar_phase: float = fposmod(_phase_beats / 4.0, 1.0)
	var bar_count: int = maxi(0, int(_phase_beats / 4.0))
	var phrase: Dictionary = _phrase_from_bar(bar_count)
	return {
		"beat_phase": beat_phase,
		"bar_phase": bar_phase,
		"bar_count": bar_count,
		"downbeat": beat_phase < 0.06,
		"phrase_state": phrase.get("phrase_state", "verse"),
		"phrase_progress": phrase.get("phrase_progress", bar_phase),
		"wall_clock": true,
		"confidence": _clock_confidence,
		"drop_detected": _drop_detect_until > 0.0,
		"onsets": [],
	}


func get_analysis() -> Dictionary:
	return _analysis.duplicate()


func get_status() -> Dictionary:
	return {
		"enabled": _enabled,
		"playing": is_external_playing(),
		"track": _track_meta.duplicate(),
		"features": _audio_features.duplicate(),
		"drive": get_drive(),
		"intensity": _intensity,
	}


func get_search_results() -> Array:
	return _search_results.duplicate(true)


func set_intensity(v: float) -> void:
	_intensity = clampf(v, 0.0, 1.0)
	TankConfig.music_sync_intensity = _intensity


func fauna_behavior_mods(instance_id: int) -> Dictionary:
	var mc := get_node_or_null("/root/MusicContext")
	if mc != null and mc.has_method("fauna_behavior_mods"):
		return mc.fauna_behavior_mods(instance_id)
	return _legacy_fauna_behavior_mods(instance_id)


func _legacy_fauna_behavior_mods(instance_id: int) -> Dictionary:
	if not is_active() or not TankConfig.music_sync_fish:
		return _FAUNA_NEUTRAL
	var i: float = _intensity
	var bass: float = maxf(float(_drive.bass), 0.18)
	var mid: float = maxf(float(_drive.mid), 0.14)
	var high: float = maxf(float(_drive.high), 0.10)
	var energy: float = maxf(float(_drive.energy), 0.22)
	var beat: float = float(_drive.beat)
	var dance: float = float(_drive.danceability)
	var phase: float = sin(float(instance_id % 997) * 0.17 + _beat_serial * 0.4)
	var groove: float = clampf(bass * 0.5 + mid * 0.35 + energy * 0.4 + dance * 0.3, 0.0, 1.0)
	groove = maxf(groove, 0.38)
	var beat_phase: float = float(_beat_serial) * 1.57 + float(instance_id % 997) * 0.17
	# Any audible pulse — whole school surges so the tank visibly dances.
	var beat_dart: bool = beat > 0.08
	return {
		"speed": 1.0 + groove * 2.35 * i + beat * 1.35 * i,
		"wander": 1.0 + mid * 2.05 * i + absf(phase) * 0.95 * i,
		"wander_amp": 1.0 + groove * 1.85 * i + beat * 0.55 * i,
		"home_radius": 1.0 + energy * 4.8 * i + dance * 1.85 * i,
		"home_pull": maxf(0.02, 1.0 - groove * 0.98 * i),
		"tightness": maxf(0.08, 1.0 - mid * 0.88 * i - beat * 0.55 * i),
		"accel": 1.0 + bass * 2.05 * i + beat * 1.35 * i,
		"turn": 1.0 + high * 1.35 * i + beat * 0.85 * i,
		"dart_chance": groove * 0.72 * i + beat * 0.42 * i,
		"sweep": maxf(0.55, clampf(groove * 1.05 + beat * 0.95 + dance * 0.35, 0.0, 1.0)) * i,
		"vertical": maxf(0.35, clampf(mid * 0.45 + high * 0.72 + beat * 0.65, 0.0, 1.0)) * i,
		"beat_phase": beat_phase,
		"beat_dart": beat_dart,
		"wander_refresh": 1.0 + groove * 5.5 * i,
		"home_drift": 1.0 + groove * 6.5 * i,
		"scale": fauna_scale_pulse(instance_id),
	}


func fauna_speed_mult(instance_id: int) -> float:
	return float(fauna_behavior_mods(instance_id).get("speed", 1.0))


func fauna_scale_pulse(instance_id: int) -> float:
	if not is_active() or not TankConfig.music_sync_fish:
		return 1.0
	var beat: float = float(_drive.beat)
	var wobble: float = sin(_bass_peak * 8.0 + float(instance_id % 50) * 0.31) * 0.5 + 0.5
	return 1.0 + beat * 0.22 * _intensity + wobble * float(_drive.bass) * 0.16 * _intensity


func should_beat_dart(instance_id: int) -> bool:
	return bool(fauna_behavior_mods(instance_id).get("beat_dart", false))


func plant_sway_mult() -> float:
	var mc := get_node_or_null("/root/MusicContext")
	if mc != null and mc.is_active() and mc.has_method("plant_sway_mult"):
		return float(mc.plant_sway_mult())
	if not is_active() or not TankConfig.music_sync_plants:
		return 1.0
	return 1.0 + (float(_drive.mid) * 0.65 + float(_drive.beat) * 0.45) * _intensity


func light_fixture_mul() -> float:
	var mc := get_node_or_null("/root/MusicContext")
	if mc != null and mc.is_active() and mc.has_method("light_fixture_mul"):
		return float(mc.light_fixture_mul())
	if not is_active() or not TankConfig.music_sync_lights:
		return 1.0
	return 1.0 + float(_drive.bass) * 0.55 * _intensity + float(_drive.beat) * 0.35 * _intensity


func light_beam_warmth_mix() -> float:
	if not is_active() or not TankConfig.music_sync_lights:
		return 0.0
	return clampf(float(_drive.valence) * 0.35 + float(_drive.mid) * 0.25, 0.0, 1.0) * _intensity


func caustic_mul() -> float:
	var mc := get_node_or_null("/root/MusicContext")
	if mc != null and mc.is_active() and mc.has_method("caustic_mul"):
		return float(mc.caustic_mul())
	if not is_active() or not TankConfig.music_sync_lights:
		return 1.0
	return 1.0 + float(_drive.high) * 0.5 * _intensity + float(_drive.beat) * 0.2 * _intensity


func aquatic_shimmer() -> float:
	if not is_active():
		return 0.0
	var base: float = float(_drive.energy) * 0.35
	return clampf(base * _intensity * 0.25, 0.0, 0.22)


func palette_overlay() -> Dictionary:
	if not is_active() or not TankConfig.music_sync_color:
		return {"hue": 0.0, "sat": 1.0, "warmth": 0.0, "val": 1.0}
	var valence: float = float(_drive.valence)
	var env: float = float(_drive.energy) * _intensity * 0.4
	return {
		"hue": (valence - 0.5) * 0.08 * _intensity,
		"sat": lerpf(1.0, 1.04, env),
		"warmth": (valence - 0.35) * 0.22 * _intensity,
		"val": lerpf(1.0, 1.03, env * 0.5),
	}


func bubble_rate_mult() -> float:
	if not is_active() or not TankConfig.music_sync_bubbles:
		return 1.0
	return 1.0 + float(_drive.high) * 1.8 * _intensity + float(_drive.beat) * 0.8 * _intensity


func pick_local_file() -> void:
	_file_dialog.popup_centered_ratio(0.62)


func play_res_path(res_path: String, display_name: String = "", artists: String = "Demo track") -> void:
	if not ResourceLoader.exists(res_path):
		emit_signal("status_message", "Demo file missing: %s" % res_path.get_file(), true)
		return
	var stream: AudioStream = load(res_path) as AudioStream
	if stream == null:
		emit_signal("status_message", "Could not load: %s" % res_path.get_file(), true)
		return
	var title: String = display_name if not display_name.is_empty() else res_path.get_file().get_basename()
	_start_external_stream(stream, {
		"name": title,
		"artists": artists,
		"id": "",
		"preview_url": res_path,
		"local": true,
		"demo": true,
	})


func stop() -> void:
	if _player != null:
		_player.stop()
	_track_meta = {}
	_audio_features = {}
	_drive.beat = 0.0
	_beat_cooldown = 0.0
	_beat_serial += 1
	_decay_drive(1.0)
	_drive.active = false
	_analyzer.reset()
	_analysis = {}
	_apply_visual_uniforms(true)
	_emit_sync_state()


func toggle_pause() -> void:
	if _player == null or _player.stream == null:
		return
	_player.stream_paused = not _player.stream_paused


func search_spotify(query: String) -> void:
	var q: String = query.strip_edges()
	if q.is_empty():
		emit_signal("status_message", "Enter a song or artist to search.", true)
		return
	if not _spotify_configured():
		emit_signal("status_message",
			"Add Spotify Client ID + Secret below (free at developer.spotify.com), or use Load local file.",
			true)
		return
	_ensure_token("search", {"query": q})


func play_spotify_url(url: String) -> void:
	var id: String = _parse_spotify_id(url.strip_edges())
	if id.is_empty():
		emit_signal("status_message", "Paste a Spotify track link or URI.", true)
		return
	play_track_id(id)


func play_track_id(track_id: String) -> void:
	if not _spotify_configured():
		emit_signal("status_message", "Spotify credentials required.", true)
		return
	_ensure_token("track", {"id": track_id})


func play_search_result(index: int) -> void:
	if index < 0 or index >= _search_results.size():
		return
	var item: Dictionary = _search_results[index]
	var tid: String = String(item.get("id", ""))
	if tid.is_empty():
		return
	play_track_id(tid)


func _process(dt: float) -> void:
	if _enabled and is_external_playing():
		_analyze_audio(dt)
		_maybe_spawn_bubbles(dt)
	elif _enabled and not _track_meta.is_empty() and not is_external_playing():
		# Preview ended — loop if we still have the stream cached.
		if _player.stream != null:
			_player.play()
	else:
		_decay_drive(dt * 2.5)
	_drive.active = _enabled and (is_external_playing() or float(_drive.energy) > 0.04)


func _analyze_audio(dt: float) -> void:
	if _spectrum == null:
		_bind_spectrum()
	if _spectrum == null:
		return
	var mode := AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE
	var bass_raw: float = _spectrum.get_magnitude_for_frequency_range(40.0, 160.0, mode).length()
	var mid_raw: float = _spectrum.get_magnitude_for_frequency_range(220.0, 2200.0, mode).length()
	var high_raw: float = _spectrum.get_magnitude_for_frequency_range(2200.0, 12000.0, mode).length()
	var bass: float = _norm_band(bass_raw, "bass", dt)
	var mid: float = _norm_band(mid_raw, "mid", dt)
	var high: float = _norm_band(high_raw, "high", dt)
	_bass_smooth = lerpf(_bass_smooth, bass, clampf(dt * 10.0, 0.0, 1.0))
	var combined: float = bass * 0.52 + mid * 0.33 + high * 0.15
	_energy_smooth = lerpf(_energy_smooth, combined, clampf(dt * 10.0, 0.0, 1.0))
	_drive.bass = lerpf(float(_drive.bass), bass, clampf(dt * 12.0, 0.0, 1.0))
	_drive.mid = lerpf(float(_drive.mid), mid, clampf(dt * 10.0, 0.0, 1.0))
	_drive.high = lerpf(float(_drive.high), high, clampf(dt * 10.0, 0.0, 1.0))
	_drive.energy = lerpf(float(_drive.energy), combined, clampf(dt * 8.0, 0.0, 1.0))
	_analysis = _analyzer.analyze(_spectrum, dt, bass, mid, high, combined, float(_drive.tempo))
	if float(_analysis.get("tempo", 0.0)) > 1.0:
		_drive.tempo = lerpf(float(_drive.tempo), float(_analysis.tempo), 0.12)
		_clock_confidence = float(_analysis.get("confidence", _clock_confidence))
	var kick_on: float = 0.0
	var onsets: Array = _analysis.get("onsets", [])
	if onsets.size() > 0 and onsets[0] is Dictionary:
		kick_on = float(onsets[0].get("strength", 0.0))
	if kick_on > 0.82:
		_drive.beat = 1.0
		_bass_peak = bass
		_beat_serial += 1
	_beat_cooldown = maxf(0.0, _beat_cooldown - dt)
	var beat_thresh: float = maxf(_energy_smooth * 1.08 + 0.02, _bass_smooth * 1.12 + 0.03)
	if combined > beat_thresh and _beat_cooldown <= 0.0 and kick_on < 0.5:
		_drive.beat = 1.0
		_bass_peak = bass
		_beat_serial += 1
		_beat_cooldown = maxf(0.06, 60.0 / maxf(float(_drive.tempo), 80.0) * 0.32)
	else:
		_drive.beat = maxf(0.0, float(_drive.beat) - dt * 2.6)
	_detect_drop(combined, dt)
	if not _analysis.is_empty():
		_phase_beats = float(_analysis.get("bar_count", 0)) * 4.0 + float(_analysis.get("beat_phase", 0.0))
	_update_music_clock(dt)
	_apply_visual_uniforms()


func _decay_drive(dt: float) -> void:
	for key in ["bass", "mid", "high", "energy", "beat"]:
		_drive[key] = maxf(0.0, float(_drive[key]) - dt * 1.8)
	if float(_drive.energy) <= 0.02:
		_apply_visual_uniforms(true)


func _apply_visual_uniforms(reset: bool = false) -> void:
	var mc := get_node_or_null("/root/MusicContext")
	if mc != null and mc.is_active():
		return
	if reset or not is_active():
		var cfg: Node = get_node_or_null("/root/TankConfig")
		if cfg != null:
			VoxelMat.apply_global_palette(cfg)
		else:
			VoxelMat.apply_music_sync_overlay({"hue": 0.0, "sat": 1.0, "warmth": 0.0, "val": 1.0}, 0.0)
		return
	var pal: Dictionary = palette_overlay()
	VoxelMat.apply_music_sync_overlay(pal, aquatic_shimmer())


func _maybe_spawn_bubbles(dt: float) -> void:
	if not TankConfig.music_sync_bubbles:
		return
	var ml: MainLoop = Engine.get_main_loop()
	if not (ml is SceneTree):
		return
	var scene: Node = (ml as SceneTree).current_scene
	if scene == null:
		return
	var world: Node = scene.get_node_or_null("SubViewport/World")
	if world == null:
		return
	var visuals: Node = world.get_node_or_null("AquariumVisuals")
	if visuals == null or not visuals.has_method("spawn_snail_bubble"):
		return
	_bubble_accum += dt * bubble_rate_mult()
	while _bubble_accum >= 1.0:
		_bubble_accum -= 1.0
		if randf() > 0.35:
			continue
		var half_w: float = 4.0
		if "TANK_HALF_W" in world:
			half_w = float(world.TANK_HALF_W)
		var water_y: float = 5.0
		if "WATER_HEIGHT" in world:
			water_y = float(world.WATER_HEIGHT)
		var pos := Vector3(randf_range(-half_w * 0.7, half_w * 0.7), water_y - 0.2,
			randf_range(-2.0, 2.0))
		visuals.spawn_snail_bubble(pos)


func _on_track_finished() -> void:
	if _enabled and _player.stream != null:
		_player.play()


func _on_local_file_selected(path: String) -> void:
	_play_local_path(path)


func _resolve_path_case(path: String) -> String:
	if path.is_empty() or not path.is_absolute_path():
		return path
	var segments: PackedStringArray = path.split("/", false)
	if segments.is_empty():
		return path
	var built: String = "/" if path.begins_with("/") else ""
	for seg in segments:
		var parent: String = built if built != "" else "."
		var dir := DirAccess.open(parent)
		if dir == null:
			built = seg if built == "" else built.path_join(seg)
			continue
		var canonical: String = seg
		dir.list_dir_begin()
		var entry: String = dir.get_next()
		while entry != "":
			if entry.to_lower() == seg.to_lower():
				canonical = entry
				break
			entry = dir.get_next()
		dir.list_dir_end()
		if built == "":
			built = canonical
		elif built == "/":
			built = "/%s" % canonical
		else:
			built = built.path_join(canonical)
	return built


func _play_local_path(path: String) -> void:
	path = _resolve_path_case(path)
	var ext: String = path.get_extension().to_lower()
	var stream: AudioStream = null
	match ext:
		"ogg":
			stream = AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			stream = AudioStreamMP3.load_from_file(path)
		"wav":
			stream = AudioStreamWAV.load_from_file(path)
	if stream == null:
		emit_signal("status_message", "Could not load audio: %s" % path.get_file(), true)
		return
	_start_external_stream(stream, {
		"name": path.get_file().get_basename(),
		"artists": "Local file",
		"id": "",
		"preview_url": path,
		"local": true,
	})


func _start_external_stream(stream: AudioStream, meta: Dictionary) -> void:
	if not _enabled:
		set_enabled(true)
		TankConfig.music_sync_enabled = true
	_track_meta = meta.duplicate()
	_audio_features = {
		"tempo": 120.0,
		"energy": 0.6,
		"valence": 0.55,
		"danceability": 0.5,
	}
	_apply_features_to_drive()
	_phase_beats = 0.0
	_last_serial_snap = -1
	reset_session_calibration()
	_analyzer.reset()
	_analysis = {}
	_player.stream = stream
	_player.play()
	emit_signal("track_changed", _track_meta.duplicate())
	emit_signal("status_message", "Playing %s — tank is listening." % _track_meta.name, false)
	_emit_sync_state()


func _play_preview_url(url: String) -> void:
	if url.is_empty():
		emit_signal("status_message", "This track has no Spotify preview clip.", true)
		return
	var err: int = _http_download.request(url)
	if err != OK:
		emit_signal("status_message", "Could not download preview (error %d)." % err, true)


func _setup_audio_bus() -> void:
	if AudioServer.get_bus_index(BUS_NAME) < 0:
		var idx: int = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, BUS_NAME)
		AudioServer.set_bus_send(idx, "Master")
		var fx := AudioEffectSpectrumAnalyzer.new()
		fx.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
		AudioServer.add_bus_effect(idx, fx)
	_bind_spectrum()


func _bind_spectrum() -> void:
	var bus_idx: int = AudioServer.get_bus_index(BUS_NAME)
	if bus_idx < 0:
		return
	if AudioServer.get_bus_effect_count(bus_idx) < 1:
		return
	_spectrum = AudioServer.get_bus_effect_instance(bus_idx, 0) as AudioEffectSpectrumAnalyzerInstance


func _make_http(node_name: String, callback: Callable) -> HTTPRequest:
	var h := HTTPRequest.new()
	h.name = node_name
	h.timeout = 12.0
	h.request_completed.connect(callback)
	add_child(h)
	return h


func _spotify_configured() -> bool:
	return not String(TankConfig.spotify_client_id).strip_edges().is_empty() \
		and not String(TankConfig.spotify_client_secret).strip_edges().is_empty()


func _ensure_token(kind: String, ctx: Dictionary) -> void:
	_pending_api = {"kind": kind, "ctx": ctx}
	if not _token.is_empty() and Time.get_unix_time_from_system() < _token_expires_at - 30.0:
		_dispatch_api()
		return
	var auth: String = "Basic " + Marshalls.raw_to_base64(
		("%s:%s" % [TankConfig.spotify_client_id, TankConfig.spotify_client_secret]).to_utf8_buffer())
	var headers := PackedStringArray([
		"Authorization: " + auth,
		"Content-Type: application/x-www-form-urlencoded",
	])
	var err: int = _http_token.request(TOKEN_URL, headers, HTTPClient.METHOD_POST,
		"grant_type=client_credentials")
	if err != OK:
		emit_signal("status_message", "Spotify auth request failed (%d)." % err, true)


func _dispatch_api() -> void:
	var kind: String = String(_pending_api.get("kind", ""))
	var ctx: Dictionary = _pending_api.get("ctx", {})
	var headers := PackedStringArray(["Authorization: Bearer " + _token])
	match kind:
		"search":
			var q: String = String(ctx.get("query", "")).uri_encode()
			var url: String = "%s/search?q=%s&type=track&limit=8" % [API_BASE, q]
			_http_api.request(url, headers, HTTPClient.METHOD_GET)
		"track":
			var tid: String = String(ctx.get("id", ""))
			_http_api.request("%s/tracks/%s" % [API_BASE, tid], headers, HTTPClient.METHOD_GET)
		"features":
			var fid: String = String(ctx.get("id", ""))
			_http_api.request("%s/audio-features/%s" % [API_BASE, fid], headers, HTTPClient.METHOD_GET)


func _on_token_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		emit_signal("status_message", "Spotify login failed (HTTP %d)." % code, true)
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		emit_signal("status_message", "Spotify token response was not JSON.", true)
		return
	_token = String(data.get("access_token", ""))
	var expires: int = int(data.get("expires_in", 3600))
	_token_expires_at = Time.get_unix_time_from_system() + float(expires)
	_dispatch_api()


func _on_api_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		emit_signal("status_message", "Spotify API error (HTTP %d)." % code, true)
		return
	var text: String = body.get_string_from_utf8()
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		emit_signal("status_message", "Unexpected Spotify response.", true)
		return
	var kind: String = String(_pending_api.get("kind", ""))
	match kind:
		"search":
			_parse_search_results(data)
		"track":
			_parse_track(data)
		"features":
			_parse_features(data)


func _parse_search_results(data: Dictionary) -> void:
	_search_results.clear()
	var tracks: Variant = data.get("tracks", {})
	if typeof(tracks) != TYPE_DICTIONARY:
		emit_signal("search_results_ready", [])
		return
	var items: Array = tracks.get("items", [])
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var artists: Array = item.get("artists", [])
		var artist_names: PackedStringArray = PackedStringArray()
		for a in artists:
			if typeof(a) == TYPE_DICTIONARY:
				artist_names.append(String(a.get("name", "")))
		_search_results.append({
			"id": String(item.get("id", "")),
			"name": String(item.get("name", "")),
			"artists": ", ".join(artist_names),
			"preview_url": String(item.get("preview_url", "")),
		})
	emit_signal("search_results_ready", _search_results.duplicate(true))
	if _search_results.is_empty():
		emit_signal("status_message", "No tracks found.", true)
	else:
		emit_signal("status_message", "%d tracks — pick one to sync the tank." % _search_results.size(), false)


func _parse_track(data: Dictionary) -> void:
	var artists: Array = data.get("artists", [])
	var artist_names: PackedStringArray = PackedStringArray()
	for a in artists:
		if typeof(a) == TYPE_DICTIONARY:
			artist_names.append(String(a.get("name", "")))
	_track_meta = {
		"id": String(data.get("id", "")),
		"name": String(data.get("name", "")),
		"artists": ", ".join(artist_names),
		"preview_url": String(data.get("preview_url", "")),
		"local": false,
	}
	TankConfig.music_sync_last_track_id = _track_meta.id
	_pending_api = {"kind": "features", "ctx": {"id": _track_meta.id}}
	_dispatch_api()
	var preview: String = String(_track_meta.preview_url)
	if preview.is_empty():
		emit_signal("track_changed", _track_meta.duplicate())
		emit_signal("status_message",
			"'%s' has no preview — try another track or load a local file." % _track_meta.name, true)
		return
	_play_preview_url(preview)


func _parse_features(data: Dictionary) -> void:
	_audio_features = {
		"tempo": float(data.get("tempo", 120.0)),
		"energy": float(data.get("energy", 0.5)),
		"valence": float(data.get("valence", 0.5)),
		"danceability": float(data.get("danceability", 0.5)),
		"key": int(data.get("key", 0)),
	}
	_apply_features_to_drive()
	if not _track_meta.is_empty():
		emit_signal("track_changed", _track_meta.duplicate())


func _apply_features_to_drive() -> void:
	_drive.tempo = float(_audio_features.get("tempo", 120.0))
	_drive.valence = float(_audio_features.get("valence", 0.5))
	_drive.danceability = float(_audio_features.get("danceability", 0.5))
	_drive.energy = lerpf(float(_drive.energy), float(_audio_features.get("energy", 0.5)), 0.35)


func _on_preview_downloaded(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
		emit_signal("status_message", "Preview download failed (HTTP %d)." % code, true)
		return
	var stream := AudioStreamMP3.new()
	stream.data = body
	_phase_beats = 0.0
	_last_serial_snap = -1
	_player.stream = stream
	_player.play()
	emit_signal("track_changed", _track_meta.duplicate())
	emit_signal("status_message",
		"♪ %s — %.0f BPM, tank synced to beat." % [_track_meta.name, float(_drive.tempo)], false)
	_emit_sync_state()


func _parse_spotify_id(raw: String) -> String:
	if raw.is_empty():
		return ""
	if raw.begins_with("spotify:track:"):
		return raw.substr("spotify:track:".length())
	var marker := "/track/"
	var idx: int = raw.find(marker)
	if idx >= 0:
		var tail: String = raw.substr(idx + marker.length())
		var q: int = tail.find("?")
		if q >= 0:
			tail = tail.substr(0, q)
		return tail.strip_edges()
	return ""


func _norm_mag(v: float) -> float:
	return clampf(log(maxf(v, 1e-7)) * 0.22 + 0.55, 0.0, 1.0)


func _norm_band(v: float, band: String, dt: float) -> float:
	var peak: float = float(_band_peak.get(band, 0.004))
	peak = maxf(v, peak * exp(-dt * 1.6))
	_band_peak[band] = peak
	var rel: float = v / maxf(peak, 1e-6)
	return clampf(sqrt(rel) * 0.92 + rel * 0.08, 0.0, 1.0)


func _beat_phase() -> float:
	var lat: float = session_latency_ms() / 1000.0
	return fposmod(_phase_beats + lat * float(_drive.tempo) / 60.0, 1.0)


func _update_music_clock(dt: float) -> void:
	var tempo: float = maxf(float(_drive.tempo), 72.0)
	_phase_beats += dt * tempo / 60.0
	if float(_drive.beat) > 0.75 and _beat_serial != _last_serial_snap:
		_last_serial_snap = _beat_serial
		_phase_beats = floorf(_phase_beats + 0.5)
		_clock_confidence = minf(1.0, _clock_confidence + 0.1)
	_drop_detect_until = maxf(0.0, _drop_detect_until - dt)


func _detect_drop(combined: float, _dt: float) -> void:
	if combined > _prev_energy_peak * 1.26 + 0.14 and _energy_smooth > 0.38:
		_drop_detect_until = 0.45
		var mc := get_node_or_null("/root/MusicContext")
		if mc != null and mc.has_method("notify_drop_pulse"):
			mc.notify_drop_pulse()
	_prev_energy_peak = lerpf(_prev_energy_peak, combined, 0.12)


func _phrase_from_bar(bar_count: int) -> Dictionary:
	var cycle: int = bar_count % 32
	if cycle < 12:
		return {"phrase_state": "verse", "phrase_progress": float(cycle % 4) / 4.0}
	if cycle < 16:
		return {"phrase_state": "build", "phrase_progress": float(cycle - 12) / 4.0}
	if cycle < 24:
		return {"phrase_state": "drop", "phrase_progress": float(cycle - 16) / 8.0}
	if cycle < 28:
		return {"phrase_state": "breakdown", "phrase_progress": float(cycle - 24) / 4.0}
	return {"phrase_state": "chorus", "phrase_progress": float(cycle - 28) / 4.0}


func _emit_sync_state() -> void:
	emit_signal("sync_state_changed", is_active())
