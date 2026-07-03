class_name MindCacheRegistry
extends RefCounted

# REFINEMENT_II #7 + #16 — one place to clear transient mind caches on load/reset.

const EpisodicMemory = preload("res://scripts/episodic_memory.gd")


static func reset_transient(f: Fish) -> void:
	if f == null:
		return
	f._ws_bids_digest = -1
	f._ws_broadcast_digest = -2
	f._ws_competition_cache = {}
	f._cycle_bias_cache = {}
	f._self_model_cache = {}
	f._self_model_key = ""
	f._bid_slow_cache = []
	f._bid_slow_accum = 0.0
	f._bid_slow_due = true
	f._bid_dirty = 0
	f._bid_decayed_this_cycle = false
	f._episodic_retrieval_hint = {}
	f._episodic_retrieval_hint_ttl = 0.0
	f._episodic_hint_focus = ""
	f._cycle_use_efe = false
	EpisodicMemory.clear_retrieve_cache_for(f)


static func tick_retrieval_hint(f: Fish, dt: float) -> void:
	if f == null:
		return
	if f._episodic_retrieval_hint.is_empty():
		return
	f._episodic_retrieval_hint_ttl = maxf(0.0, f._episodic_retrieval_hint_ttl - dt)
	if f._episodic_retrieval_hint_ttl <= 0.0:
		f._episodic_retrieval_hint = {}
