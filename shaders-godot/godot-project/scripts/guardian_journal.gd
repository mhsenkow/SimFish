extends RefCounted

# Per-Guardian diary (#28–36). Separate from tank-wide `story_events` — this
# is authored in the Guardian's voice and persists across sessions (save v6+).

const MAX_ENTRIES: int = 150


static func append_entry(
		journal: Array,
		text: String,
		chapter: int,
		tags: PackedStringArray,
		meta: Dictionary) -> Dictionary:
	var entry: Dictionary = {
		"t": float(meta.get("t", 0.0)),
		"tank_age_s": float(meta.get("tank_age_s", 0.0)),
		"sim_day": String(meta.get("sim_day", "")),
		"chapter": chapter,
		"text": text.strip_edges(),
		"tags": tags,
		"source": String(meta.get("source", "template")),
		"cache_key": String(meta.get("cache_key", "")),
	}
	if entry["text"] == "":
		return {}
	journal.append(entry)
	while journal.size() > MAX_ENTRIES:
		journal.pop_front()
	return entry


static func upgrade_entry_text(journal: Array, cache_key: String, new_text: String) -> void:
	if cache_key == "" or new_text.strip_edges() == "":
		return
	for i in range(journal.size() - 1, -1, -1):
		var e: Dictionary = journal[i]
		if String(e.get("cache_key", "")) == cache_key:
			e["text"] = new_text.strip_edges()
			e["source"] = "ai"
			journal[i] = e
			return


static func merge_predecessor(
		journal: Array,
		predecessor_journal: Array,
		predecessor_name: String,
		predecessor_bio: String) -> void:
	if predecessor_journal.is_empty() and predecessor_name == "":
		return
	var header: String = "I inherit this journal from %s." % (
		predecessor_name if predecessor_name != "" else "the last voice")
	if predecessor_bio != "":
		header += " %s" % predecessor_bio
	append_entry(journal, header, 0, PackedStringArray(["successor", "torch"]),
			{"source": "event", "sim_day": "—", "t": 0.0})
	# Carry forward the last few predecessor entries as quoted memory.
	var start: int = maxi(0, predecessor_journal.size() - 5)
	for j in range(start, predecessor_journal.size()):
		var pe: Dictionary = predecessor_journal[j]
		var quote: String = String(pe.get("text", ""))
		if quote == "":
			continue
		append_entry(journal,
				"(from %s) %s" % [predecessor_name if predecessor_name != "" else "before", quote],
				int(pe.get("chapter", 0)),
				PackedStringArray(["legacy"]),
				{"source": "legacy", "sim_day": String(pe.get("sim_day", "")),
					"t": float(pe.get("t", 0.0))})


static func format_bbcode(journal: Array) -> String:
	if journal.is_empty():
		return "[color=#9aa8c8]The Guardian has not written anything yet.[/color]"
	var lines: Array[String] = []
	for i in range(journal.size() - 1, -1, -1):
		var e: Dictionary = journal[i]
		var day: String = String(e.get("sim_day", ""))
		var ch: int = int(e.get("chapter", 0))
		var tag_line: String = ""
		if ch > 0:
			tag_line = " · ch.%d" % ch
		lines.append("[color=#9aa8c8]%s%s[/color]  %s" % [
			day if day != "" else "—", tag_line, String(e.get("text", "")),
		])
	return "\n".join(lines)


static func export_plain(journal: Array, guardian_name: String) -> String:
	var out: Array[String] = []
	out.append("Guardian journal — %s" % (guardian_name if guardian_name != "" else "Tank voice"))
	out.append("")
	for e in journal:
		var day: String = String(e.get("sim_day", ""))
		out.append("[%s] %s" % [day if day != "" else "—", String(e.get("text", ""))])
	return "\n".join(out)
