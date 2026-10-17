extends CanvasLayer
## Debug/probe HUD: room name, flag readout, Save (F5) / Load (F9) / New game, one-line hint.

const QUICK_SLOT: String = "quick"
const HINT_SECONDS: float = 6.0

@onready var room_label: Label = $Panel/VBox/RoomLabel
@onready var flags_label: Label = $Panel/VBox/FlagsLabel
@onready var hint_label: Label = $HintLabel
@onready var save_button: Button = $Panel/VBox/Buttons/SaveButton
@onready var load_button: Button = $Panel/VBox/Buttons/LoadButton
@onready var new_button: Button = $Panel/VBox/Buttons/NewGameButton

var _hint_serial: int = 0


func _ready() -> void:
	RoomManager.room_changed.connect(_on_room_changed)
	GameState.flag_changed.connect(_on_flag_changed)
	GameState.state_reset.connect(_refresh_flags)
	GameState.state_loaded.connect(_on_state_loaded)
	GameState.hint_shown.connect(show_hint)
	save_button.pressed.connect(_on_save)
	load_button.pressed.connect(_on_load)
	new_button.pressed.connect(_on_new_game)
	_refresh_flags()
	if RoomManager.current_room != null:
		_on_room_changed(RoomManager.current_room.room_id)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quick_save"):
		_on_save()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quick_load"):
		_on_load()
		get_viewport().set_input_as_handled()


func _on_room_changed(room_id: String) -> void:
	var title := room_id
	if RoomManager.current_room != null and RoomManager.current_room.room_name != "":
		title = "%s — %s" % [room_id, RoomManager.current_room.room_name]
	room_label.text = title


func _on_flag_changed(_flag: String, _value: bool) -> void:
	_refresh_flags()


func _on_state_loaded(_slot: String) -> void:
	_refresh_flags()


func _refresh_flags() -> void:
	var keys := GameState.flags.keys()
	keys.sort()
	var parts: Array[String] = []
	for k in keys:
		parts.append("%s=%s" % [k, "1" if GameState.flags[k] else "0"])
	flags_label.text = "flags: " + (", ".join(parts) if not parts.is_empty() else "(none)")


func show_hint(text: String) -> void:
	_hint_serial += 1
	var serial := _hint_serial
	hint_label.text = text
	await get_tree().create_timer(HINT_SECONDS).timeout
	if serial == _hint_serial and is_instance_valid(hint_label):
		hint_label.text = ""


func _on_save() -> void:
	if RoomManager.save_game(QUICK_SLOT):
		GameState.show_hint("Сохранено (слот '%s')." % QUICK_SLOT)
	else:
		GameState.show_hint("Не удалось сохранить.")


func _on_load() -> void:
	if not GameState.has_save(QUICK_SLOT):
		GameState.show_hint("Нет сохранения в слоте '%s'." % QUICK_SLOT)
		return
	# Deferred: rebuilding the room frees nodes, which must not happen inside input dispatch.
	_do_load.call_deferred()


func _do_load() -> void:
	if RoomManager.load_game(QUICK_SLOT):
		GameState.show_hint("Загружено (слот '%s')." % QUICK_SLOT)
	else:
		GameState.show_hint("Не удалось загрузить.")


func _on_new_game() -> void:
	_do_new_game.call_deferred()


func _do_new_game() -> void:
	RoomManager.new_game()
	GameState.show_hint("Новая игра.")
