extends MechanicPanel
## Бечёвка с Митей — рыбалка с натяжением (партия J, часть G; Директор 25.10: «бечёвка с Митей как рыбалка с
## натяжением», 29.10: «на конце — рыба»). The river at the Olkhovka pier (a part of R3's painting, `art`), in the
## game's carved frame; a float on the water, the string from the rod above.
##   wait   — the float rests and bobs; a while (`wait_s`) and a nibble or two (small dips) — don't strike yet;
##   bite   — the float goes under: strike now (a click on the picture or Space) within `bite_s`; too early — the fish
##            only tried it (texts.early), too late — it is gone (texts.late); both — wait again;
##   fight  — hold the mouse button or Space to pull: the string's tension rises; let go — it falls; the perch runs
##            now and then (FishingLogic, data `fight`). In the green (wider with «Облегчить») it comes nearer; held too
##            hard too long the string snaps (texts.snap); slack — it swims off and is gone (texts.escaped);
##   caught — the perch shown (drawn by the engine), Mitya's word (texts.caught), event "caught"; «Ещё»; «Хватит» is the
##            close-up's own button, bottom right (spec `close_label`, `close_event` "done" — his word).
## Everything is data: art (image, variants by time of day), wait_s, bite_s, fight (FishingLogic), gauge, far, texts, events.
## Polish (J, ночь 30.10, «как в прошлых мини-играх»): the rod comes in from her hands at the lower left and bends to
## the fish as the string tightens; the float plops at a nibble and goes under with a splash (sounds — SynthSfx);
## the string creaks taut, snaps with a crack; the tension bar in the carved frame — red at the top, the green band,
## the gold leaf of the string, a little fish climbing the gauge beside it as it comes in, the bar shaking near the
## snap and the green pulsing while the string hangs slack; the perches caught lie in a row in the corner;
## «Облегчить» under the bar (a wider green). The picture sits higher so the hint and «Ещё» stay above the text box.
## In the room (утренняя страница 01.11, Директор: «перенести на мостки», вариант А): spec `in_room` — no frame, no
## picture, no backdrop: the float sits on the water of the room itself (`float`, screen coordinates), the rod comes
## from Agata's hands where she stands (RoomManager.player), Mitya's own rod from his (npc_mitya) to `mitya.float`;
## `simple` — no fight: the float goes under → a strike → the perch at once (too early / too late as before).
## Вечер 01.11 (Директор, 21:59: «вернуть натяжение и шкалу сразу красивой сделать… окунь вытягивался независимо от
## натяжения; а в обычной рыбалке смысл другой: он уплывает, если не тянуть»): the fight is back and is the default in
## R3 (`simple` false). Its logic — FishingLogic (the perch runs and takes line; slack — it swims away and works the
## hook loose, too hard — the string snaps; only the string held right brings it in). Its gauge — a carved plaque on
## the water (`gauge`, screen [x, y, w, h] of its field): the tension scale painted in three zones with their words
## («уйдёт» — river-slate, «держи» — green, «лопнет» — amber to red), the brass needle with the gold leaf, the risk
## of losing the fish filling its zone; under it the way to the jetty — the water, the jetty's posts, the painted
## perch at its distance with the metres. In the room the perch is seen under the water where it is (`far` — the
## farthest it gets, screen), dragging the float, a wake on its runs.

const FLOAT_RED := Color(0.82, 0.16, 0.1)
const FLOAT_WHITE := Color(0.95, 0.93, 0.88)
const LINE := Color(0.88, 0.84, 0.74, 0.85)
## Партия 14 (01.11, по замечанию Директора стр. 59): the perch and the floats are painted — sprites instead of the shapes
## drawn by the engine. Paths and anchors may come from the data (`sprites`); the README of партия 14 gives these:
## floats on a 300 px tall sheet with the waterline at y 200 (anchor — the contact ring), the tilted one drawn ×1.75 the
## upright scale to keep one length; the caught perch 600 px long with its line from the mouth up to y 0 at x 77.
const SPRITES := {
	# Директор 08.11, 19:47 («пожирнее немного, чтобы заметнее») 0.227 → 0.3; 20:14 («ещё увеличить немного») → 0.36
	# (9 × 60 px → 14 × 96), наклонный тоже; красный кончик ярче и длиннее — tools/retouch/fishing_float_tip.py
	"float": {"image": "res://assets/mechanics/fishing/float_on_water.png", "anchor": [60, 200], "scale": 0.36},
	"float_tilted": {"image": "res://assets/mechanics/fishing/float_tilted.png", "anchor": [100, 200], "scale": 0.64},
	# Director 02.11 вечер, № 14 («окуня поменьше сделать и вниз практически висящим»): ×0.7 (0.283 → 0.2) and turned
	# 72° about the line's top — head up at the hook, tail hanging down (was level, as if swimming in the air)
	"perch_caught": {"image": "res://assets/mechanics/fishing/perch_caught.png", "anchor": [77, 0], "scale": 0.2, "rot_deg": 72.0},
	"perch_lying": {"image": "res://assets/mechanics/fishing/perch_lying.png", "anchor": [240, 100], "scale": 0.136},
}
const WATERLINE := 200.0
## Директор 01.11, стр. 59 («удочка… должна как бы из руки Агаты идти»; «хватит» и «ещё» разнесены): the rod's butt in
## her hand (the 3D figure's hand bone, `hand_bone`), the rod held up at `rod_deg` above the level towards the water,
## `rod_len` × her height; «Ещё» beside «Хватит» at the bottom right.
const ROD_DEG := 38.0
const ROD_LEN := 1.25

