class_name MindAblation
extends RefCounted

# META #14 — per-module ablation switches. Every cognitive module can be disabled
# independently so the mind becomes an experimental apparatus, not a black box:
# turn off theory-of-mind / contagion / signals / world-model and observe whether
# behaviour actually changes. Enabled by default; flipping a flag is the in-code
# equivalent of a lesion study (pairs with the consciousness instruments).

# Module keys (extend as modules are made ablatable).
const SIGNALS: String = "signals"          # 1D inter-fish signal bus
const CONTAGION: String = "contagion"      # META #10 emotional contagion
const THEORY_OF_MIND: String = "theory_of_mind"
const WORLD_MODEL: String = "world_model"  # generative / active-inference model
const SOUL: String = "soul"                # learned soul / habits / narrative stack

static var _disabled: Dictionary = {}
# Bumped on every flag change so per-fish caches built under the old flags
# (the workspace slow-lane bid cache) can tell they are stale. Stays 0 in
# normal play, so caches that never saw a lesion never refresh because of it.
static var generation: int = 0


# True unless explicitly disabled — modules run by default.
static func enabled(module: String) -> bool:
	return not bool(_disabled.get(module, false))


static func set_enabled(module: String, on: bool) -> void:
	var was: bool = enabled(module)
	if on:
		_disabled.erase(module)
	else:
		_disabled[module] = true
	if was != on:
		generation += 1


static func reset() -> void:
	if not _disabled.is_empty():
		generation += 1
	_disabled.clear()
