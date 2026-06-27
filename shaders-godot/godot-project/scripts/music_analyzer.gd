# Lightweight on-device music analysis from spectrum bands.
# Beat/tempo (#26), multi-band onsets (#27), sections (#28), key (#30), timbre (#35).
class_name MusicAnalyzer
extends RefCounted

const CHROMA_BANDS: Array = [
	[32.7, 65.4], [65.4, 130.8], [130.8, 196.0], [196.0, 261.6],
	[261.6, 329.6], [329.6, 392.0], [392.0, 493.9], [493.9, 587.3],
	[587.3, 659.3], [659.3, 783.9], [783.9, 987.8], [987.8, 1318.5],
]

var _bass_prev: float = 0.0
var _mid_prev: float = 0.0
var _high_prev: float = 0.0

var _ioi_samples: Array[float] = []
var _last_onset_t: float = -1.0
var _time: float = 0.0
var _phase_beats: float = 0.0
var _estimated_bpm: float = 120.0
var _confidence: float = 0.35

var _kick_pulse: float = 0.0
var _snare_pulse: float = 0.0
var _hat_pulse: float = 0.0

var _chroma: Array[float] = []
var _detected_key: int = 0
var _detected_mode: String = "major"

var _section: String = "verse"
var _section_bar: int = 0
var _bar_energy_avg: float = 0.0
var _prev_section_energy: float = 0.0
var _build_ramp: float = 0.0

var _centroid: float = 0.5
var _rolloff: float = 0.5
var _brightness: float = 0.5


func _init() -> void:
	_chroma.resize(12)
	for i in 12:
		_chroma[i] = 0.0


func reset() -> void:
	_bass_prev = 0.0
	_mid_prev = 0.0
	_high_prev = 0.0
	_ioi_samples.clear()
	_last_onset_t = -1.0
	_time = 0.0
	_phase_beats = 0.0
	_estimated_bpm = 120.0
	_confidence = 0.35
	_section = "verse"
	_build_ramp = 0.0


func analyze(
	spectrum: AudioEffectSpectrumAnalyzerInstance,
	dt: float,
	bass: float,
	mid: float,
	high: float,
	combined: float,
	seed_tempo: float = 120.0,
) -> Dictionary:
	_time += dt
	var mode := AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX

	var bass_flux: float = maxf(0.0, bass - _bass_prev)
	var mid_flux: float = maxf(0.0, mid - _mid_prev)
	var high_flux: float = maxf(0.0, high - _high_prev)
	_bass_prev = bass
	_mid_prev = mid
	_high_prev = high

	_kick_pulse = maxf(0.0, _kick_pulse - dt * 4.5)
	_snare_pulse = maxf(0.0, _snare_pulse - dt * 5.0)
	_hat_pulse = maxf(0.0, _hat_pulse - dt * 6.5)
	if bass_flux > 0.08 and bass > 0.12:
		_kick_pulse = 1.0
		_register_onset(dt)
	if mid_flux > 0.07 and mid > 0.14:
		_snare_pulse = maxf(_snare_pulse, 0.85)
	if high_flux > 0.06 and high > 0.1:
		_hat_pulse = maxf(_hat_pulse, 0.7)

	_update_tempo(dt, seed_tempo)
	_update_chroma(spectrum, mode)
	_update_timbre(spectrum, mode, bass, mid, high, combined)
	_update_section(combined, dt)

	var beat_phase: float = fposmod(_phase_beats, 1.0)
	var bar_phase: float = fposmod(_phase_beats / 4.0, 1.0)
	var bar_count: int = maxi(0, int(_phase_beats / 4.0))

	var phrase_state: String = _section
	if _build_ramp > 0.55 and _section != "drop":
		phrase_state = "build"
	if _kick_pulse > 0.7 and combined > 0.55 and _build_ramp > 0.35:
		phrase_state = "drop"

	return {
		"beat_phase": beat_phase,
		"bar_phase": bar_phase,
		"bar_count": bar_count,
		"downbeat": beat_phase < 0.07,
		"tempo": _estimated_bpm,
		"confidence": _confidence,
		"phrase_state": phrase_state,
		"section": _section,
		"phrase_progress": bar_phase,
		"key": _detected_key,
		"mode": _detected_mode,
		"centroid": _centroid,
		"rolloff": _rolloff,
		"brightness": _brightness,
		"build_ramp": _build_ramp,
		"drop_detected": phrase_state == "drop" and _kick_pulse > 0.6,
		"onsets": [
			{"band": "kick", "strength": _kick_pulse},
			{"band": "snare", "strength": _snare_pulse},
			{"band": "hat", "strength": _hat_pulse},
		],
	}


