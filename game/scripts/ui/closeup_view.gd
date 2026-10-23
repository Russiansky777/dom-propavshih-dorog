class_name CloseupView
extends CanvasLayer
## Look-only close-up of a hotspot (rooms data `view`), opened by StoryRunner.open_view() when the
## hotspot is clicked; its use / look text plays in the dialogue box above it (GameUi is layer 5, this
## is layer 4), so what the text says is on screen while it is read and heard.
##
## type "mirror" (H3 «Домашнее зеркало», Director 18.10: «не интуитивно — показать то, что описывается»):
##   - the mirror face-on, cut from the room's own painting: the glass quadrilateral of the side-wall
##     mirror (`frame.glass_quad`, background pixels) is mapped to an upright rectangle (`frame.glass`)
##     by a homography in shaders/closeup_mirror.gdshader; frame and wall follow the same mapping;
##   - in the glass a live reflection: `GalleryView` — a SubViewport sharing the game world, framed on
##     the gallery behind Agata (`reflection.gallery`), drawing the room only (canvas_cull_mask 1; the
##     player is moved to visibility layer 2 while the close-up is open) — and Agata herself, an
##     AnimatedSprite2D with the player's own frames facing the glass (`reflection.agata.row`), her
##     current idle frame and light tone every frame. The shader mirrors it left↔right, darkens and
##     cools it, adds old-glass waves. The mirror hangs in its own place, so it shows an ordinary
##     reflection (not a view of anywhere else);
##   - next to it the old photograph the text speaks of: the same wall of the same painting
##     (`photo.region`) in sepia (shaders/closeup_photo.gdshader) — nothing added to the picture.
## type "papers" (O1 teacher's drawer, M07): what lies in the drawer, side by side — `pictures` (a thing's own
##   picture: the photo print, the child's drawing), `photos` (each like `photo` below: a region of a painting in
##   sepia with a caption) and `papers` (a sheet with a title and handwritten text in the game's italic: the plan
##   «Тому, кто придёт через эту дверь…»). Until their own art is drawn these are the
##   stand-ins (assets/manifest.json); the text of the scene plays over them as usual.
## `zoom_from` [x, y, w, h] (screen px — where the thing hangs in the room): the close-up rides in from there to
##   the full view, like the Zarechye plan at the post office (Director 23.10, F19 «чтобы можно было приблизить,
##   как карту на почте» — the shift board at the mill).
## A paper with `"sheet": "none"` draws no sheet of its own — only its words, over a sheet painted in a picture
##   (the board close-up: the paper is in the art, the text is the game's): `blocks` [{rect [x, y, w, h] in the
##   paper's rect, title?, text?, font_size?, title_size?, align?: "center"}], the whole set turned by `angle_deg`
##   with the paper.
## Closes with a click once the text is over, with «Закрыть», or with Esc (the mouse alone is enough).

const LAYER := 4
const MIRROR_SHADER: Shader = preload("res://shaders/closeup_mirror.gdshader")
const PHOTO_SHADER: Shader = preload("res://shaders/closeup_photo.gdshader")
const PLAYER_VIEW_LAYER := 2     # the player's visibility layer while the reflection is built
const ROOM_VIEW_MASK := 1        # the gallery view draws the room only

var spec: Dictionary = {}
var root: Control = null
var title_label: Label = null
var mirror_rect: TextureRect = null
var mirror_material: ShaderMaterial = null
var gallery_vp: SubViewport = null
var reflection_vp: SubViewport = null
var agata: AnimatedSprite2D = null
var photo: Control = null
var sheets: Array[Control] = []  # every photo / paper of a "papers" close-up (probe, tests)
## `pages` [{title?, pictures, photos, papers}]: a close-up of several spreads turned with «‹ Назад» / «Дальше ›»
## (Evdokia's notebooks, Nina's letters — blocks 3 and 5); every page's sheets are built at once, one is shown.
var pages: Array[Control] = []
var page_index: int = 0
var prev_button: Button = null
var next_button: Button = null
var _into: Control = null        # where the builders put sheets: the view itself or the page being built
var close_button: Button = null
var glass_screen_rect: Rect2 = Rect2()
var _player: Node2D = null
var _player_layer_saved: int = -1


