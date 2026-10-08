extends RefCounted

# Seeds may carry a live Script, a stable path, or pre-fix JSON debug text.
static var _cache: Dictionary = {}

static func path_for(value: Variant) -> String:
	if value is Script:
		return value.resource_path
	if not (value is String or value is StringName):
		return ""
	var text: String = str(value).strip_edges()
	if text.begins_with("(") and text.contains("):<GDScript#"):
		text = text.substr(1, text.find("):<GDScript#") - 1)
	if not text.begins_with("res://") or not text.ends_with(".gd"):
		return ""
	return text

static func resolve(value: Variant) -> Script:
	if value is Script:
		return value if _is_plant_script(value) else null
	var path: String = path_for(value)
	if path == "":
		return null
	if _cache.has(path):
		return _cache[path]
	var script: Script = null
	if ResourceLoader.exists(path, "Script"):
		var candidate: Script = load(path) as Script
		if _is_plant_script(candidate):
			script = candidate
	# Includes missing paths, so a broken saved seed cannot spam filesystem work.
	if _cache.size() >= 128:
		_cache.clear()
	_cache[path] = script
	return script

static func _is_plant_script(script: Script) -> bool:
	if script == null or not script.can_instantiate():
		return false
	var base: Script = script
	while base != null:
		if base.resource_path == "res://scripts/plant.gd":
			return true
		base = base.get_base_script()
	return false

static func normalize_genome(genome: Dictionary) -> Dictionary:
	var out: Dictionary = genome.duplicate(true)
	if out.has("script"):
		var path: String = path_for(out.script)
		if path == "":
			out.erase("script")
		else:
			out.script = path
	return out
