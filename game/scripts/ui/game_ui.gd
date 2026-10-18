extends CanvasLayer
## Mouse-only game UI: top bar (room name, the bag, Journal / Hint / Menu), dialogue box with
## options, examine/narration text, journal panel, save-slot menu, hint line, fade overlay.
## It renders StoryRunner/GameState state and never decides story logic itself.
##
## The bag (InventoryBag) lives in the top bar, not at the bottom: in every room the walkable floor
## is the lower 40–55 % of the frame (Agata at the front edge is 1.6× larger, her feet reach
## y≈1000), the dialogue box and the hint line are there too; the top 80 px are ceiling/sky with no
## hotspot centres, and the bar already reserves them.

## Bag sounds for the sound agent: "receive" (an item flew into the bag), "select" (taken in hand),
## "deselect" (put back). The UI only asks; whoever owns sfx_bag_leather plays it.
signal bag_sound_requested(kind: String)
## The pointer came onto / left a bag pocket with an item (InventoryBag.pocket_hover_changed). VoiceDirector
## plays the item's voice-over line after a dwell (data/story/voice.json → narration.item_hover) and asks
## item_hover_still() before it starts.
signal item_hover_started(item_id: String)
signal item_hover_ended(item_id: String)

const QUICK_SLOT: String = "quick"
const HINT_SECONDS: float = 7.0
const TOP_H: float = 80.0
const CURSOR_ITEM_SIZE: float = 52.0
## Dialogue box: 60 % of the width, centred, as tall as its text, pressed to the bottom edge —
## the characters above it stay visible (Director/coordinator 17.10, frame ui_10).
const DIALOGUE_W: float = 1152.0
const DIALOGUE_BOTTOM: float = 1062.0
const HINT_Y: float = 996.0
const CURSOR_ITEM_OFFSET := Vector2(12, 16)   # below-right of the pointer tip

var top_bar: PanelContainer
var room_label: Label
var room_code_label: Label
var bag: InventoryBag
var fx_layer: Control           # flying icons (above panels, under the fade)
var cursor_item: BagSlot        # the held item's small icon that follows the pointer
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
var hover_label: Label
var map_view: ZarechyeMap       # the Zarechye plan up close (hotspot panel / journal «План»)
var journal_plan_button: Button
var music_slider: HSlider               # menu: music volume 0–100 % (MusicDirector, user://settings.cfg)
var music_value_label: Label
var sfx_slider: HSlider                 # menu: sound effects volume 0–100 % (SfxDirector, user://settings.cfg)
var sfx_value_label: Label
var voice_slider: HSlider               # menu: voice volume 0–100 % (VoiceDirector, user://settings.cfg)
var voice_value_label: Label
var reveal: HotspotReveal               # Space: every hotspot and exit of the room for 1.5 s (exit_hints)
var _exit_cursor: String = ""           # exit cursor kind on now ("" — the ordinary pointer)
var _hover_node: Node = null

var _hint_serial: int = 0


func _ready() -> void:
	layer = 5
	_build()
	# One look for the whole UI (UiTheme: Old Standard TT + PT Serif, warm panels). A CanvasLayer
	# breaks theme inheritance, so each top-level Control gets the theme itself.
	for c in get_children():
		if c is Control:
			(c as Control).theme = UiTheme.get_theme()
	StoryRunner.beat_changed.connect(_render_dialogue)
	StoryRunner.item_selection_changed.connect(func(_i): _render_inventory())
	StoryRunner.item_received.connect(_on_item_received)
	StoryRunner.loop_transition.connect(_on_loop_transition)
	StoryRunner.hint_revealed.connect(func(tier, text): GameState.show_hint(StoryData.text("@ui.hint_title", {"tier": tier}) + ": " + text))
	GameState.inventory_changed.connect(_render_inventory)
	GameState.state_reset.connect(func(): bag.cancel_flights())
	GameState.state_loaded.connect(func(_s): bag.cancel_flights())
	GameState.hint_shown.connect(show_hint)
	StoryRunner.panel_requested.connect(_on_panel_requested)
	RoomManager.room_changed.connect(_on_room_changed)
	_render_inventory()
	_render_dialogue()
	if RoomManager.current_room != null:
		_on_room_changed(RoomManager.current_room.room_id)


