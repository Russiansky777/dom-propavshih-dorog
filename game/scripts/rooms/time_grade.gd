class_name TimeGrade
extends Node2D
## The room under its time of day (F17, TimeOfDay): built by RoomBuilder after the lights (one hook line).
##   - removes the room effects its time file `replaces_effects` lists (the old per-room «dusk» tints keyed on
##     evening_dusk, which also stayed on days 3–4);
##   - grade: a room with a light map takes ambient sources from TimeOfDay.light_sources (RoomLighting merged
##     them at build: the art darkens, fires and lamps keep their light, figures take the tone); any other
##     room gets one full-frame multiply polygon (z GRADE_Z: over the art, the figures and the snow, under the
##     drizzle and the exit marks) in the grade colour — white (off) while the room is as painted;
##   - lit windows (time file `windows[]`): additive warm panes with a soft halo above the grade, on by their
##     `if` / `unless` / `if_any` flags (tod_ virtual flags: «tod_dark» — dusk, evening, night); `"blend": "mul"` —
##     a window going dark instead (the daylight painted in the glass of a room at dusk): a multiply pane right
##     over the painting (z −5: under the figures), no halo; `flicker` {amount, speed, seed} — G25 (Director 23.10:
##     «свет в окнах естественнее и чуть дрожит, как в мастерской»): the pane and its halo breathe with the same
##     flame noise as the lamps (LightFlicker, lights/<LOC>.json `flicker`), each window on its own seed;
##   - a room lit by its Lighting (light route): the «living world» layer (river, puddles, trees swaying, dust,
##     drizzle — drawn from the unlit painting by its own shaders) takes the grade colour as its modulate, so the
##     water does not stay daylight-bright at night;
##   - a state change while in the room eases over `fade_s` (index); entering the room, loading a save or a new
##     game shows the final look at once (no replayed transitions).
## Nothing here takes input.

const GRADE_Z := 4090
const WINDOW_Z := 4091
## J (Director 29.10, стр. 72 / 25.10 стр. 155: «свет окна сквозь модели», «не ложится на фигуры»): a lit window stays
## over the grade (a warm light under a blue night multiply turns grey-green — tried, frame 29.10), and a figure in
## front of it now covers it: the window's light fades by how much of the pane the figure hides (_occlusion).

var room_id: String = ""
var route: String = "tint"        # "tint" — the polygon; "light" — ambient sources in the room's Lighting
var state: String = ""
var tint: Polygon2D = null
var windows: Array[Node2D] = []
var ambient: CanvasItem = null    # the room's «Ambient» layer (light route: modulated by the grade)
var fade_s: float = 2.0
var _tween: Tween = null
var _flickers: Array = []         # [{pane, halo, flicker: LightFlicker, alpha, halo_alpha}] — G25
var _flicker_t: float = 0.0


static func build(room: Node2D, id: String) -> TimeGrade:
	var data := TimeOfDay.room_data(id)
	var fx := room.get_node_or_null("Effects")
	for eid in data.get("replaces_effects", []):
		var n: Node = fx.get_node_or_null(NodePath(String(eid))) if fx != null else null
		if n != null:
			fx.remove_child(n)
			n.free()
	var tg := TimeGrade.new()
	tg.name = "TimeOfDay"
	tg.room_id = id
	tg.fade_s = float(TimeOfDay.index().get("fade_s", 2.0))
	var lighting := room.get_node_or_null("Lighting")
	if lighting != null and lighting.get("light_map") != null and not TimeOfDay.light_sources(id).is_empty():
		tg.route = "light"
	if tg.route == "light":
		tg.ambient = room.get_node_or_null("Ambient") as CanvasItem
	room.add_child(tg)
	tg._build()
	return tg


