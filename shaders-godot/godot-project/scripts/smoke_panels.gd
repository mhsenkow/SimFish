extends SceneTree

# Instantiates procedural side panels headlessly to catch layout/build errors.


func _initialize() -> void:
	await process_frame
	var panels: Array[Dictionary] = [
		{"script": "res://scripts/settings_panel.gd", "name": "SettingsPanel"},
		{"script": "res://scripts/render_panel.gd", "name": "RenderPanel"},
		{"script": "res://scripts/sound_panel.gd", "name": "SoundPanel"},
		{"script": "res://scripts/camera_views_panel.gd", "name": "CameraViewsPanel"},
		{"script": "res://scripts/residents_panel.gd", "name": "ResidentsPanel"},
	]
	var failed: Array[String] = []
	for entry in panels:
		var scr: Script = load(String(entry["script"]))
		if scr == null:
			failed.append("%s: script load failed" % entry["name"])
			continue
		var panel: PanelContainer = scr.new() as PanelContainer
		if panel == null:
			failed.append("%s: instantiate failed" % entry["name"])
			continue
		panel.name = String(entry["name"])
		root.add_child(panel)
		await process_frame
		panel.queue_free()
		await process_frame
	quit(TestSupport.report("smoke_panels", failed))