# --- Building ------------------------------------------------------------------

func _button(text: String, min_w: float = 0.0, variation: StringName = &"") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if variation != &"":
		b.theme_type_variation = variation
	if variation == &"BarButton":
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # a plate on the bar, not a full-height box
	if min_w > 0:
		b.custom_minimum_size = Vector2(min_w, 0)
	return b


func _build() -> void:
	# Reveal overlay (Space): first child — drawn under the bar, the dialogue and the panels.
	reveal = HotspotReveal.new()
	reveal.name = "Reveal"
	add_child(reveal)
	ExitCursors.install()

	# Top bar
	top_bar = PanelContainer.new()
	top_bar.name = "TopBar"
	top_bar.theme_type_variation = &"TopBarPanel"   # 64 px pockets + 2×4 strip + 2×4 bar margins = TOP_H
	top_bar.position = Vector2(0, 0)
	top_bar.size = Vector2(1920, TOP_H)
	add_child(top_bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	top_bar.add_child(h)
	var title := HBoxContainer.new()
	title.name = "Title"
	title.add_theme_constant_override("separation", 12)
	title.custom_minimum_size = Vector2(440, 0)
	h.add_child(title)
	room_label = Label.new()
	room_label.name = "RoomLabel"
	room_label.theme_type_variation = &"RoomTitle"
	room_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_child(room_label)   # longest name (Кабинет управляющего) fits the 440 px title box
	# Location code (H1, Z2 …): small and muted — players read the name, testers quote the code.
	room_code_label = Label.new()
	room_code_label.name = "RoomCode"
	room_code_label.theme_type_variation = &"RoomCode"
	room_code_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	room_code_label.modulate = Color(1, 1, 1, 0.6)
	title.add_child(room_code_label)
	var bag_center := CenterContainer.new()
	bag_center.name = "BagCenter"
	bag_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bag_center)
	bag = InventoryBag.new()
	bag.tooltip_top = TOP_H
	bag.sound_requested.connect(func(kind): bag_sound_requested.emit(kind))
	bag.pocket_hover_changed.connect(_on_pocket_hover_changed)
	bag_center.add_child(bag)
	journal_button = _button(StoryData.text("@ui.button_journal"), 140, &"BarButton")
	journal_button.name = "JournalButton"
	journal_button.pressed.connect(toggle_journal)
	h.add_child(journal_button)
	hint_button = _button(StoryData.text("@ui.button_hint"), 160, &"BarButton")
	hint_button.name = "HintButton"
	hint_button.pressed.connect(_on_hint_pressed)
	h.add_child(hint_button)
	menu_button = _button(StoryData.text("@ui.button_menu"), 120, &"BarButton")
	menu_button.name = "MenuButton"
	menu_button.pressed.connect(toggle_menu)
	h.add_child(menu_button)

	# Hint line (bottom, click-through)
	hint_line = Label.new()
	hint_line.name = "HintLine"
	hint_line.position = Vector2(0, HINT_Y)
	hint_line.size = Vector2(1920, 52)
	hint_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_line.theme_type_variation = &"HintLabel"
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
	dialogue.theme_type_variation = &"DialoguePanel"
	dialogue.position = Vector2(roundf((1920.0 - DIALOGUE_W) / 2.0), 900)
	dialogue.size = Vector2(DIALOGUE_W, 0)
	dialogue.visible = false
	dialogue.mouse_filter = Control.MOUSE_FILTER_STOP
	dialogue.gui_input.connect(_on_modal_input)
	dialogue.minimum_size_changed.connect(func(): _fit_dialogue.call_deferred())
	add_child(dialogue)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	dialogue.add_child(v)
	speaker_label = Label.new()
	speaker_label.name = "Speaker"
	speaker_label.theme_type_variation = &"SpeakerLabel"
	v.add_child(speaker_label)
	# Text and «Дальше» share a row: no extra line of height for the prompt to continue.
	var text_row := HBoxContainer.new()
	text_row.name = "TextRow"
	text_row.add_theme_constant_override("separation", 18)
	v.add_child(text_row)
	text_label = RichTextLabel.new()
	text_label.name = "Text"
	text_label.bbcode_enabled = false
	text_label.fit_content = true
	text_label.scroll_active = false
	text_label.theme_type_variation = &"DialogueText"
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_row.add_child(text_label)
	continue_label = Label.new()
	continue_label.name = "Continue"
	continue_label.text = StoryData.text("@ui.continue")
	continue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	continue_label.size_flags_vertical = Control.SIZE_SHRINK_END
	continue_label.theme_type_variation = &"MutedLabel"
	text_row.add_child(continue_label)
	options_box = VBoxContainer.new()
	options_box.name = "Options"
	options_box.add_theme_constant_override("separation", 6)
	v.add_child(options_box)

	# Journal panel
	journal_panel = PanelContainer.new()
	journal_panel.name = "Journal"
	journal_panel.position = Vector2(360, 140)
	journal_panel.size = Vector2(1200, 760)
	journal_panel.visible = false
	add_child(journal_panel)
	var jv := VBoxContainer.new()
	jv.add_theme_constant_override("separation", 10)
	journal_panel.add_child(jv)
	var jt := Label.new()
	jt.text = StoryData.text("@ui.journal_title")
	jt.theme_type_variation = &"HeaderLarge"
	jv.add_child(jt)
	var jg := Label.new()
	jg.text = StoryData.text("@ui.journal_goal")
	jg.theme_type_variation = &"HeaderSmall"
	jv.add_child(jg)
	journal_goal_label = Label.new()
	journal_goal_label.name = "Goal"
	journal_goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	journal_goal_label.theme_type_variation = &"BodyLabel"
	jv.add_child(journal_goal_label)
	var jf := Label.new()
	jf.text = StoryData.text("@ui.journal_facts")
	jf.theme_type_variation = &"HeaderSmall"
	jv.add_child(jf)
	journal_facts_label = RichTextLabel.new()
	journal_facts_label.name = "Facts"
	journal_facts_label.bbcode_enabled = false
	journal_facts_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	journal_facts_label.theme_type_variation = &"JournalText"
	jv.add_child(journal_facts_label)
	var jbuttons := HBoxContainer.new()
	jbuttons.add_theme_constant_override("separation", 12)
	jv.add_child(jbuttons)
	var jclose := _button(StoryData.text("@ui.close"), 200)
	jclose.name = "CloseJournal"
	jclose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jclose.pressed.connect(toggle_journal)
	jbuttons.add_child(jclose)
	# «План»: the Zarechye plan, once it has been looked at on the post-office wall (map journal_flag).
	journal_plan_button = _button(StoryData.text("@ui.button_plan"), 220)
	journal_plan_button.name = "JournalPlan"
	journal_plan_button.pressed.connect(_open_map_from_journal)
	jbuttons.add_child(journal_plan_button)

	# Menu panel (save slots)
	menu_panel = PanelContainer.new()
	menu_panel.name = "Menu"
	menu_panel.position = Vector2(510, 220)
	menu_panel.size = Vector2(900, 560)
	menu_panel.visible = false
	add_child(menu_panel)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 12)
	menu_panel.add_child(mv)
	var mt := Label.new()
	mt.text = StoryData.text("@ui.menu_title")
	mt.theme_type_variation = &"HeaderLarge"
	mv.add_child(mt)
	for slot in GameState.MANUAL_SLOTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		mv.add_child(row)
		var name_l := Label.new()
		name_l.text = StoryData.text("@ui.slot", {"n": slot})
		name_l.custom_minimum_size = Vector2(120, 0)
		name_l.theme_type_variation = &"SlotNameLabel"
		row.add_child(name_l)
		var info := Label.new()
		info.custom_minimum_size = Vector2(400, 0)
		info.theme_type_variation = &"SmallLabel"
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
	# Music volume: a setting (user://settings.cfg), not part of a save slot.
	var music_row := HBoxContainer.new()
	music_row.add_theme_constant_override("separation", 12)
	mv.add_child(music_row)
	var music_l := Label.new()
	music_l.text = StoryData.text("@ui.music_volume")
	music_l.custom_minimum_size = Vector2(120, 0)
	music_l.theme_type_variation = &"SlotNameLabel"
	music_row.add_child(music_l)
	music_slider = HSlider.new()
	music_slider.name = "MusicSlider"
	music_slider.min_value = 0
	music_slider.max_value = 100
	music_slider.step = 1
	music_slider.custom_minimum_size = Vector2(420, 40)
	music_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	music_slider.value = roundf(MusicDirector.music_volume * 100.0)
	music_slider.value_changed.connect(_on_music_slider)
	music_row.add_child(music_slider)
	music_value_label = Label.new()
	music_value_label.custom_minimum_size = Vector2(90, 0)
	music_value_label.theme_type_variation = &"SmallLabel"
	music_value_label.text = "%d %%" % int(music_slider.value)
	music_row.add_child(music_value_label)
	var sfx_row := HBoxContainer.new()
	sfx_row.add_theme_constant_override("separation", 12)
	mv.add_child(sfx_row)
	var sfx_l := Label.new()
	sfx_l.text = StoryData.text("@ui.sfx_volume")
	sfx_l.custom_minimum_size = Vector2(120, 0)
	sfx_l.theme_type_variation = &"SlotNameLabel"
	sfx_row.add_child(sfx_l)
	sfx_slider = HSlider.new()
	sfx_slider.name = "SfxSlider"
	sfx_slider.min_value = 0
	sfx_slider.max_value = 100
	sfx_slider.step = 1
	sfx_slider.custom_minimum_size = Vector2(420, 40)
	sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sfx_slider.value = roundf(SfxDirector.sfx_volume * 100.0)
	sfx_slider.value_changed.connect(_on_sfx_slider)
	sfx_row.add_child(sfx_slider)
	sfx_value_label = Label.new()
	sfx_value_label.custom_minimum_size = Vector2(90, 0)
	sfx_value_label.theme_type_variation = &"SmallLabel"
	sfx_value_label.text = "%d %%" % int(sfx_slider.value)
	sfx_row.add_child(sfx_value_label)
	var voice_row := HBoxContainer.new()
	voice_row.add_theme_constant_override("separation", 12)
	mv.add_child(voice_row)
	var voice_l := Label.new()
	voice_l.text = StoryData.text("@ui.voice_volume")
	voice_l.custom_minimum_size = Vector2(120, 0)
	voice_l.theme_type_variation = &"SlotNameLabel"
	voice_row.add_child(voice_l)
	voice_slider = HSlider.new()
	voice_slider.name = "VoiceSlider"
	voice_slider.min_value = 0
	voice_slider.max_value = 100
	voice_slider.step = 1
	voice_slider.custom_minimum_size = Vector2(420, 40)
	voice_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	voice_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	voice_slider.value = roundf(VoiceDirector.voice_volume * 100.0)
	voice_slider.value_changed.connect(_on_voice_slider)
	voice_row.add_child(voice_slider)
	voice_value_label = Label.new()
	voice_value_label.custom_minimum_size = Vector2(90, 0)
	voice_value_label.theme_type_variation = &"SmallLabel"
	voice_value_label.text = "%d %%" % int(voice_slider.value)
	voice_row.add_child(voice_value_label)
	# Controls line: the reveal key (exit_hints, Director 18.10).
	var keys_l := Label.new()
	keys_l.name = "KeysHint"
	keys_l.text = StoryData.text("@ui.controls_reveal")
	keys_l.theme_type_variation = &"MutedLabel"
	keys_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mv.add_child(keys_l)
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

	# Hover label: name of the hotspot/exit under the cursor (real-art rooms draw no placeholders).
	hover_label = Label.new()
	hover_label.name = "Hover"
	hover_label.visible = false
	hover_label.theme_type_variation = &"HoverLabel"
	hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hover_label)

	# The Zarechye plan: above the panels, catches every click while open.
	map_view = ZarechyeMap.new()
	map_view.closed.connect(_on_map_closed)
	add_child(map_view)

	# Flying icons ("item flies into the bag"): above the panels, under the fade.
	fx_layer = Control.new()
	fx_layer.name = "Fx"
	fx_layer.position = Vector2.ZERO
	fx_layer.size = Vector2(1920, 1080)
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx_layer)
	bag.fx_parent = fx_layer

	# Fade overlay
	fade = ColorRect.new()
	fade.name = "Fade"
	fade.color = Color(0, 0, 0, 0)
	fade.position = Vector2.ZERO
	fade.size = Vector2(1920, 1080)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)

	# The held item rides with the pointer (a small icon below-right of the tip; the arrow stays).
	cursor_item = BagSlot.new()
	cursor_item.name = "CursorItem"
	cursor_item.loose = true
	cursor_item.top_level = true
	cursor_item.size = Vector2(CURSOR_ITEM_SIZE, CURSOR_ITEM_SIZE)
	cursor_item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor_item.visible = false
	add_child(cursor_item)


