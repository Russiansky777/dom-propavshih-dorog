extends CanvasLayer
## Mouse-only game UI: top bar (room name, inventory, Journal / Hint / Menu), dialogue box with
## options, examine/narration text, journal panel, save-slot menu, hint line, fade overlay.
## It renders StoryRunner/GameState state and never decides story logic itself.

const QUICK_SLOT: String = "quick"
const HINT_SECONDS: float = 7.0
const TOP_H: float = 80.0

var top_bar: PanelContainer
var room_label: Label
var inventory_box: HBoxContainer
var journal_button: Button
var hint_button: Button
var menu_button: Button
var hint_line: Label
var modal: Control
var dialogue: PanelContainer
var speaker_label: Label
var text_label: RichTextLabel
var continue_label: Label
var options_box: VBoxContainer
var journal_panel: PanelContainer
var journal_goal_label: Label
var journal_facts_label: RichTextLabel
var menu_panel: PanelContainer
var slot_rows: Dictionary = {}   # slot -> {info: Label, save: Button, load: Button}
var fade: ColorRect
var inventory_buttons: Dictionary = {}  # item -> Button

var _hint_serial: int = 0


func _ready() -> void:
	layer = 5
	_build()
	StoryRunner.beat_changed.connect(_render_dialogue)
	StoryRunner.item_selection_changed.connect(func(_i): _render_inventory())
	StoryRunner.loop_transition.connect(_on_loop_transition)
	StoryRunner.hint_revealed.connect(func(tier, text): show_hint(StoryData.text("@ui.hint_title", {"tier": tier}) + ": " + text))
	GameState.inventory_changed.connect(_render_inventory)
	GameState.state_reset.connect(_render_inventory)
	GameState.state_loaded.connect(func(_s): _render_inventory())
	GameState.hint_shown.connect(show_hint)
	RoomManager.room_changed.connect(_on_room_changed)
	_render_inventory()
	_render_dialogue()
	if RoomManager.current_room != null:
		_on_room_changed(RoomManager.current_room.room_id)


# --- Building ------------------------------------------------------------------

