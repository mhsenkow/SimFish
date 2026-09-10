# COMMS_AI foundations — toast policy, quiet mute, return ceremony, death window.
# Player-facing inbox rules only; does not own Guardian mind / LLM generation.
extends RefCounted
class_name CommsInbox

const CAPTION_MIN_INTERVAL_S: float = 20.0
const CONSENT_DEFER_S: float = 300.0
const DEATH_WINDOW_S: float = 8.0
const TOAST_QUEUE_SOFT_CAP: int = 8
const TOAST_MAX_VISIBLE: int = 2

const KIND_ALL: String = "all"

## Dropdown order for the notification center kind filter.
const KIND_FILTER_ENTRIES: Array[Dictionary] = [
	{"id": "all", "label": "Kind: All"},
	{"id": "discovery", "label": "Kind: Discovery"},
	{"id": "population", "label": "Kind: Population"},
	{"id": "water_alert", "label": "Kind: Water"},
	{"id": "milestone", "label": "Kind: Milestone"},
	{"id": "welcome_back", "label": "Kind: Welcome"},
	{"id": "guardian", "label": "Kind: Guardian"},
	{"id": "guardian_llm", "label": "Kind: Guardian LLM"},
	{"id": "care", "label": "Kind: Care"},
	{"id": "fish_thought", "label": "Kind: Fish thought"},
	{"id": "residents", "label": "Kind: Residents"},
	{"id": "system", "label": "Kind: System"},
	{"id": "mind_upgrade", "label": "Kind: Mind upgrade"},
]


static func kind_icon(kind: String) -> String:
	match kind:
		"discovery":
			return "◇"
		"population":
			return "◉"
		"water_alert":
			return "!"
		"milestone":
			return "*"
		"welcome_back":
			return "↺"
		"guardian", "guardian_llm":
			return "◈"
		"care":
			return "≈"
		"fish_thought":
			return "…"
		"residents":
			return "○"
		"system", "mind_upgrade":
			return "⚙"
		_:
			return "•"


## Higher = more urgent. Used to order the shared toast queue.
static func lane_priority(kind: String, severity: String) -> int:
	var sev: int = 0
	match severity:
		"critical":
			sev = 30
		"important":
			sev = 20
		_:
			sev = 10
	match kind:
		"water_alert":
			return sev + 8
		"care":
			return sev + 6
		"residents":
			return sev + 5
		"guardian", "guardian_llm":
			return sev + 4
		"welcome_back":
			return sev + 3
		"population", "milestone":
			return sev + 2
		"discovery", "system", "mind_upgrade":
			return sev + 1
		"fish_thought":
			return sev - 2
		"caption", "feed", "status":
			return sev - 4
		_:
			return sev


## Quiet mode: voice + ambient toasts off; critical water (and memorial) remain.
static func allows_toast(kind: String, severity: String, quiet: bool) -> bool:
	if not quiet:
		return true
	if kind == "water_alert" and severity == "critical":
		return true
	if kind == "residents" and (severity == "important" or severity == "critical"):
		return true
	# Player-initiated status (photo/care) is not "ambient" — callers pass
	# kind "care"/"system" with allow_when_quiet via allows_status_toast.
	if kind in ["guardian", "guardian_llm", "fish_thought", "discovery",
			"milestone", "welcome_back", "population", "mind_upgrade",
			"caption", "feed"]:
		return false
	if severity == "info":
		return false
	return false


static func allows_status_toast(message: String, quiet: bool) -> bool:
	if not quiet:
		return true
	var low: String = message.to_lower()
	# Autosave is ambient; photo/care confirms are player-triggered.
	if low == "saved" or low.begins_with("saved"):
		return false
	return true


static func allows_caption(quiet: bool) -> bool:
	return not quiet


## Insert by priority (critical first). Drop oldest ambient when over soft cap.
static func enqueue_toast(queue: Array, notif: Dictionary) -> void:
	var pri: int = lane_priority(
			String(notif.get("kind", "system")),
			String(notif.get("severity", "info")))
	notif["_pri"] = pri
	var inserted: bool = false
	for i in range(queue.size()):
		if pri > int((queue[i] as Dictionary).get("_pri", 0)):
			queue.insert(i, notif)
			inserted = true
			break
	if not inserted:
		queue.append(notif)
	while queue.size() > TOAST_QUEUE_SOFT_CAP:
		var drop_idx: int = -1
		var drop_pri: int = 9999
		for i in range(queue.size()):
			var p: int = int((queue[i] as Dictionary).get("_pri", 0))
			if p < drop_pri:
				drop_pri = p
				drop_idx = i
		if drop_idx < 0 or drop_pri >= 30:
			break
		queue.remove_at(drop_idx)


## Claim one return ceremony per session. Prefer "away" over "welcome".
static func claim_return_ceremony(state: Dictionary, kind: String) -> bool:
	var cur: String = String(state.get("return_ceremony", ""))
	if cur == "":
		state["return_ceremony"] = kind
		return true
	if cur == kind:
		return false
	# Away wins: if welcome already claimed, away may steal; welcome cannot steal away.
	if kind == "away" and cur == "welcome":
		state["return_ceremony"] = "away"
		return true
	return false


static func return_ceremony(state: Dictionary) -> String:
	return String(state.get("return_ceremony", ""))


## Aggregate deaths in a short window into one summary payload.
static func note_death(state: Dictionary, name_str: String, now_s: float) -> Dictionary:
	var window_start: float = float(state.get("death_window_start", -9999.0))
	var names: Array = state.get("death_names", []) as Array
	if now_s - window_start > DEATH_WINDOW_S or names.is_empty():
		state["death_window_start"] = now_s
		state["death_names"] = [name_str]
		state["death_pending"] = true
		return {"ready": false, "count": 1, "names": state["death_names"]}
	names.append(name_str)
	state["death_names"] = names
	state["death_pending"] = true
	return {"ready": false, "count": names.size(), "names": names}


static func flush_death_summary(state: Dictionary) -> Dictionary:
	if not bool(state.get("death_pending", false)):
		return {}
	var names: Array = state.get("death_names", []) as Array
	if names.is_empty():
		state["death_pending"] = false
		return {}
	state["death_pending"] = false
	var count: int = names.size()
	var body: String
	if count == 1:
		body = "%s has passed on" % String(names[0])
	elif count == 2:
		body = "%s and %s have passed on" % [String(names[0]), String(names[1])]
	else:
		body = "%d residents have passed on" % count
	state["death_names"] = []
	return {
		"kind": "residents",
		"severity": "important",
		"title": "In memoriam" if count == 1 else "Tank losses",
		"body": body,
		"count": count,
	}


static func caption_allowed(state: Dictionary, now_s: float, quiet: bool) -> bool:
	if not allows_caption(quiet):
		return false
	var last: float = float(state.get("caption_last_s", -9999.0))
	if now_s - last < CAPTION_MIN_INTERVAL_S:
		return false
	state["caption_last_s"] = now_s
	return true


static func consent_deferred(session_start_s: float, now_s: float) -> bool:
	return (now_s - session_start_s) < CONSENT_DEFER_S


static func tier_chip_line(tier: String) -> String:
	match tier:
		"inprocess", "embedded":
			return "Voice: built-in"
		"ollama":
			return "Voice: Ollama"
		_:
			return "Voice: templates"
