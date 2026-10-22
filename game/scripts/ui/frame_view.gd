class_name FrameView
extends CanvasLayer
## A frame over the world (blocks 3–4): a shot of a place where the player does not walk — the manager back at the
## mill, the council in the office, Nina in her sister's gallery and workshop, the first span, the epilogue
## three weeks later. A scene staging asks for it (scenes data `stage[].frame`, StoryRunner.frame_changed) while the
## screen is black; the scene's lines play over it in the dialogue box (GameUi, layer 5 — above this layer 3).
##
## A frame is an ordinary room file of data/story/rooms marked `"frame": true` and built by RoomBuilder: the same
## background, state layers by flags (the inscription on the beam end, the cup Nina recognises), text layers,
## effects (snow), ambient (smoke, water, fog — data/story/ambient) and lights (flickering windows, candles —
## data/story/lights). Characters are composited layers (tools/make_frame_layers.py from the 3D sheets) — a frame
## has no hotspots, exits or walking. Nothing here decides story state.
##
## `hold` — the last shot of the game: it stays after its scene, with «Конец», the traces of the player's choices
## (data/story/achievements.json) and «Начать заново»; the menu (GameUi) stays reachable for loading a save.

const LAYER := 3

var frame_id: String = ""
var room: Node2D = null
var end_panel: Control = null
var blocker: Control = null
var _hold: bool = false


func _ready() -> void:
	layer = LAYER
	visible = false
	StoryRunner.frame_changed.connect(_on_frame_changed)


func is_open() -> bool:
	return visible and room != null


func _on_frame_changed(id: String, hold: bool) -> void:
	_clear()
	frame_id = id
	_hold = hold
	if id == "":
		visible = false
		return
	if not StoryData.has_room(id):
		push_error("FrameView: no frame data for %s" % id)
		visible = false
		return
	room = RoomBuilder.build(id)
	if room == null:
		visible = false
		return
	room.name = "Frame_" + id
	add_child(room)
	# The frame takes the clicks that would reach the world under it (the dialogue above still gets its own).
	blocker = Control.new()
	blocker.name = "Blocker"
	blocker.size = Vector2(1920, 1080)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)
	visible = true


## The end panel comes once the last scene is over (its lines read), not when the last shot fades in.
func _process(_delta: float) -> void:
	if _hold and end_panel == null and room != null and StoryRunner.current_beat.is_empty() \
			and not StoryRunner.is_staging() and StoryRunner.end_frame_now() == frame_id:
		_build_end_panel()


func _clear() -> void:
	for n in [room, end_panel, blocker]:
		if n != null and is_instance_valid(n):
			remove_child(n)
			n.queue_free()
	room = null
	end_panel = null
	blocker = null
	frame_id = ""
	_hold = false


## The end of the game over the last shot: «Конец», what the player's choices left (achievements), «Начать заново».
func _build_end_panel() -> void:
	end_panel = Control.new()
	end_panel.name = "End"
	end_panel.size = Vector2(1920, 1080)
	end_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.theme = UiTheme.get_theme()
	add_child(end_panel)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.025, 0.02, 0.62)
	shade.position = Vector2(1260, 120)
	shade.size = Vector2(620, 820)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.add_child(shade)
	var title := Label.new()
	title.name = "Title"
	title.text = StoryData.text("@ui.the_end")
	title.position = Vector2(1290, 140)
	title.size = Vector2(560, 70)
	title.theme_type_variation = &"CloseupTitle"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.add_child(title)
	var sub := Label.new()
	sub.name = "Traces"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.position = Vector2(1290, 220)
	sub.size = Vector2(560, 620)
	sub.add_theme_font_override("font", UiTheme.font("body"))
	sub.add_theme_font_size_override("font_size", 25)
	sub.add_theme_color_override("font_color", Color(0.95, 0.91, 0.82))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lines: Array[String] = [StoryData.text("@ui.traces_title")]
	for a in achieved():
		lines.append("• " + StoryData.text(String(a.get("title", ""))))
	sub.text = "\n".join(lines)
	end_panel.add_child(sub)
	var again := Button.new()
	again.name = "NewGame"
	again.text = StoryData.text("@ui.new_game_again")
	again.size = Vector2(300, 56)
	again.position = Vector2(1290, 860)
	again.focus_mode = Control.FOCUS_NONE
	again.pressed.connect(func(): RoomManager.new_game())
	end_panel.add_child(again)


## Traces of the player's choices this game: data/story/achievements.json entries whose `if` flags all hold
## and, with `any`, at least one of those.
static func achieved() -> Array:
	var out: Array = []
	var path := StoryData.DATA_DIR + "/achievements.json"
	if not FileAccess.file_exists(path):
		return out
	var doc = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (doc is Dictionary):
		return out
	for a in doc.get("achievements", []):
		var ok := true
		for f in a.get("if", []):
			if not GameState.has_flag(String(f)):
				ok = false
		if a.has("any"):
			var anyok := false
			for f in a["any"]:
				if GameState.has_flag(String(f)):
					anyok = true
			ok = ok and anyok
		if ok:
			out.append(a)
	return out


## Tests and the web probe: which frame, its layers and their visibility, the end panel.
func probe() -> Dictionary:
	var out := {"open": is_open(), "frame": frame_id, "hold": _hold}
	if room == null:
		return out
	var layers := {}
	for box in ["Layers", "Occluders"]:
		var c := room.get_node_or_null(box)
		if c == null:
			continue
		for l in c.get_children():
			if l is CanvasItem:
				layers[String(l.name)] = (l as CanvasItem).visible
	out["layers"] = layers
	if end_panel != null:
		var b: Button = end_panel.get_node_or_null("NewGame")
		if b != null:
			var r := b.get_global_rect()
			out["new_game"] = {"x": r.get_center().x, "y": r.get_center().y}
		var t: Label = end_panel.get_node_or_null("Traces")
		out["traces"] = t.text if t != null else ""
	return out