func _build() -> void:
	z_as_relative = false
	if route == "tint":
		tint = Polygon2D.new()
		tint.name = "Grade"
		tint.polygon = PackedVector2Array([Vector2(-40, -40), Vector2(1960, -40), Vector2(1960, 1120), Vector2(-40, 1120)])
		tint.color = Color.WHITE
		tint.z_index = GRADE_Z
		tint.z_as_relative = false
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		tint.material = m
		add_child(tint)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var mul := CanvasItemMaterial.new()
	mul.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	for w in TimeOfDay.room_data(room_id).get("windows", []):
		var node := _make_window(w, mul if String(w.get("blend", "add")) == "mul" else add)
		if node != null:
			windows.append(node)
			add_child(node)
	GameState.flag_changed.connect(_on_flag_changed)
	GameState.state_reset.connect(_jump)
	GameState.state_loaded.connect(_on_loaded)
	_jump()


func _exit_tree() -> void:
	if GameState.flag_changed.is_connected(_on_flag_changed):
		GameState.flag_changed.disconnect(_on_flag_changed)
	if GameState.state_reset.is_connected(_jump):
		GameState.state_reset.disconnect(_jump)
	if GameState.state_loaded.is_connected(_on_loaded):
		GameState.state_loaded.disconnect(_on_loaded)


func _on_loaded(_slot: String) -> void:
	_jump()


