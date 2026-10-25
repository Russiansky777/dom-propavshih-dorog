class_name GlossText
extends RichTextLabel
## A RichTextLabel for story text with hints to old words (Gloss, H59/T7): `set_story_text` keeps the text as written
## (`story_text`, marks included) and shows it with each `[[слово|значение]]` as a gold, dashed-underlined word; hovering
## it pops up the meaning in the game's style (the native tooltip of `[hint]` with our own content). The label passes
## clicks on to its parent (the dialogue box advances as before).

var story_text: String = ""
## The last pop-up made (tests and the web probe: was the meaning shown, and which).
var last_tooltip: Control = null
var last_tooltip_text: String = ""
var _targets_key: String = ""
var _targets: Array = []


func _init() -> void:
	bbcode_enabled = true
	hint_underlined = true
	meta_underlined = false
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_story_text(s: String) -> void:
	story_text = s
	text = Gloss.bbcode(s)
	_targets_key = ""


func _make_custom_tooltip(for_text: String) -> Object:
	var word := ""
	for m in Gloss.marks(story_text):
		if String(m["meaning"]).replace("\"", "'") == for_text:
			word = String(m["word"])
			break
	last_tooltip = Gloss.make_tooltip(for_text, word, get_theme_font_size("normal_font_size"))
	last_tooltip_text = for_text
	return last_tooltip


## The pop-up is on screen now.
func tooltip_open() -> bool:
	return last_tooltip != null and is_instance_valid(last_tooltip) and last_tooltip.is_inside_tree() and last_tooltip.is_visible_in_tree()


## Where the marked words are, in global (canvas) coordinates: [{word, meaning, x, y, w, h}] — found by asking the
## label what hint lies under each point (the same lookup the tooltip uses), so it matches the drawn text exactly.
func gloss_targets() -> Array:
	if not Gloss.has_marks(story_text) or not is_visible_in_tree():
		return []
	var key := "%s|%s" % [story_text, size]
	if key == _targets_key:
		return _targets
	_targets_key = key
	_targets = []
	var found := {}
	var step := Vector2(4.0, 6.0)
	var y := 2.0
	while y < size.y:
		var x := 0.0
		while x < size.x:
			var t := get_tooltip(Vector2(x, y))
			if t != "" and t != tooltip_text:
				var r: Rect2 = found.get(t, Rect2(Vector2(x, y), Vector2.ZERO))
				found[t] = r.expand(Vector2(x, y))
			x += step.x
		y += step.y
	var gp := get_global_rect().position
	for m in Gloss.marks(story_text):
		var meaning := String(m["meaning"]).replace("\"", "'")
		if found.has(meaning):
			var r: Rect2 = found[meaning]
			_targets.append({"word": m["word"], "meaning": m["meaning"], "x": gp.x + r.position.x, "y": gp.y + r.position.y,
				"w": r.size.x, "h": r.size.y, "cx": gp.x + r.get_center().x, "cy": gp.y + r.get_center().y})
	return _targets


func probe() -> Dictionary:
	return {"text": Gloss.plain(story_text), "targets": gloss_targets(), "tooltip_open": tooltip_open(),
		"tooltip_text": last_tooltip_text if tooltip_open() else ""}
