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
##   caught — the perch shown (drawn by the engine), Mitya's word (texts.caught), event "caught"; «Ещё»; «Хватит» is the
##            close-up's own button, bottom right (spec `close_label`, `close_event` "done" — his word).
## Everything is data: art (image, variants by time of day), wait_s, bite_s, green, pull, surge, texts, events.
## Polish (J, ночь 30.10, «как в прошлых мини-играх»): the rod comes in from her hands at the lower left and bends to
## the fish as the string tightens; the float plops at a nibble and goes under with a splash (sounds — SynthSfx);
## the string creaks taut, snaps with a crack; the tension bar in the carved frame — red at the top, the green band,
## the gold leaf of the string, a little fish climbing the gauge beside it as it comes in, the bar shaking near the
## snap and the green pulsing while the string hangs slack; the perches caught lie in a row in the corner;
## «Облегчить» under the bar (a wider green). The picture sits higher so the hint and «Ещё» stay above the text box.

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
var slow_check: CheckButton = null
var _taut_snd: float = 0.0       # time to the next creak of the taut string


func build() -> void:
	_rng.seed = int(spec.get("seed", Time.get_ticks_usec()))
	eased()
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
	again_btn = _button(text("again"), Vector2(_pic.get_center().x - 100.0, _pic.end.y + 66.0), "Again")
	again_btn.pressed.connect(_restart)
	slow_check = easy_toggle(Vector2(_bar.get_center().x - 60.0, _pic.end.y + 20.0))
	_restart()


