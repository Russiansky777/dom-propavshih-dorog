class_name TimeOfDay
extends RefCounted
## Time of day of the story (Director 23.10, F17: «ещё раз подумать над временами дня, чтобы они
## скоординированно со сценарием и логикой сменялись»). Data — data/story/time/_index.json (ordered states
## with the scene-progress flags that start them, the grades by room class) and data/story/time/<LOC>.json
## (what a room changes: its own grade per state/phase, effects it replaces, lit windows). The table by scene —
## Docs/TIME_OF_DAY.md; the scene → state map in the data is checked by game/tests/test_time_of_day.gd.
##
## The state is never stored: it is derived from flags that are only ever set (done_<scene> of the main
## story), so a save restores it by itself and it cannot run backwards inside a day.
##
## Virtual flags (GameState.has_flag answers them; never written into the save): every existing condition —
## layers / effects `if` `unless`, lights `if` `unless` `energy_if`, hotspots `visible_if`, dialogue `if` —
## can test the time without new code:
##   tod_<state>   — exactly this state (tod_d2_dusk);
##   tod_<phase>   — any day at this phase (tod_morning, tod_dusk, tod_night …);
##   tod_day<N>    — the day (tod_day1 … tod_day4, tod_day5 = the epilogue);
##   tod_dark      — dusk, evening or night (lamps lit, windows glowing).
## Places with their own clock (the cut-off school before the road returns: «там своё время») override the
## state for their room only (`locals`): grade and journal line; the virtual flags stay the story's.

const DATA_DIR := "res://data/story/time"
const FLAG_PREFIX := "tod_"
const DARK_PHASES: Array[String] = ["dusk", "evening", "night"]

static var _index: Dictionary = {}
static var _rooms: Dictionary = {}        # room id -> its time file (or {})
static var _loaded: bool = false


static func reload() -> void:
	_loaded = false
	_index = {}
	_rooms = {}


static func index() -> Dictionary:
	if not _loaded:
		_loaded = true
		_index = _read(DATA_DIR + "/_index.json")
	return _index


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		push_error("TimeOfDay: %s is not a JSON object" % path)
		return {}
	return d


static func room_data(room_id: String) -> Dictionary:
	if not _rooms.has(room_id):
		_rooms[room_id] = _read("%s/%s.json" % [DATA_DIR, room_id])
	return _rooms[room_id]


static func states() -> Array:
	return index().get("states", [])


static func state_spec(id: String) -> Dictionary:
	for s in states():
		if String(s.get("id", "")) == id:
			return s
	return {}


## True when the condition {all: [...], any: [...]} holds on the stored flags (never the virtual ones).
static func _cond(c: Dictionary, flags: Dictionary) -> bool:
	for f in c.get("all", []):
		if not bool(flags.get(String(f), false)):
			return false
	var any: Array = c.get("any", [])
	if not any.is_empty():
		for f in any:
			if bool(flags.get(String(f), false)):
				return true
		return false
	return true


## The story's state for a set of flags: the last state (in story order) whose `when` holds.
static func state_for(flags: Dictionary) -> String:
	var out := ""
	for s in states():
		if s.get("room_only", false):
			continue
		if _cond(s.get("when", {}), flags):
			out = String(s.get("id", ""))
	return out


static func current_state() -> String:
	return state_for(GameState.flags)


## The state a room shows: a place with its own clock (index `locals`) or the story's.
static func room_state(room_id: String) -> String:
	for l in index().get("locals", []):
		if not (l.get("rooms", []) as Array).has(room_id):
			continue
		if _flags_ok(l):
			return String(l.get("state", ""))
	var fixed := String(room_data(room_id).get("fixed_state", ""))
	if fixed != "":
		return fixed
	return current_state()


static func _flags_ok(d: Dictionary) -> bool:
	for f in d.get("if", []):
		if not bool(GameState.flags.get(String(f), false)):
			return false
	for f in d.get("unless", []):
		if bool(GameState.flags.get(String(f), false)):
			return false
	return true


static func phase_of(state_id: String) -> String:
	return String(state_spec(state_id).get("phase", ""))


static func day_of(state_id: String) -> int:
	return int(state_spec(state_id).get("day", 0))


# --- Virtual flags ------------------------------------------------------------------------

static func is_virtual(flag: String) -> bool:
	return flag.begins_with(FLAG_PREFIX)


## GameState.has_flag for a tod_ flag.
static func has_virtual(flag: String) -> bool:
	var st := current_state()
	if st == "":
		return false
	var name := flag.substr(FLAG_PREFIX.length())
	if name == st:
		return true
	var ph := phase_of(st)
	if name == ph:
		return true
	if name == "dark":
		return DARK_PHASES.has(ph)
	if name.begins_with("day") and name.substr(3).is_valid_int():
		return int(name.substr(3)) == day_of(st)
	return false


