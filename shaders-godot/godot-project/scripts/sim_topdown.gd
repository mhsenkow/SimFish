class_name SimTopdown
extends RefCounted

# TOPDOWN §D/E flock + sync-turn state extracted from sim_driver.gd (#4 strangler-fig).
# SimDriver owns one instance and delegates; fish/world read via SimDriver public API.

var sync_turn_remaining: float = 0.0
var sync_turn_dir: Vector3 = Vector3(1.0, 0.0, 0.0)
var sync_turn_origin: Vector3 = Vector3.ZERO
var sync_turn_flip: int = 0
var sync_polarization: float = 0.0
var startle_bolt_remaining: float = 0.0
var startle_bolt_origin: Vector3 = Vector3.ZERO
var sync_settle: float = 0.0
var group_reversal_timer: float = 12.0
var edge_turn_cooldown: float = 0.0
var flip_cascade_left: int = 0
var was_sync_turn: bool = false
var density_wave_radius: float = 0.0
var density_wave_origin: Vector3 = Vector3.ZERO
var density_wave_strength: float = 0.0
var flock_orbit_phase: float = 0.0
var conduct_center: Vector3 = Vector3.ZERO
var conduct_radius: float = 0.0
var conduct_until: float = 0.0
var predator_wave_cd: float = 0.0
var startle_bolt_was: bool = false


func pulse_startle_bolt(origin: Vector3) -> void:
	startle_bolt_origin = origin
	startle_bolt_remaining = 0.62
	sync_settle = 0.0


func startle_bolt_active() -> bool:
	return startle_bolt_remaining > 0.0


func pulse_sync_turn(dir: Vector3 = Vector3.ZERO, origin: Vector3 = Vector3.ZERO) -> void:
	if dir.length_squared() < 1e-4:
		sync_turn_flip += 1
		dir = Vector3(1.0 if sync_turn_flip % 2 == 0 else -1.0, 0.0, 0.0)
	sync_turn_dir = dir.normalized()
	sync_turn_origin = origin
	sync_turn_remaining = 0.52
	sync_polarization = 0.0


func sync_turn_heading_for(fish_pos: Vector3, instance_id: int) -> Vector3:
	if sync_turn_remaining <= 0.0:
		return Vector3.ZERO
	var dist: float = Vector2(
		fish_pos.x - sync_turn_origin.x, fish_pos.z - sync_turn_origin.z).length()
	var delay: float = dist * 0.085 + float(instance_id % 17) * 0.004
	var phase: float = clampf(1.0 - delay / maxf(sync_turn_remaining + 0.08, 0.12), 0.0, 1.0)
	if phase <= 0.02:
		return Vector3.ZERO
	var perp := Vector3(-sync_turn_dir.z, 0.0, sync_turn_dir.x)
	return perp * phase * 0.95


func sync_turn_active() -> bool:
	return sync_turn_remaining > 0.0


func pulse_density_wave(origin: Vector3, strength: float = 1.0) -> void:
	density_wave_origin = origin
	density_wave_radius = 0.0
	density_wave_strength = clampf(strength, 0.0, 1.5)


func density_wave_push_at(pos: Vector3) -> Vector3:
	if density_wave_strength <= 0.01:
		return Vector3.ZERO
	var away: Vector3 = pos - density_wave_origin
	away.y = 0.0
	var dist: float = away.length()
	var push_amt: float = TopdownMotion.density_wave_sep_push(
		dist, density_wave_radius, density_wave_strength)
	if push_amt <= 0.01 or away.length_squared() < 1e-4:
		return Vector3.ZERO
	return away.normalized() * push_amt


func flock_split_pull(instance_id: int, pos: Vector3) -> Vector3:
	var centers: Array = TopdownMotion.flock_split_centers(flock_orbit_phase, 8.0)
	var half: int = instance_id % 2
	var target: Vector3 = centers[half]
	var d: Vector3 = target - pos
	d.y = 0.0
	if d.length_squared() < 0.08:
		return Vector3.ZERO
	return d.normalized() * sin(flock_orbit_phase) * 0.35


func set_conduct_anchor(center: Vector3, radius: float, duration: float = 8.0) -> void:
	conduct_center = center
	conduct_radius = maxf(radius, 0.5)
	conduct_until = duration


