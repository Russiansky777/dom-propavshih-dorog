extends MechanicPanel
## Бечёвка с Митей — рыбалка с натяжением (партия J, часть G; Директор 25.10: «бечёвка с Митей как рыбалка с
## натяжением», 29.10: «на конце — рыба»). The river at the Olkhovka pier (a part of R3's painting, `art`), in the
## game's carved frame; a float on the water, the string from the rod above.
##   wait   — the float rests and bobs; a while (`wait_s`) and a nibble or two (small dips) — don't strike yet;
##   bite   — the float goes under: strike now (a click on the picture or Space) within `bite_s`; too early — the fish
##            only tried it (texts.early), too late — it is gone (texts.late); both — wait again;
##   fight  — hold the mouse button or Space to pull: the string's tension rises; let go — it falls; the fish surges
##            now and then. In the green (`green`, wider with «Облегчить») the fish comes nearer (progress); past the
##            red the string snaps (texts.snap), slack too long — it gets away (texts.escaped);
##   caught — the perch shown (drawn by the engine), Mitya's word (texts.caught), event "caught"; «Ещё» / «Хватит»
##            (event "done").
## Everything is data: art (image, variants by time of day), wait_s, bite_s, green, pull, surge, texts, events.

const FLOAT_RED := Color(0.82, 0.16, 0.1)
const FLOAT_WHITE := Color(0.95, 0.93, 0.88)
const LINE := Color(0.88, 0.84, 0.74, 0.85)

var phase: String = "wait"       # wait | bite | fight | caught | lost
var phase_t: float = 0.0
var next_event: float = 3.0
var nibbles: int = 0
var _nibbles_to: int = 1
var _dip: float = 0.0
var tension: float = 0.0
var progress: float = 0.0
var slack_t: float = 0.0
var over_t: float = 0.0
var pulling: bool = false
var surge: float = 0.0
var fish_x: float = 0.0          # where the fish pulls the float in the fight (-1 … 1)
var caught: int = 0
var lost: int = 0
var green: Vector2 = Vector2(0.35, 0.75)
var _rng := RandomNumberGenerator.new()
var _pic: Rect2 = Rect2(260, 130, 1400, 788)
var _float0: Vector2 = Vector2(980, 560)
var _bar: Rect2 = Rect2(1700, 200, 46, 640)
var _draw: Control = null
var hint: Label = null
var again_btn: Button = null
var stop_btn: Button = null


func build() -> void:
	_rng.seed = int(spec.get("seed", Time.get_ticks_usec()))
	var easy := TimingBar.slow_k() > 1.0
	var g: Array = spec.get("green_easy", [0.25, 0.85]) if easy else spec.get("green", [0.35, 0.75])
	green = Vector2(float(g[0]), float(g[1]))
	var art: Dictionary = spec.get("art", {})
	var pr: Array = spec.get("picture", [260, 130, 1400, 788])
	_pic = Rect2(float(pr[0]), float(pr[1]), float(pr[2]), float(pr[3]))
	var fp: Array = spec.get("float", [980, 560])
	_float0 = Vector2(float(fp[0]), float(fp[1]))
	_bar = Rect2(_pic.end.x + 40.0, _pic.position.y + 60.0, 46.0, _pic.size.y - 120.0)
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
	_draw = Control.new()
	_draw.name = "Water"
	_draw.size = Vector2(1920, 1080)
	_draw.mouse_filter = Control.MOUSE_FILTER_STOP
	_draw.draw.connect(_on_draw)
	_draw.gui_input.connect(_on_input)
	add_child(_draw)
	hint = label(text("wait"), Vector2(_pic.position.x, _pic.end.y + 26.0), _pic.size.x, &"CloseupLabel")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	again_btn = _button(text("again"), Vector2(_pic.get_center().x - 230.0, _pic.end.y + 66.0), "Again")
	again_btn.pressed.connect(_restart)
	stop_btn = _button(text("stop"), Vector2(_pic.get_center().x + 30.0, _pic.end.y + 66.0), "Stop")
	stop_btn.visible = true
	stop_btn.pressed.connect(func(): event("done"))
	_restart()


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
					next_event = phase_t + _rng.randf_range(0.9, 1.8)
				else:
					phase = "bite"
					phase_t = 0.0
		"bite":
			if phase_t > float(spec.get("bite_s", 0.9)):
				lost += 1
				say("late")
				_to_wait()
		"fight":
			_fight(delta)
	_draw.queue_redraw()


func _fight(delta: float) -> void:
	var pull := float(spec.get("pull", 0.55))
	tension += (pull if pulling else -pull * 0.9) * delta
	# the fish: a surge now and then (a run), and a steady tug
	if _rng.randf() < delta * 0.9:
		surge = _rng.randf_range(0.18, 0.36) * float(spec.get("surge", 1.0))
		fish_x = clampf(fish_x + _rng.randf_range(-0.8, 0.8), -1.0, 1.0)
	tension += surge * delta * 3.0
	surge = maxf(surge - delta * 0.9, 0.0)
	tension = clampf(tension, 0.0, 1.0)
	if tension >= green.x and tension <= green.y:
		progress += delta * float(spec.get("reel", 0.16))
	elif tension > green.y:
		progress += delta * 0.04
	slack_t = slack_t + delta if tension < green.x * 0.5 else 0.0
	over_t = over_t + delta if tension > 0.97 else 0.0
	if over_t > 0.35:
		lost += 1
		say("snap")
		_to_wait()
	elif slack_t > 2.2:
		lost += 1
		say("escaped")
		_to_wait()
	elif progress >= 1.0:
		phase = "caught"
		phase_t = 0.0
		caught += 1
		pulling = false
		hint.text = ""
		event("caught")
		say("caught")
		again_btn.visible = true


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
			phase = "fight"
			phase_t = 0.0
			tension = (green.x + green.y) * 0.5
			progress = 0.0
			slack_t = 0.0
			over_t = 0.0
			fish_x = 0.0
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

