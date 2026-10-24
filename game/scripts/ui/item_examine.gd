class_name ItemExamine
extends CanvasLayer
## «Рассмотреть» — any item in the bag up close (Director 23.10, F9: «чтобы можно было рассмотреть при
## нажатии, а не бессмысленные иконки»). Opened by StoryRunner.examine_item(id) — a double click on the
## pocket or its magnifier (InventoryBag); the single click still takes the item in hand. Everything is data,
## items.json → <item>.examine:
##   text        Agata's line about the thing (a text key; plays in the dialogue box over the close-up)
##   art         the thing's own close-up picture (photo print, child's drawing, the plan…); without it — the bag
##               icon enlarged on the backdrop (a gap for the art queue, listed in the report)
##   region      [x, y, w, h] — a part of `art` (a crop of a room painting)
##   width       display width of the picture (px at 1920×1080; height by aspect; default fits 1300×700)
##   angle_deg   the picture lies slightly askew
##   backdrop    what it lies on: "cloth" (linen, default), "table" (scrubbed wood), "paper"
##   writing     {text, text_rect [x, y, w, h] in `image_size` px, font_size, ink, angle_deg} — written words over the art
##               (the plan of the crossing; the manager's journal — its empty right page, партия 8)
##   note        {title, text, font_size} — a sheet beside the thing with what is written in it (the manager's
##               journal: the last record and the rule of the pond)
##   watch       {center, r, face} — the pocket watch goes (PocketWatchDial over `art` or the icon; centre — fractions of
##               the picture's width / height, r — of its height; face false — the art's dial has no hands to cover)
## Layer 4, the last child of Main: above MechanicView (an item can be looked at inside a close-up — the watch
## at mother's mirror) and under GameUi (5), so the bag stays usable and the line is read over the picture.
## Closes with a click once the line is read, «Закрыть», Esc; a load or a new game closes it.

const LAYER := 4
const BACKDROP_SHADER: Shader = preload("res://shaders/examine_backdrop.gdshader")
const AREA := Rect2(140, 128, 1640, 742)     # where the picture is fitted (above the text box)
const BACKDROPS := {
	"cloth": {"base": Color(0.6, 0.53, 0.42), "dark": Color(0.08, 0.06, 0.045), "weave": 0.09, "grain": 0.0},
	"table": {"base": Color(0.42, 0.3, 0.2), "dark": Color(0.06, 0.045, 0.03), "weave": 0.0, "grain": 0.22},
	"paper": {"base": Color(0.78, 0.71, 0.58), "dark": Color(0.1, 0.08, 0.06), "weave": 0.0, "grain": 0.06},
}

var item_id: String = ""
var spec: Dictionary = {}
var root: Control = null
var picture: Control = null       # the thing (its art, or the icon) — probe/tests
var picture_source: String = ""   # "art" | "icon" | "patch"
var dial: PocketWatchDial = null
var note: Control = null
var close_button: Button = null


func _ready() -> void:
	layer = LAYER
	visible = false
	StoryRunner.examine_opened.connect(_open)
	StoryRunner.examine_closed.connect(_close)


func is_open() -> bool:
	return visible and root != null


func _open(id: String) -> void:
	_free_nodes()
	item_id = id
	spec = StoryRunner.examine_spec(id)
	_build()
	visible = true


func _close() -> void:
	visible = false
	_free_nodes()
	item_id = ""
	spec = {}


func _free_nodes() -> void:
	if root != null and is_instance_valid(root):
		root.queue_free()
	root = null
	picture = null
	picture_source = ""
	dial = null
	note = null
	close_button = null


