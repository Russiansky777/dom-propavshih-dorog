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
## Block 3 (Director 05.11: villagers' actions with things in hand — Tamara's key, Nina's chalk, Ilya's knife): actor
## data rt3d.props {clip: [spec]} — a picture shown only while that one-shot clip plays (`during`), between the
## shares `from`..`until` of it, fading with the clip; `grip` "wrist" — it turns with the hand (forearm → hand on
## screen, plus `turn_deg`), held `out_rel` of the figure's height past the wrist, not hanging on a bail.
## Director 09.11, 11:34 («ключ приклеен на руку, а не в руке; Агата не забирает его в тот момент, он пропадает»):
## `grip` "fingers" — the thing is in the fingers: a picture inside the figure's own 3D render at the hand's grip
## (Actor3D.add_hand_prop: the fingers in front hide its gripped end), `size_m` its height, `anchor` the gripped px,
## `turn_deg`, `hang` / `tip_k` / `lift_m` (Actor3D.add_hand_prop opts); on sheets (no live 3D) it falls back to "wrist". A hand-over (StoryRunner staging `handover`) hides the
## giver's (`taken`) and shows the taker's from that moment (`shown_from`: the action's time; Agata — player.gd).

var npc: Node2D = null
var data: Dictionary = {}
var pic: Sprite2D = null
var glow: Sprite2D = null
var _t: float = 0.0
var _seed: float = 0.0
var hand3d: MeshInstance3D = null   # grip "fingers": the picture inside the 3D render
var taken: bool = false             # a hand-over: the thing went to the other hand
var fade_s: float = 0.0             # a hand-over: the giver's picture goes out over this long (the taker's comes in)
var _fade_t: float = -1.0
var _last_t: float = -1.0
var _last_act: String = ""


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


## The live figure's one-shot action now: {view, body, act, t, len, w} — a villager (NpcLive3D) or Agata (player.gd
## held_act_state); {} on sheets.
func _act_state() -> Dictionary:
	if npc.has_method("held_act_state"):
		return npc.call("held_act_state")
	var live = npc.get("live")
	if live == null or not is_instance_valid(live) or live.get("view") == null:
		return {}
	var act := String(live.get("act_name")) if bool(live.get("_once_clip")) else ""
	var L: float = live.view.action_length(act) if act != "" else 1.0
	return {"view": live.view, "body": live.get("body"), "act": act, "t": float(live.get("act_t")), "len": L,
		"w": float(live.view.shown_act_w())}


## The share of its one-shot clip now and how much of the clip is shown (0 — not playing `during`).
func _during_w() -> float:
	var st := _act_state()
	if st.is_empty() or String(st.get("act", "")) != String(data["during"]):
		return 0.0
	var f := float(st["t"]) / maxf(float(st["len"]), 0.01)
	if f < float(data.get("from", 0.0)) or f > float(data.get("until", 1.0)):
		return 0.0
	return clampf(float(st["w"]), 0.0, 1.0)


func flags_allow() -> bool:
	for f in data.get("if", []):
		if not GameState.has_flag(String(f)):
			return false
	for f in data.get("unless", []):
		if GameState.has_flag(String(f)):
			return false
	return true


## The figure's height on screen now (px): the sheet's figure at the villager's depth scale.
var _h_per_scale: float = 0.0   # the live figure's standing height per unit of its scale (the largest seen)


func _figure_h() -> float:
	# the live figure: feet to the top of the head (the head bone sits ~0.9 of the height) — standing: 09.11, Mitya bent
	# down to the lantern and it shrank with his lowered head; now the tallest seen per unit of the figure's scale, so
	# a bow does not shrink the thing and a walk into the distance still does
	var head := _bone_world("Head")
	var sc := maxf(absf(npc.global_scale.y), 0.001)
	if head != Vector2.INF and npc.global_position.y - head.y > 10.0:
		_h_per_scale = maxf(_h_per_scale, (npc.global_position.y - head.y) / 0.9 / sc)
	if _h_per_scale > 0.0:
		return _h_per_scale * sc
	var sheet = npc.get("sheet")
	var spr: Node2D = npc.get("sprite")
	var fh := float(sheet.figure_height_px) if sheet != null else 380.0
	var ss := absf(spr.scale.y) if spr != null else 1.0
	return fh * ss * absf(npc.global_scale.y)


## A bone of the live figure in the room's coordinates; Vector2.INF when drawn from sheets.
func _bone_world(bone: String) -> Vector2:
	var st := _act_state()
	if st.get("view") != null and st.get("body") != null:
		var v3 = st["view"]
		var b3: Sprite2D = st["body"]
		var px: Vector2 = v3.call("bone_frame_px", bone)
		if px != Vector2.INF and b3.is_visible_in_tree():
			return b3.global_transform * (px + b3.offset)
	return Vector2.INF


## grip "fingers": where the thing is held, in the room (the 3D grip projected); Vector2.INF on sheets.
func grip_screen() -> Vector2:
	var st := _act_state()
	if st.get("view") == null or st.get("body") == null:
		return Vector2.INF
	var side := "Left" if String(data.get("bone", "RightHand")).begins_with("Left") else "Right"
	var px: Vector2 = st["view"].call("hand_grip_frame_px", side)
	var b3: Sprite2D = st["body"]
	return b3.global_transform * (px + b3.offset) if px != Vector2.INF else Vector2.INF


## The hand-over (StoryRunner `handover`): the giver's picture goes out over `seconds` (0 — at once).
func give_away(seconds: float = 0.0) -> void:
	fade_s = seconds
	_fade_t = 0.0
	if seconds <= 0.0:
		taken = true