func _ready() -> void:
	layer = LAYER
	visible = false
	StoryRunner.view_opened.connect(_open)
	StoryRunner.view_closed.connect(_close)


func is_open() -> bool:
	return visible and root != null


const ZOOM_S := 0.55
var _zoom_tween: Tween = null


func _open(s: Dictionary) -> void:
	_free_nodes()
	spec = s
	_build()
	visible = true
	if spec.has("zoom_from"):
		_zoom_in(_rect_of(spec["zoom_from"]))


func _rect_of(a) -> Rect2:
	if a is Array and a.size() >= 4:
		return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
	return Rect2()


## The view rides in from where the thing hangs (the whole 1920×1080 view scaled into `from` by width,
## centred on it) to the full screen; it fades in while it starts.
func _zoom_in(from: Rect2) -> void:
	if root == null or from.size.x <= 4.0:
		return
	var k := from.size.x / 1920.0
	var start_pos := from.get_center() - Vector2(1920.0, 1080.0) * k * 0.5
	root.pivot_offset = Vector2.ZERO
	root.scale = Vector2(k, k)
	root.position = start_pos
	root.modulate.a = 0.0
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.set_parallel(true)
	_zoom_tween.tween_property(root, "scale", Vector2.ONE, ZOOM_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_zoom_tween.tween_property(root, "position", Vector2.ZERO, ZOOM_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_zoom_tween.tween_property(root, "modulate:a", 1.0, ZOOM_S * 0.4)


## True while the close-up is still riding in (tests, probes).
func zooming() -> bool:
	return _zoom_tween != null and _zoom_tween.is_valid() and _zoom_tween.is_running()


func _close() -> void:
	visible = false
	_restore_player()
	_free_nodes()
	spec = {}


func _free_nodes() -> void:
	for n in [root, gallery_vp, reflection_vp]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	root = null
	gallery_vp = null
	reflection_vp = null
	agata = null
	mirror_rect = null
	mirror_material = null
	photo = null
	sheets.clear()
	pages.clear()
	page_index = 0
	prev_button = null
	next_button = null
	_into = null
	close_button = null


func _build() -> void:
	root = Control.new()
	root.name = "View"
	root.position = Vector2.ZERO
	root.size = Vector2(1920, 1080)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.gui_input.connect(_on_root_input)
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.06, 1.0)
	bg.size = root.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var t := UiTheme.get_theme()
	title_label = Label.new()
	title_label.name = "Title"
	title_label.text = StoryData.text(String(spec.get("title", "")))
	title_label.position = Vector2(40, 100)
	title_label.size = Vector2(520, 60)
	title_label.theme = t
	title_label.theme_type_variation = &"CloseupTitle"
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_label)
	_into = root
	if String(spec.get("type", "")) == "mirror":
		_build_mirror()
	_build_sheets(spec)
	for i in spec.get("pages", []).size():
		var pg := Control.new()
		pg.name = "Page%d" % i
		pg.size = root.size
		pg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(pg)
		_into = pg
		_build_sheets(spec["pages"][i])
		var pt := String(spec["pages"][i].get("title", ""))
		if pt != "":
			pg.set_meta("title", StoryData.text(pt))
		pages.append(pg)
	_into = root
	if not pages.is_empty():
		_build_page_buttons(t)
		_show_page(0)
	close_button = Button.new()
	close_button.name = "Close"
	close_button.text = StoryData.text(String(spec.get("close_label", "@ui.close")))
	close_button.size = Vector2(200, 56)
	close_button.position = Vector2(1680, 990)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.theme = t
	close_button.pressed.connect(func(): StoryRunner.close_view())
	root.add_child(close_button)


func _build_sheets(sp: Dictionary) -> void:
	if sp.has("photo"):
		_build_photo(sp["photo"])
	for ph in sp.get("photos", []):
		_build_photo(ph)
	for pi in sp.get("pictures", []):
		_build_picture(pi)
	for pa in sp.get("papers", []):
		_build_paper(pa)