func _build() -> void:
	root = Control.new()
	root.name = "Examine"
	root.size = Vector2(1920, 1080)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = UiTheme.get_theme()
	root.gui_input.connect(_on_root_input)
	add_child(root)
	var bg := ColorRect.new()
	bg.name = "Backdrop"
	bg.size = root.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = BACKDROP_SHADER
	var b: Dictionary = BACKDROPS.get(String(spec.get("backdrop", "cloth")), BACKDROPS["cloth"])
	mat.set_shader_parameter("base", b["base"])
	mat.set_shader_parameter("dark", b["dark"])
	mat.set_shader_parameter("weave", b["weave"])
	mat.set_shader_parameter("grain", b["grain"])
	bg.material = mat
	root.add_child(bg)
	var title := Label.new()
	title.name = "Title"
	title.text = StoryData.item_name(item_id)
	title.position = Vector2(40, 100)
	title.size = Vector2(1200, 60)
	title.theme_type_variation = &"CloseupTitle"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title)
	var area := AREA
	if spec.has("note"):
		area = Rect2(AREA.position, Vector2(AREA.size.x * 0.5, AREA.size.y))
	_build_picture(area)
	if spec.has("note"):
		_build_note(Rect2(AREA.position + Vector2(AREA.size.x * 0.52, 20), Vector2(AREA.size.x * 0.48, AREA.size.y - 40)))
	close_button = Button.new()
	close_button.name = "Close"
	close_button.text = StoryData.text("@ui.close")
	close_button.size = Vector2(200, 56)
	close_button.position = Vector2(1680, 990)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(func(): StoryRunner.close_examine())
	root.add_child(close_button)


