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
## (Director 01.11, lines 61 and 68). With sheet clips (`compose.anim`) it plays them — see _setup_anim; a figure
## without them (Agata seated at the dinner: a one-frame sheet) breathes and sways a little, and moves its head with
## its own line while that line is being said — game/shaders/frame_figure.gdshader. Values game/data/frame_life.json,
## the layer's `life` {…} overrides them, `life: false` keeps it still.
const LIFE_PATH := "res://data/frame_life.json"   # not in data/actors: every file there is an actor sheet (run_tests «Loop seams»)
const LIFE_SHADER := preload("res://shaders/frame_figure.gdshader")
var life_mat: ShaderMaterial = null
var life_char: String = ""
var life_talk: float = 0.0       # 0..1 as shown (tests)
var _life_t: float = 0.0
var _life_cfg: Dictionary = {}


func _setup_life() -> void:
	var c = data.get("compose", {})
	var lf = data.get("life", true)
	if lf is bool and not lf:
		return
	# Director 02.11 вечер, № 25 («Тихон на последнем кадре двигался и говорил — почему убрали?»): a figure pasted from
	# a picture (compose src, not a sheet) — Tikhon at the dinner — breathes and moves his head with his words when the
	# layer's `life` names him: {"char", "feet", "height"} in canvas px (the sheet figures take these from compose)
	if c is Dictionary and String(c.get("char", "")) == "" and lf is Dictionary and String(lf.get("char", "")) != "":
		c = (c as Dictionary).duplicate()
		for k in ["char", "feet", "height"]:
			if lf.has(k):
				c[k] = lf[k]
	if not (c is Dictionary) or String(c.get("char", "")) == "" or not c.has("feet"):
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
	if c.has("anim") and _setup_anim(img, c):
		return
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
	if not anim.is_empty():
		_anim_step(delta, want)
		return
	var tau := float(_life_cfg.get("talk_in_s" if want > life_talk else "talk_out_s", 0.4))
	life_talk = move_toward(life_talk, want, delta / maxf(tau, 0.01))
	life_mat.set_shader_parameter("talk", smoothstep(0.0, 1.0, life_talk))
	life_mat.set_shader_parameter("time_s", _life_t)


## A frame figure with sheet clips (compose.anim, tools/make_frame_layers.py → <image>_anim.png + .json): the layer
## plays the figure's own motion instead of a still picture — the rest clip (listen / idle, to and fro) all the time,
## each figure from its own moment; while its own line is being said the talk clip (the gesture of the villagers'
## sheets: hands, head, mouth) dissolves in from its start and loops, and when the line is over it dissolves back.
## The still picture (`Image`, the rest clip's first frame) stays as the fallback and is hidden.
const ANIM_SHADER := preload("res://shaders/frame_anim.gdshader")
var anim: Dictionary = {}          # the atlas description (<image>_anim.json)
var anim_sprite: Sprite2D = null
var anim_rest_cell: int = -1       # shown cells (tests): the rest clip's and the talk clip's
var anim_talk_cell: int = -1
var _talk_t: float = 0.0
var _anim_phase: float = 0.0


func _setup_anim(img: Sprite2D, c: Dictionary) -> bool:
	var base := String(data.get("image", "")).get_basename()
	var mpath := base + "_anim.json"
	var apath := base + "_anim.png"
	if not FileAccess.file_exists(mpath) or not ResourceLoader.exists(apath):
		push_warning("StateLayer %s: compose.anim without its atlas (%s) — tools/make_frame_layers.py" % [name, apath])
		return false
	var meta = JSON.parse_string(FileAccess.get_file_as_string(mpath))
	if not (meta is Dictionary) or not (meta as Dictionary).has("clips") or not meta["clips"].has("rest"):
		return false
	anim = meta
	var cell := Vector2(float(anim["cell"][0]), float(anim["cell"][1]))
	var origin := Vector2(float(anim["origin"][0]), float(anim["origin"][1]))
	anim_sprite = Sprite2D.new()
	anim_sprite.name = "Anim"
	anim_sprite.texture = load(apath)
	anim_sprite.centered = false
	anim_sprite.region_enabled = true
	anim_sprite.region_rect = Rect2(Vector2.ZERO, cell)
	anim_sprite.scale = img.scale
	anim_sprite.position = img.position + origin * img.scale
	life_mat = ShaderMaterial.new()
	life_mat.shader = ANIM_SHADER
	life_mat.set_shader_parameter("atlas_px", Vector2(float(anim["size"][0]), float(anim["size"][1])))
	life_mat.set_shader_parameter("cell_px", cell)
	life_mat.set_shader_parameter("feet_px", Vector2(float(anim["feet"][0]), float(anim["feet"][1])))
	var hpx := maxf(float(anim.get("height", 300.0)), 1.0)
	life_mat.set_shader_parameter("height_px", hpx)
	_anim_phase = fposmod(float(hash(life_char + String(name))) * 0.618034, 1.0)
	life_mat.set_shader_parameter("phase", _anim_phase * TAU)
	life_mat.set_shader_parameter("talk_frac", maxf(float(_life_cfg.get("talk_frac", 0.008)), float(_life_cfg.get("talk_min_px", 0.0)) / hpx))
	anim_sprite.material = life_mat
	add_child(anim_sprite)
	img.visible = false
	_anim_step(0.0, 0.0)
	return true