# --- Rendering -------------------------------------------------------------------

func _on_room_changed(room_id: String) -> void:
	reveal.cancel()
	var name := StoryData.location_name(room_id)
	room_label.text = name
	# Служебный код комнаты игроку не показываем (решение 17.10: в тексте для игрока нет кодов);
	# виден только при отладке (OS.is_debug_build — сборка из редактора) или если имени нет.
	room_code_label.text = room_id if (name == room_id or OS.has_feature("editor")) else ""


func _render_inventory() -> void:
	bag.refresh()
	_update_cursor_item()


## A granted item flies into its pocket from above Agata (or the screen centre without a player).
func _on_item_received(item_id: String) -> void:
	var from := Vector2(960, 540)
	var p: Node2D = RoomManager.player
	if p != null and is_instance_valid(p) and p.is_inside_tree():
		var at: Vector2 = p.get_global_transform_with_canvas().origin
		from = at + Vector2(0, -190.0 * absf(p.scale.y))
	from = Vector2(clampf(from.x, 120, 1800), clampf(from.y, TOP_H + 120, 960))
	bag.fly_in(item_id, from)


func _on_pocket_hover_changed(old_item: String, new_item: String) -> void:
	if old_item != "":
		item_hover_ended.emit(old_item)
	if new_item != "":
		item_hover_started.emit(new_item)


