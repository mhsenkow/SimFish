extends "res://scripts/tank_config.gd"
var marker: int = 0
var test_slot: int = 0

func _ready() -> void:
	pass

func _current_save_path() -> String:
	return "user://settings_worker_test_%d.cfg" % test_slot

func _build_save_config_file() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.set_value("test", "marker", marker)
	return cfg