func conduct_anchor_pull(pos: Vector3) -> Vector3:
	if conduct_until <= 0.0:
		return Vector3.ZERO
	var d: Vector3 = conduct_center - pos
	d.y = 0.0
	if d.length_squared() < 0.06:
		return Vector3.ZERO
	return d.normalized() * clampf(conduct_radius * 0.22, 0.12, 0.85)


func register_sync_alignment(strength: float) -> void:
	sync_polarization = lerpf(sync_polarization, clampf(strength, 0.0, 1.0), 0.18)


func pulse_predator_wave(origin: Vector3, away: Vector3) -> void:
	if predator_wave_cd > 0.0:
		return
	predator_wave_cd = 1.4
	if away.length_squared() < 1e-4:
		away = Vector3(1.0, 0.0, 0.0)
	pulse_sync_turn(away, origin)
	pulse_density_wave(origin, 0.9)


static func wake_count(sim: SimDriver) -> int:
	var n: int = 0
	var surface_y: float = 6.0
	if sim.world != null and sim.world.get("WATER_HEIGHT") != null:
		surface_y = float(sim.world.WATER_HEIGHT)
	for f in sim.fish:
		if not is_instance_valid(f) or f.get("_dying") == true:
			continue
		if float(f.get("speed") if f.get("speed") != null else 0.0) < 0.25:
			continue
		if absf(f.position.y - surface_y) < 1.1:
			n += 1
	return n


static func caustic_beat_pulse() -> float:
	var down: bool = false
	var bass: float = 0.0
	var energy: float = 0.0
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree:
		var mc: Node = (ml as SceneTree).root.get_node_or_null("MusicContext")
		if mc != null and mc.get("_ctx") is Dictionary:
			var ctx: Dictionary = mc._ctx
			down = bool(ctx.get("downbeat", false))
			bass = float(ctx.get("bass", 0.0))
			energy = float(ctx.get("energy", 0.0))
	return TopdownMotion.caustic_beat_pulse(down, bass, energy)


static func motion_energy(sim: SimDriver) -> float:
	var sum: float = 0.0
	var n: int = 0
	for f in sim.fish:
		if not is_instance_valid(f) or f.get("_dying") == true:
			continue
		var spd: float = float(f.get("speed") if f.get("speed") != null else 0.0)
		var burst: float = float(f.get("burst_remaining") if f.get("burst_remaining") != null else 0.0)
		sum += spd + burst * 0.35
		n += 1
	if n <= 0:
		return 0.0
	return clampf(sum / float(n) / 2.4, 0.0, 1.0)


static func tank_stress(sim: SimDriver) -> float:
	var sum: float = 0.0
	var n: int = 0
	for f in sim.fish:
		if not is_instance_valid(f) or f.get("_dying") == true:
			continue
		sum += float(f.get("stress") if f.get("stress") != null else 0.0)
		n += 1
	var fish_stress: float = sum / maxf(float(n), 1.0)
	var chem_stress: float = 0.0
	if sim.water_chemistry != null:
		chem_stress = clampf(float(sim.water_chemistry.ammonia) * 0.9
				+ float(sim.water_chemistry.nitrite) * 0.7, 0.0, 1.0)
	return clampf(fish_stress * 0.65 + chem_stress * 0.35, 0.0, 1.0)


static func cycle_ok(sim: SimDriver) -> bool:
	if sim.water_chemistry == null:
		return true
	return float(sim.water_chemistry.ammonia) < 0.35 \
			and float(sim.water_chemistry.nitrite) < 0.4 \
			and float(sim.water_chemistry.bacteria_colony) > 0.12


func shadow_flash(sim: SimDriver) -> float:
	var flash: float = 0.0
	if sync_turn_active():
		flash = TopdownMotion.shadow_flash_strength(0.85, sync_polarization)
	for f in sim.fish:
		if not is_instance_valid(f):
			continue
		var sf_v: Variant = f.get("_silver_flash")
		if sf_v != null:
			flash = maxf(flash, TopdownMotion.shadow_flash_strength(float(sf_v), sync_polarization))
	return flash