func _panel_style(bg: Color = Color(0.08, 0.07, 0.06, 0.92)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(0.75, 0.65, 0.45, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	return sb


func _button(text: String, min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 22)
	if min_w > 0:
		b.custom_minimum_size = Vector2(min_w, 0)
	return b


func _build() -> void:
	# Top bar
	top_bar = PanelContainer.new()
	top_bar.name = "TopBar"
	top_bar.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.05, 0.04, 0.9)))
	top_bar.position = Vector2(0, 0)
	top_bar.size = Vector2(1920, TOP_H)
	add_child(top_bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	top_bar.add_child(h)
	room_label = Label.new()
	room_label.name = "RoomLabel"
	room_label.add_theme_font_size_override("font_size", 24)
	room_label.custom_minimum_size = Vector2(420, 0)
	room_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(room_label)
	inventory_box = HBoxContainer.new()
	inventory_box.name = "Inventory"
	inventory_box.add_theme_constant_override("separation", 8)
	inventory_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(inventory_box)
	journal_button = _button(StoryData.text("@ui.button_journal"), 140)
	journal_button.name = "JournalButton"
	journal_button.pressed.connect(toggle_journal)
	h.add_child(journal_button)
	hint_button = _button(StoryData.text("@ui.button_hint"), 160)
	hint_button.name = "HintButton"
	hint_button.pressed.connect(_on_hint_pressed)
	h.add_child(hint_button)
	menu_button = _button(StoryData.text("@ui.button_menu"), 120)
	menu_button.name = "MenuButton"
	menu_button.pressed.connect(toggle_menu)
	h.add_child(menu_button)

	# Hint line (bottom, click-through)
	hint_line = Label.new()
	hint_line.name = "HintLine"
	hint_line.position = Vector2(0, 1000)
	hint_line.size = Vector2(1920, 44)
	hint_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_line.add_theme_font_size_override("font_size", 24)
	hint_line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint_line.add_theme_constant_override("outline_size", 6)
	hint_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_line)

	# Modal catcher (dialogue / panels)
	modal = Control.new()
	modal.name = "Modal"
	modal.position = Vector2.ZERO
	modal.size = Vector2(1920, 1080)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.visible = false
	modal.gui_input.connect(_on_modal_input)
	add_child(modal)

	# Dialogue box
	dialogue = PanelContainer.new()
	dialogue.name = "Dialogue"
	dialogue.add_theme_stylebox_override("panel", _panel_style())
	dialogue.position = Vector2(200, 740)
	dialogue.size = Vector2(1520, 300)
	dialogue.visible = false
	dialogue.mouse_filter = Control.MOUSE_FILTER_STOP
	dialogue.gui_input.connect(_on_modal_input)
	add_child(dialogue)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	dialogue.add_child(v)
	speaker_label = Label.new()
	speaker_label.name = "Speaker"
	speaker_label.add_theme_font_size_override("font_size", 24)
	speaker_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.55))
	v.add_child(speaker_label)
	text_label = RichTextLabel.new()
	text_label.name = "Text"
	text_label.bbcode_enabled = false
	text_label.fit_content = true
	text_label.scroll_active = false
	text_label.add_theme_font_size_override("normal_font_size", 28)
	text_label.custom_minimum_size = Vector2(0, 60)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(text_label)
	options_box = VBoxContainer.new()
	options_box.name = "Options"
	options_box.add_theme_constant_override("separation", 6)
	v.add_child(options_box)
	continue_label = Label.new()
	continue_label.name = "Continue"
	continue_label.text = StoryData.text("@ui.continue")
	continue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	continue_label.add_theme_font_size_override("font_size", 20)
	continue_label.modulate = Color(1, 1, 1, 0.7)
	v.add_child(continue_label)

	# Journal panel
	journal_panel = PanelContainer.new()
	journal_panel.name = "Journal"
	journal_panel.add_theme_stylebox_override("panel", _panel_style())
	journal_panel.position = Vector2(360, 140)
	journal_panel.size = Vector2(1200, 760)
	journal_panel.visible = false
	add_child(journal_panel)
	var jv := VBoxContainer.new()
	jv.add_theme_constant_override("separation", 10)
	journal_panel.add_child(jv)
	var jt := Label.new()
	jt.text = StoryData.text("@ui.journal_title")
	jt.add_theme_font_size_override("font_size", 32)
	jv.add_child(jt)
	var jg := Label.new()
	jg.text = StoryData.text("@ui.journal_goal")
	jg.add_theme_font_size_override("font_size", 22)
	jg.add_theme_color_override("font_color", Color(0.95, 0.82, 0.55))
	jv.add_child(jg)
	journal_goal_label = Label.new()
	journal_goal_label.name = "Goal"
	journal_goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	journal_goal_label.add_theme_font_size_override("font_size", 26)
	jv.add_child(journal_goal_label)
	var jf := Label.new()
	jf.text = StoryData.text("@ui.journal_facts")
	jf.add_theme_font_size_override("font_size", 22)
	jf.add_theme_color_override("font_color", Color(0.95, 0.82, 0.55))
	jv.add_child(jf)
	journal_facts_label = RichTextLabel.new()
	journal_facts_label.name = "Facts"
	journal_facts_label.bbcode_enabled = false
	journal_facts_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	journal_facts_label.add_theme_font_size_override("normal_font_size", 22)
	jv.add_child(journal_facts_label)
	var jclose := _button(StoryData.text("@ui.close"), 200)
	jclose.name = "CloseJournal"
	jclose.pressed.connect(toggle_journal)
	jv.add_child(jclose)

	# Menu panel (save slots)
	menu_panel = PanelContainer.new()
	menu_panel.name = "Menu"
	menu_panel.add_theme_stylebox_override("panel", _panel_style())
	menu_panel.position = Vector2(510, 220)
	menu_panel.size = Vector2(900, 560)
	menu_panel.visible = false
	add_child(menu_panel)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 12)
	menu_panel.add_child(mv)
	var mt := Label.new()
	mt.text = StoryData.text("@ui.menu_title")
	mt.add_theme_font_size_override("font_size", 32)
	mv.add_child(mt)
	for slot in GameState.MANUAL_SLOTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		mv.add_child(row)
		var name_l := Label.new()
		name_l.text = StoryData.text("@ui.slot", {"n": slot})
		name_l.custom_minimum_size = Vector2(120, 0)
		name_l.add_theme_font_size_override("font_size", 24)
		row.add_child(name_l)
		var info := Label.new()
		info.custom_minimum_size = Vector2(400, 0)
		info.add_theme_font_size_override("font_size", 20)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var sb := _button(StoryData.text("@ui.save"), 150)
		sb.name = "Save" + slot
		sb.pressed.connect(_on_save_slot.bind(slot))
		row.add_child(sb)
		var lb := _button(StoryData.text("@ui.load"), 150)
		lb.name = "Load" + slot
		lb.pressed.connect(_on_load_slot.bind(slot))
		row.add_child(lb)
		slot_rows[slot] = {"info": info, "save": sb, "load": lb}
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	mv.add_child(bottom)
	var ng := _button(StoryData.text("@ui.new_game"), 220)
	ng.name = "NewGame"
	ng.pressed.connect(_on_new_game)
	bottom.add_child(ng)
	var mclose := _button(StoryData.text("@ui.close"), 160)
	mclose.name = "CloseMenu"
	mclose.pressed.connect(toggle_menu)
	bottom.add_child(mclose)

	# Fade overlay
	fade = ColorRect.new()
	fade.name = "Fade"
	fade.color = Color(0, 0, 0, 0)
	fade.position = Vector2.ZERO
	fade.size = Vector2(1920, 1080)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)


