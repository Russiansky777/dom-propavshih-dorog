extends SceneTree
## Hand-over geometry (Director 09.11 11:34: Tamara's key — Agata should take it from her hand at once): where the
## giver's hand goes over her one-shot clip and where Agata's hands go over her action, on screen, in the room as
## played. Prints per frame: the share of the clip, both hands (room px), so a staging can put Agata where the hands meet
## and switch the thing between them at the closest moment.
##   xvfb-run godot --path game --display-driver x11 --rendering-driver opengl3 --fixed-fps 30 \
##       -s res://tests/probe_give_take.gd -- <room> <npc_id> <npc_action> <agata x,y> <face x,y> <agata_action> [shot_dir|-]
##       [npc x,y|-] [hold_share]
## Prints the hands' grips too (Actor3D.hand_grip_frame_px — where a thing held in the fingers is).

var gs; var rm; var sd


func _initialize() -> void:
	_run()


func _bone(view, body: Sprite2D, bone: String) -> Vector2:
	if view == null or body == null:
		return Vector2.INF
	var px: Vector2 = view.call("bone_frame_px", bone)
	if px == Vector2.INF:
		return px
	return body.global_transform * (px + body.offset)


func _grip(view, body: Sprite2D, side: String) -> Vector2:
	if view == null or body == null:
		return Vector2.INF
	var px: Vector2 = view.call("hand_grip_frame_px", side)
	return body.global_transform * (px + body.offset) if px != Vector2.INF else px


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState"); rm = root.get_node("RoomManager"); sd = root.get_node("StoryData")
	var a := OS.get_cmdline_user_args()
	var room_id: String = a[0]; var npc_id: String = a[1]; var npc_act: String = a[2]
	var ap := a[3].split(","); var fp := a[4].split(",")
	var ag_pos := Vector2(float(ap[0]), float(ap[1])); var face := Vector2(float(fp[0]), float(fp[1]))
	var ag_act: String = a[5]
	var shots := a[6] if a.size() > 6 and a[6] != "-" else ""
	var npc_at := a[7] if a.size() > 7 else "-"
	var hold := float(a[8]) if a.size() > 8 else -1.0
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	for f in OS.get_environment("PG_FLAGS").split(",", false):
		gs.set_flag(f, true)
	rm.change_room(room_id, "default")
	for i in 20:
		await process_frame
	var pl: Node2D = rm.player
	pl.global_position = ag_pos
	pl.call("face_towards", face)
	var npc: Node2D = rm.current_room.get_node_or_null("npc_" + npc_id)
	if npc == null:
		print("no npc_", npc_id)
		quit(1)
		return
	if npc_at != "-":
		var q := npc_at.split(",")
		npc.global_position = Vector2(float(q[0]), float(q[1]))
	npc.call("face_towards", pl.global_position)
	for i in 60:
		await process_frame
	var live = npc.get("live")
	var secs := float(npc.call("play_action", npc_act, hold >= 0.0, hold, false))
	print("NPC %s %s %.2f s; npc at %s" % [npc_id, npc_act, secs, npc.global_position])
	var t := 0.0
	var k := 0
	if hold >= 0.0:
		secs = maxf(secs, 0.5)
	while t < secs + 0.2:
		await process_frame
		t += 1.0 / 30.0
		var rh := _bone(live.view, live.body, "RightHand")
		var lh := _bone(live.view, live.body, "LeftHand")
		var sh := _bone(live.view, live.body, "RightShoulder")
		var gr := _grip(live.view, live.body, "Right")
		var pinfo := ""
		for hp in npc.get("action_props"):
			var h3 = hp.get("hand3d")
			pinfo += " prop[%s on %s w %.2f%s]" % [hp.data.get("grip", ""), hp.call("shown"), hp.call("_during_w"), (" 3d vis %s at %s" % [h3.visible, h3.global_position]) if h3 != null else " no3d"]
		print("N %.3f share %.3f R %s grip %s L %s Rsh %s%s" % [t, t / secs, rh.round(), gr.round(), lh.round(), sh.round(), pinfo])
		if shots != "" and k % 6 == 0:
			root.get_viewport().get_texture().get_image().save_jpg("%s/npc_%03d.jpg" % [shots, k], 0.85)
		k += 1
	for i in 30:
		await process_frame
	# Agata's action where she stands
	pl.call("perform_at", pl.global_position, face, ag_act)
	t = 0.0
	k = 0
	while t < 6.0:
		await process_frame
		t += 1.0 / 30.0
		var v = pl.get("view3d")
		var b = pl.get("body3d")
		var rh := _bone(v, b, "RightHand")
		var lh := _bone(v, b, "LeftHand")
		var len := float(pl.get("_act_len"))
		var at := float(pl.get("_act_t"))
		print("A %.3f share %.3f acting %s R %s gripR %s L %s gripL %s" % [t, at / maxf(len, 0.01), pl.call("is_acting"), rh.round(), _grip(v, b, "Right").round(), lh.round(), _grip(v, b, "Left").round()])
		if shots != "" and k % 6 == 0:
			root.get_viewport().get_texture().get_image().save_jpg("%s/agata_%03d.jpg" % [shots, k], 0.85)
		k += 1
		if not bool(pl.call("is_acting")) and t > 0.5:
			break
	quit(0)
