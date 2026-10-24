class_name StateLayer
extends Node2D
## Image layer of a room built from `layers[]` in rooms/<id>.json. Visible when every `if` flag
## holds and no `unless` flag holds (both optional). Drawn with the room's art scale (the same as
## the background), moved by `offset`; an extra `scale` only with `scale_reason` (RoomBuilder).

var data: Dictionary = {}
## Shown ahead of its flags (Player: hotspot data carry.show_layers — the bench is bare while the kerchief
## is carried to the hook, before the interaction sets the flag).
var forced: bool = false


func setup(p_data: Dictionary) -> void:
	data = p_data
	if data.has("if") or data.has("unless") or data.has("spin") or data.has("swing") or data.has("frames"):
		if not GameState.flag_changed.is_connected(_on_flag_changed):
			GameState.flag_changed.connect(_on_flag_changed)
		if not GameState.state_reset.is_connected(refresh):
			GameState.state_reset.connect(refresh)
	refresh()


## A script with _process gets processing switched on when it enters the tree — the room is built before
## it is added, so the spin state is set again here.
func _ready() -> void:
	refresh()


func _exit_tree() -> void:
	if GameState.flag_changed.is_connected(_on_flag_changed):
		GameState.flag_changed.disconnect(_on_flag_changed)
	if GameState.state_reset.is_connected(refresh):
		GameState.state_reset.disconnect(refresh)


func _on_flag_changed(_f: String, _v: bool) -> void:
	refresh()


func set_forced(on: bool) -> void:
	forced = on
	refresh()


func is_active() -> bool:
	if forced:
		return true
	for f in data.get("if", []):
		if not GameState.has_flag(String(f)):
			return false
	for f in data.get("unless", []):
		if GameState.has_flag(String(f)):
			return false
	return true


func refresh() -> void:
	visible = is_active()
	set_process(visible and (_spin_on() or data.has("swing") or data.has("frames")))


## `spin` {deg_per_s, if, unless}: the layer turns about its `pivot` while the flags allow (the M1 water
## wheel stops once the pond is let down — «Спустишь пруд — мельница встанет»).
func _spin_on() -> bool:
	var sp: Dictionary = data.get("spin", {})
	if sp.is_empty():
		return false
	for f in sp.get("if", []):
		if not GameState.has_flag(String(f)):
			return false
	for f in sp.get("unless", []):
		if GameState.has_flag(String(f)):
			return false
	return true


func is_spinning() -> bool:
	return visible and _spin_on()


## Index of the shown sprite of a `frames` loop (tests).
func frame_index() -> int:
	return _frame


var _frame: int = 0
var _frame_t: float = 0.0


var _swing_t: float = 0.0


func _process(delta: float) -> void:
	if data.has("frames"):
		_frame_t += delta
		var sprites := get_children().filter(func(c): return c is Sprite2D)
		if sprites.size() > 1:
			_frame = int(_frame_t * float(data.get("fps", 7.0))) % sprites.size()
			for i in sprites.size():
				sprites[i].visible = i == _frame
	var img := get_node_or_null("Image") as Node2D
	if img == null:
		return
	# `swing` {deg, period_s, phase}: a pendulum about the layer's `pivot` (the clock in Nina's room) — eased
	# both ways like a real one: ±deg, one full swing per period_s.
	if data.has("swing"):
		var sw: Dictionary = data["swing"]
		_swing_t += delta
		var per := maxf(float(sw.get("period_s", 1.0)), 0.05)
		img.rotation_degrees = float(data.get("rotation_deg", 0.0)) + float(sw.get("deg", 4.0)) * sin(TAU * (_swing_t / per + float(sw.get("phase", 0.0))))
		return
	if not _spin_on():
		return
	img.rotation_degrees = fmod(img.rotation_degrees + float(data.get("spin", {}).get("deg_per_s", 0.0)) * delta, 360.0)
