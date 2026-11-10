extends SceneTree
## Plays the game by a script of commands and takes shots — the night's survey tool (Director 09.11, 22:18: «пересмотри
## игру и найди все недочёты… кадр за кадром»). Run under a display:
##   xvfb-run godot --path game --display-driver x11 --rendering-driver opengl3 --resolution 960x540 --fixed-fps 30 \
##       -s res://tests/probe_play.gd -- <out_dir> <start_point> <cmd> <cmd> …
## Commands (one argument each):
##   wait:S          — S seconds (engine time)
##   click:X,Y       — Agata clicks the room point (as the player)
##   walkend         — wait until Agata stops walking (≤ 20 s)
##   scene:ID        — start the scene
##   adv             — advance the current line (option 0 for a choice) once its staging is done
##   adv:N           — N times, each after the staging and `line_s` seconds (default 0.3)
##   line_s:S        — seconds a line stays before `adv:N` advances it
##   flag:F          — set a flag
##   room:ID[,spawn] — change the room (a scene with trigger `enter` starts as in the game)
##   info            — print the scene, its line, the frame
##   mech:METHOD[,ARG] — call the open mechanic panel's method (windlass: mech:signal_pressed,lower)
##   frame:ID        — show a frame (FrameView)
##   shot:NAME       — screenshot <out>/<NAME>.jpg (whole screen)
##   crop:X,Y,W,H    — later shots are cropped (source px 1920×1080 space); crop:- resets
##   film:NAME,S,STEP — a frame every STEP s for S s → <out>/<NAME>_NNN.jpg
##   npc:ID          — print the villager's position, yaw, state, act
##   agata           — print Agata's position, walking, acting, action
##   hand:ID[,Left]  — print where the villager's hand is on screen
## Prints "shot NAME" per shot; the screen is 1920×1080 in design px (the viewport is scaled).


var out := ""
var crop := Rect2i(0, 0, 0, 0)
var line_s := 0.3
var rm; var sr; var gs; var sd


func _initialize() -> void:
	_run()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	if crop.size.x > 0:
		var k := float(img.get_width()) / 1920.0
		var r := Rect2i(int(crop.position.x * k), int(crop.position.y * k), int(crop.size.x * k), int(crop.size.y * k))
		img = img.get_region(r.intersection(Rect2i(0, 0, img.get_width(), img.get_height())))
	img.save_jpg("%s/%s.jpg" % [out, name], 0.9)
	print("shot ", name)


func _npc(id: String) -> Node:
	for n in root.find_children("*", "Node2D", true, false):
		var aid = n.get("actor_id")
		if aid != null and str(aid) == id:
			return n
	return null


func _wait(s: float) -> void:
	var n := int(ceil(s * 30.0))
	for i in n:
		await process_frame


func _advance_once() -> void:
	var g := 0
	while g < 3000 and (sr.is_staging() or sr.current_beat.is_empty()):
		g += 1
		await process_frame
	if sr.current_beat.is_empty():
		return
	if sr.current_beat.get("type") == "options":
		sr.choose(String(sr.current_beat["options"][0]["id"]))
	else:
		sr.advance()


func _run() -> void:
	await process_frame
	rm = root.get_node("RoomManager"); sr = root.get_node("StoryRunner"); gs = root.get_node("GameState"); sd = root.get_node("StoryData")
	var a := OS.get_cmdline_user_args()
	out = a[0]
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	rm.start_at(a[1])
	for i in 30:
		await process_frame
	for i in range(2, a.size()):
		var c: String = a[i]
		var k := c.split(":", true, 1)
		var cmd := k[0]
		var arg := k[1] if k.size() > 1 else ""
		match cmd:
			"wait":
				await _wait(float(arg))
			"click":
				var p := arg.split(",")
				rm.player.call("click_at", Vector2(float(p[0]), float(p[1])))
			"walkend":
				var g := 0
				await _wait(0.2)
				while g < 600 and bool(rm.player.call("is_walking")):
					g += 1
					await process_frame
			"scene":
				sr.start_scene(arg)
			"room":
				var rp := arg.split(",")
				rm.change_room(rp[0], rp[1] if rp.size() > 1 else "default")
				await _wait(1.0)
			"mech":
				# the open mechanic's own input by name: mech:signal_pressed,lower
				var mp := arg.split(",")
				var done := false
				for nd in root.find_children("*", "", true, false):
					if nd.has_method(mp[0]) and nd is CanvasItem and (nd as CanvasItem).is_visible_in_tree():
						if mp.size() > 1:
							nd.call(mp[0], mp[1])
						else:
							nd.call(mp[0])
						done = true
						break
				print("  mech ", arg, " → ", done)
			"info":
				print("scene %s staging %s frame %s beat %s" % [sr.active_scene, sr.is_staging(), sr.get("current_frame"), str(sr.current_beat).substr(0, 160)])
			"adv":
				var n := int(arg) if arg != "" else 1
				for j in n:
					await _advance_once()
					await _wait(line_s)
					print("  adv → ", sr.current_beat.get("line_id", sr.current_beat.get("type", "-")), " frame ", sr.get("current_frame"))
			"line_s":
				line_s = float(arg)
			"flag":
				gs.set_flag(arg, true)
			"frame":
				sr.set_frame(arg, false)
			"shot":
				await _shot(arg)
			"crop":
				if arg == "-":
					crop = Rect2i(0, 0, 0, 0)
				else:
					var p := arg.split(",")
					crop = Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3]))
			"film":
				var p := arg.split(",")
				var t := 0.0
				var n := 0
				while t < float(p[1]):
					await _shot("%s_%03d" % [p[0], n])
					n += 1
					await _wait(float(p[2]))
					t += float(p[2])
			"npc":
				var n = _npc(arg)
				if n == null:
					print("npc %s: not found" % arg)
				else:
					var live = n.get("live")
					print("npc %s pos %s state %s act %s yaw %s" % [arg, n.global_position.round(), live.get("state") if live else "-", live.get("once") if live else "-", rad_to_deg(float(live.get("yaw"))) if live else "-"])
			"hand":
				# hand:ID[,Left] — where the villager's hand is on screen (design px)
				var hp := arg.split(",")
				var hn = _npc(hp[0])
				var hl = hn.get("live") if hn != null else null
				if hl == null:
					print("hand %s: no live figure" % arg)
				else:
					var b: Sprite2D = hl.get("body")
					var side := hp[1] if hp.size() > 1 else "Right"
					var aa = hl.get("act_arm")
					print("hand %s %s: %s  (feet %s, act %s w %.2f; arm tweak %s)" % [hp[0], side, (b.global_transform * (hl.view.hand_grip_frame_px(side) + b.offset)).round(), hn.global_position.round(), hl.get("act_name"), hl.view.shown_act_w(), ("%.2f × %.0f° bone %d clip %s" % [aa.weight, rad_to_deg(aa.angle), aa.bone, aa.clip]) if aa != null else "none"])
			"agata":
				var pl = rm.player
				print("agata pos %s walking %s acting %s action %s" % [pl.global_position.round(), pl.call("is_walking"), pl.call("is_acting"), pl.call("current_action")])
			_:
				print("unknown command ", c)
	quit(0)
