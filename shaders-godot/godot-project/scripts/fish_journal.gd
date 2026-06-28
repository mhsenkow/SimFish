extends RefCounted

const FishMind = preload("res://scripts/fish_mind.gd")

const MAX_ENTRIES: int = 48


static func append_entry(journal: Array, text: String, tags: PackedStringArray,
		meta: Dictionary = {}) -> void:
	var line: String = text.strip_edges()
	if line == "":
		return
	journal.append({
		"t": float(meta.get("t", 0.0)),
		"sim_day": String(meta.get("sim_day", "")),
		"text": line,
		"tags": tags,
		"source": String(meta.get("source", "event")),
	})
	while journal.size() > MAX_ENTRIES:
		journal.pop_front()


static func life_story_from_salient(f: Fish) -> String:
	if f == null:
		return ""
	var name: String = f.fish_name if f.fish_name != "" else f.species.capitalize()
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%s lived in this tank" % name)
	var mems: PackedStringArray = FishMind.top_salient_memories(f, 4)
	for m in mems:
		parts.append(" — %s" % m)
	if f.bio is Dictionary and int(f.bio.get("meals_eaten", 0)) > 0:
		parts.append(" (%d meals)" % int(f.bio.get("meals_eaten", 0)))
	return "".join(parts) + "."


static func format_bbcode(journal: Array, fish_name: String) -> String:
	if journal.is_empty():
		return "[color=#9aa8c8]%s has no journal yet.[/color]" % fish_name
	var lines: Array[String] = []
	for i in range(journal.size() - 1, -1, -1):
		var e: Dictionary = journal[i]
		var day: String = String(e.get("sim_day", ""))
		lines.append("[color=#9aa8c8]%s[/color]  %s" % [
			day if day != "" else "—", String(e.get("text", "")),
		])
	return "\n".join(lines)


static func export_plain(journal: Array, fish_name: String) -> String:
	var out: Array[String] = ["Journal — %s" % fish_name, ""]
	for e in journal:
		out.append("[%s] %s" % [String(e.get("sim_day", "—")), String(e.get("text", ""))])
	return "\n".join(out)