## VoiceDirector asks at the end of the dwell: the tooltip still shows `item_id`, nothing modal is open,
## no icon is flying in.
func item_hover_still(item_id: String) -> bool:
	return bag.tooltip_shows(item_id) and not modal.visible and not map_view.visible


## Same as clicking the item's pocket (tests, probe): take it in hand / put it back.
func click_inventory_item(item_id: String) -> String:
	return bag.click_item(item_id)


func _update_cursor_item() -> void:
	var id := StoryRunner.selected_item
	if id == "" or not GameState.has_item(id):
		cursor_item.visible = false
		cursor_item.item_id = ""
		return
	if cursor_item.item_id != id:
		cursor_item.item_id = id
		cursor_item.item_name = StoryData.item_name(id)
		cursor_item.icon = InventoryBag.icon_for(id)
	cursor_item.position = get_viewport().get_mouse_position() + CURSOR_ITEM_OFFSET
	cursor_item.visible = true


func _render_dialogue() -> void:
	var beat := StoryRunner.current_beat
	for c in options_box.get_children():
		c.queue_free()
	if beat.is_empty():
		dialogue.visible = false
		_update_modal()
		_fit_dialogue()
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
			var b := _button(String(o.get("label", o.get("id", ""))), 0.0, &"DialogueOption")
			b.name = "Option_" + String(o.get("id", ""))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.pressed.connect(func(): StoryRunner.choose(String(o.get("id", ""))))
			options_box.add_child(b)
	else:
		text_label.visible = true
		text_label.text = String(beat.get("text", ""))
		continue_label.visible = true
	_update_modal()
	_fit_dialogue.call_deferred()


