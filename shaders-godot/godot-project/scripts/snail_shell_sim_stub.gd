extends Node

# Minimal SimDriver stand-in for smoke_snail_shell.gd — Snail's shell tick only
# reaches for `water_chemistry`, so nothing else needs to exist.
#
# Deliberately NOT named smoke_* : the suite runner globs scripts/smoke_*.gd and
# executes each one, and a plain `extends Node` has no MainLoop, so a smoke-
# prefixed helper boots the whole game instead and hangs the run.
var water_chemistry: WaterChemistry = null