func tick(sim: SimDriver, dt: float, school_pulse_phase: float) -> void:
	if sync_turn_remaining > 0.0:
		sync_turn_remaining = maxf(0.0, sync_turn_remaining - dt)
		sync_settle = TopdownMotion.sync_settle_tightness(sync_turn_remaining, 0.52)
		was_sync_turn = true
		if sync_turn_remaining <= 0.0:
			if sync_polarization > 0.62 and flip_cascade_left < 1:
				flip_cascade_left = 1
			sync_polarization = lerpf(sync_polarization, 0.0, 0.35)
	elif was_sync_turn:
		was_sync_turn = false
	_tick_flock_events(sim, dt, school_pulse_phase)
	if startle_bolt_remaining > 0.0:
		startle_bolt_remaining = maxf(0.0, startle_bolt_remaining - dt)
		startle_bolt_was = true
	elif startle_bolt_was:
		startle_bolt_was = false
		pulse_density_wave(startle_bolt_origin, 1.0)
	if density_wave_strength > 0.01:
		density_wave_radius += dt * 4.2
		density_wave_strength = maxf(0.0, density_wave_strength - dt * 0.38)
	flock_orbit_phase += dt * 0.065
	conduct_until = maxf(0.0, conduct_until - dt)
	predator_wave_cd = maxf(0.0, predator_wave_cd - dt)


func _tick_flock_events(sim: SimDriver, dt: float, school_pulse_phase: float) -> void:
	var active: bool = TopdownMotion.pond_active
	if sim.world != null and sim.world.has_method("_topdown_surface_active"):
		active = active or sim.world._topdown_surface_active()
	if not active:
		return
	group_reversal_timer -= dt
	edge_turn_cooldown -= dt
	if flip_cascade_left > 0 and sync_turn_remaining <= 0.0 and startle_bolt_remaining <= 0.0:
		flip_cascade_left -= 1
		pulse_sync_turn()
		return
	if group_reversal_timer <= 0.0 and sim.fish.size() >= 4 and sync_turn_remaining <= 0.0:
		if sin(school_pulse_phase) > 0.94:
			group_reversal_timer = randf_range(16.0, 26.0)
			pulse_sync_turn(Vector3.ZERO, _school_centroid(sim))
	if edge_turn_cooldown > 0.0:
		return
	var hw: float = 8.0
	var hd: float = 4.0
	if sim.world != null:
		if sim.world.get("TANK_HALF_W") != null:
			hw = float(sim.world.TANK_HALF_W)
		if sim.world.get("TANK_HALF_D") != null:
			hd = float(sim.world.TANK_HALF_D)
	var edge_n: int = 0
	var edge_origin := Vector3.ZERO
	for f in sim.fish:
		if not is_instance_valid(f) or f.get("_dying") == true:
			continue
		var p: Vector3 = f.position
		if absf(p.x) > hw * 0.78 or absf(p.z) > hd * 0.78:
			edge_n += 1
			edge_origin += p
	if edge_n >= 3:
		edge_origin /= float(edge_n)
		var away := Vector3(-signf(edge_origin.x), 0.0, -signf(edge_origin.z))
		if away.length_squared() < 0.01:
			away = Vector3(1.0, 0.0, 0.0)
		pulse_sync_turn(away, edge_origin)
		pulse_density_wave(edge_origin, 0.55)
		edge_turn_cooldown = 2.8
	if predator_wave_cd <= 0.0 and sim.fish.size() >= 3:
		for pf in sim.fish:
			if not is_instance_valid(pf) or pf.get("_dying") == true:
				continue
			if float(pf.get("growth_factor") if pf.get("growth_factor") != null else 1.0) < 1.22:
				continue
			var prey_n: int = 0
			var flee := Vector3.ZERO
			for f in sim.fish:
				if f == pf or not is_instance_valid(f) or f.get("_dying") == true:
					continue
				var sp: String = String(
					f.get("swim_pattern") if f.get("swim_pattern") != null else "")
				if sp not in ["school", "shoal"]:
					continue
				var d2: float = pf.position.distance_squared_to(f.position)
				if d2 < 9.0 and d2 > 0.12:
					prey_n += 1
					flee += (f.position - pf.position).normalized()
			if prey_n >= 2 and flee.length_squared() > 0.01:
				pulse_predator_wave(pf.position, flee.normalized())
				return


static func _school_centroid(sim: SimDriver) -> Vector3:
	if sim.fish.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	var n: int = 0
	for f in sim.fish:
		if not is_instance_valid(f) or f.get("_dying") == true:
			continue
		sum += f.position
		n += 1
	if n <= 0:
		return Vector3.ZERO
	sum /= float(n)
	sum.y = 0.0
	return sum
