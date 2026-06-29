extends Node

# Minimal sim host for headless smokes (META #15 / #31).
const SimRngScript = preload("res://scripts/sim_rng.gd")

var rng: SimRngScript = SimRngScript.new()