## The thing itself, fitted into `area`: its art, or the bag icon enlarged, or (no icon) a patch with a letter.
func _build_picture(area: Rect2) -> void:
	var tex: Texture2D = null
	var path := String(spec.get("art", ""))
	if path != "" and ResourceLoader.exists(path):
		tex = load(path)
		picture_source = "art"
		if spec.has("region"):
			var r: Array = spec["region"]
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
			tex = at
	else:
		# No close-up art yet: the bag icon, from its large copy (tools/make_examine_icons.py) when there is one.
		var big := "res://assets/examine/%s.png" % InventoryBag.icon_name(item_id)
		tex = load(big) as Texture2D if ResourceLoader.exists(big) else InventoryBag.icon_for(item_id)
		picture_source = "icon" if tex != null else "patch"
	var src := tex.get_size() if tex != null else Vector2(192, 192)
	var w := float(spec.get("width", 0.0))
	if w <= 0.0:
		w = minf(area.size.x, area.size.y * src.x / src.y) if picture_source == "art" else minf(area.size.y * 0.86, 600.0)
	var h := w * src.y / src.x
	if h > area.size.y:
		h = area.size.y
		w = h * src.x / src.y
	var holder := Control.new()
	holder.name = "Picture"
	holder.size = Vector2(w, h)
	holder.position = area.position + (area.size - holder.size) * 0.5
	holder.pivot_offset = holder.size * 0.5
	holder.rotation = deg_to_rad(float(spec.get("angle_deg", 0.0)))
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)
	picture = holder
	if spec.has("watch"):
		dial = PocketWatchDial.new()
		dial.name = "Watch"
		if picture_source == "art":
			dial.texture = tex     # the watch's own close-up (партия 8: dial without hands) instead of the bag icon
		dial.configure(spec["watch"])
		dial.size = holder.size
		holder.add_child(dial)
		return
	if tex == null:
		var patch := BagSlot.new()
		patch.loose = true
		patch.item_id = item_id
		patch.item_name = StoryData.item_name(item_id)
		patch.size = holder.size
		patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(patch)
		return
	for i in 2:
		var tr := TextureRect.new()
		tr.name = "Shadow" if i == 0 else "Image"
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.size = holder.size
		tr.position = Vector2(12, 16) if i == 0 else Vector2.ZERO
		tr.modulate = Color(0, 0, 0, 0.42) if i == 0 else Color.WHITE
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tr)
	if spec.has("writing"):
		var wr: Dictionary = spec["writing"]
		var isz: Array = wr.get("image_size", [src.x, src.y])
		var k := w / maxf(float(isz[0]), 1.0)
		var trc: Array = wr.get("text_rect", [0, 0, isz[0], isz[1]])
		var hand := String(wr.get("font", "")) == "hand"   # H31: the manager's journal written by hand on the ruling
		var l: Label = HandWriting.new() if hand else Label.new()
		l.name = "Writing"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text = Gloss.plain(StoryData.text(String(wr.get("text", ""))))
		l.position = Vector2(float(trc[0]), float(trc[1])) * k
		l.size = Vector2(float(trc[2]), float(trc[3])) * k
		l.pivot_offset = l.size * 0.5
		l.rotation = deg_to_rad(float(wr.get("angle_deg", 0.0)))   # the page lies askew (the manager's journal)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", UiTheme.font("body_italic"))
		l.add_theme_font_size_override("font_size", int(wr.get("font_size", 24)))
		l.add_theme_color_override("font_color", Color.html(String(wr.get("ink", "#2a2117"))))
		l.add_theme_constant_override("line_spacing", 0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if hand:
			(l as HandWriting).setup(wr, int(wr.get("font_size", 24)), k)
		holder.add_child(l)


## A sheet beside the thing with what is written in it (the journal's last record).
func _build_note(r: Rect2) -> void:
	var nd: Dictionary = spec["note"]
	note = Control.new()
	note.name = "Note"
	note.position = r.position
	note.size = r.size
	note.pivot_offset = r.size * 0.5
	note.rotation = deg_to_rad(float(nd.get("angle_deg", 1.2)))
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(note)
	var shadow := ColorRect.new()
	shadow.color = Color(0, 0, 0, 0.42)
	shadow.position = Vector2(12, 16)
	shadow.size = r.size
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.add_child(shadow)
	var paper := ColorRect.new()
	paper.name = "Sheet"
	paper.color = Color.html(String(nd.get("paper", "#e2d5b5")))
	paper.size = r.size
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.add_child(paper)
	var ink := Color.html(String(nd.get("ink", "#2b241b")))
	var y := 28.0
	if String(nd.get("title", "")) != "":
		var t := Label.new()
		t.name = "Title"
		t.text = StoryData.text(String(nd["title"]))
		t.position = Vector2(34, y)
		t.size = Vector2(r.size.x - 68, 40)
		t.add_theme_font_override("font", UiTheme.font("head"))
		t.add_theme_font_size_override("font_size", 28)
		t.add_theme_color_override("font_color", Color(ink, 0.75))
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		note.add_child(t)
		y += 56.0
	var body := Label.new()
	body.name = "Text"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = Gloss.plain(StoryData.text(String(nd.get("text", ""))))
	body.position = Vector2(34, y)
	body.size = Vector2(r.size.x - 68, r.size.y - y - 24)
	body.add_theme_font_override("font", UiTheme.font("body_italic"))
	body.add_theme_font_size_override("font_size", int(nd.get("font_size", 30)))
	body.add_theme_color_override("font_color", ink)
	body.add_theme_constant_override("line_spacing", 4)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.add_child(body)


# --- Input ----------------------------------------------------------------------------------

func _on_root_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and \
			(event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		root.accept_event()
		if StoryRunner.current_beat.is_empty():
			StoryRunner.close_examine()


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo and \
			(event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		StoryRunner.close_examine()
		return
	# G55: «Закрыть» closes at the first click even while Agata's line is up — the dialogue's modal (GameUi, the layer
	# above) would take that click and only turn the line; here, before the GUI, the button's place is ours.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and close_button != null and close_button.is_visible_in_tree() \
			and close_button.get_global_rect().has_point(event.position):
		get_viewport().set_input_as_handled()
		StoryRunner.close_examine()


func probe() -> Dictionary:
	var out := {"open": is_open(), "item": item_id}
	if not is_open():
		return out
	out["source"] = picture_source
	if picture != null:
		var r := picture.get_global_rect()
		out["picture"] = {"x": r.get_center().x, "y": r.get_center().y, "w": r.size.x, "h": r.size.y}
	var c := close_button.get_global_rect()
	out["close"] = {"x": c.get_center().x, "y": c.get_center().y}
	out["watch"] = dial != null
	out["note"] = note != null
	return out