## Cell `i` of the atlas: its top-left, px.
func _anim_cell_px(i: int) -> Vector2:
	var cols := maxi(int(anim.get("cols", 1)), 1)
	var g := float(anim.get("gap", 0))
	var row := floori(float(i) / float(cols))
	return Vector2(float(i % cols) * (float(anim["cell"][0]) + g), float(row) * (float(anim["cell"][1]) + g))


## Position `pos` (frames, fractional) in a clip → [cell, next cell, share of the next].
func _anim_clip_at(cl: Dictionary, pos: float) -> Array:
	var n := maxi(int(cl.get("frames", 1)), 1)
	var first := int(cl.get("first", 0))
	if n == 1:
		return [first, first, 0.0]
	var a: int
	var b: int
	var f: float
	if String(cl.get("playback", "loop")) == "pingpong":
		var per := float(2 * (n - 1))
		var m := fposmod(pos, per)
		if m < float(n - 1):
			a = int(floor(m))
			b = a + 1
			f = m - floor(m)
		else:
			var back := m - float(n - 1)
			a = n - 1 - int(floor(back))
			b = a - 1
			f = back - floor(back)
	else:
		var m2 := fposmod(pos, float(n))
		a = int(floor(m2))
		b = (a + 1) % n
		f = m2 - floor(m2)
	if not bool(cl.get("blend", false)):
		f = 0.0
		b = a
	else:
		f = smoothstep(float(_life_cfg.get("anim_blend_hold", 0.5)), 1.0, f)
	return [first + a, first + b, f]


func _anim_step(delta: float, want: float) -> void:
	var clips: Dictionary = anim["clips"]
	var rest: Dictionary = clips["rest"]
	var r := _anim_clip_at(rest, (_life_t + _anim_phase * 9.7) * float(rest.get("fps", 12.0)))
	anim_rest_cell = int(r[0])
	life_mat.set_shader_parameter("rest_a", _anim_cell_px(int(r[0])))
	life_mat.set_shader_parameter("rest_b", _anim_cell_px(int(r[1])))
	life_mat.set_shader_parameter("rest_mix", float(r[2]))
	life_mat.set_shader_parameter("time_s", _life_t)
	var fade_in := float(_life_cfg.get("anim_talk_in_s", 0.25))
	var fade_out := float(_life_cfg.get("anim_talk_out_s", 0.4))
	if not clips.has("talk"):
		# no gesture in the sheet: the head moves with the words (soft warp), the rest clip goes on
		life_talk = move_toward(life_talk, want, delta / maxf(fade_in if want > life_talk else fade_out, 0.01))
		life_mat.set_shader_parameter("warp_talk", smoothstep(0.0, 1.0, life_talk))
		life_mat.set_shader_parameter("talk_w", 0.0)
		anim_talk_cell = -1
		return
	if want > 0.0 and life_talk <= 0.0:
		_talk_t = 0.0     # a new line: the gesture starts from its beginning (the sheet's talk starts in the stance)
	life_talk = move_toward(life_talk, want, delta / maxf(fade_in if want > life_talk else fade_out, 0.01))
	if life_talk > 0.0:
		_talk_t += delta
	var talk: Dictionary = clips["talk"]
	var t := _anim_clip_at(talk, _talk_t * float(talk.get("fps", 9.0)))
	anim_talk_cell = int(t[0]) if life_talk > 0.0 else -1
	life_mat.set_shader_parameter("talk_a", _anim_cell_px(int(t[0])))
	life_mat.set_shader_parameter("talk_b", _anim_cell_px(int(t[1])))
	life_mat.set_shader_parameter("talk_mix", float(t[2]))
	life_mat.set_shader_parameter("talk_w", smoothstep(0.0, 1.0, life_talk))
	life_mat.set_shader_parameter("warp_talk", 0.0)


## The cell the figure shows now (tests): the talk clip's once it has mostly dissolved in, else the rest clip's;
## -1 — the layer is a still picture.
func anim_cell() -> int:
	if anim.is_empty():
		return -1
	return anim_talk_cell if life_talk >= 0.5 and anim_talk_cell >= 0 else anim_rest_cell


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
