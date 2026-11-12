extends RefCounted
## (no class_name: loaded by preload — the tests run with `godot -s`, where a new global class is not known until an import)
## Lips by sounds (Director 12.11, 21:40: «нужны губы как минимум»): until now the painted mouth opened by loudness alone
## — wider or narrower, one shape on every sound. Every recording has its letters timed (the synthesis' alignment);
## tools/bake_lips.py turns them into a sequence of mouth shapes per line: shut on «м, б, п», nearly shut on «в, ф»,
## round on «о, у», wide on «а, э, и», a little open on the other consonants, shut in pauses
## (res://data/lips/<lang>.json — pairs [centiseconds from the game file's start, class]); the shapes themselves
## (width and height shares per class) are data: res://data/lips/shapes.json.
## JawModifier asks shape_at() for the line VoiceDirector plays. Tests: tests/test_jaw.gd (JW-6), tools/bake_lips.py --check.

const DIR := "res://data/lips"
const NONE := Vector2(-1.0, -1.0)

## off — the mouth by loudness alone, as before 12.11 (the tests' self-check)
static var enabled := true
static var _lines := {}      # lang → {line id: PackedInt32Array [cs, class, cs, class, …]}
static var _classes := {}    # lang → [class names]
static var _cfg := {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/shapes.json")) if FileAccess.file_exists(DIR + "/shapes.json") else null
		_cfg = d if d is Dictionary else {"shapes": {}}
	return _cfg


static func _load(lang: String) -> void:
	if _lines.has(lang):
		return
	_lines[lang] = {}
	_classes[lang] = []
	var path := "%s/%s.json" % [DIR, lang]
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		return
	_classes[lang] = d.get("classes", [])
	var out := {}
	var src: Dictionary = d.get("lines", {})
	for lid in src.keys():
		var seq := PackedInt32Array()
		for v in (src[lid] as Dictionary).get("seq", []):
			seq.append(int(v))
		out[String(lid)] = seq
	_lines[lang] = out


static func has_line(lang: String, line_id: String) -> bool:
	_load(lang)
	return (_lines[lang] as Dictionary).has(line_id)


## The class of the mouth's shape `t` seconds into the line («» — no table for this line).
static func class_at(lang: String, line_id: String, t: float) -> String:
	_load(lang)
	var seq = (_lines[lang] as Dictionary).get(line_id, null)
	if seq == null:
		return ""
	var s: PackedInt32Array = seq
	var cs := int(floor(maxf(t, 0.0) * 100.0))
	var lo := 0
	var hi := s.size() / 2 - 1
	while lo < hi:   # the last event at or before cs
		var mid := (lo + hi + 1) / 2
		if s[mid * 2] <= cs:
			lo = mid
		else:
			hi = mid - 1
	var names: Array = _classes[lang]
	var ci := s[lo * 2 + 1] if s.size() >= 2 else 0
	return String(names[ci]) if ci >= 0 and ci < names.size() else ""


## The mouth's shape `t` seconds into the line: (width share, height share); NONE — no table for this line.
static func shape_at(lang: String, line_id: String, t: float) -> Vector2:
	if not enabled or not bool(cfg().get("on", true)):
		return NONE
	var c := class_at(lang, line_id, t)
	if c == "":
		return NONE
	var sh = (cfg().get("shapes", {}) as Dictionary).get(c, null)
	if not (sh is Array) or (sh as Array).size() < 2:
		return NONE
	return Vector2(float(sh[0]), float(sh[1]))