## As tall as the content (name + 1–3 lines, or the options), centred, pressed to the bottom; the
## hint line moves above it while it is open.
func _fit_dialogue() -> void:
	if dialogue.visible:
		dialogue.size = Vector2(DIALOGUE_W, 0)
		dialogue.position = Vector2(roundf((1920.0 - DIALOGUE_W) / 2.0), roundf(DIALOGUE_BOTTOM - dialogue.size.y))
		hint_line.position.y = dialogue.position.y - hint_line.size.y - 6.0
	else:
		hint_line.position.y = HINT_Y


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


# --- The Zarechye plan ---------------------------------------------------------------

## A hotspot with `panel` (rooms data) was clicked: the plan rides in from where it hangs on the wall.
func _on_panel_requested(panel_id: String, source: Node) -> void:
	if panel_id != map_view.panel_id():
		push_warning("GameUi: unknown panel '%s'" % panel_id)
		return
	var src := Rect2()
	if source != null and is_instance_valid(source) and source.get("data") is Dictionary:
		var r: Array = (source.get("data") as Dictionary).get("rect", [])
		if r.size() == 4:
			src = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	_set_hover(null)
	map_view.open_from(src)


func _open_map_from_journal() -> void:
	if not map_view.available_in_journal():
		return
	var from := journal_plan_button.get_global_rect()
	journal_panel.visible = false
	_update_modal()
	map_view.open_from(from, true)


