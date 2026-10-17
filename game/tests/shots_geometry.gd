extends SceneTree
## Evidence frames for the room geometry (not a test; needs a display — tools/shots_geometry.sh runs it
## under Xvfb with the OpenGL renderer):
##   xvfb-run -s "-screen 0 1920x1080x24" godot --path game --display-driver x11 \
##     --rendering-driver opengl3 -s res://tests/shots_geometry.gd -- <out_dir>
## For every in-scope room: the real game (Main.tscn) enters the room, Agata walks from the default
## spawn towards the first `no_walk_samples` point (what a click into the counter / water / desks
## does) and the frame is saved after she stops: Docs/evidence/M1/geometry_<LOC>.png. A thin overlay
## shows the floor outline (green), holes (red), the clicked point (red cross) and where she stopped
## (yellow ring) — so the frame shows she stops at the edge instead of walking through.

var _out_dir := ""
var _overlay: Node2D = null


class Overlay extends Node2D:
	var outline := PackedVector2Array()
	var holes: Array = []
	var target := Vector2.ZERO
	var stop := Vector2.ZERO
	var caption := ""

	func _draw() -> void:
		if outline.size() >= 3:
			var o := outline.duplicate()
			o.append(outline[0])
			draw_polyline(o, Color(0.2, 1.0, 0.3, 0.75), 3.0)
		for h in holes:
			var hh: PackedVector2Array = h.duplicate()
			hh.append(h[0])
			draw_polyline(hh, Color(1.0, 0.25, 0.25, 0.85), 3.0)
		var c := Color(1, 0.15, 0.15, 1)
		draw_line(target + Vector2(-14, -14), target + Vector2(14, 14), c, 4.0)
		draw_line(target + Vector2(-14, 14), target + Vector2(14, -14), c, 4.0)
		draw_arc(stop, 16.0, 0.0, TAU, 32, Color(1, 0.9, 0.1, 1), 4.0)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(24, 1060), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, 1))
		draw_string_outline(font, Vector2(24, 1060), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 6, Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(24, 1060), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, 1))


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://../Docs/evidence/M1")
	_run()


static func _pt(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func _run() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	var sd = root.get_node("StoryData")
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await process_frame
	await process_frame
	rm.autosave_enabled = false
	var player: Node2D = main_node.get_node("World/Player")
	player.set("speed_factor", 4.0)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var made := 0
	for rid in sd.rooms_index.get("in_scope", []):
		var spec: Dictionary = sd.room(rid)
		var samples: Array = spec.get("no_walk_samples", [])
		if samples.is_empty():
			continue
		rm.change_room(rid, "default")
		for i in 8:
			await physics_frame
		var room: Node = rm.current_room
		var start: Vector2 = room.get_spawn("default").position
		var s0: Array = samples[0]
		var target := _pt(s0)
		player.call("walk_to", target)
		var frames := 0
		while player.call("is_walking") and frames < 1200:
			await physics_frame
			frames += 1
		for i in 20:
			await process_frame
		var stop: Vector2 = player.global_position
		if _overlay != null and is_instance_valid(_overlay):
			_overlay.queue_free()
		_overlay = Overlay.new()
		_overlay.z_index = 4096
		_overlay.outline = PackedVector2Array()
		for p in spec.get("walkable", []):
			_overlay.outline.append(_pt(p))
		for h in spec.get("walkable_holes", []):
			var hv := PackedVector2Array()
			for p in h:
				hv.append(_pt(p))
			_overlay.holes.append(hv)
		_overlay.target = target
		_overlay.stop = stop
		_overlay.caption = "%s: клик в «%s» %s → Агата остановилась в %s (от точки %d px)" % [
			rid, String(s0[2]) if s0.size() > 2 else "препятствие", str(target.round()), str(stop.round()), int(stop.distance_to(target))]
		room.add_child(_overlay)
		# The cursor never moves in this run and the hover caption of a hotspot freed with the previous
		# room stays on screen (game_ui._set_hover: a freed _hover_node compares equal to null) — hide it.
		var hover: Node = main_node.find_child("Hover", true, false)
		if hover is CanvasItem:
			(hover as CanvasItem).visible = false
		await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		if img.get_width() != 1920:
			img.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)
		var path := _out_dir.path_join("geometry_%s.png" % rid)
		img.save_png(path)
		made += 1
		print("geometry frame %s: start %s → click %s → stop %s (%d frames) → %s" % [rid, str(start), str(target), str(stop.round()), frames, path])
	gs.reset()
	quit(0 if made > 0 else 1)
