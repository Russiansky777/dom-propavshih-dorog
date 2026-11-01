class_name StateLayer
extends Node2D
## Image layer of a room built from `layers[]` in rooms/<id>.json. Visible when every `if` flag
## holds and no `unless` flag holds (both optional), and no `hidden_when` condition holds ({all: [flags], not: [flags]},
## as on hotspots — J, Р11: the boat at the turn is away while Pelageya has rowed it to her pier, M15 → M16). Drawn with the room's art scale (the same as
## the background), moved by `offset`; an extra `scale` only with `scale_reason` (RoomBuilder).

var data: Dictionary = {}
## Shown ahead of its flags (Player: hotspot data carry.show_layers — the bench is bare while the kerchief
## is carried to the hook, before the interaction sets the flag).
var forced: bool = false


func setup(p_data: Dictionary) -> void:
	data = p_data
	_setup_life()
	if data.has("if") or data.has("unless") or data.has("hidden_when") or data.has("spin") or data.has("swing") or data.has("frames"):
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
	for c in data.get("hidden_when", []):
		var all_set := true
		for f in c.get("all", []):
			if not GameState.has_flag(String(f)):
				all_set = false
		var none_set := true
		for f in c.get("not", []):
			if GameState.has_flag(String(f)):
				none_set = false
		if all_set and none_set:
			return false
	return true


func refresh() -> void:
	visible = is_active()
	set_process(visible and (_spin_on() or data.has("swing") or data.has("frames") or life_mat != null))


## A figure of a composed frame (a layer with `compose.char`, tools/make_frame_layers.py) is not a still picture
## (Director 01.11, lines 61 and 68): it breathes and sways a little, and moves its head with its own line while
## that line is being said — game/shaders/frame_figure.gdshader, values game/data/actors/frame_life.json, the
## layer's `life` {…} overrides them, `life: false` keeps it still.
const LIFE_PATH := "res://data/actors/frame_life.json"
const LIFE_SHADER := preload("res://shaders/frame_figure.gdshader")
var life_mat: ShaderMaterial = null
var life_char: String = ""
var life_talk: float = 0.0       # 0..1 as shown (tests)
var _life_t: float = 0.0
var _life_cfg: Dictionary = {}


func _setup_life() -> void:
	var c = data.get("compose", {})
	if not (c is Dictionary) or String(c.get("char", "")) == "" or not c.has("feet"):
		return
	var lf = data.get("life", true)
	if lf is bool and not lf:
		return
	var img := get_node_or_null("Image") as Sprite2D
	if img == null:
		return
	var cfg: Dictionary = {}
	if FileAccess.file_exists(LIFE_PATH):
		var doc = JSON.parse_string(FileAccess.get_file_as_string(LIFE_PATH))
		if doc is Dictionary:
			cfg = (doc as Dictionary).duplicate()
			var by: Dictionary = cfg.get("by_action", {})
			cfg.merge(by.get(String(c.get("action", "")), {}), true)
	if data.get("life") is Dictionary:
		cfg.merge(data["life"], true)
	_life_cfg = cfg
	life_char = String(c["char"])
	life_mat = ShaderMaterial.new()
	life_mat.shader = LIFE_SHADER
	var feet: Array = c["feet"]
	life_mat.set_shader_parameter("feet_px", Vector2(float(feet[0]), float(feet[1])))
	life_mat.set_shader_parameter("height_px", float(c.get("height", 300.0)))
	# each figure its own moment: from its id and place, the same from run to run
	life_mat.set_shader_parameter("phase", fposmod(float(hash(life_char + String(name))) * 0.618034, TAU))
	var hpx := maxf(float(c.get("height", 300.0)), 1.0)
	for k in ["breath_frac", "breath_period_s", "sway_frac", "sway_period_s", "talk_frac"]:
		if cfg.has(k):
			var v := float(cfg[k])
			# a small figure: its share of the height would be under a pixel — at least `<x>_min_px` picture pixels
			var mk := String(k).replace("_frac", "_min_px")
			if String(k).ends_with("_frac") and cfg.has(mk):
				v = maxf(v, float(cfg[mk]) / hpx)
			life_mat.set_shader_parameter(k, v)
	img.material = life_mat


func _life_step(delta: float) -> void:
	_life_t += delta
	var b: Dictionary = StoryRunner.current_beat
	var want := 0.0
	if String(b.get("type", "")) == "line" and String(b.get("speaker", "")) == life_char:
		var vd := get_node_or_null("/root/VoiceDirector")
		want = 1.0 if vd == null or bool(vd.call("line_being_said", b)) else 0.0
	var tau := float(_life_cfg.get("talk_in_s" if want > life_talk else "talk_out_s", 0.4))
	life_talk = move_toward(life_talk, want, delta / maxf(tau, 0.01))
	life_mat.set_shader_parameter("talk", smoothstep(0.0, 1.0, life_talk))
	life_mat.set_shader_parameter("time_s", _life_t)


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
	if life_mat != null:
		_life_step(delta)
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