func _build_page_buttons(t: Theme) -> void:
	prev_button = Button.new()
	prev_button.name = "Prev"
	prev_button.text = StoryData.text("@ui.page_prev")
	prev_button.size = Vector2(200, 56)
	prev_button.position = Vector2(1240, 990)
	prev_button.focus_mode = Control.FOCUS_NONE
	prev_button.theme = t
	prev_button.pressed.connect(func(): turn_page(-1))
	root.add_child(prev_button)
	next_button = Button.new()
	next_button.name = "Next"
	next_button.text = StoryData.text("@ui.page_next")
	next_button.size = Vector2(200, 56)
	next_button.position = Vector2(1460, 990)
	next_button.focus_mode = Control.FOCUS_NONE
	next_button.theme = t
	next_button.pressed.connect(func(): turn_page(1))
	root.add_child(next_button)


## Turns to the next (+1) / previous (−1) page of a `pages` close-up; the page's title replaces the view's.
func turn_page(step: int) -> void:
	if pages.is_empty():
		return
	_show_page(clampi(page_index + step, 0, pages.size() - 1))


func _show_page(i: int) -> void:
	page_index = i
	for k in pages.size():
		pages[k].visible = k == i
	if title_label != null:
		title_label.text = String(pages[i].get_meta("title", StoryData.text(String(spec.get("title", "")))))
	if prev_button != null:
		prev_button.disabled = i == 0
	if next_button != null:
		next_button.disabled = i == pages.size() - 1


# --- Mirror ---------------------------------------------------------------------------------

func _build_mirror() -> void:
	var fr: Dictionary = spec.get("frame", {})
	var image := String(fr.get("image", ""))
	if image == "" or not ResourceLoader.exists(image):
		push_warning("CloseupView: mirror frame image missing: %s" % image)
		return
	var tex: Texture2D = load(image)
	var src_size := tex.get_size()
	var glass := _v2(fr.get("glass", [300, 714]))
	var mg: Array = fr.get("margin", [120, 210, 120, 150])   # left, top, right, bottom (canvas px)
	var canvas := Vector2(float(mg[0]) + glass.x + float(mg[2]), float(mg[1]) + glass.y + float(mg[3]))
	var glass_pos := Vector2(float(mg[0]), float(mg[1]))
	var dst: Array[Vector2] = [glass_pos, glass_pos + Vector2(glass.x, 0), glass_pos + glass, glass_pos + Vector2(0, glass.y)]
	var src: Array[Vector2] = []
	for p in fr.get("glass_quad", []):
		src.append(_v2(p))
	var h := homography(dst, src)
	var r: Array = fr.get("rect", [470, 110, 0, 840])
	var disp_h := float(r[3])
	var disp_w := float(r[2]) if float(r[2]) > 0.0 else disp_h * canvas.x / canvas.y
	var k := disp_h / canvas.y
	mirror_rect = TextureRect.new()
	mirror_rect.name = "Mirror"
	mirror_rect.texture = tex
	mirror_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mirror_rect.stretch_mode = TextureRect.STRETCH_SCALE
	mirror_rect.position = Vector2(float(r[0]), float(r[1]))
	mirror_rect.size = Vector2(disp_w, disp_h)
	mirror_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mirror_material = ShaderMaterial.new()
	mirror_material.shader = MIRROR_SHADER
	mirror_material.set_shader_parameter("homography", _basis(h))
	mirror_material.set_shader_parameter("canvas_size", canvas)
	mirror_material.set_shader_parameter("src_size", src_size)
	mirror_material.set_shader_parameter("glass_rect", Color(glass_pos.x, glass_pos.y, glass.x, glass.y))
	var rf: Dictionary = spec.get("reflection", {})
	if rf.has("tint"):
		mirror_material.set_shader_parameter("tint", Color.html(String(rf["tint"])))
	for key in ["tint_amount", "dim", "haze", "waviness"]:
		if rf.has(key):
			mirror_material.set_shader_parameter(key, float(rf[key]))
	mirror_rect.material = mirror_material
	root.add_child(mirror_rect)
	glass_screen_rect = Rect2(mirror_rect.position + glass_pos * k, glass * k)
	_build_reflection(glass, rf)
	if reflection_vp != null:
		mirror_material.set_shader_parameter("reflection", reflection_vp.get_texture())
		mirror_material.set_shader_parameter("reflection_on", 1.0)
	else:
		mirror_material.set_shader_parameter("reflection_on", 0.0)


