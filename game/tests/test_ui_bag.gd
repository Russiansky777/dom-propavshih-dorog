extends SceneTree
## Headless test of the bag (game/scripts/ui/inventory_bag.gd, bag_slot.gd, game_ui.gd). Usage:
##   godot --headless --path game -s res://tests/test_ui_bag.gd
## Behind it — the Director's task of 17.10 «сумка: лого предметов и слоты»:
##   - the bag is a row of pockets in the top bar (never over the floor), an empty bag says so;
##   - every E0–E1 inventory item has its icon by name (res://assets/icons/<id>.png); an item
##     without an icon gets a patch with a letter, not an error;
##   - hover: name from items.json + the short line from data/story/text, under the bar;
##   - click (a real mouse event): the item is in hand, its pocket glows, the cursor carries it;
##     second click / right click: back in the bag; sounds select / deselect requested;
##   - a granted item flies into its pocket (one "receive" per batch); loading a save never does;
##   - more items than pockets: pages, ‹ › and a received item turns to its page;
##   - probe_positions().inventory: pocket centres the web walkthrough clicks;
##   - fonts (Director: «стилизованные под игру шрифты в меню и на верхней панели»): the OFL faces are
##     really loaded (not the engine fallback), have Cyrillic, and the dialogue reads at 1280×720.
## Exit code 0 only when every check passed.

const E0E1_ITEMS := ["key_house", "letter_tamara", "pocket_watch", "mitten", "door_hinges",
	"invoice_chalk", "photo_school_pier", "chalk"]

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null
var ui: Node = null
var bag: Control = null   # InventoryBag (untyped: autoloads do not exist yet when -s compiles)
var sounds: Array[String] = []
var SLOT := "test_ui_bag_%d" % OS.get_process_id()   # parallel runs share user://saves


func _initialize() -> void:
	_run()


func _check(cond: bool, message: String) -> void:
	if not cond:
		_fails.append(message)


func _test(test_name: String, fn: Callable) -> void:
	_fails = []
	var started := Time.get_ticks_msec()
	await fn.call()
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
	sd = root.get_node("StoryData")
	gs.reset()
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	ui = main_node.get_node("GameUi")
	bag = ui.get("bag")
	ui.connect("bag_sound_requested", func(kind): sounds.append(kind))
	await _test("Bag: 8 pockets in the top bar, above every room's floor; an empty bag says so", _test_layout)
	await _test("Icons by name: every E0–E1 item has res://assets/icons/<id>.png; no icon → patch, no error", _test_icons)
	await _test("Hover a pocket: items.json name + short line from data, tooltip under the bar", _test_hover)
	await _test("Real click: in hand (pocket glows, cursor carries the icon); again / right click: back; sounds", _test_select)
	await _test("Received item flies into its pocket; one 'receive' per batch; load never replays it", _test_receive)
	await _test("More items than pockets: pages, ‹ ›, wheel; a received item turns the bag to its page", _test_pages)
	await _test("probe_positions().inventory: centres of visible pockets inside the bar", _test_probe)
	await _test("Theme: Old Standard TT (bar, buttons, headings) + PT Serif (dialogue, journal, tooltips), Cyrillic, sizes", _test_theme)
	gs.reset()
	gs.delete_save(SLOT)
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== ui bag: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _fresh(items: Array = []) -> void:
	gs.reset()
	sr.call("_on_state_reset")
	for it in items:
		gs.add_item(String(it))
	bag.page = 0
	bag.refresh()
	sounds.clear()
	await _frames(2)