## Every virtual flag name (validators accept them; the same list — tools/validate_*.py::tod_flags).
static func virtual_flags() -> Array[String]:
	var out: Array[String] = [FLAG_PREFIX + "dark"]
	var seen := {}
	for s in states():
		for n in [String(s.get("id", "")), String(s.get("phase", "")), "day%d" % int(s.get("day", 0))]:
			if n != "" and not seen.has(n):
				seen[n] = true
				out.append(FLAG_PREFIX + n)
	return out


# --- Labels -------------------------------------------------------------------------------

## «День второй · сумерки» for the journal; a place with its own clock says so.
static func label(room_id: String = "") -> String:
	var st := current_state()
	var spec := state_spec(st)
	if spec.is_empty():
		return ""
	var out := StoryData.text(String(spec.get("label", "")))
	var local := room_state(room_id) if room_id != "" else st
	if local != st and not state_spec(local).is_empty():
		out += " — " + StoryData.text(String(state_spec(local).get("label", "")))
	return out


# --- Grades -------------------------------------------------------------------------------

## The room's class for the default grades: its time file `class`, else from the room data
## (frame rooms → frame; locations inside the cut → cut_<kind>; else background.kind).
static func room_class(room_id: String) -> String:
	var own := String(room_data(room_id).get("class", ""))
	if own != "":
		return own
	var spec: Dictionary = StoryData.room(room_id)
	if bool(spec.get("frame", false)):
		return "frame"
	var kind := String(spec.get("background", {}).get("kind", "interior"))
	if bool(StoryData.locations.get(room_id, {}).get("inside_cut", false)):
		return "cut_" + kind
	return kind


## The grade of a room in a state: {tint: Color, …} or {} (as painted). Lookup: the room's `grade` by state,
## then by phase; then the class defaults by state, by phase; a class may `inherit` another.
static func grade(room_id: String, state_id: String) -> Dictionary:
	var ph := phase_of(state_id)
	var own: Dictionary = room_data(room_id).get("grade", {})
	for k in [state_id, ph]:
		if own.has(k):
			return _grade_value(own[k])
	var classes: Dictionary = index().get("grades", {})
	var cls := room_class(room_id)
	var guard := 0
	while cls != "" and guard < 6:
		guard += 1
		var g: Dictionary = classes.get(cls, {})
		for k in [state_id, ph]:
			if g.has(k):
				return _grade_value(g[k])
		cls = String(g.get("inherit", ""))
	return {}


static func _grade_value(v) -> Dictionary:
	if v is Dictionary:
		return v
	return {}   # "none" / "painted" / null — as painted


static func tint_of(g: Dictionary) -> Color:
	return Color.html(String(g.get("tint", "#ffffff")))


## Ambient light sources a room with a light map takes instead of the tint polygon (RoomLighting.build merges
## them): one per state with a grade, on while that state lasts (virtual flag tod_<state>), fading like a
## source. Fires, lamp glows and the UI keep their brightness; figures take the lowered light like the floor.
static func light_sources(room_id: String) -> Array:
	var out: Array = []
	if String(room_data(room_id).get("route", "")) == "tint":
		return out
	var locals_here := false
	for l in index().get("locals", []):
		if (l.get("rooms", []) as Array).has(room_id):
			locals_here = true
	if locals_here:
		return out   # a place with its own clock: the polygon follows its local state (TimeGrade)
	var fixed := String(room_data(room_id).get("fixed_state", ""))
	for s in states():
		var id := String(s.get("id", ""))
		if fixed != "" and id != fixed:
			continue
		var g := grade(room_id, id)
		if g.is_empty():
			continue
		var t := tint_of(g)
		# No actor_tint: the lowered light map already reaches the figures (RoomLighting.actor_tone_at — the ambient
		# field), a tint on top darkened them twice (Agata black in Z4 at dusk, 23.10).
		var src := {"id": "tod_" + id, "type": "ambient", "subtract": [1.0 - t.r, 1.0 - t.g, 1.0 - t.b], "energy": 1.0,
			"fade_s": float(index().get("fade_s", 2.0)),
			"_note": "время суток (TimeOfDay, data/story/time)"}
		if fixed == "":
			src["if"] = [FLAG_PREFIX + id]
		out.append(src)
	return out


static func probe(room_id: String = "") -> Dictionary:
	var st := current_state()
	var rs := room_state(room_id) if room_id != "" else st
	return {"state": st, "phase": phase_of(st), "day": day_of(st), "room_state": rs, "label": label(room_id),
		"class": room_class(room_id) if room_id != "" else ""}