## The reflection: the gallery (the live room, without Agata) and Agata facing the glass, composed in a
## SubViewport of the glass's size; the mirror shader flips it.
func _build_reflection(glass: Vector2, rf: Dictionary) -> void:
	var res := float(rf.get("resolution", 1.0))
	var size := Vector2i(maxi(int(glass.x * res), 8), maxi(int(glass.y * res), 8))
	# Gallery: the game world itself through our own canvas transform.
	gallery_vp = SubViewport.new()
	gallery_vp.name = "GalleryView"
	gallery_vp.size = size
	gallery_vp.disable_3d = true
	gallery_vp.transparent_bg = false
	gallery_vp.canvas_cull_mask = ROOM_VIEW_MASK
	gallery_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	gallery_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	var g: Dictionary = rf.get("gallery", {})
	var gh := float(g.get("height", 1020.0))
	var gw := gh * glass.x / glass.y
	var left := float(g.get("center_x", 776.0)) - gw / 2.0
	var top := float(g.get("top", 60.0))
	var gk := float(size.y) / gh
	add_child(gallery_vp)
	# World first (inside the tree), then the transform: it is set on the shared world's canvas.
	gallery_vp.world_2d = get_viewport().world_2d
	gallery_vp.canvas_transform = Transform2D(0.0, Vector2(gk, gk), 0.0, Vector2(-left * gk, -top * gk))
	_hide_player_from_gallery()
	# Composition: gallery + Agata.
	reflection_vp = SubViewport.new()
	reflection_vp.name = "Reflection"
	reflection_vp.size = size
	reflection_vp.disable_3d = true
	reflection_vp.transparent_bg = false
	reflection_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	reflection_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	add_child(reflection_vp)
	var gal := Sprite2D.new()
	gal.name = "Gallery"
	gal.centered = false
	gal.texture = gallery_vp.get_texture()
	reflection_vp.add_child(gal)
	var player: Node2D = RoomManager.player
	var sprite: AnimatedSprite2D = player.get("sprite") if player != null and is_instance_valid(player) else null
	var sheet = player.get("sheet") if player != null and is_instance_valid(player) else null
	if sprite == null or sheet == null or sprite.sprite_frames == null:
		return
	var a: Dictionary = rf.get("agata", {})
	agata = AnimatedSprite2D.new()
	agata.name = "Agata"
	agata.sprite_frames = sprite.sprite_frames
	agata.centered = false
	agata.offset = sheet.sprite_offset()
	agata.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var anim: String = sheet.anim_name(String(sheet.idle_action), int(a.get("row", 0)))
	if agata.sprite_frames.has_animation(anim):
		agata.animation = anim
	var fig_h := float(sheet.figure_height_px) if float(sheet.figure_height_px) > 0.0 else 337.0
	var sc := float(a.get("height", 0.92)) * float(size.y) / fig_h
	agata.scale = sheet.sprite_scale() * sc  # sc: unit px → screen; the sheet's own px are 1/texture_scale of them
	agata.position = Vector2(float(a.get("x", 0.5)) * size.x, float(a.get("feet", 1.22)) * size.y)
	reflection_vp.add_child(agata)
	_sync_agata()


func _hide_player_from_gallery() -> void:
	_player = RoomManager.player
	if _player == null or not is_instance_valid(_player):
		_player = null
		return
	_player_layer_saved = int(_player.visibility_layer)
	_player.visibility_layer = PLAYER_VIEW_LAYER


func _restore_player() -> void:
	if _player != null and is_instance_valid(_player) and _player_layer_saved >= 0:
		_player.visibility_layer = _player_layer_saved
	_player = null
	_player_layer_saved = -1


## Agata in the glass breathes with Agata in the room: same idle frame, same light tone.
func _sync_agata() -> void:
	if agata == null:
		return
	var player: Node2D = RoomManager.player
	var sprite: AnimatedSprite2D = player.get("sprite") if player != null and is_instance_valid(player) else null
	if sprite == null:
		return
	var n := agata.sprite_frames.get_frame_count(agata.animation)
	var f := sprite.frame if String(sprite.animation).begins_with(String(agata.animation).get_slice("_", 0) + "_") else 0
	agata.frame = clampi(f, 0, maxi(n - 1, 0))
	agata.self_modulate = sprite.self_modulate


