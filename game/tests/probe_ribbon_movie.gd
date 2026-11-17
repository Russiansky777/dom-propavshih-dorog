extends SceneTree
## Mama's ribbon as it plays in the game, for the Director (17.11: «видео как в игре полностью этот диалог и лента и
## возвращение обратно»): the evening of day two in the horenka (start point bedtime2), the ribbon taken from its
## pocket in the bag, a click on Mama, Agata goes to her, the close-up of the braiding opens with the narrator's words
## (voice), the words are clicked away, «Закрыть», back in the room — the ribbon's pocket is empty. Real clicks through
## Input, as the player's mouse. Run with a display and Godot's movie writer (sound included):
##   xvfb-run godot --path game --write-movie out.avi --fixed-fps 30 --resolution 1920x1080 \
##       -s res://tests/probe_ribbon_movie.gd

const FPS := 30.0

var gs
var rm
var sr
var sd
var _mouse := Vector2(960, 700)


func _initialize() -> void:
	# a watchdog: a script error stops `_run` but not the movie writer — the recording ends anyway
	create_timer(150.0).timeout.connect(func(): print("[ribbon] watchdog: 150 s"); quit(1))
	_run()


func _hold(seconds: float) -> void:
	for i in int(seconds * FPS):
		await process_frame


func _move(to: Vector2, seconds: float) -> void:
	var from := _mouse
	var n := maxi(1, int(seconds * FPS))
	for i in n:
		var t := float(i + 1) / float(n)
		t = t * t * (3.0 - 2.0 * t)
		_mouse = from.lerp(to, t)
		var m := InputEventMouseMotion.new()
		m.position = root.get_final_transform() * _mouse
		m.global_position = m.position
		# with a display the system pointer is the mouse the game reads (the first take: it stayed in the middle of
		# the screen, and the ribbon went to the notches on the door frame) — it is moved too
		Input.warp_mouse(m.position)
		Input.parse_input_event(m)
		await process_frame


func _click() -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = root.get_final_transform() * _mouse
		ev.global_position = ev.position
		Input.parse_input_event(ev)
		await process_frame


func _ui() -> Node:
	for n in root.find_children("*", "", true, false):
		if n.get_script() != null and String(n.get_script().resource_path).ends_with("ui/game_ui.gd"):
			return n
	return null


func _nina_center() -> Vector2:
	for h in rm.current_room.find_children("*", "", true, false):
		if h.get("hotspot_id") != null and String(h.get("hotspot_id")) == "nina":
			var r: Array = (h.get("data") as Dictionary).get("rect", [1250, 160, 160, 630])
			return Vector2(float(r[0]) + float(r[2]) / 2.0, float(r[1]) + float(r[3]) * 0.4)
	return Vector2(1330, 400)


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	sd = root.get_node("StoryData")
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	rm.start_with((sd.start_points.get("bedtime2", {}) as Dictionary).duplicate(true))
	for i in 600:
		await process_frame
		if i > 30 and not sr.is_busy():
			break
	if not gs.has_item("school_ribbon"):
		gs.set_flag("has_school_ribbon")
		gs.add_item("school_ribbon")
	await _hold(2.0)
	# the ribbon from its pocket
	var ui := _ui()
	var inv: Dictionary = ui.call("probe_positions").get("inventory", {}) if ui != null else {}
	if inv.has("school_ribbon"):
		await _move(Vector2(float(inv["school_ribbon"]["x"]), float(inv["school_ribbon"]["y"])), 1.0)
		await _hold(0.6)
		await _click()
	else:
		print("[ribbon] the ribbon's pocket is not on the bag's page — picked by the runner")
		sr.select_item("school_ribbon")
	await _hold(1.4)
	# to Mama
	await _move(_nina_center(), 1.0)
	await _hold(0.4)
	await _click()
	var vd := root.get_node_or_null("VoiceDirector")
	var g := 0
	while g < int(30 * FPS) and not sr.view_open:
		g += 1
		await process_frame
	print("[ribbon] close-up open: %s after %.1f s" % [str(sr.view_open), g / FPS])
	# the narrator's words over the close-up, as long as they are said, then a moment more
	g = 0
	while g < int(40 * FPS):
		g += 1
		await process_frame
		if sr.current_beat.is_empty():
			break
		if vd != null and bool(vd.call("line_being_said", sr.current_beat)):
			continue
		print("[ribbon] line: «%s»" % String(sr.current_beat.get("text", "")).left(60))
		await _hold(1.6)
		sr.advance()
		await _hold(0.2)
	await _hold(1.8)
	# «Закрыть» — where the close-up put it
	var close_at := Vector2(1780, 1038)
	for n in root.find_children("Close", "Button", true, false):
		var b := n as Button
		if b.is_visible_in_tree() and b.get_parent() != null and String(b.get_parent().get_path()).contains("Closeup"):
			close_at = b.get_global_rect().get_center()
	print("[ribbon] before close: beat empty %s, close at %s" % [str(sr.current_beat.is_empty()), str(close_at)])
	await _move(close_at, 0.9)
	await _hold(0.4)
	await _click()
	await _hold(0.6)
	print("[ribbon] closed: %s; ribbon in the bag: %s; braided: %s" % [str(not sr.view_open), str(gs.has_item("school_ribbon")), str(gs.has_flag("ribbon_braided"))])
	# back in the room; the mouse to the bag — the ribbon's pocket is empty now
	if inv.has("school_ribbon"):
		await _move(Vector2(float(inv["school_ribbon"]["x"]), float(inv["school_ribbon"]["y"])), 1.0)
	await _hold(3.0)
	quit(0)