func _on_map_closed(reopen_journal: bool) -> void:
	if reopen_journal and not journal_panel.visible:
		toggle_journal()


func toggle_journal() -> void:
	if StoryRunner.is_busy() and not journal_panel.visible:
		return
	journal_panel.visible = not journal_panel.visible
	menu_panel.visible = false
	if journal_panel.visible:
		journal_plan_button.visible = map_view.available_in_journal()
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
		_fit_panel.call_deferred(menu_panel)
		music_slider.set_value_no_signal(roundf(MusicDirector.music_volume * 100.0))
		music_value_label.text = "%d %%" % int(music_slider.value)
		sfx_slider.set_value_no_signal(roundf(SfxDirector.sfx_volume * 100.0))
		sfx_value_label.text = "%d %%" % int(sfx_slider.value)
		voice_slider.set_value_no_signal(roundf(VoiceDirector.voice_volume * 100.0))
		voice_value_label.text = "%d %%" % int(voice_slider.value)
	_update_modal()


## Panel as tall as its content, centred under the top bar.
func _fit_panel(p: PanelContainer) -> void:
	p.size = Vector2(p.size.x, 0)
	p.reset_size()
	p.position.y = roundf(TOP_H + (1080.0 - TOP_H - p.size.y) / 2.0)


func _on_music_slider(value: float) -> void:
	music_value_label.text = "%d %%" % int(value)
	MusicDirector.set_music_volume(value / 100.0)


func _on_sfx_slider(value: float) -> void:
	sfx_value_label.text = "%d %%" % int(value)
	SfxDirector.set_sfx_volume(value / 100.0)


func _on_voice_slider(value: float) -> void:
	voice_value_label.text = "%d %%" % int(value)
	VoiceDirector.set_voice_volume(value / 100.0)


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


func _input(event: InputEvent) -> void:
	# The held item's icon follows the pointer without waiting for _process.
	if event is InputEventMouseMotion and cursor_item.visible:
		cursor_item.position = get_viewport().get_mouse_position() + CURSOR_ITEM_OFFSET


func _unhandled_input(event: InputEvent) -> void:
	# Right click anywhere on the scene puts the held item back into the bag.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT \
			and StoryRunner.selected_item != "":
		bag.put_back()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("reveal_hotspots", false):
		reveal_hotspots()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("quick_save"):
		if not StoryRunner.is_busy():
			_on_save_slot(QUICK_SLOT)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quick_load"):
		if not StoryRunner.is_busy():
			_on_load_slot(QUICK_SLOT)
		get_viewport().set_input_as_handled()


# --- Hover ------------------------------------------------------------------------