func _process(_delta: float) -> void:
	if visible and agata != null:
		_sync_agata()


# --- Photo ----------------------------------------------------------------------------------

func _build_photo(p: Dictionary) -> void:
	var image := String(p.get("image", ""))
	if image == "" or not ResourceLoader.exists(image):
		return
	var tex: Texture2D = load(image)
	var reg: Array = p.get("region", [0, 0, 400, 500])
	var region := Rect2(float(reg[0]), float(reg[1]), float(reg[2]), float(reg[3]))
	var r: Array = p.get("rect", [1150, 200, 470, 0])
	var w := float(r[2])
	var h := float(r[3]) if float(r[3]) > 0.0 else w * region.size.y / region.size.x
	var border := float(p.get("border", 18.0))
	photo = Control.new()
	photo.name = "Photo"
	photo.position = Vector2(float(r[0]), float(r[1]))
	photo.size = Vector2(w + border * 2.0, h + border * 2.0 + 34.0)
	photo.pivot_offset = photo.size / 2.0
	photo.rotation = deg_to_rad(float(p.get("angle_deg", -3.0)))
	photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_into.add_child(photo)
	var shadow := ColorRect.new()
	shadow.color = Color(0, 0, 0, 0.45)
	shadow.position = Vector2(10, 12)
	shadow.size = photo.size
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo.add_child(shadow)
	var paper := ColorRect.new()
	paper.name = "Paper"
	paper.color = Color(0.86, 0.80, 0.68)
	paper.size = photo.size
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo.add_child(paper)
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = region
	var pic := TextureRect.new()
	pic.name = "Picture"
	pic.texture = at
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.position = Vector2(border, border)
	pic.size = Vector2(w, h)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = PHOTO_SHADER
	pic.material = mat
	photo.add_child(pic)
	var cap := Label.new()
	cap.name = "Caption"
	cap.text = StoryData.text(String(p.get("label", "")))
	cap.position = Vector2(border, border + h + 2.0)
	cap.size = Vector2(w, 32)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_color_override("font_color", Color(0.30, 0.22, 0.14))
	cap.theme = UiTheme.get_theme()
	cap.theme_type_variation = &"CloseupLabel"
	cap.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0))
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo.add_child(cap)
	sheets.append(photo)


## A picture of a thing as it is (its own paper edges and transparency — a photo print, a child's drawing):
## `image`, `rect` [x, y, w, h = 0 → by aspect], `angle_deg`, optional `label` under it; the shadow is the
## picture's own silhouette.
func _build_picture(p: Dictionary) -> void:
	var image := String(p.get("image", ""))
	if image == "" or not ResourceLoader.exists(image):
		push_warning("CloseupView: picture missing: %s" % image)
		return
	var tex: Texture2D = load(image)
	var r: Array = p.get("rect", [100, 150, 500, 0])
	var w := float(r[2])
	var h := float(r[3]) if float(r[3]) > 0.0 else w * tex.get_height() / maxf(tex.get_width(), 1.0)
	var holder := Control.new()
	holder.name = "Picture%d" % sheets.size()
	holder.position = Vector2(float(r[0]), float(r[1]))
	holder.size = Vector2(w, h + (40.0 if p.has("label") else 0.0))
	holder.pivot_offset = Vector2(w, h) / 2.0
	holder.rotation = deg_to_rad(float(p.get("angle_deg", 0.0)))
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_into.add_child(holder)
	for i in 2:
		var tr := TextureRect.new()
		tr.name = "Shadow" if i == 0 else "Image"
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.size = Vector2(w, h)
		tr.position = Vector2(10, 12) if i == 0 else Vector2.ZERO
		tr.modulate = Color(0, 0, 0, 0.45) if i == 0 else Color.WHITE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tr)
	if p.has("label"):
		var cap := Label.new()
		cap.name = "Text"
		cap.text = StoryData.text(String(p["label"]))
		cap.position = Vector2(0, h + 6.0)
		cap.size = Vector2(w, 34)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.theme = UiTheme.get_theme()
		cap.theme_type_variation = &"CloseupLabel"
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(cap)
	sheets.append(holder)