var phase: String = "wait"       # wait | bite | fight | caught | lost
var phase_t: float = 0.0
var next_event: float = 3.0
var nibbles: int = 0
var _nibbles_to: int = 1
var _dip: float = 0.0
var tension: float = 0.0
var progress: float = 0.0
var pulling: bool = false
var fight: FishingLogic = null   # the fight (FishingLogic) while phase is "fight"; the last one after it
var last_end: String = ""        # how the last fight ended: landed | escaped | snapped (tests)
var fish_x: float = 0.0          # the perch's sideways swing in the fight (-1 … 1)
var _fish_at: Vector2 = Vector2.ZERO   # where the perch is under the water now (screen; eased after the logic's distance)
var _face: float = 1.0           # +1 — it heads in (to the left, to the stones), −1 — away
var _gauge: Rect2 = Rect2(1430, 818, 440, 144)
var _far: Vector2 = Vector2(1760, 730)
var caught: int = 0
var lost: int = 0
var green: Vector2 = Vector2(0.35, 0.75)
var _rng := RandomNumberGenerator.new()
var _pic: Rect2 = Rect2(260, 130, 1400, 788)
var _float0: Vector2 = Vector2(980, 560)
var _draw: Control = null
var hint: Label = null
var again_btn: Button = null
var slow_check: CheckButton = null
var rod_seen: Dictionary = {}       # where the rod was drawn last (in the room): hand bone, grip, butt, tip (tests)
var _taut_snd: float = 0.0       # time to the next creak of the taut string
var in_room: bool = false
var simple: bool = false
var _mitya_float: Vector2 = Vector2.ZERO
## Director 10.11, 22:46 («когда Агата поймала рыбу, то можно убрать удочку у Мити»; 23:26 «да, убрать его удочку после
## того, как она вылавливает рыбу»): the perch hung on her line right under Mitya's rod, as if he had caught it. With
## `mitya.rod_off_after_catch` his rod and float fade out at her first catch (he puts his rod down to look at her
## perch) and stay away for «Ещё». Drawn on a layer of its own (MityaRod, under the water layer) to fade as one.
const MITYA_ROD_FADE_S := 0.6
var mitya_rod_k: float = 1.0        # 1 — Mitya's rod seen, 0 — put away
var _mitya_layer: Control = null
var _tex: Dictionary = {}           # sprite id -> {tex, anchor, scale}


func build() -> void:
	_rng.seed = int(spec.get("seed", Time.get_ticks_usec()))
	eased()
	in_room = bool(spec.get("in_room", false))
	simple = bool(spec.get("simple", false))
	var art: Dictionary = spec.get("art", {})
	var pr: Array = spec.get("picture", [260, 130, 1400, 788])
	_pic = Rect2(float(pr[0]), float(pr[1]), float(pr[2]), float(pr[3]))
	var fp: Array = spec.get("float", [980, 560])
	_float0 = Vector2(float(fp[0]), float(fp[1]))
	var mf: Array = spec.get("mitya", {}).get("float", [])
	_mitya_float = Vector2(float(mf[0]), float(mf[1])) if mf.size() == 2 else Vector2.ZERO
	var gr: Array = spec.get("gauge", [1430, 818, 440, 144] if in_room else [_pic.end.x - 470.0, _pic.end.y - 180.0, 440, 150])
	_gauge = Rect2(float(gr[0]), float(gr[1]), float(gr[2]), float(gr[3]))
	var fr: Array = spec.get("far", [_float0.x + 450.0, _float0.y + 60.0])
	_far = Vector2(float(fr[0]), float(fr[1]))
	var sp: Dictionary = spec.get("sprites", {})
	for id in SPRITES.keys():
		var d: Dictionary = SPRITES[id].merged(sp.get(id, {}), true)
		var path := String(d["image"])
		if ResourceLoader.exists(path):
			_tex[id] = {"tex": load(path), "anchor": Vector2(float(d["anchor"][0]), float(d["anchor"][1])), "scale": float(d["scale"]), "rot": deg_to_rad(float(d.get("rot_deg", 0.0)))}
	if not in_room:
		var frame := Control.new()
		frame.name = "Frame"
		frame.size = Vector2(1920, 1080)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.draw.connect(func(): CarvedFrame.draw_frame(frame, _pic, 16.0))
		add_child(frame)
		# the river as it is now: `image` (the day), or the first of `variants` whose `if_any` flags are set (dusk, night)
		var img := String(art.get("image", ""))
		for v in art.get("variants", []):
			var hit := false
			for f in v.get("if_any", []):
				hit = hit or flag(String(f))
			if hit:
				img = String(v.get("image", img))
				break
		if img != "":
			var r: Array = art.get("region", [880, 420, 792, 446])
			var tr := crop(img, r, _pic.position, _pic.size.x / float(r[2]), self)
			tr.name = "River"
			tr.size = _pic.size
	if in_room and _mitya_float != Vector2.ZERO:
		_mitya_layer = Control.new()
		_mitya_layer.name = "MityaRod"
		_mitya_layer.size = Vector2(1920, 1080)
		_mitya_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mitya_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_mitya_layer.draw.connect(_on_draw_mitya)
		add_child(_mitya_layer)
	_draw = Control.new()
	_draw.name = "Water"
	_draw.size = Vector2(1920, 1080)
	_draw.mouse_filter = Control.MOUSE_FILTER_STOP
	_draw.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # the painted perch at a fifth of its size
	_draw.draw.connect(_on_draw)
	_draw.gui_input.connect(_on_input)
	add_child(_draw)
	if in_room:
		# the hint under the title at the upper left (the text box is at the bottom, the water at the right)
		hint = label(text("wait"), Vector2(40, 160), 760, &"CloseupLabel")
		# стр. 59: «Ещё» right beside «Хватит» (MechanicView's own button, 200 × 56 at (1680, 990))
		var ag: Array = spec.get("again_at", [1460, 990])
		again_btn = _button(text("again"), Vector2(float(ag[0]), float(ag[1])), "Again")
		var pl: Node = RoomManager.player
		if pl != null and is_instance_valid(pl) and pl.has_method("face_screen_dir"):
			pl.call("face_screen_dir", Vector2(signf(_float0.x - (pl as Node2D).position.x), 0.0))   # she faces her float
	else:
		hint = label(text("wait"), Vector2(_pic.position.x, _pic.end.y + 26.0), _pic.size.x, &"CloseupLabel")
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		again_btn = _button(text("again"), Vector2(_pic.get_center().x - 100.0, _pic.end.y + 66.0), "Again")
	again_btn.pressed.connect(_restart)
	if not simple:
		var ea: Array = spec.get("easy_at", [40, 262] if in_room else [_pic.end.x - 240.0, _pic.end.y + 20.0])
		slow_check = easy_toggle(Vector2(float(ea[0]), float(ea[1])))
	_restart()


