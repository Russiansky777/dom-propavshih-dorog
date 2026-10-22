extends MechanicPanel
## M09, the photograph on the wall of the mill passage (M2): the office from inside, the mirror in its old
## frame on its place opposite the door, with a caption saying what the photograph is. A click anywhere puts
## it away; opening it is the look (event "seen" → `seen_office_photo`).
## Art: «Фото в сенях» (партия 3, closeup_office_photo — an old sepia print with its own worn edge). Data
## `photo.sepia` / `photo.paper` / `photo.mirror` keep the stand-in path (a room painting in sepia on a paper
## mount with the mirror's frame drawn by the engine) for a photograph that has no art yet.

var photo: Control = null


func build() -> void:
	var p: Dictionary = spec.get("photo", {})
	var reg: Array = p.get("region", [0, 0, 1672, 941])
	var pos := v2(p.get("pos", [360, 170]))
	var k := float(p.get("scale", 0.72))
	var size := Vector2(float(reg[2]), float(reg[3])) * k
	var pad := 22.0 if bool(p.get("paper", true)) else 0.0
	photo = Control.new()
	photo.name = "Photo"
	photo.position = pos - Vector2(pad, pad)
	photo.size = size + Vector2(pad * 2, pad + 68)
	photo.pivot_offset = photo.size * 0.5
	photo.rotation = deg_to_rad(float(p.get("angle_deg", -2.0)))
	photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(photo)
	if pad > 0.0:
		var paper := ColorRect.new()
		paper.color = Color(0.86, 0.80, 0.68)
		paper.size = photo.size
		paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		photo.add_child(paper)
	var pic := crop(String(p.get("image", "")), reg, Vector2(pad, pad), k, photo)
	pic.name = "Picture"
	if bool(p.get("sepia", true)):
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/closeup_photo.gdshader")
		pic.material = mat
	# Stand-in only: the mirror on its old place drawn on a room painting that has none on that wall.
	if p.has("mirror"):
		var m: Array = p["mirror"]
		var frame := Panel.new()
		frame.name = "Mirror"
		frame.position = Vector2(pad, pad) + Vector2(float(m[0]), float(m[1]))
		frame.size = Vector2(float(m[2]), float(m[3]))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.62, 0.58, 0.5)
		sb.border_color = Color(0.25, 0.18, 0.1)
		sb.set_border_width_all(10)
		frame.add_theme_stylebox_override("panel", sb)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		photo.add_child(frame)
	var cap := Label.new()
	cap.name = "Caption"
	cap.text = text("label_caption")
	cap.position = Vector2(pad, pad + size.y + 12)
	cap.size = Vector2(size.x, 40)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if pad > 0.0:
		cap.add_theme_color_override("font_color", Color(0.30, 0.22, 0.14))
	else:
		cap.theme_type_variation = &"CloseupLabel"
	cap.add_theme_font_override("font", UiTheme.font("body_italic"))
	cap.add_theme_font_size_override("font_size", 26)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo.add_child(cap)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_input)


func opened() -> void:
	event("seen")


func _on_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if not dialogue_up():
			StoryRunner.close_mechanic()


func probe() -> Dictionary:
	return {"photo": center_of(photo)}