func _process(_delta: float) -> void:
	hint_line.visible = not map_view.visible
	if StoryRunner.selected_item != "":
		_update_cursor_item()
		if modal.visible or map_view.visible:
			cursor_item.visible = false
	elif cursor_item.visible:
		cursor_item.visible = false
	var room := RoomManager.current_room
	var blocked := StoryRunner.is_busy() or modal.visible or map_view.visible
	ExitCue.suppressed = blocked   # exit marks fade out under a dialogue / panel / the plan
	if blocked and reveal.active():
		reveal.cancel()
	if room == null or not is_instance_valid(room) or blocked:
		_set_hover(null)
		return
	var mouse := room.get_global_mouse_position()
	if mouse.y < TOP_H:
		_set_hover(null)
		return
	var node = room.pick(mouse)
	_set_hover(node)
	if node != null:
		var screen := get_viewport().get_mouse_position()
		hover_label.position = Vector2(clampf(screen.x + 18, 0, 1920 - hover_label.size.x - 8), clampf(screen.y - 34, TOP_H, 1040))


func _set_hover(node: Node) -> void:
	_set_exit_hover(node)
	# A hotspot from the previous room is freed on room change; a freed instance compares equal
	# to null, so without this reset the old label would stay on screen.
	if not is_instance_valid(_hover_node):
		_hover_node = null
		if node == null:
			hover_label.visible = false
			return
	if node == _hover_node and (node == null or hover_label.visible):
		return
	_hover_node = node
	if node == null or not node.has_method("label_text"):
		hover_label.visible = false
		return
	hover_label.text = node.call("label_text")
	hover_label.visible = true


# --- Exit hints: marks, exit cursor, reveal key (Director 18.10) ------------------------

var _hot_exit: Node = null


## The pointer on an exit: its mark (ExitCue) brightens and the cursor becomes the exit arrow (or the
## doorway for an exit drawn in the art); anywhere else — the ordinary pointer.
func _set_exit_hover(node: Node) -> void:
	var ex: Node = node if node != null and is_instance_valid(node) and node.has_method("cursor_kind") else null
	if ex != _hot_exit:
		if _hot_exit != null and is_instance_valid(_hot_exit):
			_hot_exit.call("set_hot", false)
		_hot_exit = ex
		if ex != null:
			ex.call("set_hot", true)
	_set_exit_cursor(String(ex.call("cursor_kind")) if ex != null else "")


func _set_exit_cursor(kind: String) -> void:
	if kind == _exit_cursor:
		return
	_exit_cursor = kind
	Input.set_default_cursor_shape(ExitCursors.shape(kind))


## Space: every active hotspot and every exit of the room for HotspotReveal.DURATION seconds.
## Returns false when nothing can be shown (dialogue, panel, plan, no room).
func reveal_hotspots() -> bool:
	var room := RoomManager.current_room
	if room == null or not is_instance_valid(room) or StoryRunner.is_busy() or modal.visible or map_view.visible:
		return false
	var cues: Array = []
	for e in room.get_exits():
		if e is StoryExit and (e as StoryExit).cue != null:
			cues.append((e as StoryExit).cue)
	reveal.show_targets(reveal_targets(), cues)
	return true


## What the reveal shows: [{kind: "hotspot"|"exit", id, label, at: Vector2, dir}] — active hotspots at
## the centre of their (current) rect, exits at their mark (or the centre of the drawn door).
func reveal_targets() -> Array:
	var out: Array = []
	var room := RoomManager.current_room
	if room == null or not is_instance_valid(room):
		return out
	for h in room.get_hotspots():
		if h is StoryHotspot and (h as StoryHotspot).is_active():
			# The node sits at the centre of its rect (a state may move it — StoryHotspot._apply_geometry).
			out.append({"kind": "hotspot", "id": (h as StoryHotspot).hotspot_id, "label": (h as StoryHotspot).label_text(), "at": h.global_position, "dir": ""})
	for e in room.get_exits():
		if e is StoryExit:
			var se := e as StoryExit
			var at: Vector2 = se.cue.global_position if se.cue != null else se.global_position
			out.append({"kind": "exit", "id": se.target_room, "label": se.label_text(), "at": at, "dir": se.cue_dir})
	return out