func eased() -> void:
	var easy := TimingBar.slow_k() > 1.0
	var g: Array = spec.get("green_easy", [0.25, 0.85]) if easy else spec.get("green", [0.35, 0.75])
	green = Vector2(float(g[0]), float(g[1]))


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
	var pull := float(spec.get("pull", 0.55))
	tension += (pull if pulling else -pull * 0.9) * delta
	# the fish: a surge now and then (a run), and a steady tug
	if _rng.randf() < delta * 0.9:
		surge = _rng.randf_range(0.18, 0.36) * float(spec.get("surge", 1.0))
		fish_x = clampf(fish_x + _rng.randf_range(-0.8, 0.8), -1.0, 1.0)
	tension += surge * delta * 3.0
	surge = maxf(surge - delta * 0.9, 0.0)
	tension = clampf(tension, 0.0, 1.0)
	_taut_snd -= delta
	if pulling and tension > green.x and _taut_snd <= 0.0:
		sound("line_taut")
		_taut_snd = lerpf(0.75, 0.35, tension)
	if tension >= green.x and tension <= green.y:
		progress += delta * float(spec.get("reel", 0.16))
	elif tension > green.y:
		progress += delta * 0.04
	slack_t = slack_t + delta if tension < green.x * 0.5 else 0.0
	over_t = over_t + delta if tension > 0.97 else 0.0
	if over_t > 0.35:
		lost += 1
		sound("line_snap")
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
		sound("water_slap")
		hint.text = ""
		event("caught")
		say("caught")


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
	var taut := tension if phase == "fight" else 0.1
	# the rod: from her hands below the lower left corner up over the water; it bends to the fish as the string tightens
	var butt := Vector2(_pic.position.x + 64.0, _pic.end.y - 3.0)   # it comes in at the frame's lower edge
	var tip0 := Vector2(_pic.position.x + _pic.size.x * 0.24, _pic.position.y + _pic.size.y * 0.16)
	var bend := (taut if phase == "fight" else 0.0) + (0.25 if phase == "bite" else 0.0)
	var tip := tip0 + (fp - tip0).normalized() * 70.0 * bend + Vector2(0.0, sin(clock * 1.3) * 2.0)
	var ctrl := butt.lerp(tip0, 0.55) + (fp - tip0).normalized() * 40.0 * bend
	var rod := PackedVector2Array()
	for i in 17:
		var tt := float(i) / 16.0
		rod.append(butt.lerp(ctrl, tt).lerp(ctrl.lerp(tip, tt), tt))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in rod.size() - 1:
		var w := lerpf(11.0, 2.5, float(i) / (rod.size() - 1))
		c.draw_line(rod[i] + Vector2(2, 3), rod[i + 1] + Vector2(2, 3), Color(0, 0, 0, 0.3), w + 1.0, true)
		c.draw_line(rod[i], rod[i + 1], Color(0.33, 0.22, 0.12), w, true)
		c.draw_line(rod[i] + Vector2(-w * 0.2, -w * 0.25), rod[i + 1] + Vector2(-w * 0.2, -w * 0.25), Color(0.6, 0.45, 0.28, 0.6), maxf(w * 0.25, 1.0), true)
	# the string: sags while slack, straight when taut
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
		if phase == "bite" and phase_t < 0.35:   # the splash as it goes under
			var k := phase_t / 0.35
			for d in 6:
				var ang := -PI * (0.15 + 0.7 * float(d) / 5.0)
				var dp := fp + Vector2(cos(ang), sin(ang)) * (10.0 + 34.0 * k) + Vector2(0.0, 60.0 * k * k)
				c.draw_circle(dp, 3.0 * (1.0 - k) + 1.0, Color(1, 1, 1, 0.75 * (1.0 - k)))
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
	# the perches caught so far, in a row in the upper corner of the picture
	for k in caught:
		c.draw_set_transform(Vector2(_pic.end.x - 60.0 - 66.0 * k, _pic.position.y + 40.0), 0.0, Vector2(0.38, 0.38))
		_fish_shape(c)
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _tension_bar(c: CanvasItem) -> void:
	# near the snap the bar shakes; slack — the green band pulses (pull!)
	var shake := Vector2(sin(clock * 61.0), cos(clock * 47.0)) * 3.0 * clampf(over_t / 0.35 + (tension - 0.9) * 4.0, 0.0, 1.0)
	var bar := Rect2(_bar.position + shake, _bar.size)
	CarvedFrame.draw_frame(c, bar, 12.0)
	c.draw_rect(bar, TimingBar.TRACK)
	var y := func(v: float) -> float: return bar.end.y - bar.size.y * v
	var gl := 0.85 if slack_t <= 0.4 else 0.6 + 0.35 * sin(clock * 10.0)
	c.draw_rect(Rect2(bar.position.x, y.call(green.y), bar.size.x, y.call(green.x) - y.call(green.y)), Color(TimingBar.GREEN, gl))
	c.draw_rect(Rect2(bar.position.x, bar.position.y, bar.size.x, y.call(0.92) - bar.position.y), Color(TimingBar.RED, 0.9))
	for k in range(1, 10):   # carved notches
		var ny: float = y.call(k / 10.0)
		c.draw_line(Vector2(bar.position.x, ny), Vector2(bar.position.x + (14.0 if k % 5 == 0 else 8.0), ny), Color(0, 0, 0, 0.45), 2.0)
	var ty: float = y.call(tension)
	CarvedFrame.leaf(c, Vector2(bar.position.x - 6.0, ty), Vector2.RIGHT, 30.0)
	c.draw_line(Vector2(bar.position.x, ty), Vector2(bar.end.x, ty), TimingBar.BRASS, 3.0)
	CarvedFrame.shade(c, bar, true)
	# how near the fish is: a gauge beside, a little fish climbing it
	var pr := Rect2(bar.end.x + 18.0, bar.position.y, 10.0, bar.size.y)
	c.draw_rect(pr, Color(0, 0, 0, 0.45))
	c.draw_rect(Rect2(pr.position.x, pr.end.y - pr.size.y * progress, pr.size.x, pr.size.y * progress), CarvedFrame.GOLD_DIM)
	c.draw_set_transform(Vector2(pr.get_center().x, pr.end.y - pr.size.y * progress), -PI * 0.5, Vector2(0.2, 0.2))
	_fish_shape(c)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A perch, drawn: olive back, golden flank, dark bands, red fins, held up on the string.
func _fish(c: CanvasItem, at: Vector2) -> void:
	c.draw_set_transform(at, deg_to_rad(-12.0), Vector2.ONE)
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
		"slow": {"x": slow_check.get_global_rect().get_center().x, "y": slow_check.get_global_rect().get_center().y} if slow_check != null else {}}
