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


# True unless explicitly disabled — modules run by default.
static func enabled(module: String) -> bool:
	return not bool(_disabled.get(module, false))


static func set_enabled(module: String, on: bool) -> void:
	if on:
		_disabled.erase(module)
	else:
		_disabled[module] = true


static func reset() -> void:
	_disabled.clear()