# --- Rendering -------------------------------------------------------------------

func _on_room_changed(room_id: String) -> void:
	var name := StoryData.location_name(room_id)
	room_label.text = "%s — %s" % [room_id, name] if name != room_id else room_id


func _render_inventory() -> void:
	for c in inventory_box.get_children():
		c.queue_free()
	inventory_buttons.clear()
	if GameState.inventory.is_empty():
		var l := Label.new()
		l.text = StoryData.text("@ui.inventory_empty")
		l.modulate = Color(1, 1, 1, 0.5)
		l.add_theme_font_size_override("font_size", 20)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		inventory_box.add_child(l)
		return
	for item_id in GameState.inventory:
		var b := Button.new()
		b.name = "Item_" + item_id
		b.custom_minimum_size = Vector2(64, 56)
		b.text = _abbrev(StoryData.item_name(item_id))
		b.tooltip_text = StoryData.item_name(item_id)
		b.add_theme_font_size_override("font_size", 20)
		b.toggle_mode = true
		b.button_pressed = StoryRunner.selected_item == item_id
		b.pressed.connect(func(): StoryRunner.select_item(item_id))
		inventory_box.add_child(b)
		inventory_buttons[item_id] = b


func _abbrev(name: String) -> String:
	var parts := name.split(" ", false)
	var out := ""
	for p in parts:
		if p.length() > 0 and out.length() < 3:
			out += p.substr(0, 1).to_upper()
	return out if out != "" else name.substr(0, 2)


func _render_dialogue() -> void:
	var beat := StoryRunner.current_beat
	for c in options_box.get_children():
		c.queue_free()
	if beat.is_empty():
		dialogue.visible = false
		_update_modal()
		return
	dialogue.visible = true
	var t := String(beat.get("type", ""))
	speaker_label.visible = t == "line"
	speaker_label.text = String(beat.get("speaker_name", ""))
	if t == "options":
		text_label.text = String(beat.get("prompt", ""))
		text_label.visible = text_label.text != ""
		continue_label.visible = false
		for o in beat.get("options", []):
			var b := _button(String(o.get("label", o.get("id", ""))))
			b.name = "Option_" + String(o.get("id", ""))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.pressed.connect(func(): StoryRunner.choose(String(o.get("id", ""))))
			options_box.add_child(b)
	else:
		text_label.visible = true
		text_label.text = String(beat.get("text", ""))
		continue_label.visible = true
	_update_modal()


func _update_modal() -> void:
	modal.visible = dialogue.visible or journal_panel.visible or menu_panel.visible


func _on_modal_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if dialogue.visible and StoryRunner.current_beat.get("type", "") != "options":
			StoryRunner.advance()
			get_viewport().set_input_as_handled()


func show_hint(text: String) -> void:
	_hint_serial += 1
	var serial := _hint_serial
	hint_line.text = text
	await get_tree().create_timer(HINT_SECONDS).timeout
	if serial == _hint_serial and is_instance_valid(hint_line):
		hint_line.text = ""


func _on_hint_pressed() -> void:
	if StoryRunner.is_busy():
		return
	StoryRunner.next_hint()