## «Облегчить мини-игры» (G3, TimingBar.slow): a wider green, the perch weaker and slower, the risks slower to fill —
## FishingLogic.configure; toggled mid-fight the fight goes on as it is.
func eased() -> void:
	var easy := TimingBar.slow_k() > 1.0
	if fight != null:
		fight.configure(easy)
		green = fight.green
		return
	green = FishingLogic.new(spec.get("fight", {}), easy).green


## The fight's logic for a new strike, from the data (`fight`), eased if «Облегчить» is on.
func new_fight() -> FishingLogic:
	var l := FishingLogic.new(spec.get("fight", {}), TimingBar.slow_k() > 1.0, _rng.randi() & 0x7fffffff)
	l.event.connect(_on_fight_event)
	return l


func _button(t: String, at: Vector2, node_name: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = t
	b.theme = UiTheme.get_theme()
	b.position = at
	b.size = Vector2(200, 54)
	b.focus_mode = Control.FOCUS_NONE
	b.visible = false
	add_child(b)
	return b


func _restart() -> void:
	again_btn.visible = false
	_to_wait()


func _to_wait() -> void:
	phase = "wait"
	phase_t = 0.0
	nibbles = 0
	tension = 0.0
	progress = 0.0
	pulling = false
	var w: Array = spec.get("wait_s", [2.5, 5.5])
	next_event = _rng.randf_range(float(w[0]), float(w[1]))
	_nibbles_to = _rng.randi_range(1, 2)
	_dip = 0.0
	hint.text = text("wait")


func tick(delta: float) -> void:
	# «Ещё» waits for Mitya's word to be read (the text box would cover it)
	_sync_again()
	if _mitya_layer != null:
		var off := caught > 0 and bool(spec.get("mitya", {}).get("rod_off_after_catch", false))
		mitya_rod_k = move_toward(mitya_rod_k, 0.0 if off else 1.0, delta / MITYA_ROD_FADE_S)
		_mitya_layer.modulate.a = mitya_rod_k
		_mitya_layer.visible = mitya_rod_k > 0.0
		_mitya_layer.queue_redraw()
	if dialogue_up():
		_draw.queue_redraw()
		return
	phase_t += delta
	_dip = maxf(_dip - delta, 0.0)
	match phase:
		"wait":
			if phase_t >= next_event:
				if nibbles < _nibbles_to:
					nibbles += 1
					_dip = 0.45
					sound("plop")
					next_event = phase_t + _rng.randf_range(0.9, 1.8)
				else:
					phase = "bite"
					phase_t = 0.0
					sound("float_dive")
		"bite":
			if phase_t > float(spec.get("bite_s", 0.9)):
				lost += 1
				say("late")
				_to_wait()
		"fight":
			_fight(delta)
	_draw.queue_redraw()


func _fight(delta: float) -> void:
	fight.pulling = pulling
	fight.step(delta)
	if phase != "fight":   # it ended in this step (landed / escaped / snapped — _on_fight_event)
		return
	tension = fight.tension
	progress = clampf(fight.progress(), 0.0, 1.0)
	# where the perch is: out on the water by its distance (the float's place by the stones at 0, `far` at max_m)
	var to := _float0.lerp(_far, clampf(fight.dist / maxf(fight.max_m, 0.01), 0.0, 1.0))
	fish_x = sin(clock * (2.6 if fight.running() else 1.1)) * (1.0 if fight.running() else 0.45)
	to += Vector2(-0.35, 1.0).normalized() * fish_x * 22.0
	_fish_at = _fish_at.lerp(to, clampf(delta * 3.0, 0.0, 1.0))
	if absf(fight.away) > 0.05:
		_face = -1.0 if fight.away > 0.0 else 1.0
	_taut_snd -= delta
	if pulling and tension > green.x and _taut_snd <= 0.0:
		sound("line_taut")
		_taut_snd = lerpf(0.75, 0.3, tension)


func _on_fight_event(ev: String) -> void:
	match ev:
		"run":
			sound("plop")
		"landed":
			last_end = ev
			_catch()
		"escaped":
			last_end = ev
			lost += 1
			say("escaped")
			_to_wait()
		"snapped":
			last_end = ev
			lost += 1
			sound("line_snap")
			say("snap")
			_to_wait()


func _catch() -> void:
	phase = "caught"
	phase_t = 0.0
	caught += 1
	pulling = false
	sound("water_slap")
	hint.text = ""
	event("caught")
	# 02.11 вечер, № 15: the words of a catch alternate — Mitya's on the odd ones, Agata's on the even (texts.caught_alt)
	say("caught_alt" if caught % 2 == 0 and spec.get("texts", {}).has("caught_alt") else "caught")


## A strike or a pull: a press (mouse button / Space) — `down` true, a release — false.
func press(down: bool) -> void:
	if not down:
		pulling = false
		return
	match phase:
		"wait":
			if nibbles > 0:
				say("early")
				_to_wait()
		"bite":
			if simple:
				_catch()
				return
			phase = "fight"
			phase_t = 0.0
			fight = new_fight()
			green = fight.green
			tension = fight.tension
			progress = 0.0
			fish_x = 0.0
			_fish_at = _float0
			_face = -1.0
			pulling = true
			hint.text = text("fight")
		"fight":
			pulling = true


func _on_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_draw.accept_event()
		press(ev.pressed)


func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and not ev.echo and (ev.keycode == KEY_SPACE or ev.physical_keycode == KEY_SPACE):
		get_viewport().set_input_as_handled()
		press(ev.pressed)


# --- Drawing ------------------------------------------------------------------------------------

## The water's surface at the float (it rises and falls with the swell; the float may be under it).
func _float_wl() -> Vector2:
	return Vector2(_float_pos().x, _float0.y + sin(clock * 2.1) * 2.5)


func _float_pos() -> Vector2:
	var p := _float0 + Vector2(0.0, sin(clock * 2.1) * 2.5)
	match phase:
		"wait":
			if _dip > 0.0:
				p.y += 7.0 * sin((0.45 - _dip) / 0.45 * PI)
		"bite":
			p.y += 18.0 * minf(phase_t / 0.15, 1.0)
		"fight":
			p = _fish_at + Vector2(0.0, sin(clock * 2.1) * 2.5)
		"caught":
			# the painted perch hangs clear of the water — hanging down it is longer than it was wide (600 × 0.2 ≈ 120 px)
			p += Vector2(0.0, -40.0 if not _tex.has("perch_caught") else -150.0)
	return p


## Mitya's rod and float (their own layer, under the water layer, faded by mitya_rod_k).
func _on_draw_mitya() -> void:
	_rod(_mitya_layer, _hands("npc_mitya", 1.1), _mitya_float, 0.0, 0.1)
	_float_shape(_mitya_layer, _mitya_float + Vector2(0.0, sin(clock * 1.7 + 1.0) * 2.0), false)


func _on_draw() -> void:
	var c := _draw
	var fp := _float_pos()
	var taut := tension if phase == "fight" else 0.1
	# the rod: from her hands below the lower left corner up over the water; it bends to the fish as the string tightens
	var butt := Vector2(_pic.position.x + 64.0, _pic.end.y - 3.0)   # it comes in at the frame's lower edge
	var tip0 := Vector2(_pic.position.x + _pic.size.x * 0.24, _pic.position.y + _pic.size.y * 0.16)
	if in_room:
		var hand := _hands("", 1.0)
		tip0 = rod_tip(hand, _float0, _figure_h(""))
		# Director 02.11 вечер, № 16 («конец удочки должен быть ровно в руке; по слоям — под рукой, но над телом»): the hand
		# bone is the wrist — the fingers close a palm lower (`grip_drop_rel` × her height, as the lantern's bail); the rod
		# begins at the fist's far side (`grip_out_rel`), so the fist stays in front of it and nothing sticks out behind
		var fh := _figure_h("")
		var grip := hand + Vector2(0.0, fh * float(spec.get("grip_drop_rel", 0.05)))
		tip0 = rod_tip(grip, _float0, fh)
		butt = grip + (tip0 - grip).normalized() * fh * float(spec.get("grip_out_rel", 0.022))
		rod_seen = {"hand": hand, "grip": grip, "butt": butt, "tip": tip0}
	var bend := (taut if phase == "fight" else 0.0) + (0.25 if phase == "bite" else 0.0)
	var tip := tip0 + (fp - tip0).normalized() * 70.0 * bend + Vector2(0.0, sin(clock * 1.3) * 2.0)
	_rod(c, butt, fp, bend, taut, tip)
	if phase != "caught":
		# rings on the water round the float
		for k in 3:
			var age := fposmod(clock * (0.6 if phase != "fight" else 1.1) + k / 3.0, 1.0)
			var big := 1.0 + (2.5 if phase == "bite" else 1.4 if phase == "fight" else 0.0)
			var ring_at := fp if phase == "fight" else _float_wl()
			c.draw_set_transform(ring_at + (Vector2(0, 1) if _tex.has("float") else Vector2(0, 10)), 0.0, Vector2(1.0, 0.32))
			c.draw_arc(Vector2.ZERO, 14.0 + age * 40.0 * big, 0.0, TAU, 40, Color(1, 1, 1, 0.35 * (1.0 - age)), 2.0, true)
			c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var under := phase == "bite" or phase == "fight"
		if phase == "bite" and phase_t < 0.35:   # the splash as it goes under
			var k := phase_t / 0.35
			for d in 6:
				var ang := -PI * (0.15 + 0.7 * float(d) / 5.0)
				var dp := fp + Vector2(cos(ang), sin(ang)) * (10.0 + 34.0 * k) + Vector2(0.0, 60.0 * k * k)
				c.draw_circle(dp, 3.0 * (1.0 - k) + 1.0, Color(1, 1, 1, 0.75 * (1.0 - k)))
		var tilt := (phase == "wait" and _dip > 0.0) or phase == "bite"
		if phase == "fight":
			_fight_water(c, fp)
		else:
			_float_shape(c, _float_wl(), under and phase_t >= 0.15, tilt, fp.y - _float_wl().y)
	else:
		_fish(c, fp)
	if phase == "fight":
		draw_gauge(c)
	# the perches caught so far, in a row in the upper corner of the picture (in the room — under the hint and «Облегчить»)
	for k in caught:
		var at := Vector2(80.0 + 70.0 * k, 345.0) if in_room else Vector2(_pic.end.x - 60.0 - 70.0 * k, _pic.position.y + 40.0)
		_perch_small(c, at, 60.0)


## The float: the painted one (партия 14) — upright at rest, tilted at a nibble and as it goes under (`sink` px down,
## the part under the waterline dimmed); without the sprites — the old white-over-red shape.
func _float_shape(c: CanvasItem, fp: Vector2, under: bool, tilted: bool = false, sink: float = 0.0) -> void:
	var id := "float_tilted" if tilted and _tex.has("float_tilted") else "float"
	if _tex.has(id):
		_float_sprite(c, _tex[id], fp, 0.0 if not under else maxf(sink, 1000.0))
		if under:
			c.draw_circle(fp + Vector2(0, 8), 5.0, Color(FLOAT_RED, 0.35))   # seen under the water
		return
	if not under:
		c.draw_line(fp + Vector2(0, -24), fp + Vector2(0, -8), Color(0.2, 0.15, 0.1), 2.0, true)
		c.draw_set_transform(fp, 0.0, Vector2(1.0, 1.6))
		c.draw_circle(Vector2(0, -2), 9.0, FLOAT_RED)
		c.draw_circle(Vector2(0, -6), 6.0, FLOAT_WHITE)
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		c.draw_circle(fp + Vector2(0, 8), 5.0, Color(FLOAT_RED, 0.45))   # seen under the water


## A float sprite with its contact ring at `wl` (the waterline on screen): above the water as painted, under it dimmed;
## `sink` — screen px the float has gone down (a part of it passes under the waterline).
func _float_sprite(c: CanvasItem, t: Dictionary, wl: Vector2, sink: float) -> void:
	var tex: Texture2D = t["tex"]
	var k: float = t["scale"]
	var an: Vector2 = t["anchor"]
	var ts := tex.get_size()
	var cut := clampf(WATERLINE - sink / k, 0.0, ts.y)    # texture rows above this stay above the water
	var top := wl + (Vector2(0.0, -WATERLINE) - Vector2(an.x, 0.0)) * k + Vector2(0.0, sink)
	if cut > 0.0:
		c.draw_texture_rect_region(tex, Rect2(top, Vector2(ts.x, cut) * k), Rect2(0, 0, ts.x, cut))
	if cut < ts.y:
		var under_h := minf(ts.y - cut, 60.0)              # the painted part under the water, a little of it
		c.draw_texture_rect_region(tex, Rect2(Vector2(top.x, wl.y), Vector2(ts.x, under_h) * k), Rect2(0, cut, ts.x, under_h), Color(1, 1, 1, 0.45))


## The rod from `butt` (the hands) bending towards `fp` (the float), and the string from its tip to the float.
func _rod(c: CanvasItem, butt: Vector2, fp: Vector2, bend: float, taut: float, tip: Vector2 = Vector2.ZERO) -> void:
	var tip0 := Vector2(_pic.position.x + _pic.size.x * 0.24, _pic.position.y + _pic.size.y * 0.16)
	if in_room:
		tip0 = rod_tip(butt, fp, _figure_h("npc_mitya" if fp == _mitya_float else ""))
	if tip == Vector2.ZERO:
		tip = tip0 + Vector2(0.0, sin(clock * 1.3) * 2.0)
	var ctrl := butt.lerp(tip0, 0.55) + (fp - tip0).normalized() * 40.0 * bend
	var rod := PackedVector2Array()
	for i in 17:
		var tt := float(i) / 16.0
		rod.append(butt.lerp(ctrl, tt).lerp(ctrl.lerp(tip, tt), tt))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var k := 0.55 if in_room else 1.0   # thinner in the room: the figures are smaller than in the close-up
	for i in rod.size() - 1:
		var w := lerpf(11.0, 2.5, float(i) / (rod.size() - 1)) * k
		c.draw_line(rod[i] + Vector2(2, 3), rod[i + 1] + Vector2(2, 3), Color(0, 0, 0, 0.3), w + 1.0, true)
		c.draw_line(rod[i], rod[i + 1], Color(0.33, 0.22, 0.12), w, true)
		c.draw_line(rod[i] + Vector2(-w * 0.2, -w * 0.25), rod[i + 1] + Vector2(-w * 0.2, -w * 0.25), Color(0.6, 0.45, 0.28, 0.6), maxf(w * 0.25, 1.0), true)
	# the string: sags while slack, straight when taut
	var mid := tip.lerp(fp, 0.5) + Vector2(0.0, 60.0 * (1.0 - taut) * k)
	if phase == "fight" and fp != _mitya_float and fight != null and fight.zone() == "over":
		mid += Vector2(sin(clock * 83.0), cos(clock * 71.0)) * 2.5   # the string hums, held too hard
	var pts := PackedVector2Array()
	for i in 21:
		var t := float(i) / 20.0
		pts.append(tip.lerp(mid, t).lerp(mid.lerp(fp, t), t))
	c.draw_polyline(pts, Color(0, 0, 0, 0.35), 3.0 * k, true)
	c.draw_polyline(pts, LINE, maxf(1.6 * k, 1.0), true)


## Where a figure's hands are on screen: Agata's — her 3D figure's hand bone as the camera sees it (Директор 01.11,
## стр. 59: the rod comes out of her hand); else (sprites, an NPC) at its feet plus `up` × 0.55 of its height
## (345 px × the depth scale) and a little forward (towards the water, to the right).
func _hands(who: String, up: float) -> Vector2:
	var room: Node = RoomManager.current_room
	var n: Node2D = RoomManager.player if who == "" else (room.get_node_or_null(who) as Node2D if room != null else null)
	if n == null or not is_instance_valid(n):
		return Vector2(_pic.position.x + 64.0, _pic.end.y - 3.0)
	if who == "":
		var hb := hand_bone_screen(n, String(spec.get("hand_bone", "RightHand")))
		if hb != Vector2.INF:
			return hb
	var h := _figure_h(who) * up
	var fwd := signf(_float0.x - n.position.x) if who == "" else 1.0
	return n.position + Vector2(h * 0.18 * (fwd if fwd != 0.0 else 1.0), -h * 0.55)


## A figure's height on screen (345 px × the room's depth scale where it stands).
func _figure_h(who: String) -> float:
	var room: Node = RoomManager.current_room
	var n: Node2D = RoomManager.player if who == "" else (room.get_node_or_null(who) as Node2D if room != null else null)
	var sc := 0.5
	if n != null and is_instance_valid(n) and room != null and room.has_method("depth_scale_at"):
		sc = float(room.call("depth_scale_at", n.position))
	return 345.0 * sc


## The player's hand bone on screen (her live 3D frame: Actor3D.bone_frame_px → the Body3D sprite), Vector2.INF when
## she is drawn from sheets or the bone is missing.
static func hand_bone_screen(pl: Node, bone: String) -> Vector2:
	var v3 = pl.get("view3d")
	var b3 = pl.get("body3d")
	if v3 == null or b3 == null or not is_instance_valid(v3) or not is_instance_valid(b3) or not (b3 as Sprite2D).is_visible_in_tree():
		return Vector2.INF
	var px: Vector2 = v3.call("bone_frame_px", bone)
	if px == Vector2.INF:
		return Vector2.INF
	var spr := b3 as Sprite2D
	return spr.get_global_transform_with_canvas() * (px + spr.offset)


## The rod held as an angler holds it: from the hand up at `rod_deg` above the level, towards the float's side,
## `rod_len` × the figure's height long.
func rod_tip(butt: Vector2, float_at: Vector2, fig_h: float) -> Vector2:
	var side := signf(float_at.x - butt.x)
	if side == 0.0:
		side = 1.0
	var a := deg_to_rad(float(spec.get("rod_deg", ROD_DEG)))
	return butt + Vector2(cos(a) * side, -sin(a)) * fig_h * float(spec.get("rod_len", ROD_LEN))


## The fight on the water: the perch under the surface where it is (dim, its head to the stones while it comes in, away
## on a run), a wake when it runs; the float dragged after it, pulled under the more the string is held.
func _fight_water(c: CanvasItem, fp: Vector2) -> void:
	var running := fight != null and fight.running()
	var fish_at := fp + Vector2(46.0, 16.0)   # a body's length past the float, under the water
	if running:
		# the wake: a V from its head along the way it goes
		var dir := Vector2(-_face, 0.0)
		for sgn in [-1.0, 1.0]:
			var pts := PackedVector2Array()
			for i in 9:
				var t := float(i) / 8.0
				var back := -dir * (8.0 + 70.0 * t)
				pts.append(fish_at + Vector2(back.x, -14.0 + sgn * 26.0 * t * 0.35) + Vector2(0.0, sin(clock * 9.0 + t * 6.0) * 1.5))
			c.draw_polyline(pts, Color(1, 1, 1, 0.45), 2.0, true)
	if _tex.has("perch_lying"):
		var t: Dictionary = _tex["perch_lying"]
		var k := 78.0 / 440.0
		var wig := sin(clock * (15.0 if running else 6.0)) * (0.09 if running else 0.04)
		c.draw_set_transform(fish_at, wig, Vector2(k * _face, k))
		c.draw_texture(t["tex"], -(t["anchor"] as Vector2), Color(0.22, 0.34, 0.38, 0.42))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _tex.has("float_tilted"):
		_float_sprite(c, _tex["float_tilted"], fp, 5.0 + 14.0 * tension)
	else:
		_float_shape(c, fp, true)


const SLATE_DEEP := Color(0.1, 0.19, 0.24)
const SLATE := Color(0.3, 0.44, 0.48)
const RED_DEEP := Color(0.42, 0.07, 0.04)


## A word of the gauge: `texts.<key>` of the spec, else the game's own (@mech.fish.<key>).
func _word(key: String) -> String:
	if spec.get("texts", {}).has(key):
		return text(key)
	return StoryData.text("@mech.fish." + key)


## The tension scale's field inside the gauge (screen).
func scale_rect() -> Rect2:
	return Rect2(_gauge.position + Vector2(18.0, 16.0), Vector2(_gauge.size.x - 36.0, 42.0))


## The way to the jetty inside the gauge (screen).
func way_rect() -> Rect2:
	return Rect2(_gauge.position + Vector2(18.0, _gauge.size.y - 54.0), Vector2(_gauge.size.x - 36.0, 38.0))


## The colour painted at tension `v`: river-slate where the string hangs (the perch leaves), the green where it is held
## right (brightest in its middle), amber to deep red where it is held too hard.
func zone_color(v: float) -> Color:
	var g := fight.green if fight != null else green
	if v < g.x:
		return SLATE_DEEP.lerp(SLATE, pow(v / maxf(g.x, 0.01), 1.3))
	if v <= g.y:
		var mid := (g.x + g.y) * 0.5
		var t := 1.0 - absf(v - mid) / maxf((g.y - g.x) * 0.5, 0.01)
		return TimingBar.GREEN.darkened(0.12).lerp(TimingBar.GREEN.lightened(0.2), t)
	var u := (v - g.y) / maxf(1.0 - g.y, 0.01)
	return TimingBar.AMBER.lerp(TimingBar.RED, minf(u * 1.7, 1.0)).lerp(RED_DEEP, clampf((u - 0.6) / 0.4, 0.0, 1.0))


## The gauge in the fight: a carved plaque on the water — the tension scale in three painted zones with their words
## («уйдёт», «держи», «лопнет»), the brass needle with the gold leaf, the risk of losing the perch filling the zone the
## needle is in (from its outer end); under it the way to the jetty — the water, the jetty's posts, the metre notches,
## the hooking place (a red float), the painted perch at its distance with the metres over it.
func draw_gauge(c: CanvasItem) -> void:
	if fight == null:
		return
	var gr := _gauge
	CarvedFrame.draw_frame(c, gr, 14.0)
	# the plaque: dark wood with its grain
	c.draw_rect(gr, CarvedFrame.WOOD.darkened(0.25))
	for i in 9:
		var y := gr.position.y + 6.0 + (gr.size.y - 12.0) * i / 8.0
		var pts := PackedVector2Array()
		for j in 13:
			var x := gr.position.x + gr.size.x * j / 12.0
			pts.append(Vector2(x, y + sin(j * 0.9 + i * 1.7) * 2.2))
		c.draw_polyline(pts, Color(CarvedFrame.WOOD_LIGHT, 0.14), 1.0, true)
	var s := scale_rect()
	var gz := fight.green
	var xa := func(v: float) -> float: return s.position.x + s.size.x * clampf(v, 0.0, 1.0)
	var x_g0: float = xa.call(gz.x)
	var x_g1: float = xa.call(gz.y)
	c.draw_rect(s.grow(3.0), CarvedFrame.WOOD_DARK)
	var n := 96
	for i in n:
		var v0 := float(i) / n
		var v1 := float(i + 1) / n
		var x0: float = xa.call(v0)
		c.draw_rect(Rect2(x0, s.position.y, float(xa.call(v1)) - x0 + 0.6, s.size.y), zone_color((v0 + v1) * 0.5))
	# the slack: the river moving in it
	for r in 3:
		var y := s.position.y + s.size.y * (0.28 + 0.24 * r)
		var pts := PackedVector2Array()
		for j in 17:
			var x := s.position.x + (x_g0 - s.position.x) * j / 16.0
			pts.append(Vector2(x, y + sin(x * 0.11 + clock * 2.4 + r * 1.9) * 1.6))
		c.draw_polyline(pts, Color(0.8, 0.92, 0.98, 0.16), 1.2, true)
	# the risk of losing it fills its zone from the outer end, pulsing
	var pulse := 0.55 + 0.45 * sin(clock * 11.0)
	if fight.slack_risk > 0.01:
		var wr := (x_g0 - s.position.x) * fight.slack_risk
		c.draw_rect(Rect2(s.position.x, s.position.y, wr, s.size.y), Color(0.86, 0.95, 1.0, 0.24 + 0.2 * pulse))
		c.draw_rect(Rect2(s.position.x, s.position.y, x_g0 - s.position.x, s.size.y).grow(-1.5), Color(0.92, 0.98, 1.0, 0.35 + 0.6 * pulse * fight.slack_risk), false, 3.0)
	if fight.over_risk > 0.01:
		var wr := (s.end.x - x_g1) * fight.over_risk
		c.draw_rect(Rect2(s.end.x - wr, s.position.y, wr, s.size.y), Color(1.0, 0.88, 0.6, 0.24 + 0.24 * pulse))
		c.draw_rect(Rect2(x_g1, s.position.y, s.end.x - x_g1, s.size.y).grow(-1.5), Color(1.0, 0.85, 0.5, 0.35 + 0.6 * pulse * fight.over_risk), false, 3.0)
	CarvedFrame.shade(c, s)
	# the band's edges: brass ticks past the field
	for e in [x_g0, x_g1]:
		c.draw_line(Vector2(e, s.position.y - 5.0), Vector2(e, s.end.y + 5.0), Color(0, 0, 0, 0.5), 4.0)
		c.draw_line(Vector2(e, s.position.y - 5.0), Vector2(e, s.end.y + 5.0), TimingBar.BRASS, 2.0)
	# the words of the zones, painted on; the one the needle is in lit
	var font := UiTheme.font("body_bold")
	var z := fight.zone()
	var words := [["slack", s.position.x, x_g0, "label_slack"], ["green", x_g0, x_g1, "label_hold"], ["over", x_g1, s.end.x, "label_over"]]
	for wd in words:
		var on: bool = String(wd[0]) == z
		var col := CarvedFrame.GOLD.lightened(0.15) if on else Color(UiTheme.CREAM, 0.5)
		var fs := 24 if on else 20
		var wdt: float = float(wd[2]) - float(wd[1])
		while fs > 13 and font.get_string_size(_word(String(wd[3])), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > wdt - 8.0:
			fs -= 1   # a narrow zone (the red with «Облегчить»): the word smaller, never cut
		var at := Vector2(float(wd[1]), s.position.y + s.size.y * 0.5 + fs * 0.36)
		c.draw_string_outline(font, at, _word(String(wd[3])), HORIZONTAL_ALIGNMENT_CENTER, wdt, fs, 6 if on else 4, Color(0.05, 0.03, 0.02, 0.9 if on else 0.6))
		c.draw_string(font, at, _word(String(wd[3])), HORIZONTAL_ALIGNMENT_CENTER, wdt, fs, col)
	# the needle: a brass line across the field, the gold leaf over it; it trembles held too hard
	var shake := sin(clock * 61.0) * 3.0 * clampf(fight.over_risk * 1.5, 0.0, 1.0) if z == "over" else 0.0
	var nx: float = float(xa.call(fight.tension)) + shake
	c.draw_line(Vector2(nx, s.position.y - 2.0), Vector2(nx, s.end.y + 4.0), Color(0, 0, 0, 0.6), 7.0)
	c.draw_line(Vector2(nx, s.position.y - 2.0), Vector2(nx, s.end.y + 4.0), TimingBar.BRASS if z != "over" else Color(1.0, 0.7, 0.55), 3.5)
	CarvedFrame.leaf(c, Vector2(nx, s.position.y + 2.0), Vector2.DOWN, 30.0, CarvedFrame.GOLD)
	_draw_way(c)


## The way to the jetty: water from the jetty's posts (at the left, where Agata stands) out to where the perch is gone.
func _draw_way(c: CanvasItem) -> void:
	var w := way_rect()
	c.draw_rect(w.grow(3.0), CarvedFrame.WOOD_DARK)
	var rows := 8
	for i in rows:
		var t := float(i) / rows
		c.draw_rect(Rect2(w.position.x, w.position.y + w.size.y * t, w.size.x, w.size.y / rows + 0.5), Color(0.24, 0.38, 0.42).lerp(Color(0.08, 0.16, 0.2), t))
	# the far end: where it is gone — the water darker there
	for i in 10:
		var t := float(i) / 10.0
		c.draw_rect(Rect2(w.end.x - 46.0 + 4.6 * i, w.position.y, 4.7, w.size.y), Color(0.03, 0.06, 0.08, 0.05 + 0.05 * t))
	for r in 3:
		var y := w.position.y + 8.0 + r * 10.0
		var x := w.position.x + fposmod(-clock * (16.0 + r * 5.0) + r * 61.0, w.size.x)
		for q in 3:
			var xx := w.position.x + fposmod(x - w.position.x + q * w.size.x / 3.0, w.size.x)
			c.draw_line(Vector2(xx, y), Vector2(minf(xx + 14.0, w.end.x - 1.0), y), Color(0.85, 0.95, 1.0, 0.3), 1.4, true)
	var j0 := w.position.x + 50.0      # the jetty's edge: 0 m
	var j1 := w.end.x - 16.0           # max_m: gone
	var mx := func(m: float) -> float: return lerpf(j0, j1, clampf(m / maxf(fight.max_m, 0.01), 0.0, 1.0))
	# metre notches cut along the bottom (longer every five)
	for m in range(1, int(fight.max_m) + 1):
		var x: float = mx.call(float(m))
		c.draw_line(Vector2(x, w.end.y), Vector2(x, w.end.y - (9.0 if m % 5 == 0 else 5.0)), Color(UiTheme.CREAM, 0.45), 1.5)
	# the jetty: posts in the water, the boards over them, snow on the boards
	c.draw_rect(Rect2(w.position.x, w.position.y, 50.0, w.size.y), Color(0.05, 0.1, 0.13, 0.35))
	for px in [8.0, 24.0, 40.0]:
		c.draw_rect(Rect2(w.position.x + px - 3.5, w.position.y + 6.0, 7.0, w.size.y - 6.0), CarvedFrame.WOOD)
		c.draw_line(Vector2(w.position.x + px - 3.5, w.position.y + 8.0), Vector2(w.position.x + px - 3.5, w.end.y), Color(CarvedFrame.WOOD_LIGHT, 0.6), 1.5)
	c.draw_rect(Rect2(w.position.x - 2.0, w.position.y + 2.0, 52.0, 7.0), CarvedFrame.WOOD_LIGHT)
	c.draw_rect(Rect2(w.position.x - 2.0, w.position.y - 1.0, 52.0, 4.0), Color(0.93, 0.95, 0.97))
	# where it took the hook: the red float, small
	var hx: float = mx.call(fight.start_m)
	c.draw_circle(Vector2(hx, w.position.y + 6.0), 4.0, Color(0.82, 0.16, 0.1, 0.9))
	c.draw_circle(Vector2(hx, w.position.y + 3.5), 2.5, Color(0.95, 0.93, 0.88, 0.9))
	# the perch at its distance: its head to the jetty while it comes in, away while it runs off
	var fx: float = mx.call(fight.dist)
	var fy := w.get_center().y + 2.0
	if _tex.has("perch_lying"):
		var t: Dictionary = _tex["perch_lying"]
		var k := 62.0 / 440.0
		var wig := sin(clock * (14.0 if fight.running() else 5.0)) * (0.08 if fight.running() else 0.03)
		c.draw_set_transform(Vector2(fx, fy), wig, Vector2(k * _face, k))
		c.draw_texture(t["tex"], -(t["anchor"] as Vector2))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		_perch_small(c, Vector2(fx, fy), 50.0)
	# the metres beside it, on the water (behind its tail; before its head near the far end)
	var font := UiTheme.font("body_bold")
	var label_t := _word("label_metres").format({"n": str(int(ceil(fight.dist - 0.05)))})
	var lx := fx + 38.0 if fx + 100.0 < w.end.x else fx - 98.0
	var at := Vector2(lx, w.get_center().y + 7.0)
	c.draw_string_outline(font, at, label_t, HORIZONTAL_ALIGNMENT_LEFT if lx > fx else HORIZONTAL_ALIGNMENT_RIGHT, 60.0, 20, 5, Color(0.03, 0.05, 0.06, 0.9))
	c.draw_string(font, at, label_t, HORIZONTAL_ALIGNMENT_LEFT if lx > fx else HORIZONTAL_ALIGNMENT_RIGHT, 60.0, 20, UiTheme.CREAM)


## The perch caught, held up on the string: the painted one (партия 14, ~170 px long) hanging from `at` (its line's top);
## without the sprite — the shape drawn by the engine.
func _fish(c: CanvasItem, at: Vector2) -> void:
	if _tex.has("perch_caught"):
		var t: Dictionary = _tex["perch_caught"]
		var tex: Texture2D = t["tex"]
		var k: float = t["scale"]
		var sway := sin(clock * 2.3) * 0.06
		c.draw_set_transform(at, float(t.get("rot", 0.0)) + sway, Vector2.ONE * k)
		c.draw_texture(tex, -(t["anchor"] as Vector2))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	c.draw_set_transform(at + Vector2(0, 30), deg_to_rad(-12.0), Vector2.ONE)
	_fish_shape(c)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A small lying perch (the row of those caught, the gauge): the painted one, `len_px` long, centred at `at`, turned by
## `ang`; without the sprite — the drawn shape.
func _perch_small(c: CanvasItem, at: Vector2, len_px: float, ang: float = 0.0) -> void:
	if _tex.has("perch_lying"):
		var t: Dictionary = _tex["perch_lying"]
		var k := len_px / 440.0
		c.draw_set_transform(at, ang, Vector2.ONE * k)
		c.draw_texture(t["tex"], -(t["anchor"] as Vector2))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	c.draw_set_transform(at, ang, Vector2.ONE * len_px / 150.0)
	_fish_shape(c)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The perch at the origin of the current transform (head to the left).
func _fish_shape(c: CanvasItem) -> void:
	var L := 150.0
	var H := 52.0
	var body := PackedVector2Array()
	for i in 33:
		var a := TAU * float(i) / 32.0
		body.append(Vector2(cos(a) * L * 0.5, sin(a) * H * 0.5 * (1.0 - 0.25 * cos(a))))
	c.draw_colored_polygon(PackedVector2Array([Vector2(L * 0.42, 0), Vector2(L * 0.7, -H * 0.45), Vector2(L * 0.64, 0), Vector2(L * 0.7, H * 0.45)]), Color(0.75, 0.3, 0.15))
	c.draw_colored_polygon(body, Color(0.62, 0.58, 0.28))
	for k in 6:
		var x := -L * 0.25 + k * L * 0.11
		c.draw_line(Vector2(x, -H * 0.42), Vector2(x - 6.0, H * 0.2), Color(0.18, 0.2, 0.1, 0.7), 6.0, true)
	c.draw_colored_polygon(PackedVector2Array([Vector2(-L * 0.1, -H * 0.48), Vector2(L * 0.15, -H * 0.75), Vector2(L * 0.25, -H * 0.42)]), Color(0.35, 0.33, 0.2))
	c.draw_colored_polygon(PackedVector2Array([Vector2(-L * 0.05, H * 0.4), Vector2(L * 0.05, H * 0.7), Vector2(L * 0.12, H * 0.38)]), Color(0.8, 0.28, 0.12))
	c.draw_circle(Vector2(-L * 0.38, -H * 0.08), 5.0, Color(0.95, 0.85, 0.4))
	c.draw_circle(Vector2(-L * 0.38, -H * 0.08), 2.5, Color(0.05, 0.05, 0.05))
	c.draw_polyline(body, Color(0, 0, 0, 0.5), 2.0, true)


## «Ещё» shows once the word after the game is read (the text box would cover it).
func _sync_again() -> void:
	again_btn.visible = phase == "caught" and not dialogue_up()


func probe() -> Dictionary:
	_sync_again()
	return {"phase": phase, "tension": tension, "progress": progress, "caught": caught, "lost": lost, "nibbles": nibbles,
		"green": [green.x, green.y], "again": again_btn.visible, "picture": {"x": _pic.get_center().x, "y": _pic.get_center().y},
		"slow": {"x": slow_check.get_global_rect().get_center().x, "y": slow_check.get_global_rect().get_center().y} if slow_check != null else {},
		"in_room": in_room, "simple": simple, "float": {"x": _float_pos().x, "y": _float_pos().y},
		"mitya_rod": mitya_rod_k if _mitya_layer != null else 0.0,
		"dist": fight.dist if fight != null else 0.0, "zone": fight.zone() if fight != null else "",
		"slack_risk": fight.slack_risk if fight != null else 0.0, "over_risk": fight.over_risk if fight != null else 0.0,
		"last_end": last_end, "easy": TimingBar.slow_k() > 1.0,
		"gauge": [_gauge.position.x, _gauge.position.y, _gauge.size.x, _gauge.size.y]}
