extends SceneTree
## Title screen and pause menu (Director 23.10: «главное меню и меню паузы … пауза всплывает на первый план, чуть
## замыливая картинку; по Esc»):
##   - the title shows on launch (and the game waits under it); a test runner or a start point skips it;
##   - its items act: «Продолжить» only with a save and loads the newest one, «Новая игра», «Загрузить» and «Настройки»
##     open the panel in their mode, «Выход» only off the web;
##   - Esc opens the pause over a blurred, paused game and closes it again; the «Меню» button opens it too;
##   - Esc closes an open close-up (item examine), the journal or the save panel first, and only then the pause;
##   - the pause items act: Save / Load / Settings panels, «В главное меню» → the title, «Продолжить» there loads
##     the save; Save and Load are held while a line is on screen.
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_menus.gd
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var main_node: Node = null
var ui: Node = null
var title: Node = null
var pause: Node = null
var player: Node2D = null
var SLOT := "test_menus_%d" % OS.get_process_id()
var AUTO := "test_menus_auto_%d" % OS.get_process_id()
var _reached_end: bool = false


func _initialize() -> void:
	_run()


func _check(cond: bool, message: String) -> void:
	if not cond:
		_fails.append(message)


func _test(test_name: String, fn: Callable) -> void:
	_fails = []
	_reached_end = false
	var started := Time.get_ticks_msec()
	await fn.call()
	if not _reached_end:
		_fails.append("the test stopped before its end (script error?)")
	var passed := _fails.is_empty()
	_results.append([test_name, passed])
	print("%s  %s  (%d ms)" % ["PASS" if passed else "FAIL", test_name, Time.get_ticks_msec() - started])
	for f in _fails:
		print("        - " + f)


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	gs.reset()
	rm.autosave_slot = AUTO
	await _test("A test runner (a -s script) skips the title: the game starts at once, as before", _test_skip)
	await _test("The title on launch: the panel art, the signature layer, the animated background; the game waits, paused", _test_title_launch)
	await _test("Title items: «Продолжить» only with a save (and gone once the saves are deleted in «Загрузить»); «Загрузить» / «Настройки» open the panel in their mode; «Новая игра» starts", _test_title_items)
	await _test("Esc opens the pause over the blurred game, the game stands still; Esc again closes it; «Меню» opens it too", _test_pause_esc)
	await _test("Esc closes a close-up, the journal, the save panel first — only then the pause", _test_esc_order)
	await _test("Pause items: Save / Load / Settings panels, held during a line; «В главное меню» → title → «Продолжить» loads the save", _test_pause_items)
	_teardown()
	gs.reset()
	for s in [SLOT, AUTO]:
		gs.delete_save(s)
	paused = false
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== menus: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _seconds(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _setup(mode: String) -> void:
	_teardown()
	gs.reset()
	paused = false
	rm.current_room = null
	main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", mode)
	root.add_child(main_node)
	await _frames(3)
	ui = main_node.get_node("GameUi")
	title = main_node.get_node("Title")
	pause = main_node.get_node("Pause")
	player = main_node.get_node("World/Player")
	rm.autosave_enabled = false
	rm.autosave_slot = AUTO
	title.set("slots_override", [SLOT, AUTO])


func _teardown() -> void:
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	main_node = null
	rm.current_room = null
	paused = false


func _esc() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	root.push_input(ev)
	var up := ev.duplicate()
	up.pressed = false
	root.push_input(up)
	await _frames(2)


func _room_id() -> String:
	return rm.current_room.room_id if rm.current_room != null and is_instance_valid(rm.current_room) else ""


# --- Tests -------------------------------------------------------------------------------

func _test_skip() -> void:
	await _setup("")
	_check(not title.call("is_open"), "a -s test runner must skip the title")
	_check(_room_id() == root.get_node("StoryData").start_location, "the game starts at the start location (%s)" % _room_id())
	_check(not paused, "the tree runs")
	_reached_end = true


func _test_title_launch() -> void:
	gs.delete_save(SLOT)
	gs.delete_save(AUTO)
	await _setup("show")
	_check(title.call("is_open"), "the title is open on launch")
	_check(paused, "the game waits under the title (tree paused)")
	_check(_room_id() == "", "no game started under the title (room %s)" % _room_id())
	var bg: TextureRect = title.get("bg")
	_check(bg.texture != null and bg.texture.get_width() == 1672, "the clean panel art is the background")
	_check(bg.material is ShaderMaterial and (bg.material as ShaderMaterial).get_shader_parameter("mask_tex") != null, "the background is animated through the fx mask")
	_check((title.get("signature") as TextureRect).visible, "the scratched signature layer is on")
	# H57 (Director 24.10): the larger signature of batch 10a, moved onto the LEFT panel (the menu is not mirrored).
	var sig_img := ((title.get("signature") as TextureRect).texture as Texture2D).get_image()
	var sig_box := sig_img.get_used_rect()
	_check(sig_box.position.x >= 100 and sig_box.end.x <= 470 and sig_box.position.y > 700 and sig_box.size.x >= 300,
		"H57: the signature sits on the bottom of the left panel, larger (art box %s)" % str(sig_box))
	var mat_t := bg.material as ShaderMaterial
	_check(float(mat_t.get_shader_parameter("sway_gust")) > 0.5 and float(mat_t.get_shader_parameter("water_amp_px")) >= 2.0
		and float(mat_t.get_shader_parameter("window_flicker")) >= 0.03,
		"H57: wind in gusts, livelier water, the lamp trembles (gust %s, water %s, flicker %s)" % [mat_t.get_shader_parameter("sway_gust"),
		mat_t.get_shader_parameter("water_amp_px"), mat_t.get_shader_parameter("window_flicker")])
	var md := root.get_node("MusicDirector")
	_check(String(md.get("room_theme")) == String(MenuConfig.section("title").get("music", "")), "the menu theme plays (%s)" % md.get("room_theme"))
	var pr: Dictionary = title.call("probe")
	_check(pr["open"] and pr["items"].has("new_game"), "probe: open with «Новая игра» (%s)" % str(pr["items"].keys()))
	_check(String(pr["items"]["new_game"]["text"]) == "Новая игра", "items are drawn from ui.title_* texts")
	# Hover moves the highlight (the leaf follows it).
	var leaf: TextureRect = title.get("leaf")
	var y0 := leaf.position.y
	(title.get("buttons")["settings"] as Button).mouse_entered.emit()
	await _seconds(0.3)
	_check(String(title.get("highlighted")) == "settings", "hover highlights «Настройки»")
	_check(leaf.position.y > y0 + 60.0, "the leaf slid down to the hovered item (%.0f → %.0f)" % [y0, leaf.position.y])
	_reached_end = true


func _test_title_items() -> void:
	gs.delete_save(SLOT)
	gs.delete_save(AUTO)
	await _setup("show")
	title.call("refresh")   # with the test's own slots (the shared user://saves may hold the player's)
	var order: Array = title.get("order")
	_check(not order.has("continue"), "no save — no «Продолжить» (%s)" % str(order))
	_check(order.has("quit") == not OS.has_feature("web"), "«Выход» only off the web")
	title.call("activate", "load")
	await _frames(2)
	_check(ui.call("menu_panel_open") and String(ui.get("menu_mode")) == "load", "«Загрузить» opens the panel in load mode")
	var any_row := false
	for s in ui.get("slot_rows").keys():
		any_row = any_row or (ui.get("slot_rows")[s]["row"] as Control).visible
	_check((ui.get("menu_empty_label") as Label).visible == not any_row, "load mode with no save rows says so")
	_check(title.call("is_open"), "the title stays under the panel")
	await _esc()
	_check(not ui.call("menu_panel_open") and title.call("is_open"), "Esc closes the panel back to the title")
	title.call("activate", "settings")
	await _frames(2)
	_check(String(ui.get("menu_mode")) == "settings" and (ui.get("music_slider") as Control).is_visible_in_tree(), "«Настройки» opens the volumes")
	var row_vis := false
	for s in ui.get("slot_rows").keys():
		row_vis = row_vis or (ui.get("slot_rows")[s]["row"] as Control).visible
	_check(not row_vis, "settings mode shows no slot rows")
	ui.call("close_menu_panel")
	title.call("activate", "new_game")
	await _frames(3)
	_check(not title.call("is_open") and not paused, "«Новая игра» closes the title and runs the game")
	_check(_room_id() == root.get_node("StoryData").start_location, "the new game starts at the start location (%s)" % _room_id())
	# A save makes «Продолжить» appear and load it.
	player.global_position = Vector2(900, 880)
	_check(rm.save_game(SLOT), "saved into the test slot")
	title.call("open")
	await _frames(2)
	_check(paused, "the title holds the game")
	order = title.get("order")
	_check(order.size() > 0 and order[0] == "continue", "with a save «Продолжить» comes first (%s)" % str(order))
	_check(String(title.get("continue_slot")) == SLOT, "«Продолжить» takes the newest save (%s)" % title.get("continue_slot"))
	title.call("activate", "continue")
	await _frames(3)
	_check(not title.call("is_open") and not paused, "«Продолжить» closes the title")
	_check(_room_id() == root.get_node("StoryData").start_location and player.global_position.distance_to(Vector2(900, 880)) < 2.0,
		"«Продолжить» loaded the save (room %s, at %s)" % [_room_id(), str(player.global_position)])
	# 31.10 (Director, line 4: «При нажатии продолжить и отсутствии сохранений — в недопиленную рыбу игры пускает…
	# Перед этим сохранения удалял»): the saves deleted in «Загрузить» under the title — «Продолжить» goes away when
	# the panel closes, and an old «Продолжить» does nothing (it used to stay, pointing at the deleted save).
	title.call("open")
	await _frames(2)
	_check((title.get("order") as Array).has("continue"), "a save — «Продолжить» on the title")
	title.call("activate", "load")
	await _frames(2)
	ui.set("delete_slot", SLOT)
	if ui.get("delete_dialog") != null:
		(ui.get("delete_dialog") as Control).visible = true
		ui.call("_close_delete", true)
	else:
		gs.delete_save(SLOT)
	gs.delete_save(AUTO)
	_check(not gs.has_save(SLOT), "the save is deleted in the panel")
	ui.call("close_menu_panel")
	await _frames(2)
	_check(title.call("is_open") and not (title.get("order") as Array).has("continue"), "no saves left — no «Продолжить» on the title (%s)" % str(title.get("order")))
	var room_before := _room_id()
	title.call("activate", "continue")
	await _frames(3)
	_check(title.call("is_open") and _room_id() == room_before, "a «Продолжить» with no save does nothing — the title stays (room %s)" % _room_id())
	# every save «Продолжить» may take is a row of «Загрузить» (the quick save F5 had none)
	var rows: Dictionary = ui.get("slot_rows")
	for sl in title.call("default_slots"):
		_check(rows.has(String(sl)), "«Продолжить» may load slot «%s» — it must be in «Загрузить» to be seen and deleted" % sl)
	_reached_end = true


func _test_pause_esc() -> void:
	gs.delete_save(SLOT)
	await _setup("")
	await _frames(5)
	await _esc()
	_check(pause.call("is_open"), "Esc opens the pause")
	_check(paused, "the tree is paused under the pause menu")
	await _seconds(0.35)
	var pr: Dictionary = pause.call("probe")
	_check(float(pr["blur"]) > 0.99, "the game frame behind is blurred (amount %.2f)" % float(pr["blur"]))
	_check((pause.get("blur") as ColorRect).visible and pause.get("layer") > ui.get("layer"), "the blur and the board are above the game UI")
	_check(pr["items"].has("continue") and pr["items"].has("main_menu") and pr["items"].has("quit") == not OS.has_feature("web"), "two columns of items (%s)" % str(pr["order"]))
	_check(String(pr["hint"]) == "Esc — вернуться", "the Esc hint in the border gap (%s)" % pr["hint"])
	# H58 (Director 24.10): the carved board at the bottom of the screen; items in two rows on it; the Esc line below them,
	# centred under the bottom ornament.
	var board_img := ((pause.get("panel") as TextureRect).texture as Texture2D).get_image()
	var bb := board_img.get_used_rect()
	_check(bb.position.y > 560 and bb.size.x > 1100, "H58: the board stands in the lower part of the screen (art box %s)" % str(bb))
	var ys := {}
	for id in pr["items"].keys():
		ys[int(round(float(pr["items"][id]["y"])))] = true
		_check(float(pr["items"][id]["y"]) > bb.position.y * 1080.0 / 941.0, "H58: «%s» is on the board (y %.0f)" % [id, float(pr["items"][id]["y"])])
	_check(ys.size() == 2, "H58: the items stand in two rows (%s)" % str(ys.keys()))
	var hint_l: Label = pause.get("hint")
	_check(absf(hint_l.get_global_rect().get_center().x - bb.get_center().x * 1920.0 / 1672.0) < 6.0 and hint_l.position.y > float(ys.keys().max()),
		"H58: «Esc — вернуться» centred below the items (%s)" % str(hint_l.get_global_rect()))
	# Walking stands still while paused.
	await _esc()
	_check(not pause.call("is_open") and not paused, "Esc again closes it")
	player.call("walk_to", player.global_position + Vector2(-400, 0))
	await _frames(6)
	await _esc()
	var at := player.global_position
	await _seconds(0.4)
	_check(player.global_position.distance_to(at) < 0.5, "Agata stands still under the pause (moved %.1f px)" % player.global_position.distance_to(at))
	await _esc()
	await _seconds(0.3)
	_check(player.global_position.distance_to(at) > 2.0, "and walks on after it")
	# The top bar «Меню» opens the pause.
	(ui.get("menu_button") as Button).pressed.emit()
	await _frames(2)
	_check(pause.call("is_open"), "«Меню» opens the pause")
	pause.call("activate", "continue")
	await _frames(2)
	_check(not pause.call("is_open") and not paused, "«Продолжить» closes it")
	_reached_end = true


func _test_esc_order() -> void:
	await _setup("")
	await _frames(5)
	var item := "photo_bridge"
	gs.add_item(item)
	var ex: Node = main_node.get_node("ItemExamine")
	_check(sr.examine_item(item), "the item close-up opens")
	await _frames(3)
	await _esc()
	_check(not ex.call("is_open"), "Esc closed the item close-up")
	_check(not pause.call("is_open"), "… and did not open the pause")
	await _esc()
	_check(pause.call("is_open"), "the next Esc opens the pause")
	await _esc()
	ui.call("toggle_journal")
	await _frames(2)
	await _esc()
	_check(not (ui.get("journal_panel") as Control).visible and not pause.call("is_open"), "Esc closes the journal, not the pause")
	await _esc()
	_check(pause.call("is_open"), "then the pause")
	pause.call("activate", "settings")
	await _frames(2)
	await _esc()
	_check(not ui.call("menu_panel_open") and pause.call("is_open"), "Esc closes the settings panel back to the pause")
	await _esc()
	_check(not pause.call("is_open") and not paused, "and then the pause")
	_reached_end = true


func _test_pause_items() -> void:
	gs.delete_save(SLOT)
	gs.delete_save(AUTO)
	await _setup("")
	await _frames(5)
	# Save and Load are held while a line is on screen.
	gs.add_item("photo_bridge")
	sr.examine_item("photo_bridge")
	await _frames(2)
	(ui.get("menu_button") as Button).pressed.emit()
	await _frames(2)
	var pr: Dictionary = pause.call("probe")
	_check(pr["items"]["save"]["disabled"] and pr["items"]["load"]["disabled"], "Save / Load held during a line")
	pause.call("activate", "save")
	await _frames(1)
	_check(not ui.call("menu_panel_open") and String(pause.call("probe")["hint"]) != "Esc — вернуться", "a held Save says why instead of opening")
	pause.call("activate", "continue")
	sr.close_examine()
	await _frames(3)
	await _esc()
	_check(pause.call("is_open"), "the pause opens")
	pr = pause.call("probe")
	_check(not pr["items"]["save"]["disabled"], "Save is free with nothing on screen")
	pause.call("activate", "save")
	await _frames(2)
	_check(ui.call("menu_panel_open") and String(ui.get("menu_mode")) == "save", "«Сохранить» opens the slots")
	var rows: Dictionary = ui.get("slot_rows")
	var r1: Dictionary = rows["1"]
	_check((r1["row"] as Control).visible and (r1["save"] as Control).visible and not (r1["load"] as Control).visible, "save mode: slot rows with «Сохранить» only")
	_check(not (ui.get("music_slider") as Control).is_visible_in_tree(), "save mode: no volumes")
	ui.call("close_menu_panel")
	pause.call("activate", "load")
	await _frames(2)
	_check(String(ui.get("menu_mode")) == "load" and not (r1["save"] as Control).visible, "«Загрузить»: load mode")
	ui.call("close_menu_panel")
	# «В главное меню»: the autosave is written, the title comes up over the held game; «Продолжить» loads it.
	player.global_position = Vector2(1000, 900)
	rm.autosave_enabled = true
	pause.call("activate", "main_menu")
	await _frames(3)
	_check(not pause.call("is_open") and title.call("is_open") and paused, "«В главное меню» → the title, the game held")
	_check(gs.has_save(AUTO), "leaving for the title wrote the autosave")
	_check(sr.current_beat.is_empty() and not sr.is_busy(), "nothing of the scene is left running")
	_check(Array(title.get("order")).has("continue"), "the title offers «Продолжить»")
	rm.autosave_enabled = false
	title.call("activate", "continue")
	await _frames(3)
	_check(not title.call("is_open") and not paused and player.global_position.distance_to(Vector2(1000, 900)) < 2.0,
		"«Продолжить» loaded the autosave (at %s)" % str(player.global_position))
	_reached_end = true