## A sheet of paper: `rect` [x, y, w, h], `angle_deg`, `paper` / `ink` / `edge` colours, `title` and `text`
## (keys of data/story/text), `font_size` of the text (the game's italic, as if written by hand).
## With `image` (a drawn sheet — the plan of the crossing, art batch 2) the picture is the sheet (h 0 — by its
## aspect) and the text goes into its free field `text_rect` [x, y, w, h], given in the pixels of the original
## picture `image_size` (the copy in the game may be smaller).
func _build_paper(p: Dictionary) -> void:
	# A sheet whose picture is ordered and not delivered yet (`pending` — a request in assets/manifest.json, batch 9:
	# clean notebook pages, Nina's blank letter): its `stub` keys replace the sheet's own until the file is imported
	# (the old picture with paper patches over its pseudo-writing; `"image": null` — the engine's plain sheet).
	if p.has("stub") and p.has("image") and not ResourceLoader.exists(String(p["image"])):
		var st: Dictionary = p["stub"]
		p = p.duplicate()
		p.erase("stub")
		for k in st.keys():
			if st[k] == null:
				p.erase(k)
			elif not String(k).begins_with("_"):
				p[k] = st[k]
	var r: Array = p.get("rect", [700, 200, 500, 500])
	var tex: Texture2D = null
	if p.has("image"):
		if not ResourceLoader.exists(String(p["image"])):
			push_warning("CloseupView: paper image missing: %s" % p["image"])
			return
		tex = load(String(p["image"]))
	var w := float(r[2])
	var h := float(r[3])
	if h <= 0.0 and tex != null:
		h = w * tex.get_height() / maxf(tex.get_width(), 1.0)
	var sheet := Control.new()
	sheet.name = "Paper%d" % sheets.size()
	sheet.position = Vector2(float(r[0]), float(r[1]))
	sheet.size = Vector2(w, h)
	sheet.pivot_offset = sheet.size / 2.0
	sheet.rotation = deg_to_rad(float(p.get("angle_deg", 0.0)))
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_into.add_child(sheet)
	if String(p.get("sheet", "")) == "none":
		_build_sheet_words(sheet, p)
		sheets.append(sheet)
		return
	var shadow := ColorRect.new()
	shadow.color = Color(0, 0, 0, 0.45)
	shadow.position = Vector2(10, 12)
	shadow.size = sheet.size
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(shadow)
	if tex != null:
		var pic := TextureRect.new()
		pic.name = "Sheet"
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_SCALE
		pic.size = sheet.size
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sheet.add_child(pic)
		var src: Array = p.get("image_size", [tex.get_width(), tex.get_height()])
		var k := w / maxf(float(src[0]), 1.0)
		# `covers` [[x, y, w, h, "#paper"], …] in the picture's pixels: patches of clean paper over painted
		# pseudo-writing («каша» on the aunt's notebook pages, G33) until the clean picture comes (batch 9).
		for ci in p.get("covers", []).size():
			var cv: Array = p["covers"][ci]
			var patch := ColorRect.new()
			patch.name = "Cover%d" % ci
			patch.color = Color.html(String(cv[4]) if cv.size() > 4 else "#e6d8b8")
			patch.position = Vector2(float(cv[0]), float(cv[1])) * k
			patch.size = Vector2(float(cv[2]), float(cv[3])) * k
			patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sheet.add_child(patch)
		var tr: Array = p.get("text_rect", [0, 0, src[0], src[1]])
		var body_i := Label.new()
		body_i.name = "Text"
		# wrap before text and size: a Label without wrapping is as wide as its text and keeps that width
		body_i.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body_i.text = StoryData.text(String(p.get("text", "")))
		body_i.position = Vector2(float(tr[0]), float(tr[1])) * k
		body_i.size = Vector2(float(tr[2]), float(tr[3])) * k
		body_i.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# `font`: "hand" — handwriting (G31/G33: Nina's letters, the aunt's notebooks); body_italic by default.
		body_i.add_theme_font_override("font", UiTheme.font(String(p.get("font", "body_italic"))))
		body_i.add_theme_font_size_override("font_size", int(p.get("font_size", 24)))
		body_i.add_theme_color_override("font_color", Color.html(String(p.get("ink", "#2e2a24"))))
		body_i.add_theme_constant_override("line_spacing", 0)
		body_i.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sheet.add_child(body_i)
		sheets.append(sheet)
		return
	if p.has("edge"):
		var edge := ColorRect.new()
		edge.color = Color.html(String(p["edge"]))
		edge.position = Vector2(-3, -3)
		edge.size = sheet.size + Vector2(6, 6)
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sheet.add_child(edge)
	var paper := ColorRect.new()
	paper.name = "Sheet"
	paper.color = Color.html(String(p.get("paper", "#e3d6b4")))
	paper.size = sheet.size
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(paper)
	var ink := Color.html(String(p.get("ink", "#2e2a24")))
	var pad := 26.0
	var y := pad * 0.8
	if String(p.get("title", "")) != "":
		var title := Label.new()
		title.name = "Title"
		title.text = StoryData.text(String(p["title"]))
		title.position = Vector2(pad, y)
		title.size = Vector2(sheet.size.x - pad * 2.0, 34)
		title.add_theme_font_override("font", UiTheme.font("head"))
		title.add_theme_font_size_override("font_size", 24)
		title.add_theme_color_override("font_color", Color(ink, 0.7))
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sheet.add_child(title)
		y += 44.0
	var body := Label.new()
	body.name = "Text"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = StoryData.text(String(p.get("text", "")))
	body.position = Vector2(pad, y)
	body.size = Vector2(sheet.size.x - pad * 2.0, sheet.size.y - y - pad * 0.6)
	body.add_theme_font_override("font", UiTheme.font(String(p.get("font", "body_italic"))))
	body.add_theme_font_size_override("font_size", int(p.get("font_size", 28)))
	body.add_theme_color_override("font_color", ink)
	body.add_theme_constant_override("line_spacing", 2)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(body)
	sheets.append(sheet)


