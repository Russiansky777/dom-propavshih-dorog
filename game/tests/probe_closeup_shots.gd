extends SceneTree
## Review 17.11 (Director: «Кнопки покажи какие скрином», «заголовки крупных планов в строку — покажи что имеешь в
## виду»): pictures of Mama's letters (several pages: «‹ Назад» / «Дальше ›» beside «Закрыть») with Agata's line over
## them and without it, and of Mitya's board «Двадцать зарубок» — both titles wrap into two lines left of the picture.
##   SHOTS_DIR=<dir> xvfb-run -a -s "-screen 0 1920x1080x24" godot --audio-driver Dummy --rendering-driver opengl3 \
##     --resolution 1920x1080 --path game -s res://tests/probe_closeup_shots.gd

var gs
var rm
var sr
var sd
var _n := 0
var _dir := ""


func _initialize() -> void:
	var wd := float(OS.get_environment("WATCHDOG")) if OS.get_environment("WATCHDOG") != "" else 1200.0
	create_timer(wd).timeout.connect(func(): print("watchdog"); quit(1))
	_run()


func _shot(tag: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	_n += 1
	print("%02d %-14s room %s view %s beat «%s»" % [_n, tag, String(rm.current_room.room_id) if rm.current_room != null else "-",
		String(sr.view.get("id", "")) if sr.view_open else "-", String(sr.current_beat.get("text", "")).left(50)])
	if _dir != "" and DisplayServer.get_name() != "headless":
		root.get_viewport().get_texture().get_image().save_jpg("%s/c%02d_%s.jpg" % [_dir, _n, tag], 0.9)


func _hotspot(id: String) -> Node:
	if rm.current_room == null:
		return null
	for h in rm.current_room.find_children("*", "", true, false):
		if h.get("hotspot_id") != null and String(h.get("hotspot_id")) == id:
			return h
	return null


func _settle(n: int) -> void:
	for i in n:
		await process_frame


## Clicks the hotspot, waits for its close-up and its first line; a picture with the line, then one after it.
func _view_of(id: String, tag: String) -> void:
	var h := _hotspot(id)
	if h == null:
		print("no hotspot %s in %s" % [id, String(rm.current_room.room_id)])
		return
	sr.interact(h)
	for i in 900:
		await process_frame
		if sr.view_open and not sr.current_beat.is_empty():
			break
	await _settle(40)
	await _shot(tag + "_line")
	for g in 60:
		if sr.current_beat.is_empty():
			break
		sr.advance()
		await _settle(10)
	await _settle(30)
	await _shot(tag + "_quiet")
	sr.close_view()
	await _settle(20)


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	sd = root.get_node("StoryData")
	_dir = OS.get_environment("SHOTS_DIR")
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	await _settle(4)
	rm.autosave_enabled = false
	rm.start_with((sd.start_points.get("freewalk", {}) as Dictionary).duplicate(true))
	for i in 900:
		await process_frame
		if i > 30 and not sr.is_busy():
			break
	rm.change_room("O3", "from_O4")
	await _settle(60)
	await _view_of("nina_letters", "letters")
	rm.change_room("O4", "default")
	await _settle(60)
	await _view_of("mitya_board", "board")
	quit(0)
