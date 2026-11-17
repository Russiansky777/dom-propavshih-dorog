extends Node
## A record of what the player is shown while a bot plays (the review of 15.11, Director 22:38: «перепройди ещё раз игру
## целиком и полностью и поищи, не осталось ли… багов, недоработок, неясностей сюжета, не интуитивности»): every room
## entered, scene started and ended, line said (speaker and text, choices), hint, thing received, mini-game, frame —
## and the journal's goal whenever it changes — appended to the file named by the environment variable PLAY_LOG.
## A bot adds it when the variable is set (run_tests.gd, test_day2.gd, test_day3.gd); the game itself never does.

var _f: FileAccess = null
var _goal := ""
var _last_line := ""
var sr: Node
var rm: Node
var sd: Node


func _ready() -> void:
	var path := OS.get_environment("PLAY_LOG")
	if path == "":
		queue_free()
		return
	_f = FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	if _f == null:
		queue_free()
		return
	_f.seek_end()
	sr = get_node("/root/StoryRunner")
	rm = get_node("/root/RoomManager")
	sd = get_node("/root/StoryData")
	rm.room_changed.connect(func(id):
		_w("\n== комната %s" % id)
		await get_tree().create_timer(0.4).timeout
		_shot("room " + String(id)))
	sr.scene_started.connect(func(id): _w("\n-- сцена %s «%s»" % [id, String(sd.scene(id).get("title", ""))]))
	sr.scene_completed.connect(func(id): _w("-- конец %s" % id))
	sr.beat_changed.connect(_on_beat)
	sr.hint_revealed.connect(func(tier, text): _w("   [подсказка %d] %s" % [tier, text]))
	sr.item_received.connect(func(id): _w("   [получено] %s" % id))
	sr.mechanic_opened.connect(func(spec): _w("   [мини-игра] %s %s" % [String(spec.get("type", "")), String(spec.get("title", ""))]))
	sr.frame_changed.connect(func(id, _hold):
		_w("   [кадр] %s" % id)
		await get_tree().create_timer(0.6).timeout
		_shot("frame " + String(id)))
	sr.mechanic_opened.connect(func(spec):
		await get_tree().create_timer(0.5).timeout
		_shot("mech " + String(spec.get("type", ""))))
	sr.day_card_requested.connect(func(key, _b): _w("   [карточка дня] %s" % key))
	sr.checkpoint_saved.connect(func(slot, title): _w("   [сохранение] %s «%s»" % [slot, title]))
	sr.examine_opened.connect(func(id): _w("   [осмотр] %s" % id))
	sr.panel_requested.connect(func(id, _src): _w("   [панель] %s" % id))


func _w(s: String) -> void:
	if _f != null:
		_f.store_line(s)
		_f.flush()


## With a display and PLAY_SHOTS=<dir>: a picture of the screen for every line and room, numbered as in the log.
var _shot_n := 0
var _shot_busy := false


func _shot(tag: String) -> void:
	var dir := OS.get_environment("PLAY_SHOTS")
	if dir == "" or DisplayServer.get_name() == "headless" or _shot_busy:
		return
	_shot_busy = true
	_shot_n += 1
	var n := _shot_n
	_w("   [снимок %04d] %s" % [n, tag])
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_jpg("%s/%04d.jpg" % [dir, n], 0.8)
	_shot_busy = false


func _on_beat() -> void:
	var b: Dictionary = sr.current_beat
	if b.is_empty():
		return
	var key := "%s|%s|%s" % [b.get("type", ""), b.get("line_id", ""), b.get("text", "")]
	if key == _last_line:
		return
	_last_line = key
	match String(b.get("type", "")):
		"line":
			_w("%s: %s" % [String(b.get("speaker_name", b.get("speaker", ""))), String(b.get("text", ""))])
			_shot(String(b.get("line_id", "")))
		"choice", "options":
			# ревью 17.11: the runner's choices are beats of type "options" — their buttons were logged empty
			# (the runner's options are {"id", "label", …} — StoryRunner._choice_beat; the question is "prompt")
			var opts: Array = []
			for o in b.get("options", []):
				opts.append(str((o as Dictionary).get("label", (o as Dictionary).get("id", ""))) if o is Dictionary else str(o))
			_w("   [выбор] %s → %s" % [str(b.get("prompt", b.get("text", ""))), " / ".join(opts)])
		_:
			_w("   [%s] %s" % [String(b.get("type", "")), String(b.get("text", ""))])


func _process(_dt: float) -> void:
	if sr == null:
		return
	var g := String(sr.journal_goal())
	if g != _goal:
		_goal = g
		_w("   [цель в дневнике] %s" % g)
