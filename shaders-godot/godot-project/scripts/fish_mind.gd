extends RefCounted

# Sentient-fish cognition layer (SENTIENT_FISH_IDEAS.md).
# fish.gd owns state; this module holds affect, deliberation, learning helpers.

const DELIB_MARGIN: float = 0.12
const COMMIT_DWELL: float = 0.35
const COMMIT_HYSTERESIS: float = 0.08

const FOOD_SUB_KEYS: Array = ["flake", "pellet", "worm", "wafer"]


# ---- Affect (#26, #27, #32) ----

static func tick_affect(f: Fish, dt: float) -> void:
	var arousal_target: float = f.stress * 0.55 + f.spooked * 0.45 + f.hunger * 0.25
	arousal_target += clampf(f.mood, 0.0, 1.0) * 0.15
	if f.burst_remaining > 0.0 or f._startle_remaining > 0.0:
		arousal_target += 0.35
	if f.current_mode == Fish.Mode.COURT or f.current_mode == Fish.Mode.SPAWN:
		arousal_target += 0.3
	if f._asleep:
		arousal_target *= 0.2
	else:
		arousal_target += clampf(f.speed * 0.035, 0.0, 0.2)
	f.arousal = lerpf(f.arousal, clampf(arousal_target, 0.0, 1.0), clampf(dt * 0.5, 0.0, 1.0))
	if f.spooked > 0.35:
		f.vigilance = clampf(f.vigilance + dt * 0.8, 0.0, 1.0)
	else:
		f.vigilance = maxf(0.0, f.vigilance - dt * 0.25)
	f._contentment = clampf((f.mood + 1.0) * 0.5 * (1.0 - f.arousal) * (1.0 - f.stress), 0.0, 1.0)


static func emotional_state(f: Fish) -> String:
	var v: float = f.mood
	var a: float = f.arousal
	if f._asleep:
		return "cozy"
	if f.vigilance > 0.55:
		return "anxious"
	if f._contentment > 0.65 and a < 0.35:
		return "content"
	if a > 0.65 and v > 0.2:
		return "excited"
	if a > 0.55 and v < 0.0:
		return "anxious"
	if f.curiosity_drive > 0.55 and a > 0.4:
		return "playful"
	if f.curiosity_drive > 0.65 and a < 0.35:
		return "bored"
	if v < -0.35 and a < 0.4:
		return "sulking"
	if v > 0.15 and a < 0.45:
		return "content"
	return "calm"


static func animation_modifiers(f: Fish) -> Dictionary:
	var v: float = f.mood
	var a: float = f.arousal
	var content: float = clampf(v, 0.0, 1.0)
	var distress: float = clampf(-v, 0.0, 1.0)
	var out: Dictionary = {
		"wag_freq": a * 0.22 - (1.0 - a) * content * 0.10,
		"pec_spread": content * 0.10 + a * 0.12 - distress * 0.06,
		"fin_amp": a * 0.08 - distress * 0.05,
		"breath_calm": (1.0 - a) * content * 0.12,
		"color_flare": a * 0.08,
		"color_pallor": distress * (1.0 - a) * 0.08,
	}
	var st: String = emotional_state(f)
	match st:
		"playful":
			out["wag_freq"] = float(out["wag_freq"]) + 0.08
		"bored":
			out["wag_freq"] = float(out["wag_freq"]) - 0.12
			out["fin_amp"] = float(out["fin_amp"]) - 0.06
		"cozy":
			out["breath_calm"] = float(out["breath_calm"]) + 0.08
			out["wag_freq"] = float(out["wag_freq"]) - 0.06
	var indec: Dictionary = indecision_modifiers(f)
	for k in indec:
		out[k] = indec[k]
	return out


static func nudge_arousal(f: Fish, amount: float) -> void:
	f.arousal = clampf(f.arousal + amount, 0.0, 1.0)


# ---- Deliberation (#10–12) ----

static func personality_commit_speed(f: Fish) -> float:
	return lerpf(0.55, 1.45, f._trait("boldness"))


static func update_conflict(f: Fish, approach: float, avoid: float,
		toward_pos: Vector3, away_from_pos: Vector3) -> void:
	f._delib_approach_pos = toward_pos
	f._delib_avoid_pos = away_from_pos
	var tied: bool = absf(approach - avoid) < DELIB_MARGIN \
		and minf(approach, avoid) > 0.32
	f._delib_active = tied
	if not tied:
		f._delib_phase = 0.0


static func deliberation_steer(f: Fish, dt: float, effective_max: float) -> Vector3:
	if not f._delib_active:
		return Vector3.ZERO
	f._delib_phase += dt * (2.2 + f._trait("curiosity") * 1.8)
	var wave: float = sin(f._delib_phase)
	var to_approach: Vector3 = f._delib_approach_pos - f.position
	var to_retreat: Vector3 = f.position - f._delib_avoid_pos
	if to_approach.length_squared() < 0.04:
		to_approach = f.heading
	if to_retreat.length_squared() < 0.04:
		to_retreat = -f.heading
	to_approach.y *= 0.35
	to_retreat.y *= 0.35
	var blend: Vector3 = to_approach.normalized() * maxf(wave, 0.0) \
		+ to_retreat.normalized() * maxf(-wave, 0.0)
	if blend.length_squared() < 1e-4:
		return Vector3.ZERO
	return blend.normalized() * effective_max * 0.42


