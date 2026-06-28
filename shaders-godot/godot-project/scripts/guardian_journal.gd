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


static func weave_callback(journal: Array, text: String, situation: String) -> String:
	var body: String = text.strip_edges()
	if body == "" or journal.is_empty():
		return body
	if situation in ["successor", "legacy", "torch"]:
		return body
	for i in range(journal.size() - 1, maxi(journal.size() - 8, -1), -1):
		var prior: Dictionary = journal[i]
		var prev: String = String(prior.get("text", ""))
		if prev == "" or prev == body:
			continue
		var tags: PackedStringArray = prior.get("tags", PackedStringArray())
		if tags.has("observe") and prev.contains(" seems "):
			var who: String = prev.get_slice("...", 1).get_slice(" seems", 0).strip_edges()
			if who != "" and not body.contains(who):
				return "%s — %s still on my mind." % [body, who]
		if tags.has("event") and prev.begins_with("I noticed:"):
			var note: String = prev.substr(11).strip_edges()
			if note != "" and randf() < 0.45:
				return "%s (after %s)" % [body, note.to_lower()]
		if tags.has("quiet") and randf() < 0.35:
			return "%s — %s" % [body, prev.to_lower()]
		break
	return body


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
		predecessor_bio: String,
		keeper_moniker: String = "",
		keeper_memories: PackedStringArray = PackedStringArray(),
		legend_note: String = "") -> void:
	if predecessor_journal.is_empty() and predecessor_name == "":
		return
	var header: String = "I inherit this journal from %s." % (
		predecessor_name if predecessor_name != "" else "the last voice")
	if legend_note != "":
		header += " %s became legend here — %s" % [predecessor_name, legend_note]
	elif predecessor_bio != "":
		header += " %s" % predecessor_bio
	if keeper_moniker != "":
		header += " They knew our keeper as %s." % keeper_moniker
	if not keeper_memories.is_empty():
		var mem0: String = String(keeper_memories[0])
		if mem0 != "":
			header += " I remember they said: \"%s.\"" % mem0
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