func toggle_journal() -> void:
	if StoryRunner.is_busy() and not journal_panel.visible:
		return
	journal_panel.visible = not journal_panel.visible
	menu_panel.visible = false
	if journal_panel.visible:
		journal_goal_label.text = StoryRunner.journal_goal()
		var facts := StoryRunner.journal_facts()
		journal_facts_label.text = "\n".join(PackedStringArray(facts.map(func(f): return "• " + f))) if not facts.is_empty() else StoryData.text("@ui.journal_empty")
	_update_modal()


func toggle_menu() -> void:
	if StoryRunner.is_busy() and not menu_panel.visible:
		return
	menu_panel.visible = not menu_panel.visible
	journal_panel.visible = false
	if menu_panel.visible:
		_refresh_slots()
	_update_modal()


func _refresh_slots() -> void:
	for slot in slot_rows.keys():
		var info: Dictionary = GameState.save_info(slot)
		var label: Label = slot_rows[slot]["info"]
		if info.is_empty():
			label.text = StoryData.text("@ui.slot_empty")
		else:
			label.text = "%s · %s" % [String(info.get("room", "")), String(info.get("saved_at", "")).replace("T", " ")]
		(slot_rows[slot]["load"] as Button).disabled = info.is_empty()


func _on_save_slot(slot: String) -> void:
	if RoomManager.save_game(slot):
		GameState.show_hint(StoryData.text("@ui.saved", {"slot": slot}))
	_refresh_slots()


func _on_load_slot(slot: String) -> void:
	if not GameState.has_save(slot):
		GameState.show_hint(StoryData.text("@ui.no_save"))
		return
	menu_panel.visible = false
	_update_modal()
	_do_load.call_deferred(slot)


func _do_load(slot: String) -> void:
	if RoomManager.load_game(slot):
		GameState.show_hint(StoryData.text("@ui.loaded", {"slot": slot}))


func _on_new_game() -> void:
	menu_panel.visible = false
	_update_modal()
	RoomManager.new_game.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quick_save"):
		if not StoryRunner.is_busy():
			_on_save_slot(QUICK_SLOT)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quick_load"):
		if not StoryRunner.is_busy():
			_on_load_slot(QUICK_SLOT)
		get_viewport().set_input_as_handled()


# --- Fade (loop transition) -----------------------------------------------------

func _on_loop_transition(_spec: Dictionary) -> void:
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, StoryRunner.LOOP_FADE_SECONDS)
	tw.tween_interval(0.15)
	tw.tween_property(fade, "color:a", 0.0, StoryRunner.LOOP_FADE_SECONDS)
	tw.tween_callback(func(): fade.mouse_filter = Control.MOUSE_FILTER_IGNORE)


# --- Probe support (positions for automated clicks) ----------------------------

func probe_positions() -> Dictionary:
	var out := {"buttons": {}, "inventory": {}, "options": {}, "dialogue_open": dialogue.visible,
		"journal_open": journal_panel.visible, "menu_open": menu_panel.visible}
	for b in [journal_button, hint_button, menu_button]:
		out["buttons"][b.name] = _center(b)
	if journal_panel.visible:
		out["buttons"]["CloseJournal"] = _center(journal_panel.find_child("CloseJournal", true, false))
	if menu_panel.visible:
		for slot in slot_rows.keys():
			out["buttons"]["Save" + slot] = _center(slot_rows[slot]["save"])
			out["buttons"]["Load" + slot] = _center(slot_rows[slot]["load"])
		out["buttons"]["NewGame"] = _center(menu_panel.find_child("NewGame", true, false))
		out["buttons"]["CloseMenu"] = _center(menu_panel.find_child("CloseMenu", true, false))
	for item_id in inventory_buttons.keys():
		out["inventory"][item_id] = _center(inventory_buttons[item_id])
	if dialogue.visible:
		out["dialogue_click"] = {"x": 960, "y": 780}
		for c in options_box.get_children():
			if c is Button:
				out["options"][String(c.name).trim_prefix("Option_")] = _center(c)
	return out


func _center(c: Control) -> Dictionary:
	if c == null:
		return {}
	var r := c.get_global_rect()
	return {"x": r.position.x + r.size.x / 2, "y": r.position.y + r.size.y / 2}