## Probe: exit marks of the current room (target → {dir, x, y, alpha, hot, source}), the cursor kind,
## the reveal state.
func exit_hints_probe() -> Dictionary:
	var cues := {}
	var room := RoomManager.current_room
	if room != null and is_instance_valid(room):
		for e in room.get_exits():
			if e is StoryExit:
				var se := e as StoryExit
				var d := {"dir": se.cue_dir, "source": se.cue_source}
				if se.cue != null:
					d["x"] = se.cue.global_position.x
					d["y"] = se.cue.global_position.y
					d["alpha"] = se.cue.current_alpha()
					d["hot"] = se.cue.is_hot()
				cues[se.target_room] = d
	var shown: Array = []
	if reveal.active():
		for t in reveal.targets:
			shown.append("%s:%s" % [t["kind"], t["id"]])
	return {"cues": cues, "cursor": _exit_cursor, "cursor_shape": int(Input.get_current_cursor_shape()),
		"hover": hover_label.text if hover_label.visible else "", "reveal": reveal.active(), "revealed": shown}


# --- Fade (loop transition) -----------------------------------------------------

func _on_loop_transition(_spec: Dictionary) -> void:
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, StoryRunner.LOOP_FADE_SECONDS)
	# The teleport happens at LOOP_FADE_SECONDS; from here on clicks go to the dialogue underneath.
	tw.tween_callback(func(): fade.mouse_filter = Control.MOUSE_FILTER_IGNORE)
	tw.tween_interval(0.15)
	tw.tween_property(fade, "color:a", 0.0, StoryRunner.LOOP_FADE_SECONDS)


# --- Probe support (positions for automated clicks) ----------------------------

func probe_positions() -> Dictionary:
	var out := {"buttons": {}, "inventory": {}, "options": {}, "dialogue_open": dialogue.visible,
		"map_open": map_view.visible, "map": map_view.probe() if map_view.visible else {},
		"journal_open": journal_panel.visible, "menu_open": menu_panel.visible}
	for b in [journal_button, hint_button, menu_button]:
		out["buttons"][b.name] = _center(b)
	if journal_panel.visible:
		out["buttons"]["CloseJournal"] = _center(journal_panel.find_child("CloseJournal", true, false))
		if journal_plan_button.visible:
			out["buttons"]["JournalPlan"] = _center(journal_plan_button)
	if menu_panel.visible:
		for slot in slot_rows.keys():
			out["buttons"]["Save" + slot] = _center(slot_rows[slot]["save"])
			out["buttons"]["Load" + slot] = _center(slot_rows[slot]["load"])
		out["buttons"]["NewGame"] = _center(menu_panel.find_child("NewGame", true, false))
		out["buttons"]["CloseMenu"] = _center(menu_panel.find_child("CloseMenu", true, false))
		var mr := music_slider.get_global_rect()
		out["music_slider"] = {"x": mr.position.x, "y": mr.position.y, "w": mr.size.x, "h": mr.size.y, "value": music_slider.value}
		var sr := sfx_slider.get_global_rect()
		out["sfx_slider"] = {"x": sr.position.x, "y": sr.position.y, "w": sr.size.x, "h": sr.size.y, "value": sfx_slider.value}
		var vr := voice_slider.get_global_rect()
		out["voice_slider"] = {"x": vr.position.x, "y": vr.position.y, "w": vr.size.x, "h": vr.size.y, "value": voice_slider.value}
	# inventory: item -> centre of its pocket (only items on the bag's current page are clickable).
	var bp: Dictionary = bag.probe()
	for item_id in bp["items"].keys():
		out["inventory"][item_id] = {"x": bp["items"][item_id]["x"], "y": bp["items"][item_id]["y"]}
	out["bag"] = bp
	out["cursor_item"] = cursor_item.item_id if cursor_item.visible else ""
	out["exit_hints"] = exit_hints_probe()
	if dialogue.visible:
		out["dialogue_click"] = _center(dialogue)
		for c in options_box.get_children():
			if c is Button:
				out["options"][String(c.name).trim_prefix("Option_")] = _center(c)
	return out


func _center(c: Control) -> Dictionary:
	if c == null:
		return {}
	var r := c.get_global_rect()
	return {"x": r.position.x + r.size.x / 2, "y": r.position.y + r.size.y / 2}
