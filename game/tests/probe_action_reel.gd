extends SceneTree
## Video reel of the villagers' live figures (block 3, Director 05.11, 23:54: «запиши видео с анимациями, которые мы
## добавили»): each segment — one villager as NpcLive3D poses it in play (feet locks, calming, hands out of the body),
## on a plain backdrop with a caption, doing a state («idle», «talk», «listen») or a one-shot action clip.
##   xvfb-run godot --path game --write-movie <out.avi> --fixed-fps 30 --resolution 1920x1080 \
##       -s res://tests/probe_action_reel.gd -- <segments.json>
## segments.json: [{"id": "nina", "clip": "write_board" | "state": "talk", "s": 6, "yaw": 20, "title": "…"}, …]
##   "talk_as": role — with "state": "talk", that clip of the talk pool (NpcLive3D.talk_role)
##   "tone_off": true — the figure without rt3d.stance_tone (a «before» shot)

const DT := 1.0 / 30.0

var _bg: ColorRect
var _pic: TextureRect
var _cap: Label
var _sub: Label


func _initialize() -> void:
	_run()


func _fake_npc() -> Node2D:
	var s := GDScript.new()
	s.source_code = "extends Node2D\nvar sprite: Sprite2D = null\nvar sheet = null\n"
	s.reload()
	var n := Node2D.new()
	n.set_script(s)
	var sp := Sprite2D.new()
	n.add_child(sp)
	n.set("sprite", sp)
	var sh := GDScript.new()
	sh.source_code = "extends RefCounted\nvar texture_scale: float = 2.25\n"
	sh.reload()
	n.set("sheet", sh.new())
	root.add_child(n)
	return n


func _ui() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	_bg = ColorRect.new()
	_bg.color = Color(0.20, 0.19, 0.18)
	_bg.size = Vector2(1920, 1080)
	layer.add_child(_bg)
	var floor_r := ColorRect.new()
	floor_r.color = Color(0.27, 0.25, 0.23)
	floor_r.position = Vector2(0, 860)
	floor_r.size = Vector2(1920, 220)
	layer.add_child(floor_r)
	_pic = TextureRect.new()
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.position = Vector2(560, 40)
	_pic.size = Vector2(800, 1000)
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA   # the live figure's picture is premultiplied (rt3d.premultiplied)
	_pic.material = cm
	layer.add_child(_pic)
	_cap = Label.new()
	_cap.position = Vector2(60, 50)
	_cap.add_theme_font_size_override("font_size", 44)
	_cap.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	layer.add_child(_cap)
	_sub = Label.new()
	_sub.position = Vector2(60, 115)
	_sub.add_theme_font_size_override("font_size", 28)
	_sub.add_theme_color_override("font_color", Color(0.8, 0.76, 0.68))
	layer.add_child(_sub)


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var segs: Array = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	_ui()
	var NL = load("res://scripts/actors/npc_live_3d.gd")
	var lives := {}
	for seg in segs:
		var id := String(seg["id"])
		var key := id + ("#before" if bool(seg.get("tone_off", false)) else "")
		if not lives.has(key):
			var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
			if bool(seg.get("tone_off", false)):
				# «before»: the stance without rt3d.stance_tone (arms as the clips have them)
				(spec["rt3d"] as Dictionary).erase("stance_tone")
			var n := _fake_npc()
			var live = NL.new()
			n.add_child(live)
			if not live.setup(n, spec, 0.55):
				print("%s: not loaded" % id)
				continue
			live.view.set_render_scale(float(seg.get("scale", 2.2)))
			lives[key] = live
		if not lives.has(key):
			continue
		var lv = lives[key]
		for other in lives.values():
			other.view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if other == lv else SubViewport.UPDATE_DISABLED
		var yaw := deg_to_rad(float(seg.get("yaw", 15.0)))
		lv.face(Vector2(sin(yaw), cos(yaw) * 0.55), 0.55, true)
		_pic.texture = lv.view.get_texture()
		_cap.text = String(seg.get("title", id))
		_sub.text = String(seg.get("sub", ""))
		if seg.has("clip"):
			lv.set_state("idle")
			for i in 15:
				lv.process(DT)
				await process_frame
			if not lv.play_once(String(seg["clip"]), bool(seg.get("hold", false))):
				print("%s: no clip %s" % [id, seg["clip"]])
		else:
			if seg.has("talk_as"):
				# one clip of the figure's talk pool (rt3d.talk_pool), said at the talk tempo as in play
				lv.set_state("idle")
				var tp: Array = lv.rt.get("talk_pool", [])
				if not tp.has(String(seg["talk_as"])):
					tp.append(String(seg["talk_as"]))
				lv.rt["talk_pool"] = tp
				lv.talk_role = String(seg["talk_as"])
				lv._talk_key = "|"
			lv.set_state(String(seg.get("state", "idle")))
		var t := 0.0
		while t < float(seg.get("s", 5.0)):
			lv.process(DT)
			await process_frame
			t += DT
		if seg.has("clip"):
			lv.release_once()
			lv.set_state("idle")
	quit(0)
