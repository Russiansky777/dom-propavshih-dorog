class_name StateLayer
extends Node2D
## Image layer of a room built from `layers[]` in rooms/<id>.json. Visible when every `if` flag
## holds and no `unless` flag holds (both optional). Drawn at `offset` with `scale` relative to
## the 1920x1080 base (the whole PNG is mapped to 1920x1080 first, as the art is 1672x941).

var data: Dictionary = {}


func setup(p_data: Dictionary) -> void:
	data = p_data
	if data.has("if") or data.has("unless"):
		if not GameState.flag_changed.is_connected(_on_flag_changed):
			GameState.flag_changed.connect(_on_flag_changed)
		if not GameState.state_reset.is_connected(refresh):
			GameState.state_reset.connect(refresh)
	refresh()


func _exit_tree() -> void:
	if GameState.flag_changed.is_connected(_on_flag_changed):
		GameState.flag_changed.disconnect(_on_flag_changed)
	if GameState.state_reset.is_connected(refresh):
		GameState.state_reset.disconnect(refresh)


func _on_flag_changed(_f: String, _v: bool) -> void:
	refresh()


func is_active() -> bool:
	for f in data.get("if", []):
		if not GameState.has_flag(String(f)):
			return false
	for f in data.get("unless", []):
		if GameState.has_flag(String(f)):
			return false
	return true


func refresh() -> void:
	visible = is_active()
