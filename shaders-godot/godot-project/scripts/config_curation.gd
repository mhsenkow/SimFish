class_name ConfigCuration
extends RefCounted

# Curation layer over TankConfig (BROAD_DIRECTIONS #18).
#
# TankConfig declares 284 properties and settings_panel.gd runs 85 functions
# over ~46 rows — an expert console bolted to an ambient toy.
#
# THE REFRAME. The count is misleading, and that is the actual problem:
# three different kinds of thing share one bag, so nobody can tell how many
# knobs there really are.
#
#   27  persisted STATE      camera_yaw, tutorial_seen, last_quit_unix —
#                            saved values, never settings
#    5  INTERNAL             _save_timer and friends
#   19  EXPERT / debug       palette_count_debug, mind_brain_threads
#   72  music                a whole synth mixing desk, one subsystem
#  161  everything else      the actual player-facing surface
#
# So this does not remove anything — it classifies. A UI can then show 19
# essentials by default and reveal the rest on request, and "how many knobs
# does this game have?" becomes an answerable question.
#
# THE GATE THAT MAKES IT STICK. `smoke_config_curation.gd` asserts that
# EVERY property on TankConfig appears in MANIFEST. Add a knob without
# triaging it and the build goes red. Without that, 284 quietly becomes 400
# and the curation rots — which is how it got to 284 in the first place.

# Tiers, coarsest first. A UI shows everything at or below the chosen tier.
enum {
	TIER_ESSENTIAL,   # first-session surface; 19 of them
	TIER_COMMON,      # a returning player will want these
	TIER_ADVANCED,    # deep tuning: the synth desk, render internals
	TIER_EXPERT,      # debug overlays, endpoints, thread counts
	TIER_STATE,       # NOT a setting: persisted state that happens to live here
	TIER_INTERNAL,    # NOT a setting: save bookkeeping
}

const TIER_NAMES: Array[String] = [
	"Essential", "Common", "Advanced", "Expert", "State", "Internal",
]

# Tiers a settings UI should ever offer. STATE/INTERNAL are excluded by
# construction — showing them would let a player edit save bookkeeping.
const UI_TIERS: Array[int] = [TIER_ESSENTIAL, TIER_COMMON, TIER_ADVANCED, TIER_EXPERT]

# The three modes a settings screen can run in, and which tiers each shows.
const MODE_SIMPLE := "simple"
const MODE_ADVANCED := "advanced"
const MODE_EXPERT := "expert"

const MODE_TIERS: Dictionary = {
	MODE_SIMPLE: [TIER_ESSENTIAL],
	MODE_ADVANCED: [TIER_ESSENTIAL, TIER_COMMON, TIER_ADVANCED],
	MODE_EXPERT: [TIER_ESSENTIAL, TIER_COMMON, TIER_ADVANCED, TIER_EXPERT],
}

# Domain display order, so a generated UI groups sensibly instead of
# alphabetically.
const DOMAIN_ORDER: Array[String] = [
	"tank", "water", "population", "lighting", "flora", "fauna",
	"render", "camera", "photo", "music", "mind", "accessibility",
	"performance", "onboarding", "misc", "internal",
]