## Words only, over a sheet painted in a picture under it (`"sheet": "none"`): each block — a title in the
## heading face and / or a text in the game's italic, as if written by hand, inside its rect of the sheet.
func _build_sheet_words(sheet: Control, p: Dictionary) -> void:
	var ink := Color.html(String(p.get("ink", "#2e2a24")))
	var i := 0
	for b in p.get("blocks", []):
		var r: Array = b.get("rect", [0, 0, sheet.size.x, sheet.size.y])
		var box := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
		var y := box.position.y
		var center := String(b.get("align", "")) == "center"
		if String(b.get("title", "")) != "":
			var t := Label.new()
			t.name = "Title%d" % i
			t.text = StoryData.text(String(b["title"]))
			t.position = Vector2(box.position.x, y)
			var ts := int(b.get("title_size", 34))
			t.size = Vector2(box.size.x, ts * 1.4)
			t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT
			t.add_theme_font_override("font", UiTheme.font("head_bold"))
			t.add_theme_font_size_override("font_size", ts)
			t.add_theme_color_override("font_color", Color(ink, 0.88))
			t.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sheet.add_child(t)
			y += ts * 1.5
		if String(b.get("text", "")) != "":
			var body := Label.new()
			body.name = "Text%d" % i
			body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.text = StoryData.text(String(b["text"]))
			body.position = Vector2(box.position.x, y)
			body.size = Vector2(box.size.x, maxf(box.end.y - y, 10.0))
			body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT
			body.add_theme_font_override("font", UiTheme.font("body_italic"))
			body.add_theme_font_size_override("font_size", int(b.get("font_size", p.get("font_size", 26))))
			body.add_theme_color_override("font_color", ink)
			body.add_theme_constant_override("line_spacing", int(b.get("line_spacing", 0)))
			body.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sheet.add_child(body)
		i += 1


# --- Input ----------------------------------------------------------------------------------