func _register_onset(_dt: float) -> void:
	if _last_onset_t >= 0.0:
		var ioi: float = _time - _last_onset_t
		if ioi > 0.22 and ioi < 2.0:
			_ioi_samples.append(ioi)
			while _ioi_samples.size() > 16:
				_ioi_samples.pop_front()
	if _ioi_samples.size() >= 4:
		var sorted: Array = _ioi_samples.duplicate()
		sorted.sort()
		var mid_idx: int = sorted.size() >> 1
		var median_ioi: float = float(sorted[mid_idx])
		var bpm_from_ioi: float = clampf(60.0 / median_ioi, 72.0, 190.0)
		_estimated_bpm = lerpf(_estimated_bpm, bpm_from_ioi, 0.18)
		_confidence = clampf(_confidence + 0.04, 0.0, 1.0)
	_last_onset_t = _time
	var nearest: float = roundf(_phase_beats)
	_phase_beats = lerpf(_phase_beats, nearest, 0.35)


func _update_tempo(dt: float, seed_tempo: float) -> void:
	_phase_beats += dt * _estimated_bpm / 60.0
	if _ioi_samples.is_empty():
		_estimated_bpm = lerpf(_estimated_bpm, seed_tempo, dt * 0.5)


func _update_chroma(spectrum: AudioEffectSpectrumAnalyzerInstance, mode: int) -> void:
	if spectrum == null:
		return
	var total: float = 0.0
	for i in 12:
		var lo: float = float(CHROMA_BANDS[i][0])
		var hi: float = float(CHROMA_BANDS[i][1])
		var mag: float = spectrum.get_magnitude_for_frequency_range(lo, hi, mode).length()
		_chroma[i] = lerpf(float(_chroma[i]), mag, 0.22)
		total += _chroma[i]
	if total < 1e-6:
		return
	var best: int = 0
	var best_v: float = 0.0
	for i in 12:
		var v: float = float(_chroma[i]) / total
		if v > best_v:
			best_v = v
			best = i
	_detected_key = best
	var major_triad: float = float(_chroma[best]) + float(_chroma[(best + 4) % 12]) + float(_chroma[(best + 7) % 12])
	var minor_triad: float = float(_chroma[best]) + float(_chroma[(best + 3) % 12]) + float(_chroma[(best + 7) % 12])
	_detected_mode = "minor" if minor_triad > major_triad * 1.05 else "major"


func _update_timbre(
	spectrum: AudioEffectSpectrumAnalyzerInstance,
	mode: int,
	bass: float,
	mid: float,
	high: float,
	combined: float,
) -> void:
	var low_e: float = bass
	var mid_e: float = mid
	var high_e: float = high
	var denom: float = maxf(low_e + mid_e + high_e, 0.001)
	var centroid_raw: float = (low_e * 0.15 + mid_e * 0.5 + high_e * 0.95) / denom
	_centroid = lerpf(_centroid, centroid_raw, 0.12)
	var rolloff_raw: float = high_e / denom
	_rolloff = lerpf(_rolloff, rolloff_raw, 0.1)
	_brightness = lerpf(_brightness, clampf(combined * 0.65 + _centroid * 0.35, 0.0, 1.0), 0.08)
	if spectrum != null:
		var air: float = spectrum.get_magnitude_for_frequency_range(8000.0, 14000.0, mode).length()
		_rolloff = lerpf(_rolloff, clampf(air * 2.2, 0.0, 1.0), 0.06)


func _update_section(combined: float, dt: float) -> void:
	_bar_energy_avg = lerpf(_bar_energy_avg, combined, 0.04)
	_build_ramp = lerpf(_build_ramp, maxf(0.0, _bar_energy_avg - _prev_section_energy), dt * 0.8)
	_section_bar += 1
	if _section_bar >= 16:
		_section_bar = 0
		var delta: float = _bar_energy_avg - _prev_section_energy
		if delta > 0.12:
			_section = "chorus"
		elif delta < -0.1:
			_section = "breakdown"
		elif _bar_energy_avg < 0.28:
			_section = "verse"
		_prev_section_energy = _bar_energy_avg
