class_name HeldProp
extends Node2D
## A thing a villager carries in his hand, drawn as a picture hanging from the hand bone of his live 3D figure
## (Director 02.11, стр. 21: «после сцены с Митей фонарь пропадает куда-то» → «подумай, как лучше и красивее»: Mitya
## lifts his lantern and goes up to the street — Agata «следом, на свет»; M19 «Впереди Митя с фонарём»). Rooms data on
## the villager's hotspot: `held` {image, anchor [x, y] (the picture's px where the hand grips — the top of the bail),
## height_rel (its height as a share of the figure's), bone, if, unless, glow {color, radius_rel, alpha, at [x, y] —
## the glass centre in picture px, flicker}}. The picture hangs straight down (a bail swings, it does not turn with the
## wrist); with the figure drawn from sheets (no live 3D), it hangs at `sheet_hand` [x, y] — share of the figure's
## width/height from the feet — so tests and the web build still see it.

var npc: Node2D = null
var data: Dictionary = {}
var pic: Sprite2D = null
var glow: Sprite2D = null
var _t: float = 0.0
var _seed: float = 0.0


static func attach(the_npc: Node2D, spec: Dictionary) -> HeldProp:
	var hp := HeldProp.new()
	hp.name = "Held"
	hp.npc = the_npc
	hp.data = spec
	hp._build()
	# drawn in the room over the figure (the hand is in front of the body seen from the side it is held on)
	the_npc.add_child(hp)
	return hp


func _build() -> void:
	top_level = true
	_seed = float(absi(hash(String(npc.name))) % 1000) * 0.37
	pic = Sprite2D.new()
	pic.name = "Picture"
	pic.centered = false
	var img := String(data.get("image", ""))
	if img != "" and ResourceLoader.exists(img):
		pic.texture = load(img)
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var g: Dictionary = data.get("glow", {})
	if not g.is_empty():
		glow = Sprite2D.new()
		glow.name = "Glow"
		glow.texture = _radial()
		var cm := CanvasItemMaterial.new()
		cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = cm
		glow.modulate = Color.html(String(g.get("color", "#ffb35a")))
		add_child(glow)
	add_child(pic)


static var _radial_tex: Texture2D = null


static func _radial() -> Texture2D:
	if _radial_tex == null:
		var gt := GradientTexture2D.new()
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 128
		gt.height = 128
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 1))
		gr.set_color(1, Color(1, 1, 1, 0))
		gr.add_point(0.35, Color(1, 1, 1, 0.45))
		gt.gradient = gr
		_radial_tex = gt
	return _radial_tex


func flags_allow() -> bool:
	for f in data.get("if", []):
		if not GameState.has_flag(String(f)):
			return false
	for f in data.get("unless", []):
		if GameState.has_flag(String(f)):
			return false
	return true


## The figure's height on screen now (px): the sheet's figure at the villager's depth scale.
func _figure_h() -> float:
	# the live figure: feet to the top of the head as drawn now (the head bone sits ~0.9 of the height)
	var head := _bone_world("Head")
	if head != Vector2.INF and npc.global_position.y - head.y > 10.0:
		return (npc.global_position.y - head.y) / 0.9
	var sheet = npc.get("sheet")
	var spr: Node2D = npc.get("sprite")
	var fh := float(sheet.figure_height_px) if sheet != null else 380.0
	var ss := absf(spr.scale.y) if spr != null else 1.0
	return fh * ss * absf(npc.global_scale.y)


## A bone of the live figure in the room's coordinates; Vector2.INF when drawn from sheets.
func _bone_world(bone: String) -> Vector2:
	var live = npc.get("live")
	if live != null and is_instance_valid(live) and live.get("view") != null and live.get("body") != null:
		var v3 = live.get("view")
		var b3: Sprite2D = live.get("body")
		var px: Vector2 = v3.call("bone_frame_px", bone)
		if px != Vector2.INF and b3.is_visible_in_tree():
			return b3.global_transform * (px + b3.offset)
	return Vector2.INF


## Where the hand is in the room: the live figure's bone, else the sheet fallback.
func hand_screen() -> Vector2:
	var hb := _bone_world(String(data.get("bone", "RightHand")))
	if hb != Vector2.INF:
		return hb
	var sh: Array = data.get("sheet_hand", [0.22, 0.45])
	var h := _figure_h()
	return npc.global_position + Vector2(float(sh[0]) * h, -float(sh[1]) * h)


func _process(delta: float) -> void:
	_t += delta
	var on := flags_allow() and npc.is_visible_in_tree()
	visible = on
	if not on or pic.texture == null:
		return
	var h := _figure_h()
	var ts := pic.texture.get_size()
	var k := h * float(data.get("height_rel", 0.2)) / maxf(ts.y, 1.0)
	var a: Array = data.get("anchor", [ts.x * 0.5, 0.0])
	# the hand bone sits at the wrist: the bail is gripped in the fingers, a palm's length lower (data drop_rel × height)
	var hand := hand_screen() + Vector2(0.0, h * float(data.get("drop_rel", 0.06)))
	# a little pendulum on the bail while he walks or turns — never more than a few degrees
	var sway := sin(_t * 3.1 + _seed) * deg_to_rad(float(data.get("sway_deg", 2.5)))
	global_position = hand
	rotation = sway
	pic.scale = Vector2(k, k)
	pic.position = -Vector2(float(a[0]), float(a[1])) * k
	z_index = clampi(int(npc.z_index) + 1, -4096, 4096)
	z_as_relative = false
	if glow != null:
		var g: Dictionary = data["glow"]
		var gc: Array = g.get("at", [ts.x * 0.5, ts.y * 0.55])
		glow.position = pic.position + Vector2(float(gc[0]), float(gc[1])) * k
		var r := h * float(g.get("radius_rel", 0.35))
		glow.scale = Vector2.ONE * (r / 64.0)
		var fl := 1.0 + float(g.get("flicker", 0.08)) * (sin(_t * 11.0 + _seed) * 0.6 + sin(_t * 23.7) * 0.4)
		glow.modulate.a = float(g.get("alpha", 0.35)) * fl
