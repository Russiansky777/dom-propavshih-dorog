extends Node
## Entry scene: wires RoomManager to the world container and the player, starts a new game
## and (on web) publishes a tiny probe state for automated screenshots.

const START_ROOM: String = "RoomHouse"
const START_SPAWN: String = "start"

@onready var world: Node2D = $World
@onready var player: Player = $World/Player

var _last_hint: String = ""


func _ready() -> void:
	RoomManager.setup(world, player)
	RoomManager.room_changed.connect(_on_room_changed)
	GameState.flag_changed.connect(_on_flag_changed)
	GameState.state_loaded.connect(_on_state_loaded)
	GameState.hint_shown.connect(_on_hint_shown)
	player.walk_started.connect(_on_walk_started)
	player.arrived.connect(_on_arrived)

	RoomManager.new_game(START_ROOM, START_SPAWN)
	_publish_probe_state()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.probeReady = true;", true)


func _on_room_changed(_room_id: String) -> void:
	_publish_probe_state()


func _on_flag_changed(_flag: String, _value: bool) -> void:
	_publish_probe_state()


func _on_state_loaded(_slot: String) -> void:
	_publish_probe_state()


func _on_hint_shown(text: String) -> void:
	_last_hint = text
	_publish_probe_state()


func _on_walk_started(_target: Vector2) -> void:
	_publish_probe_state()


func _on_arrived(_pos: Vector2) -> void:
	_publish_probe_state()


## Exposes `window.probeState` on web builds so tools/screenshots.mjs can wait for real
## state transitions instead of fixed sleeps. Harmless no-op elsewhere.
func _publish_probe_state() -> void:
	if not OS.has_feature("web"):
		return
	var mirror_wobbling := false
	if RoomManager.current_room != null:
		var mirror := RoomManager.current_room.get_node_or_null("Mirror")
		if mirror != null and mirror.has_method("is_wobbling"):
			mirror_wobbling = mirror.call("is_wobbling")
	var state := {
		"room": GameState.current_room,
		"flags": GameState.flags,
		"inventory": GameState.inventory,
		"player": {
			"x": player.global_position.x,
			"y": player.global_position.y,
			"walking": player.is_walking(),
		},
		"mirror_wobbling": mirror_wobbling,
		"last_hint": _last_hint,
		"ticks": Time.get_ticks_msec(),
	}
	JavaScriptBridge.eval("window.probeState = %s;" % JSON.stringify(state), true)
