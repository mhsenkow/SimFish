class_name SafeJson
extends RefCounted

# Guarded JSON input (BROAD_DIRECTIONS #6).
#
# The project had the right posture in two places and nowhere else:
# `TankSaves.read_json` caps at 50 MiB, sanitizes, and type-checks the
# result; `AIDirector` caps Ollama bodies at 8 KiB. Every other reader —
# the aquascape blueprint library, the global species library, the Spotify
# HTTP responses, LLM tool output — parsed whatever it was handed.
#
# That is the actual trust boundary: save files and config are user-writable,
# HTTP bodies come off the network, and LLM output is model-generated. None
# of it is ours. This module is the one place that posture lives.
#
# Design:
#   - **Bounded before parsed.** Size is checked before the bytes become a
#     String, so a hostile or corrupt 2 GB file cannot be materialised first.
#   - **Typed or nothing.** Callers get a Dictionary (or Array); a JSON
#     scalar, null, or wrong container reads as "absent", never as data.
#   - **Loud but non-fatal.** A refusal is logged with its reason (#5) and
#     returns empty. Per ENGINEERING_CREED, bad input degrades; it never
#     blocks.

# Defaults, deliberately tight. Callers that legitimately need more pass more.
const DEFAULT_MAX_BYTES: int = 1_048_576        # 1 MiB — config/library files
const NETWORK_MAX_BYTES: int = 262_144          # 256 KiB — HTTP responses
const LLM_MAX_BYTES: int = 16_384               # 16 KiB — model output


# --- Files -----------------------------------------------------------------

# Read a JSON object from disk. Empty Dictionary on any failure: missing,
# unreadable, oversize, unparseable, or not an object.
static func read_dict(path: String, max_bytes: int = DEFAULT_MAX_BYTES,
		tag: String = "json") -> Dictionary:
	var v: Variant = _read(path, max_bytes, tag)
	if v is Dictionary:
		return v
	if v != null:
		_warn(tag, "%s is valid JSON but not an object (%s)"
			% [path, type_string(typeof(v))])
	return {}


# Read a JSON array from disk. Empty Array on any failure.
static func read_array(path: String, max_bytes: int = DEFAULT_MAX_BYTES,
		tag: String = "json") -> Array:
	var v: Variant = _read(path, max_bytes, tag)
	if v is Array:
		return v
	if v != null:
		_warn(tag, "%s is valid JSON but not an array (%s)"
			% [path, type_string(typeof(v))])
	return []


static func _read(path: String, max_bytes: int, tag: String) -> Variant:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_warn(tag, "cannot open %s: err %d" % [path, FileAccess.get_open_error()])
		return null
	# Size first, before get_as_text() allocates the whole file.
	var size: int = f.get_length()
	if size > max_bytes:
		f.close()
		_warn(tag, "refusing oversized JSON at %s (%d bytes > %d cap)"
			% [path, size, max_bytes])
		return null
	if size == 0:
		f.close()
		return null
	var text: String = f.get_as_text()
	f.close()
	return _parse(text, tag, path)


# --- Bytes / text ----------------------------------------------------------

# Parse a network or subprocess body. Truncation is a refusal, not a silent
# slice: half a JSON document is not partially valid, and slicing it would
# just produce a parse error further from the cause.
static func parse_body(body: PackedByteArray, max_bytes: int = NETWORK_MAX_BYTES,
		tag: String = "json") -> Dictionary:
	if body.is_empty():
		return {}
	if body.size() > max_bytes:
		_warn(tag, "refusing oversized response body (%d bytes > %d cap)"
			% [body.size(), max_bytes])
		return {}
	var v: Variant = _parse(body.get_string_from_utf8(), tag, "<body>")
	return v if v is Dictionary else {}


static func parse_text(text: String, max_bytes: int = DEFAULT_MAX_BYTES,
		tag: String = "json") -> Dictionary:
	if text.is_empty():
		return {}
	if text.length() > max_bytes:
		_warn(tag, "refusing oversized JSON text (%d chars > %d cap)"
			% [text.length(), max_bytes])
		return {}
	var v: Variant = _parse(text, tag, "<text>")
	return v if v is Dictionary else {}


static func _parse(text: String, tag: String, source: String) -> Variant:
	# Reuse the existing save-path sanitizer: it strips the NaN/Inf tokens
	# Godot's own JSON.stringify can emit, which JSON.parse_string rejects.
	var cleaned: String = SaveHelpers.sanitize_json_text(text)
	var json := JSON.new()
	if json.parse(cleaned) != OK:
		_warn(tag, "JSON parse failed at %s line %d: %s"
			% [source, json.get_error_line(), json.get_error_message()])
		return null
	return json.get_data()


# --- Diagnostics -----------------------------------------------------------

# Routes through AppLog when the tree is up, push_warning otherwise. Static
# context and headless --script runs have no autoloads.
static func _warn(tag: String, message: String) -> void:
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree:
		var lg: Node = (ml as SceneTree).root.get_node_or_null("AppLog")
		if lg != null and lg.has_method("warn"):
			lg.warn(tag, message)
			return
	push_warning("[%s] %s" % [tag, message])