func _make_window(w: Dictionary, mat: CanvasItemMaterial) -> Node2D:
	var pts := PackedVector2Array()
	if w.has("points"):
		for p in w["points"]:
			pts.append(Vector2(float(p[0]), float(p[1])))
	elif w.has("rect"):
		var r: Array = w["rect"]
		var a := Vector2(float(r[0]), float(r[1]))
		var s := Vector2(float(r[2]), float(r[3]))
		pts = PackedVector2Array([a, a + Vector2(s.x, 0), a + s, a + Vector2(0, s.y)])
	if pts.size() < 3:
		return null
	var dark := String(w.get("blend", "add")) == "mul"
	var holder := Node2D.new()
	holder.name = String(w.get("id", "window"))
	holder.z_index = int(w.get("z", -5 if dark else WINDOW_Z))
	holder.z_as_relative = false
	holder.set_meta("spec", w)
	var bx := Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		bx = bx.expand(q)
	holder.set_meta("box", bx)
	var col := Color.html(String(w.get("color", "#ffb766")))
	var pane := Polygon2D.new()
	pane.name = "Pane"
	pane.polygon = pts
	pane.color = col if dark else Color(col.r, col.g, col.b, float(w.get("alpha", 0.5)))
	pane.material = mat
	if not dark:
		# H19 (Director 24.10: «свет в окнах — всё ещё жёлтый квадрат»): the pane is a soft glow in the window's shape —
		# a feathered mask of the polygon (LightMask), brighter in the middle, no hard edge; `feather` px in data.
		var box0 := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			box0 = box0.expand(p)
		var feather := float(w.get("feather", clampf(minf(box0.size.x, box0.size.y) * 0.22, 6.0, 30.0)))
		var shrunk := PackedVector2Array()
		var c0 := box0.get_center()
		for p in pts:
			shrunk.append(c0 + (p - c0) * float(w.get("inset", 0.9)))
		var poly_arr: Array = []
		for p in shrunk:
			poly_arr.append([p.x, p.y])
		# J (стр. 72: «градиент у занавесок»): dimmer towards the jambs, where the curtains hang — `curtains` 0..1
		var sides := {"cx": c0.x, "half": box0.size.x * 0.5, "depth": float(w.get("curtains", 0.55))}
		var m := LightMask.build([poly_arr], feather, {"sides": sides})
		var r: Rect2 = m["rect"]
		var tex: Texture2D = m["texture"]
		pane.texture = tex
		pane.polygon = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		var ts := Vector2(tex.get_width(), tex.get_height())
		pane.uv = PackedVector2Array([Vector2.ZERO, Vector2(ts.x, 0), ts, Vector2(0, ts.y)])
	holder.add_child(pane)
	var halo_k := 0.0 if dark else float(w.get("halo", 2.2))
	if halo_k > 0.0:
		var box := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			box = box.expand(p)
		var g := Gradient.new()
		g.set_color(0, Color(col.r, col.g, col.b, float(w.get("halo_alpha", 0.22))))
		g.set_color(1, Color(col.r, col.g, col.b, 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 64
		gt.height = 64
		var halo := Sprite2D.new()
		halo.name = "Halo"
		halo.texture = gt
		halo.position = box.get_center()
		halo.scale = box.size * halo_k / 64.0
		halo.material = mat
		holder.add_child(halo)
	var fl = w.get("flicker", null)
	if fl is Dictionary and not dark and float(fl.get("amount", 0.0)) > 0.0:
		_flickers.append({"pane": pane, "halo": holder.get_node_or_null("Halo"), "holder": holder,
			"flicker": LightFlicker.new(fl, holder.name.hash() & 0xffff), "alpha": pane.color.a})
	return holder


## G25: the lit windows' flame — the pane's alpha and the halo's brightness × LightFlicker.factor (never below 0).
func _process(delta: float) -> void:
	_occlusion(delta)
	if _flickers.is_empty():
		if windows.is_empty():
			set_process(false)
		return
	_flicker_t += delta
	for f in _flickers:
		var holder: Node2D = f["holder"]
		if float(holder.get_meta("on", holder.modulate.a)) <= 0.0:
			continue
		var k: float = (f["flicker"] as LightFlicker).factor(_flicker_t)
		var pane: Polygon2D = f["pane"]
		pane.color.a = clampf(float(f["alpha"]) * k, 0.0, 1.0)
		var halo = f["halo"]
		if halo != null:
			halo.self_modulate = Color(k, k, k, 1.0)


## A figure in front of a lit window hides its light (J, стр. 72): the share of the pane under the figure's box (feet,
## height by the room's depth scale) — eased, so the glow dims as she walks past and comes back behind her.
## modulate.a = on (meta «on», eased by _apply_windows) × what is left uncovered.
func _occlusion(delta: float) -> void:
	var boxes: Array[Rect2] = []
	var room := get_parent()
	var p: Node2D = RoomManager.player
	if p != null and is_instance_valid(p) and p.is_inside_tree() and RoomManager.current_room == room:
		boxes.append(_figure_box(p, room))
	if room != null:
		for c in room.get_children():
			if c is NpcActor and (c as Node2D).visible:
				boxes.append(_figure_box(c, room))
	for n in windows:
		var on := float(n.get_meta("on", n.modulate.a))
		var w: Dictionary = n.get_meta("spec")
		var cover := 0.0
		if String(w.get("blend", "add")) != "mul" and n.has_meta("box"):
			var box: Rect2 = n.get_meta("box")
			for b in boxes:
				var inter := box.intersection(b)
				if inter.has_area():
					cover = maxf(cover, inter.get_area() / maxf(box.get_area(), 1.0))
		var target := 1.0 - clampf(cover * 2.0, 0.0, 1.0) * 0.92
		var cur := float(n.get_meta("uncovered", 1.0))
		cur = target if delta <= 0.0 else move_toward(cur, target, delta * 4.0)
		n.set_meta("uncovered", cur)
		n.modulate.a = on * cur


func _figure_box(a: Node2D, room: Node) -> Rect2:
	var feet := a.global_position
	var s := 1.0
	if room != null and room.has_method("depth_scale"):
		s = float(room.call("depth_scale", feet.y))
	var h := 345.0 * s
	return Rect2(feet.x - h * 0.2, feet.y - h, h * 0.4, h)


## The flickering windows now: {id: pane alpha} (tests).
func flicker_probe() -> Dictionary:
	var out := {}
	for f in _flickers:
		out[String((f["holder"] as Node2D).name)] = (f["pane"] as Polygon2D).color.a
	return out


func _window_on(w: Dictionary) -> bool:
	for f in w.get("if", ["tod_dark"]):
		if not GameState.has_flag(String(f)):
			return false
	for f in w.get("unless", []):
		if GameState.has_flag(String(f)):
			return false
	var any: Array = w.get("if_any", [])
	if not any.is_empty():
		for f in any:
			if GameState.has_flag(String(f)):
				return true
		return false
	return true


func _on_flag_changed(_f: String, _v: bool) -> void:
	var st := TimeOfDay.room_state(room_id)
	if st != state:
		_apply(st, true)
	else:
		_apply_windows(true)


func _jump() -> void:
	_apply(TimeOfDay.room_state(room_id), false)


func _apply(st: String, ease: bool) -> void:
	state = st
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var target := Color.WHITE
	var g := TimeOfDay.grade(room_id, st)
	if not g.is_empty():
		target = TimeOfDay.tint_of(g)
	if route == "light" and get_parent() != null:
		ambient = get_parent().get_node_or_null("Ambient") as CanvasItem   # rebuilt on a quality change (F4)
	if ambient != null and is_instance_valid(ambient):
		if ease and is_inside_tree():
			create_tween().tween_property(ambient, "modulate", target, fade_s)
		else:
			ambient.modulate = target
		# J (Director 29.10, стр. 57: «вечер, кадр с почтой и домом — нет капель дождя»): the drizzle is a child of the
		# «living world» layer and took the night grade with it — dark streaks on a dark frame. It keeps at least 0.6 of
		# its brightness: rain.modulate = max(grade, 0.6) / grade per channel (1 by day).
		var rain = ambient.get("rain")
		if rain is CanvasItem and is_instance_valid(rain):
			var rk := Color(maxf(target.r, 0.6) / maxf(target.r, 0.01), maxf(target.g, 0.6) / maxf(target.g, 0.01),
				maxf(target.b, 0.6) / maxf(target.b, 0.01), 1.0)
			if ease and is_inside_tree():
				create_tween().tween_property(rain, "modulate", rk, fade_s)
			else:
				(rain as CanvasItem).modulate = rk
	if route != "tint":
		target = Color.WHITE
	if tint != null:
		# White = as painted: the polygon is hidden (no full-frame blend pass in the web build by day).
		if ease and is_inside_tree() and not tint.color.is_equal_approx(target):
			tint.visible = true
			_tween = create_tween()
			_tween.tween_property(tint, "color", target, fade_s)
			if target == Color.WHITE:
				_tween.tween_callback(func(): tint.visible = false)
		else:
			tint.color = target
			tint.visible = target != Color.WHITE
	_apply_windows(ease)


func _apply_windows(ease: bool) -> void:
	for n in windows:
		var on := _window_on(n.get_meta("spec"))
		var a := 1.0 if on else 0.0
		var cur := float(n.get_meta("on", 0.0))
		if ease and is_inside_tree() and not is_equal_approx(cur, a):
			var t := create_tween()
			t.tween_method(func(v: float) -> void: n.set_meta("on", v); n.modulate.a = v * float(n.get_meta("uncovered", 1.0)), cur, a, fade_s * 0.75)
		else:
			n.set_meta("on", a)
		n.visible = true
	_occlusion(0.0)
	set_process(true)


## The colour the polygon multiplies by now (tests), the state and the lit windows.
func probe() -> Dictionary:
	var lit: Array = []
	for n in windows:
		if float(n.get_meta("on", n.modulate.a)) > 0.5:
			lit.append(String(n.name))
	return {"room": room_id, "state": state, "route": route, "tint": tint.color.to_html(false) if tint != null else "",
		"ambient": ambient.modulate.to_html(false) if ambient != null and is_instance_valid(ambient) else "",
		"windows_lit": lit, "class": TimeOfDay.room_class(room_id)}