func _click(at: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	root.push_input(move, true)
	await _frames(1)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		root.push_input(ev, true)
		await _frames(1)


func _wait_settled(timeout: float = 4.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		if not bag.is_animating():
			return true
		await process_frame
	return false


# --- Tests ---------------------------------------------------------------------------------

func _test_layout() -> void:
	await _fresh()
	var top: float = ui.get("TOP_H")
	_check(bag.slots.size() == bag.SLOTS and bag.SLOTS == 8, "8 pockets (%d)" % bag.slots.size())
	var br := bag.get_global_rect()
	_check(br.position.y >= 0.0 and br.end.y <= top, "bag inside the top bar: %s, bar %d" % [str(br), int(top)])
	for s in bag.slots:
		var r: Rect2 = s.get_global_rect()
		_check(r.size.x >= 60 and r.size.y >= 60 and r.end.y <= top, "pocket %d: %s" % [s.index, str(r)])
	# Not over the floor: every room's walkable polygon starts below the bar.
	for rid in sd.rooms.keys():
		var poly: Array = sd.rooms[rid].get("walkable", [])
		for p in poly:
			if p is Array and p.size() == 2:
				_check(float(p[1]) > top + 200.0, "%s: floor point %s under the bag" % [rid, str(p)])
	_check(bag.empty_label.visible and bag.empty_label.text == sd.text("@ui.inventory_empty"), "empty bag text")
	gs.add_item("key_house")
	await _frames(2)
	_check(not bag.empty_label.visible, "empty text hidden once an item is in the bag")


func _test_icons() -> void:
	await _fresh(E0E1_ITEMS)
	for id in E0E1_ITEMS:
		_check(ResourceLoader.exists("res://assets/icons/%s.png" % id), "icon file for %s" % id)
		var s: Control = bag.slot_of(id)
		_check(s != null and s.icon != null, "pocket of %s shows its icon" % id)
		if s != null and s.icon != null:
			_check(s.icon.get_width() >= 128 and s.icon.get_width() <= 256, "%s icon scaled to slot size (%d px)" % [id, s.icon.get_width()])
	# Every inventory item E0–E1 grants (scenes M01–M08) is in the list above.
	for id in sd.items.keys():
		var it: Dictionary = sd.items[id]
		var sc := String(it.get("source_scene", ""))
		if bool(it.get("inventory", false)) and sc >= "M01" and sc <= "M08":
			_check(E0E1_ITEMS.has(id), "E0–E1 item %s missing from the icon list" % id)
	# An item without an icon (a later episode) → patch with a letter.
	var no_icon := ""
	for id in sd.items.keys():
		if bool(sd.items[id].get("inventory", false)) and not ResourceLoader.exists("res://assets/icons/%s.png" % id):
			no_icon = id
			break
	if no_icon != "":
		await _fresh([no_icon])
		var s: Control = bag.slot_of(no_icon)
		_check(s != null and s.icon == null and s.item_name == sd.item_name(no_icon), "%s: placeholder patch" % no_icon)
		s.queue_redraw()
		await _frames(2)


func _test_hover() -> void:
	await _fresh(["key_house", "letter_tamara"])
	var s: Control = bag.slot_of("letter_tamara")
	await _frames(1)
	var c := s.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = c
	move.global_position = c
	root.push_input(move, true)
	await _frames(3)
	_check(s.hovered, "the pocket under the pointer is hovered")
	_check(bag.tooltip.visible, "tooltip shown on hover")
	_check(bag.tip_name.text == sd.item_name("letter_tamara"), "tooltip name = items.json name (%s)" % bag.tip_name.text)
	_check(bag.tip_desc.text == sd.text("@item.letter_tamara") and bag.tip_desc.text != "", "tooltip line from data (%s)" % bag.tip_desc.text)
	_check(bag.tip_action.text == sd.text("@ui.bag_take"), "action line: take")
	var tr: Rect2 = bag.tooltip.get_global_rect()
	_check(tr.position.y >= float(ui.get("TOP_H")) and tr.end.x <= 1920.0 and tr.position.x >= 0.0, "tooltip under the bar, on screen: %s" % str(tr))
	var off := Vector2(960, 600)
	move = InputEventMouseMotion.new()
	move.position = off
	move.global_position = off
	root.push_input(move, true)
	await _frames(2)
	_check(not bag.tooltip.visible, "tooltip hidden when the pointer leaves")


func _test_select() -> void:
	await _fresh(["key_house", "mitten"])
	var s: Control = bag.slot_of("mitten")
	var c := s.get_global_rect().get_center()
	await _click(c)
	_check(sr.selected_item == "mitten", "real click on the pocket takes the mitten (%s)" % sr.selected_item)
	_check(s.selected, "pocket glows when its item is in hand")
	var cur: Control = ui.get("cursor_item")
	await _frames(1)
	_check(cur.visible and cur.item_id == "mitten" and cur.icon != null, "cursor carries the mitten icon")
	_check(cur.size.x < s.size.x, "cursor icon is smaller than the pocket")
	_check(sounds == ["select"], "sound select (%s)" % str(sounds))
	await _click(c)
	_check(sr.selected_item == "", "second click puts it back (%s)" % sr.selected_item)
	_check(not s.selected, "pocket no longer glows")
	await _frames(1)
	_check(not cur.visible, "cursor icon gone")
	_check(sounds == ["select", "deselect"], "sound deselect (%s)" % str(sounds))
	# Right click on the scene puts the held item back.
	ui.call("click_inventory_item", "key_house")
	_check(sr.selected_item == "key_house", "click_inventory_item selects")
	await _click(Vector2(960, 700), MOUSE_BUTTON_RIGHT)
	_check(sr.selected_item == "", "right click puts the item back (%s)" % sr.selected_item)
	# Selecting the other item swaps the glow.
	ui.call("click_inventory_item", "key_house")
	ui.call("click_inventory_item", "mitten")
	await _frames(1)
	_check(sr.selected_item == "mitten" and s.selected and not bag.slot_of("key_house").selected, "one pocket glows at a time")
	bag.put_back()


func _test_receive() -> void:
	await _fresh()
	rm.change_room("Z1", "")
	await _frames(3)
	sr.call("_on_state_reset")
	sounds.clear()
	for id in ["key_house", "letter_tamara", "pocket_watch"]:
		sr.grant_item(id)
	await _frames(1)
	_check(bag.is_animating(), "icons are flying")
	var fx: Control = ui.get("fx_layer")
	_check(fx.get_child_count() >= 3, "three flying icons over the scene (%d)" % fx.get_child_count())
	var s: Control = bag.slot_of("key_house")
	_check(s != null and s.arriving, "the pocket waits empty while its icon flies")
	var fly: Control = fx.find_child("Fly_key_house", false, false)
	var start_y := fly.global_position.y if fly != null else -1.0
	await _wait(0.45)
	if fly != null and is_instance_valid(fly):
		_check(fly.global_position.y < start_y, "the icon moves up towards the bag (%.0f → %.0f)" % [start_y, fly.global_position.y])
	_check(await _wait_settled(), "flights finish")
	_check(not s.arriving and s.icon != null, "pocket shows the icon after landing")
	_check(sounds.count("receive") == 1, "one receive sound per batch (%s)" % str(sounds))
	await _frames(2)
	_check(fx.get_child_count() == 0, "flying icons freed (%d left)" % fx.get_child_count())
	# Load: the inventory comes back without any flight or sound.
	_check(rm.save_game(SLOT), "save")
	gs.reset()
	sounds.clear()
	_check(rm.load_game(SLOT), "load")
	await _frames(2)
	_check(not bag.is_animating() and sounds.is_empty(), "loading never replays the arrival (%s)" % str(sounds))
	_check(bag.slot_of("letter_tamara") != null and bag.slot_of("letter_tamara").icon != null, "loaded items in their pockets")
	# A flight cut by loading leaves no pocket waiting.
	sr.grant_item("mitten")
	await _frames(1)
	_check(rm.load_game(SLOT), "load mid-flight")
	await _frames(2)
	_check(not bag.is_animating() and fx.get_child_count() == 0, "load mid-flight drops the flight")


func _test_pages() -> void:
	var many: Array = []
	for id in sd.items.keys():
		if bool(sd.items[id].get("inventory", false)):
			many.append(id)
	_check(many.size() >= 12, "at least 12 inventory items in items.json (%d)" % many.size())
	await _fresh(many.slice(0, 11))
	_check(bag.pages() == 2 and bag.page == 0, "11 items → 2 pages (%d)" % bag.pages())
	_check(bag.visible_items().size() == 8, "page 1 shows 8 items")
	_check(bag.prev_button.disabled, "‹ disabled on the first page")
	_check(not bag.next_button.disabled and bag.next_button.modulate.a > 0.5, "› active")
	bag.next_button.pressed.emit()
	await _frames(1)
	_check(bag.page == 1 and bag.visible_items().size() == 3, "page 2 shows the other 3 (%s)" % str(bag.visible_items()))
	_check(bag.prev_button.modulate.a > 0.5 and not bag.prev_button.disabled, "‹ active on page 2")
	# Clicking an item from page 1 (API) turns back to it.
	ui.call("click_inventory_item", many[0])
	_check(bag.page == 0 and bag.slot_of(many[0]).selected, "click_inventory_item turns to the item's page")
	bag.put_back()
	# Wheel over the strip.
	var c: Vector2 = bag.slots[2].get_global_rect().get_center()   # over a pocket, not just the strip
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = c
	wheel.global_position = c
	root.push_input(wheel, true)
	await _frames(2)
	_check(bag.page == 1, "wheel down → next page (%d)" % bag.page)
	# A received 12th item flies to page 2 even when page 1 is shown.
	bag.flip(-1)
	sr.grant_item(String(many[11]))
	await _frames(1)
	_check(bag.page == 1, "received item turns the bag to its page (%d)" % bag.page)
	_check(await _wait_settled(), "flight lands")
	_check(bag.slot_of(String(many[11])) != null, "item in its pocket on page 2")
	# One page again: arrows hidden and not clickable.
	await _fresh(many.slice(0, 3))
	_check(bag.pages() == 1 and bag.next_button.modulate.a == 0.0 and bag.next_button.disabled, "one page: arrows hidden")


func _test_probe() -> void:
	await _fresh(["key_house", "chalk"])
	await _frames(2)
	var p: Dictionary = ui.call("probe_positions")
	_check(p.has("inventory") and p["inventory"].has("chalk") and p["inventory"].has("key_house"), "probe lists both items")
	for id in ["key_house", "chalk"]:
		var pt: Dictionary = p["inventory"].get(id, {})
		var s: Control = bag.slot_of(id)
		if s != null and not pt.is_empty():
			_check(s.get_global_rect().has_point(Vector2(pt["x"], pt["y"])), "%s probe point inside its pocket" % id)
			_check(float(pt["y"]) < float(ui.get("TOP_H")), "%s probe point in the bar" % id)
	_check(p.has("bag") and int(p["bag"]["pages"]) == 1, "probe bag info")


func _font_name(c: Control, item: String = "font") -> String:
	var f: Font = c.get_theme_font(item)
	return f.get_font_name() if f != null else ""


func _test_theme() -> void:
	await _fresh(["key_house"])
	ui.call("_on_room_changed", "H1")
	await _frames(2)
	var top_bar: Control = ui.get("top_bar")
	_check(absf(top_bar.size.y - float(ui.get("TOP_H"))) < 0.5, "top bar stays %d px (%.0f)" % [int(ui.get("TOP_H")), top_bar.size.y])
	var head := "Old Standard TT"
	var body := "PT Serif"
	_check(_font_name(ui.get("room_label")) == head, "room name: %s" % _font_name(ui.get("room_label")))
	for b in ["journal_button", "hint_button", "menu_button"]:
		_check(_font_name(ui.get(b)) == head, "%s: %s" % [b, _font_name(ui.get(b))])
	var text: Control = ui.get("text_label")
	_check(_font_name(text, "normal_font") == body, "dialogue text: %s" % _font_name(text, "normal_font"))
	var dsize: int = text.get_theme_font_size("normal_font_size")
	_check(dsize * 720.0 / 1080.0 >= 20.0, "dialogue %d px → %.1f px at 1280×720 (≥ 20)" % [dsize, dsize * 720.0 / 1080.0])
	_check(_font_name(ui.get("speaker_label")) == head, "speaker name: %s" % _font_name(ui.get("speaker_label")))
	_check(_font_name(ui.get("journal_facts_label"), "normal_font") == body, "journal facts")
	_check(_font_name(ui.get("journal_goal_label")) == body, "journal goal")
	_check(_font_name(ui.get("hover_label")) == body, "hover label")
	_check(_font_name(ui.get("hint_line")) == body, "hint line")
	_check(_font_name(bag.tip_name) == head and _font_name(bag.tip_desc) == body, "bag tooltip: %s / %s" % [_font_name(bag.tip_name), _font_name(bag.tip_desc)])
	var menu: Control = ui.get("menu_panel")
	var ng: Control = menu.find_child("NewGame", true, false)
	_check(ng != null and _font_name(ng) == head, "menu buttons")
	# Every face has the whole Russian alphabet with ё/Ё/ъ/Ъ and the typographic marks the texts use.
	var probe_chars := "абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ«»—…№"
	for c in [ui.get("room_label"), ui.get("hover_label"), ui.get("hint_line")]:
		var f: Font = (c as Control).get_theme_font("font")
		var missing := ""
		for ch in probe_chars:
			if not f.has_char(ch.unicode_at(0)):
				missing += ch
		_check(missing == "", "%s lacks: %s" % [f.get_font_name(), missing])
	var fi: Font = text.get_theme_font("italics_font")
	_check(fi != null and fi.get_font_name() == body and fi.get_font_style() & TextServer.FONT_ITALIC, "dialogue italic = PT Serif Italic")