# property -> [tier, domain]. Generated from TankConfig and then hand-tuned;
# the smoke keeps it in step.
const MANIFEST: Dictionary = {
	"render_width": [TIER_EXPERT, "misc"],
	"render_height": [TIER_EXPERT, "misc"],
	"dither_strength": [TIER_ADVANCED, "render"],
	"water_extinction": [TIER_COMMON, "water"],
	"dither_region_aware": [TIER_ADVANCED, "render"],
	"dither_world_lock": [TIER_ADVANCED, "render"],
	"blue_noise_amount": [TIER_ADVANCED, "render"],
	"room_dither_scale": [TIER_ADVANCED, "render"],
	"reduced_motion": [TIER_ESSENTIAL, "accessibility"],
	"ui_font_scale": [TIER_ESSENTIAL, "accessibility"],
	"shader_perf_tier": [TIER_ADVANCED, "render"],
	"palette_bank_lock": [TIER_ADVANCED, "render"],
	"outline_strength": [TIER_ADVANCED, "render"],
	"creature_outline_strength": [TIER_ADVANCED, "render"],
	"crt_strength": [TIER_ADVANCED, "render"],
	"integer_upscale": [TIER_ADVANCED, "render"],
	"spark_expression_enabled": [TIER_COMMON, "mind"],
	"inner_life_panel": [TIER_COMMON, "mind"],
	"perf_hud_enabled": [TIER_EXPERT, "misc"],
	"adaptive_quality": [TIER_ADVANCED, "render"],
	"adaptive_quality_target_fps": [TIER_ADVANCED, "render"],
	"pixel_snap_camera": [TIER_ADVANCED, "render"],
	"follow_depth_of_field": [TIER_ADVANCED, "camera"],
	"follow_dof_blur_strength": [TIER_ADVANCED, "camera"],
	"follow_dof_far_softness": [TIER_ADVANCED, "camera"],
	"follow_dof_near_softness": [TIER_ADVANCED, "camera"],
	"follow_dof_focus_margin": [TIER_ADVANCED, "camera"],
	"follow_dof_near_enabled": [TIER_ADVANCED, "camera"],
	"tank_room_dof": [TIER_COMMON, "tank"],
	"tank_room_dof_blur": [TIER_COMMON, "tank"],
	"palette_count_debug": [TIER_EXPERT, "render"],
	"palette_enabled": [TIER_ADVANCED, "render"],
	"experimental_visuals": [TIER_EXPERT, "misc"],
	"pixel_purity": [TIER_ADVANCED, "render"],
	"colorblind_palette": [TIER_ESSENTIAL, "accessibility"],
	"beauty_defaults_applied": [TIER_STATE, "render"],
	"film_grain_strength": [TIER_ADVANCED, "render"],
	"selective_glow_strength": [TIER_ADVANCED, "render"],
	"crt_mode": [TIER_ADVANCED, "render"],
	"photo_mode_enhanced": [TIER_ADVANCED, "photo"],
	"photo_handheld": [TIER_ADVANCED, "photo"],
	"photo_horizon_roll_deg": [TIER_ADVANCED, "photo"],
	"photo_macro_mode": [TIER_ADVANCED, "photo"],
	"photo_sensor_noise": [TIER_ADVANCED, "photo"],
	"equipment_in_frame": [TIER_ADVANCED, "photo"],
	"pop_cap_pressure_scale": [TIER_COMMON, "population"],
	"start_matured": [TIER_COMMON, "tank"],
	"cycle_start_mode": [TIER_COMMON, "tank"],
	"plant_youth_scale": [TIER_ADVANCED, "flora"],
	"debug_growth_logging": [TIER_EXPERT, "misc"],
	"plant_limit_overlay": [TIER_EXPERT, "flora"],
	"fog_density": [TIER_ADVANCED, "render"],
	"fog_anisotropy": [TIER_ADVANCED, "render"],
	"fog_ambient_inject": [TIER_ADVANCED, "render"],
	"material_hue_shift": [TIER_ADVANCED, "render"],
	"material_saturation": [TIER_ADVANCED, "render"],
	"material_warmth": [TIER_ADVANCED, "render"],
	"material_value": [TIER_ADVANCED, "render"],
	"material_weight_fauna": [TIER_ADVANCED, "render"],
	"material_weight_foliage": [TIER_ADVANCED, "render"],
	"material_weight_substrate": [TIER_ADVANCED, "render"],
	"material_weight_hardscape": [TIER_ADVANCED, "render"],
	"material_weight_water": [TIER_ADVANCED, "render"],
	"camera_fov": [TIER_ADVANCED, "camera"],
	"msaa": [TIER_ADVANCED, "render"],
	"display_fxaa": [TIER_ADVANCED, "render"],
	"display_deband": [TIER_ADVANCED, "render"],
	"camera_yaw": [TIER_STATE, "camera"],
	"camera_pitch": [TIER_STATE, "camera"],
	"camera_radius": [TIER_STATE, "camera"],
	"camera_target_x": [TIER_STATE, "camera"],
	"camera_target_y": [TIER_STATE, "camera"],
	"camera_target_z": [TIER_STATE, "camera"],
	"camera_state_saved": [TIER_STATE, "camera"],
	"camera_view_slot_a": [TIER_STATE, "camera"],
	"camera_view_slot_b": [TIER_STATE, "camera"],
	"camera_view_slot_c": [TIER_STATE, "camera"],
	"fps_cap": [TIER_ESSENTIAL, "performance"],
	"battery_saver": [TIER_ESSENTIAL, "performance"],
	"device_tier": [TIER_STATE, "performance"],
	"tutorial_seen": [TIER_STATE, "onboarding"],
	"walkthrough_pending": [TIER_STATE, "onboarding"],
	"aquascape_pending": [TIER_STATE, "misc"],
	"walkthrough_step": [TIER_STATE, "onboarding"],
	"walkthrough_completed": [TIER_STATE, "onboarding"],
	"walkthrough_scenario_preset": [TIER_STATE, "onboarding"],
	"last_quit_unix": [TIER_STATE, "onboarding"],
	"light_spectrum": [TIER_ADVANCED, "lighting"],
	"co2_level": [TIER_COMMON, "water"],
	"ai_enabled": [TIER_ESSENTIAL, "mind"],
	"ai_endpoint": [TIER_EXPERT, "mind"],
	"ai_model": [TIER_EXPERT, "mind"],
	"ai_naming_theme": [TIER_COMMON, "mind"],
	"ai_chronicle": [TIER_COMMON, "mind"],
	"ai_onboarding_seen": [TIER_STATE, "mind"],
	"ai_embedded_enabled": [TIER_COMMON, "mind"],
	"ai_embedded_endpoint": [TIER_EXPERT, "mind"],
	"ai_embedded_model": [TIER_EXPERT, "mind"],
	"guardian_voice_enabled": [TIER_ESSENTIAL, "mind"],
	"fish_thought_voice_enabled": [TIER_ADVANCED, "misc"],
	"guardian_custom_gguf_path": [TIER_EXPERT, "mind"],
	"guardian_voice_explainer_seen": [TIER_STATE, "mind"],
	"sentience_voice_off": [TIER_COMMON, "mind"],
	"voice_language": [TIER_COMMON, "mind"],
	"mind_system_version_seen": [TIER_STATE, "mind"],
	"guardian_mind_consent": [TIER_STATE, "mind"],
	"guardian_mind_info_seen": [TIER_STATE, "mind"],
	"consciousness_workspace_enabled": [TIER_COMMON, "mind"],
	"mind_brain_threads": [TIER_EXPERT, "mind"],
	"mind_cadence_hz": [TIER_EXPERT, "mind"],
	"consciousness_writeback_enabled": [TIER_COMMON, "mind"],
	"consciousness_stream_enabled": [TIER_COMMON, "mind"],
	"consciousness_active_inference": [TIER_COMMON, "mind"],
	"episodic_quant_8bit": [TIER_EXPERT, "mind"],
	"felt_self_enabled": [TIER_COMMON, "mind"],
	"delta_g_overlay_enabled": [TIER_EXPERT, "mind"],
	"keeper_ears_enabled": [TIER_COMMON, "mind"],
	"keeper_gaze_enabled": [TIER_COMMON, "mind"],
	"keeper_mic_enabled": [TIER_COMMON, "mind"],
	"tank_shape": [TIER_ESSENTIAL, "tank"],
	"vessel_preset": [TIER_ESSENTIAL, "misc"],
	"tank_half_w": [TIER_COMMON, "tank"],
	"tank_half_d": [TIER_COMMON, "tank"],
	"tank_height": [TIER_COMMON, "tank"],
	"new_tank_fit": [TIER_COMMON, "tank"],
	"water_surface_fraction": [TIER_COMMON, "water"],
	"substrate_depth_fraction": [TIER_COMMON, "tank"],
	"density_budget": [TIER_COMMON, "population"],
	"pop_scale_with_tank": [TIER_ADVANCED, "misc"],
	"pop_cap_fish": [TIER_COMMON, "population"],
	"pop_cap_snail": [TIER_COMMON, "population"],
	"pop_cap_shrimp": [TIER_COMMON, "population"],
	"pop_cap_plant": [TIER_COMMON, "population"],
	"pop_cap_floater": [TIER_COMMON, "population"],
	"pop_cap_microfauna": [TIER_COMMON, "population"],
	"light_energy": [TIER_ESSENTIAL, "lighting"],
	"light_yaw": [TIER_ADVANCED, "lighting"],
	"light_pitch": [TIER_ADVANCED, "lighting"],
	"light_warmth": [TIER_ADVANCED, "lighting"],
	"light_fixture": [TIER_ADVANCED, "lighting"],
	"light_height": [TIER_ADVANCED, "lighting"],
	"light_size": [TIER_ADVANCED, "lighting"],
	"light_volumetric": [TIER_ADVANCED, "lighting"],
	"light_caustics": [TIER_ADVANCED, "lighting"],
	# How grown-in an established tank opens (scripts/plant_establish.gd).
	"plant_establish_scale": [TIER_COMMON, "flora"],
	"music_simple_bed": [TIER_ADVANCED, "music"],
	# Aimable spot rig (scripts/lighting_rig.gd). room_darkness is COMMON
	# because "make the room dark" is a look a player reaches for directly;
	# the cone geometry underneath it is ADVANCED because it is normally set
	# by picking a lighting preset, not by hand.
	"room_darkness": [TIER_COMMON, "lighting"],
	"spot_angle_deg": [TIER_ADVANCED, "lighting"],
	"spot_attenuation": [TIER_ADVANCED, "lighting"],
	"spot_offset_x": [TIER_ADVANCED, "lighting"],
	"spot_offset_z": [TIER_ADVANCED, "lighting"],
	"spot_tilt_deg": [TIER_ADVANCED, "lighting"],
	"spot_yaw_deg": [TIER_ADVANCED, "lighting"],
	"spot_aim_x": [TIER_ADVANCED, "lighting"],
	"spot_aim_z": [TIER_ADVANCED, "lighting"],
	"spot_shadows": [TIER_ADVANCED, "lighting"],
	"beam_strength": [TIER_ADVANCED, "lighting"],
	"tank_lights_on": [TIER_COMMON, "tank"],
	"heater_enabled": [TIER_COMMON, "water"],
	"light_master_enabled": [TIER_ESSENTIAL, "lighting"],
	"day_cycle_enabled": [TIER_ESSENTIAL, "misc"],
	"global_intensity": [TIER_ADVANCED, "lighting"],
	"global_warmth": [TIER_ADVANCED, "lighting"],
	"tank_fixture_intensity": [TIER_COMMON, "tank"],
	"tank_fixture_color": [TIER_COMMON, "tank"],
	"day_length_s": [TIER_ADVANCED, "lighting"],
	"sunset_drama": [TIER_ADVANCED, "lighting"],
	"moonlight_enabled": [TIER_ADVANCED, "lighting"],
	"backlight_enabled": [TIER_ADVANCED, "lighting"],
	"backlight_intensity": [TIER_ADVANCED, "lighting"],
	"backlight_color": [TIER_ADVANCED, "lighting"],
	"moonlight_intensity": [TIER_ADVANCED, "lighting"],
	"moonlight_color": [TIER_ADVANCED, "lighting"],
	"accent1_enabled": [TIER_ADVANCED, "lighting"],
	"accent1_intensity": [TIER_ADVANCED, "lighting"],
	"accent1_color": [TIER_ADVANCED, "lighting"],
	"accent2_enabled": [TIER_ADVANCED, "lighting"],
	"accent2_intensity": [TIER_ADVANCED, "lighting"],
	"accent2_color": [TIER_ADVANCED, "lighting"],
	"pp_vignette_strength": [TIER_ADVANCED, "render"],
	"pp_vignette_falloff": [TIER_ADVANCED, "render"],
	"pp_bloom_threshold": [TIER_ADVANCED, "render"],
	"pp_bloom_strength": [TIER_ADVANCED, "render"],
	"ambient_floor": [TIER_ADVANCED, "lighting"],
	"biolum_multiplier": [TIER_ADVANCED, "lighting"],
	"caustic_intensity_user": [TIER_ADVANCED, "lighting"],
	"tod_use_overrides": [TIER_ADVANCED, "lighting"],
	"tod_dawn_color": [TIER_ADVANCED, "lighting"],
	"tod_day_color": [TIER_ADVANCED, "lighting"],
	"tod_dusk_color": [TIER_ADVANCED, "lighting"],
	"tod_night_color": [TIER_ADVANCED, "lighting"],
	"lighting_preset": [TIER_ADVANCED, "lighting"],
	"music_enabled": [TIER_ESSENTIAL, "music"],
	"music_volume": [TIER_ESSENTIAL, "music"],
	"music_complexity": [TIER_ADVANCED, "music"],
	"music_ambient_enabled": [TIER_ADVANCED, "music"],
	"music_events_enabled": [TIER_ADVANCED, "music"],
	"music_environment_enabled": [TIER_ADVANCED, "music"],
	"music_event_volume": [TIER_ADVANCED, "music"],
	"music_reactivity": [TIER_ADVANCED, "music"],
	"music_showiness": [TIER_ADVANCED, "music"],
	"music_dance_style": [TIER_ADVANCED, "music"],
	"music_sync_latency_ms": [TIER_EXPERT, "music"],
	"music_mood": [TIER_ADVANCED, "music"],
	"music_style": [TIER_ADVANCED, "music"],
	"music_energy": [TIER_ADVANCED, "music"],
	"music_coupling_floor": [TIER_ADVANCED, "music"],
	"music_smooth_rate": [TIER_ADVANCED, "music"],
	"music_phrase_churn": [TIER_ADVANCED, "music"],
	"music_tempo_follow": [TIER_ADVANCED, "music"],
	"music_kick_mix": [TIER_ADVANCED, "music"],
	"music_bass_mix": [TIER_ADVANCED, "music"],
	"music_arp_mix": [TIER_ADVANCED, "music"],
	"music_pad_mix": [TIER_ADVANCED, "music"],
	"music_hat_mix": [TIER_ADVANCED, "music"],
	"music_sidechain": [TIER_ADVANCED, "music"],
	"music_filter_open": [TIER_ADVANCED, "music"],
	"music_delay_amount": [TIER_ADVANCED, "music"],
	"music_accent_density": [TIER_ADVANCED, "music"],
	"music_influence_fish": [TIER_ADVANCED, "music"],
	"music_influence_plants": [TIER_ADVANCED, "music"],
	"music_influence_bloom": [TIER_ADVANCED, "music"],
	"music_influence_o2": [TIER_ADVANCED, "music"],
	"music_influence_day": [TIER_ADVANCED, "music"],
	"music_influence_aeration": [TIER_ADVANCED, "music"],
	"music_influence_biomass": [TIER_ADVANCED, "music"],
	"music_seed": [TIER_STATE, "music"],
	"music_phrase_form": [TIER_ADVANCED, "music"],
	"music_scale": [TIER_ADVANCED, "music"],
	"music_persona": [TIER_ADVANCED, "music"],
	"music_drop_intensity": [TIER_ADVANCED, "music"],
	"music_breakdown_depth": [TIER_ADVANCED, "music"],
	"music_lead_mix": [TIER_ADVANCED, "music"],
	"music_lead_detune": [TIER_ADVANCED, "music"],
	"music_vinyl_crackle": [TIER_ADVANCED, "music"],
	"music_tape_wow": [TIER_ADVANCED, "music"],
	"music_jazziness": [TIER_ADVANCED, "music"],
	"music_swing": [TIER_ADVANCED, "music"],
	"music_offbeat_hat": [TIER_ADVANCED, "music"],
	"music_reverb_send": [TIER_ADVANCED, "music"],
	"music_humanize": [TIER_ADVANCED, "music"],
	"music_species_palette": [TIER_ADVANCED, "music"],
	"music_sub_bass_mix": [TIER_ADVANCED, "music"],
	"music_offbeat_bass_mix": [TIER_ADVANCED, "music"],
	"music_granular_pad": [TIER_ADVANCED, "music"],
	"music_vocoder_pad": [TIER_ADVANCED, "music"],
	"music_shaker_mix": [TIER_ADVANCED, "music"],
	"music_clap_mix": [TIER_ADVANCED, "music"],
	"music_build_drama": [TIER_ADVANCED, "music"],
	"music_bitcrush_algae": [TIER_ADVANCED, "music"],
	"music_bass_grit": [TIER_ADVANCED, "music"],
	"music_pump_gate": [TIER_ADVANCED, "music"],
	"music_key_mod": [TIER_ADVANCED, "music"],
	"music_breathe_lfo": [TIER_ADVANCED, "music"],
	"music_sync_enabled": [TIER_ADVANCED, "music"],
	"music_sync_intensity": [TIER_ADVANCED, "music"],
	"music_sync_fish": [TIER_ADVANCED, "music"],
	"music_sync_lights": [TIER_ADVANCED, "music"],
	"music_sync_color": [TIER_ADVANCED, "music"],
	"music_sync_plants": [TIER_ADVANCED, "music"],
	"music_sync_bubbles": [TIER_ADVANCED, "music"],
	"spotify_client_id": [TIER_EXPERT, "music"],
	"spotify_client_secret": [TIER_EXPERT, "music"],
	"music_sync_last_track_id": [TIER_STATE, "music"],
	"environment_preset": [TIER_ADVANCED, "render"],
	"auto_respawn_fauna": [TIER_COMMON, "population"],
	"auto_feed_fauna": [TIER_ESSENTIAL, "population"],
	"guardian_companion_enabled": [TIER_COMMON, "mind"],
	"guardian_may_enable_autofeed": [TIER_COMMON, "mind"],
	"fauna_schooling_mult": [TIER_ADVANCED, "fauna"],
	"fauna_separation_mult": [TIER_ADVANCED, "fauna"],
	"fauna_wander_mult": [TIER_ADVANCED, "fauna"],
	"fauna_speed_mult": [TIER_ADVANCED, "fauna"],
	"fauna_school_pulse_enabled": [TIER_ADVANCED, "fauna"],
	"fauna_school_pulse_amplitude": [TIER_ADVANCED, "fauna"],
	"motion_n_topo": [TIER_ADVANCED, "fauna"],
	"motion_wave_speed": [TIER_ADVANCED, "fauna"],
	"motion_flank_bias": [TIER_ADVANCED, "fauna"],
	"motion_agitation_decay": [TIER_ADVANCED, "fauna"],
	"motion_propagation_blend": [TIER_ADVANCED, "fauna"],
	"fauna_mourning_enabled": [TIER_ADVANCED, "fauna"],
	"fauna_player_glance_enabled": [TIER_ADVANCED, "fauna"],
	"tank_preset": [TIER_ESSENTIAL, "tank"],
	"custom_glassdart_count": [TIER_COMMON, "population"],
	"custom_mudsifter_count": [TIER_COMMON, "population"],
	"custom_shrimp_count": [TIER_COMMON, "population"],
	"aeration_type": [TIER_ESSENTIAL, "water"],
	"aeration_strength": [TIER_ESSENTIAL, "water"],
	"aeration_x_frac": [TIER_COMMON, "water"],
	"smart_air_enabled": [TIER_COMMON, "water"],
	"substrate_type": [TIER_ESSENTIAL, "tank"],
	"locale": [TIER_ESSENTIAL, "accessibility"],
	"settings_mode": [TIER_ESSENTIAL, "accessibility"],
	"rebuild_terrain_on_load": [TIER_STATE, "tank"],
	"_save_timer": [TIER_INTERNAL, "internal"],
	"_save_in_flight": [TIER_INTERNAL, "internal"],
	"_save_queued": [TIER_INTERNAL, "internal"],
	"_settings_batch_depth": [TIER_INTERNAL, "internal"],
	"_save_pending_from_batch": [TIER_INTERNAL, "internal"],
}