## A click on the close-up once its text is over closes it (the dialogue box above takes the clicks
## while the text is shown).
func _on_root_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and \
			(event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		root.accept_event()
		if StoryRunner.current_beat.is_empty():
			StoryRunner.close_view()


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo and \
			(event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		StoryRunner.close_view()


# --- Probe / tests --------------------------------------------------------------------------

func probe() -> Dictionary:
	var out := {"open": is_open(), "id": String(spec.get("id", "")), "type": String(spec.get("type", ""))}
	if not is_open():
		return out
	out["close"] = _center(close_button)
	out["blank"] = {"x": 1500.0, "y": 900.0}
	out["glass"] = {"x": glass_screen_rect.position.x, "y": glass_screen_rect.position.y,
		"w": glass_screen_rect.size.x, "h": glass_screen_rect.size.y}
	if photo != null:
		out["photo"] = _center(photo)
	var sh: Array = []
	for c in sheets:
		var t: Label = c.get_node_or_null("Text") as Label
		var words: Array = []
		for ch in c.get_children():
			if ch is Label and (String(ch.name).begins_with("Title") or String(ch.name).begins_with("Text")):
				words.append((ch as Label).text)
		sh.append({"name": String(c.name), "center": _center(c), "text": t.text if t != null else "\n".join(words)})
	out["sheets"] = sh
	out["pages"] = pages.size()
	out["page"] = page_index
	out["zooming"] = zooming()
	if next_button != null:
		out["next"] = _center(next_button)
		out["prev"] = _center(prev_button)
	out["reflection"] = {"agata": String(agata.animation) if agata != null else "",
		"agata_frame": agata.frame if agata != null else -1,
		"shares_world": gallery_vp != null and gallery_vp.world_2d == get_viewport().world_2d}
	return out


func _center(c: Control) -> Dictionary:
	if c == null:
		return {}
	var r := c.get_global_rect()
	return {"x": r.position.x + r.size.x / 2, "y": r.position.y + r.size.y / 2}


# --- Math -----------------------------------------------------------------------------------

static func _v2(a) -> Vector2:
	if a is Vector2:
		return a
	return Vector2(float(a[0]), float(a[1]))


## 3×3 projective map taking the 4 points `from` to the 4 points `to` (row-major, h[8] = 1).
static func homography(from: Array[Vector2], to: Array[Vector2]) -> PackedFloat64Array:
	var m: Array = []
	for i in 4:
		var x := from[i].x
		var y := from[i].y
		var u := to[i].x
		var v := to[i].y
		m.append([x, y, 1.0, 0.0, 0.0, 0.0, -x * u, -y * u, u])
		m.append([0.0, 0.0, 0.0, x, y, 1.0, -x * v, -y * v, v])
	# Gauss–Jordan with partial pivoting on the 8×9 augmented matrix.
	for c in 8:
		var piv := c
		for rr in range(c + 1, 8):
			if absf(m[rr][c]) > absf(m[piv][c]):
				piv = rr
		var tmp = m[c]
		m[c] = m[piv]
		m[piv] = tmp
		var d: float = m[c][c]
		if absf(d) < 1e-12:
			return PackedFloat64Array([1, 0, 0, 0, 1, 0, 0, 0, 1])
		for j in 9:
			m[c][j] = m[c][j] / d
		for rr in 8:
			if rr == c:
				continue
			var f: float = m[rr][c]
			if f == 0.0:
				continue
			for j in 9:
				m[rr][j] = m[rr][j] - f * m[c][j]
	var h := PackedFloat64Array()
	for i in 8:
		h.append(m[i][8])
	h.append(1.0)
	return h


static func apply_homography(h: PackedFloat64Array, p: Vector2) -> Vector2:
	var w := h[6] * p.x + h[7] * p.y + h[8]
	return Vector2((h[0] * p.x + h[1] * p.y + h[2]) / w, (h[3] * p.x + h[4] * p.y + h[5]) / w)


## Row-major 3×3 → Basis whose columns are the GLSL mat3 columns (M * v in the shader = h · v).
static func _basis(h: PackedFloat64Array) -> Basis:
	return Basis(Vector3(h[0], h[3], h[6]), Vector3(h[1], h[4], h[7]), Vector3(h[2], h[5], h[8]))