static func tick_commitment(f: Fish, dt: float, proposed_mode: int) -> bool:
	if proposed_mode == f._commit_mode:
		f._commit_dwell += dt
		return f._commit_dwell >= COMMIT_DWELL / personality_commit_speed(f)
	var beat: float = COMMIT_HYSTERESIS / personality_commit_speed(f)
	if f._commit_mode >= 0 and f._commit_dwell < beat:
		return false
	f._commit_mode = proposed_mode
	f._commit_dwell = dt
	return false


static func indecision_modifiers(f: Fish) -> Dictionary:
	if not f._delib_active:
		return {}
	var swing: float = sin(f._delib_phase)
	return {
		"gaze_split": swing * 0.38,
		"speed_mult": 0.48,
		"fin_twitch": absf(swing) * 0.14,
		"wag_freq": absf(swing) * 0.06,
	}


static func aim_before_burst(f: Fish) -> void:
	if f._aim_remaining <= 0.0:
		f._aim_remaining = lerpf(0.12, 0.22, 1.0 - f._trait("boldness"))


static func maybe_double_take(f: Fish, curiosity: float) -> void:
	if f._double_take_remaining > 0.0:
		return
	if curiosity > 0.45 and randf() < 0.22:
		f._double_take_remaining = randf_range(0.35, 0.7)


# ---- Memory & learning (#14, #18, #22–25) ----

static func memory_decay_mult(kind: String) -> float:
	match kind:
		"startled", "bullied":
			return 0.55
		"fed", "saw_player":
			return 1.0
		"bred":
			return 0.35
		_:
			return 1.0


static func habituation_decay_rate(f: Fish) -> float:
	# High curiosity → novelty returns slower (stay interested longer).
	return lerpf(1.4, 0.55, f._trait("curiosity"))


static func tick_personality_conditioning(f: Fish, dt: float) -> void:
	if f.personality.is_empty():
		return
	if f.familiarity > 0.35 and f._cached_glance_strength > 0.2:
		f.personality["boldness"] = clampf(
			float(f.personality.get("boldness", 0.5)) + dt * 0.004, 0.05, 1.0)
	if f.spooked > 0.45 or f.stress > 0.75:
		f.personality["boldness"] = clampf(
			float(f.personality.get("boldness", 0.5)) - dt * 0.006, 0.05, 1.0)


static func record_food_preference(f: Fish, subtype: int, satisfaction: float) -> void:
	var key: String = FOOD_SUB_KEYS[clampi(subtype, 0, FOOD_SUB_KEYS.size() - 1)]
	var prev: float = float(f.food_preferences.get(key, 0.5))
	f.food_preferences[key] = clampf(prev + satisfaction * 0.08, 0.0, 1.0)


static func food_preference_mult(f: Fish, subtype: int) -> float:
	var key: String = FOOD_SUB_KEYS[clampi(subtype, 0, FOOD_SUB_KEYS.size() - 1)]
	var pref: float = float(f.food_preferences.get(key, 0.5))
	return lerpf(1.15, 0.82, pref)


static func refresh_patrol_from_heatmap(f: Fish) -> void:
	if f.feed_heatmap.is_empty() or f.maturity != Fish.MATURITY_ADULT:
		return
	var best: Array = []
	var w: Node = f._world_node()
	if w == null:
		return
	var hw: float = float(w.get("TANK_HALF_W") if w.get("TANK_HALF_W") != null else 8.0)
	var hd: float = float(w.get("TANK_HALF_D") if w.get("TANK_HALF_D") != null else 4.0)
	var hh: float = float(w.get("TANK_HEIGHT") if w.get("TANK_HEIGHT") != null else 7.0)
	var sz: int = Fish.FEED_HEATMAP_SIZE
	for ix in range(sz):
		for iy in range(sz):
			for iz in range(sz):
				var idx: int = ix + iy * sz + iz * sz * sz
				var heat: float = float(f.feed_heatmap[idx])
				if heat < 0.18:
					continue
				var pos: Vector3 = Vector3(
					(ix + 0.5) / float(sz) * hw * 2.0 - hw,
					(iy + 0.5) / float(sz) * hh,
					(iz + 0.5) / float(sz) * hd * 2.0 - hd)
				if w.has_method("clamp_xyz_in_tank"):
					pos = w.clamp_xyz_in_tank(pos, 0.5, f._body_tank_margin())
				best.append({"heat": heat, "pos": pos})
	best.sort_custom(func(a, b): return float(a["heat"]) > float(b["heat"]))
	f.patrol_anchors.clear()
	for i in range(mini(3, best.size())):
		f.patrol_anchors.append(best[i]["pos"])


static func tick_home_confidence(f: Fish, dt: float) -> void:
	if f.visited_regions.is_empty():
		return
	var visited: int = 0
	for v in f.visited_regions:
		if int(v) > 0:
			visited += 1
	var explore_frac: float = float(visited) / float(f.visited_regions.size())
	f.home_confidence = lerpf(f.home_confidence, clampf(explore_frac * 1.2, 0.0, 1.0),
		clampf(dt * 0.08, 0.0, 1.0))


static func mind_to_dict(f: Fish) -> Dictionary:
	return {
		"food_preferences": f.food_preferences.duplicate(),
		"home_confidence": f.home_confidence,
		"vigilance": f.vigilance,
	}


static func apply_mind_dict(f: Fish, d: Dictionary) -> void:
	var fp: Variant = d.get("food_preferences", null)
	if fp is Dictionary:
		f.food_preferences = (fp as Dictionary).duplicate()
	f.home_confidence = float(d.get("home_confidence", f.home_confidence))
	f.vigilance = float(d.get("vigilance", f.vigilance))