# --- Queries ---------------------------------------------------------------

static func tier_of(prop: String) -> int:
	var row: Variant = MANIFEST.get(prop)
	if row == null:
		return TIER_EXPERT   # unknown: hide it rather than show it by default
	return int((row as Array)[0])


static func domain_of(prop: String) -> String:
	var row: Variant = MANIFEST.get(prop)
	if row == null:
		return "misc"
	return String((row as Array)[1])


static func is_curated(prop: String) -> bool:
	return MANIFEST.has(prop)


# True when this property is a real setting a UI may offer, as opposed to
# persisted state or save bookkeeping that merely lives on the same object.
static func is_setting(prop: String) -> bool:
	var t: int = tier_of(prop)
	return t != TIER_STATE and t != TIER_INTERNAL


static func properties_in_tier(tier: int) -> Array[String]:
	var out: Array[String] = []
	for prop in MANIFEST.keys():
		if tier_of(String(prop)) == tier:
			out.append(String(prop))
	out.sort()
	return out


static func properties_in_domain(domain: String) -> Array[String]:
	var out: Array[String] = []
	for prop in MANIFEST.keys():
		if domain_of(String(prop)) == domain:
			out.append(String(prop))
	out.sort()
	return out


# What a settings screen should show in the given mode, grouped by domain in
# DOMAIN_ORDER. Returns domain -> Array[String] of property names.
static func properties_for_mode(mode: String) -> Dictionary:
	var tiers: Array = MODE_TIERS.get(mode, MODE_TIERS[MODE_SIMPLE])
	var grouped: Dictionary = {}
	for prop in MANIFEST.keys():
		var name: String = String(prop)
		if not is_setting(name):
			continue
		if not tiers.has(tier_of(name)):
			continue
		var d: String = domain_of(name)
		if not grouped.has(d):
			grouped[d] = [] as Array[String]
		(grouped[d] as Array[String]).append(name)
	# Order domains, and properties within them.
	var ordered: Dictionary = {}
	for d in DOMAIN_ORDER:
		if grouped.has(d):
			var arr: Array[String] = grouped[d]
			arr.sort()
			ordered[d] = arr
	# Anything with a domain missing from DOMAIN_ORDER still gets shown.
	for d in grouped.keys():
		if not ordered.has(d):
			var arr2: Array[String] = grouped[d]
			arr2.sort()
			ordered[d] = arr2
	return ordered


# Headline counts, for a settings header and for the docs.
static func summary() -> Dictionary:
	var counts: Dictionary = {}
	for t in range(TIER_NAMES.size()):
		counts[TIER_NAMES[t]] = 0
	for prop in MANIFEST.keys():
		var n: String = TIER_NAMES[tier_of(String(prop))]
		counts[n] = int(counts[n]) + 1
	var settings_total: int = 0
	for prop in MANIFEST.keys():
		if is_setting(String(prop)):
			settings_total += 1
	return {
		"total": MANIFEST.size(),
		"settings": settings_total,
		"by_tier": counts,
	}