func _float_pos() -> Vector2:
	var p := _float0 + Vector2(0.0, sin(clock * 2.1) * 2.5)
	match phase:
		"wait":
			if _dip > 0.0:
				p.y += 7.0 * sin((0.45 - _dip) / 0.45 * PI)
		"bite":
			p.y += 18.0 * minf(phase_t / 0.15, 1.0)
		"fight":
			p += Vector2(fish_x * 160.0 * (1.0 - progress * 0.7), 22.0 + 200.0 * progress)
		"caught":
			p += Vector2(0.0, -40.0)
	return p


func _on_draw() -> void:
	var c := _draw
	var fp := _float_pos()
	var tip := Vector2(_pic.position.x + 120.0, _pic.position.y - 4.0)
	# the string: sags while slack, straight when taut
	var taut := tension if phase == "fight" else 0.1
	var mid := tip.lerp(fp, 0.5) + Vector2(0.0, 60.0 * (1.0 - taut))
	var pts := PackedVector2Array()
	for i in 21:
		var t := float(i) / 20.0
		pts.append(tip.lerp(mid, t).lerp(mid.lerp(fp, t), t))
	c.draw_polyline(pts, Color(0, 0, 0, 0.35), 3.0, true)
	c.draw_polyline(pts, LINE, 1.6, true)
	if phase != "caught":
		# rings on the water round the float
		for k in 3:
			var age := fposmod(clock * 0.6 + k / 3.0, 1.0)
			var big := 1.0 + (2.5 if phase == "bite" or phase == "fight" else 0.0)
			c.draw_set_transform(fp + Vector2(0, 10), 0.0, Vector2(1.0, 0.32))
			c.draw_arc(Vector2.ZERO, 14.0 + age * 40.0 * big, 0.0, TAU, 40, Color(1, 1, 1, 0.35 * (1.0 - age)), 2.0, true)
			c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var under := phase == "bite" or phase == "fight"
		if not under:   # the float: white top over red, its stick
			c.draw_line(fp + Vector2(0, -24), fp + Vector2(0, -8), Color(0.2, 0.15, 0.1), 2.0, true)
			c.draw_set_transform(fp, 0.0, Vector2(1.0, 1.6))
			c.draw_circle(Vector2(0, -2), 9.0, FLOAT_RED)
			c.draw_circle(Vector2(0, -6), 6.0, FLOAT_WHITE)
			c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			c.draw_circle(fp + Vector2(0, 8), 5.0, Color(FLOAT_RED, 0.45))   # seen under the water
	else:
		_fish(c, fp + Vector2(0, 30))
	if phase == "fight":
		_tension_bar(c)


func _tension_bar(c: CanvasItem) -> void:
	CarvedFrame.draw_frame(c, _bar, 12.0)
	c.draw_rect(_bar, CarvedFrame.WOOD_DARK)
	var y := func(v: float) -> float: return _bar.end.y - _bar.size.y * v
	c.draw_rect(Rect2(_bar.position.x, y.call(green.y), _bar.size.x, y.call(green.x) - y.call(green.y)), Color(0.35, 0.55, 0.3, 0.85))
	c.draw_rect(Rect2(_bar.position.x, _bar.position.y, _bar.size.x, y.call(0.92) - _bar.position.y), Color(0.65, 0.16, 0.1, 0.85))
	var ty: float = y.call(tension)
	CarvedFrame.leaf(c, Vector2(_bar.position.x - 6.0, ty), Vector2.RIGHT, 30.0)
	c.draw_line(Vector2(_bar.position.x, ty), Vector2(_bar.end.x, ty), CarvedFrame.GOLD, 3.0)
	# how near the fish is: a thin strip beside
	var pr := Rect2(_bar.end.x + 16.0, _bar.position.y, 8.0, _bar.size.y)
	c.draw_rect(pr, Color(0, 0, 0, 0.4))
	c.draw_rect(Rect2(pr.position.x, pr.end.y - pr.size.y * progress, pr.size.x, pr.size.y * progress), CarvedFrame.GOLD_DIM)


## A perch, drawn: olive back, golden flank, dark bands, red fins, held up on the string.
func _fish(c: CanvasItem, at: Vector2) -> void:
	var L := 150.0
	var H := 52.0
	c.draw_set_transform(at, deg_to_rad(-12.0), Vector2.ONE)
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
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func probe() -> Dictionary:
	return {"phase": phase, "tension": tension, "progress": progress, "caught": caught, "lost": lost, "nibbles": nibbles,
		"green": [green.x, green.y], "again": again_btn.visible, "picture": {"x": _pic.get_center().x, "y": _pic.get_center().y}}