## Whether the picture is on now (tests).
func shown() -> bool:
	return (hand3d != null and hand3d.visible) or (pic != null and visible and pic.visible)


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
	_figure_h()   # measured while hidden too: the standing height is known before the thing is first shown
	var on := flags_allow() and npc.is_visible_in_tree()
	var dw := 1.0
	if data.has("during"):
		dw = _during_w()
		on = on and dw > 0.01
	# the clip starts again (a scene replayed in the same room): the hand-over is undone
	var st0 := _act_state()
	var at := float(st0.get("t", 0.0))
	var aa := String(st0.get("act", ""))
	if taken and data.has("during") and (aa != _last_act or at < _last_t - 0.05) and aa == String(data["during"]):
		taken = false
		_fade_t = -1.0
	_last_t = at
	_last_act = aa
	if taken:
		on = false
	if _fade_t >= 0.0 and not taken:
		_fade_t += delta
		dw *= clampf(1.0 - _fade_t / maxf(fade_s, 0.01), 0.0, 1.0)
		if _fade_t >= fade_s:
			taken = true
			on = false
	if String(data.get("grip", "")) in ["fingers", "body"] and _fingers(on, dw):
		visible = false
		return
	visible = on
	if not on or pic.texture == null:
		return
	modulate.a = dw
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
	if String(data.get("grip", "")) == "wrist":
		var side := "Left" if String(data.get("bone", "RightHand")).begins_with("Left") else "Right"
		var fa := _bone_world(side + "ForeArm")
		var hb := _bone_world(side + "Hand")
		if fa != Vector2.INF and hb != Vector2.INF and fa.distance_to(hb) > 1.0:
			var dir := (hb - fa).normalized()
			global_position = hb + dir * h * float(data.get("out_rel", 0.04))
			rotation = dir.angle() - PI * 0.5 + deg_to_rad(float(data.get("turn_deg", 0.0)))
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


## grip "fingers" on a live 3D figure: the picture inside its render (built once); false on sheets (2D fallback).
func _fingers(on: bool, dw: float) -> bool:
	var st := _act_state()
	var v3 = st.get("view")
	if v3 == null or not is_instance_valid(v3) or not v3.has_method("add_hand_prop"):
		return false
	if hand3d == null or not is_instance_valid(hand3d) or hand3d.get_parent() != v3:
		var side := "Left" if String(data.get("bone", "RightHand")).begins_with("Left") else "Right"
		var a: Array = data.get("anchor", [0, 0])
		var off: Array = data.get("offset_m", [0, 0, 0])
		hand3d = v3.add_hand_prop(pic.texture, side, float(data.get("size_m", 0.1)), Vector2(float(a[0]), float(a[1])), float(data.get("turn_deg", 0.0)),
			{"hang": bool(data.get("hang", false)), "tip_k": float(data.get("tip_k", 0.0)), "lift_m": float(data.get("lift_m", 0.0)),
			"bone": String(data.get("bone", "")) if String(data.get("grip", "")) == "body" else "",
			"offset": Vector3(float(off[0]), float(off[1]), float(off[2]))})
	hand3d.visible = on and dw > 0.02
	_strap(st, on and dw > 0.02)
	var m := hand3d.material_override as ShaderMaterial
	# the clip's fade in/out and a hand-over's fade: the picture's own alpha against the cut (alpha_cut 0.5 → thins
	# out) is too crude for a 3D quad — it simply shows while the weight is up
	if m != null:
		m.set_shader_parameter("alpha_cut", 0.5)
	return true


func _exit_tree() -> void:
	if hand3d != null and is_instance_valid(hand3d):
		hand3d.queue_free()
		hand3d = null
	if strap != null and is_instance_valid(strap):
		strap.queue_free()
		strap = null


var strap: Line2D = null


## grip "body" + `strap` {to: bone, up_m, from_uv: [u, v], width_px, color}: the strap from the worn thing's top to a
## shoulder, drawn over the figure (Tamara's bag: the strap across her back, as in the painted frame).
func _strap(st: Dictionary, on: bool) -> void:
	var sd: Dictionary = data.get("strap", {})
	if sd.is_empty():
		return
	if strap == null:
		strap = Line2D.new()
		strap.name = "Strap"
		strap.top_level = true
		strap.antialiased = true
		strap.width = float(sd.get("width_px", 4.0))
		strap.default_color = Color.html(String(sd.get("color", "#5a3b24")))
		npc.add_child(strap)   # not under this node: it is hidden while the picture is inside the 3D render
	var v3 = st.get("view")
	var b3: Sprite2D = st.get("body")
	strap.visible = on and v3 != null and b3 != null
	if not strap.visible:
		return
	var fu: Array = sd.get("from_uv", [0.85, 0.05])
	var p0: Vector2 = v3.call("hand_prop_point_px", hand3d, Vector2(float(fu[0]), float(fu[1])))
	var p1: Vector2 = v3.call("bone_point_px", String(sd.get("to", "LeftShoulder")), float(sd.get("up_m", 0.04)))
	if p0 == Vector2.INF or p1 == Vector2.INF:
		strap.visible = false
		return
	var a := b3.global_transform * (p0 + b3.offset)
	var b := b3.global_transform * (p1 + b3.offset)
	strap.clear_points()
	for i in 7:
		var t := float(i) / 6.0
		strap.add_point(a.lerp(b, t) + Vector2(0.0, 6.0 * 4.0 * t * (1.0 - t)))
	strap.z_index = clampi(int(npc.z_index) + 1, -4096, 4096)
	strap.z_as_relative = false
