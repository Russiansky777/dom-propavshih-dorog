extends Node2D
## Стенд анимаций живых фигур (жители и Агата). Фигура создаётся тем же кодом, что в игре: NpcLive3D → Actor3D (SubViewport,
## ортокамера, шейдер actor_3d) → цепочка модификаторов скелета → BodyClear последним. Настройки — data/actors/<id>.json
## (блок rt3d), как в игре. Камера стенда — та же ортокамера Actor3D, её можно вращать вокруг фигуры; при повороте 0°
## и высоте 14° кадр совпадает с игровым.

const CHARACTERS := "res://lab/characters.json"   # [{id, name, age, role}] — порядок кнопок и клавиш 1…9, 0
const ROLES := ["walk", "idle", "listen", "talk"]
const FLOOR_K := 0.55            # ракурс пола типичной комнаты (влияет на шаги стоп, не на картинку: oblique_floor выключен)
const GAME_ELEV := 14.0
const SPEEDS := [0.1, 0.25, 0.5, 1.0]
const LabNpc := preload("res://lab/lab_npc.gd")

var IDS: Array = []
var INFO := {}                   # id → {name, age, role}
var who := 0
var npc: Node2D = null
var live: NpcLive3D = null
var state := "idle"
var cam_yaw := 0.0               # градусы вокруг вертикали через стопы; 0 — спереди, как в игре
var cam_elev := GAME_ELEV        # градусы над горизонтом; 14 — как в игре
var zoom := 1.0
var pan := Vector2.ZERO
var light_follows := true        # свет «приклеен» к камере, как в игре (три солнца шейдера заданы для игровой камеры)
var raw := false                 # без поправок движка: smooth, calm_shoulders, arm_hang, arm_body выключены
var paused := false
var speed_i := 3
var step_once := false
var base_light := {}
var _drag := 0                   # 0 — нет, 1 — вращение, 2 — сдвиг
var _extra: Array = []           # разовые клипы фигуры (роль ≠ walk/idle/listen/talk)
var _extra_i := 0
var _t := 0.0

var hud: Label = null
var panel: VBoxContainer = null
var ui: CanvasLayer = null
var actions_box: HFlowContainer = null


func _ready() -> void:
	var list = JSON.parse_string(FileAccess.get_file_as_string(CHARACTERS))
	for c in list:
		IDS.append(String(c["id"]))
		INFO[String(c["id"])] = c
	_build_ui()
	_spawn()


# ---------------------------------------------------------------- фигура

func _spawn() -> void:
	if npc != null:
		npc.queue_free()
		npc = null
		live = null
	var id: String = IDS[who]
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	if spec == null:
		push_error("data/actors/%s.json не читается" % id)
		return
	var rt: Dictionary = spec["rt3d"]
	rt["max_render_scale"] = 6.0   # крупный план без мыла (в игре 3.0 — фигура там мельче)
	if raw:
		for k in ["smooth", "calm_shoulders", "arm_hang", "arm_body"]:
			rt.erase(k)
	npc = LabNpc.new()
	npc.name = "Npc_" + id
	add_child(npc)
	_place_npc()
	live = NpcLive3D.new()
	live.name = "Live"
	npc.add_child(live)
	if not live.setup(npc, spec, FLOOR_K):
		push_error("%s: модель не загрузилась" % id)
		live = null
		return
	live.face(Vector2(0.0, 1.0), FLOOR_K, true)   # лицом к игровой камере
	_extra.clear()
	for k in live.view.clips.keys():
		if not ROLES.has(k):
			_extra.append(k)
	_extra.sort()
	_extra_i = 0
	_rebuild_action_buttons()
	_read_light()
	_t = 0.0
	if state in ["idle", "talk", "listen"]:
		live.set_state(state)
	else:
		state = "idle"
	_place_camera()


func _place_npc() -> void:
	if npc == null:
		return
	var vs := get_viewport_rect().size
	npc.scale = Vector2.ONE * zoom
	npc.position = Vector2(maxf(vs.x * 0.66, 1100.0), vs.y * 0.93) + pan   # правее панели (≈ 800 px)


func _set_state(st: String) -> void:
	state = st
	if live != null:
		live.set_state(st)


func _play_extra(clip: String) -> void:
	if live != null and live.play_once(clip):
		state = "act:" + clip


# ---------------------------------------------------------------- камера и свет

func _cam_basis(elev_deg: float) -> Basis:
	var e := deg_to_rad(elev_deg)
	var up := Vector3(0.0, cos(e), -sin(e))
	var back := Vector3(0.0, sin(e), cos(e))
	return Basis.looking_at(-back, up)


## Игровая камера (Actor3D._place_camera), повёрнутая вокруг вертикали через стопы и наклонённая на свою высоту.
## Центр кадра — точка оси фигуры, которую игровая камера видит в центре (≈ 0,97 м, у бёдер): при любой высоте
## фигура остаётся в кадре; при повороте 0° и высоте 14° камера совпадает с игровой.
func _place_camera() -> void:
	if live == null:
		return
	var v: Actor3D = live.view
	var size := v.frame_px.y / v.ppm
	var e0 := deg_to_rad(GAME_ELEV)
	var off := (v.pivot.y - 0.5) * size
	var c := Vector3(-(v.pivot.x - 0.5) * v.frame_px.x / v.ppm, off / cos(e0), 0.0)
	var t0 := off * tan(e0)
	var e := deg_to_rad(cam_elev)
	var up := Vector3(0.0, cos(e), -sin(e))
	var back := Vector3(0.0, sin(e), cos(e))
	var yaw_b := Basis(Vector3.UP, deg_to_rad(cam_yaw))
	v.camera.size = size
	v.camera.transform = Transform3D(yaw_b, Vector3.ZERO) * Transform3D(Basis.looking_at(-back, up), c + back * (10.0 - t0))
	_apply_light()


func _read_light() -> void:
	base_light.clear()
	var m: ShaderMaterial = live.view.material
	for k in ["key_dir", "fill_dir", "rim_dir"]:
		var val = m.get_shader_parameter(k)
		if val == null:
			val = RenderingServer.shader_get_parameter_default(m.shader.get_rid(), k)
		base_light[k] = val


## Свет шейдера задан в мировых осях для игровой камеры (14°, спереди). «Свет за камерой» поворачивает его вместе
## с камерой — освещение фигуры в кадре как в игре; иначе свет стоит на месте и камера обходит освещённую фигуру.
func _apply_light() -> void:
	if live == null or base_light.is_empty():
		return
	var m: ShaderMaterial = live.view.material
	var r := Basis.IDENTITY
	if light_follows:
		r = Basis(Vector3.UP, deg_to_rad(cam_yaw)) * _cam_basis(cam_elev) * _cam_basis(GAME_ELEV).inverse()
	for k in base_light.keys():
		var d: Vector3 = base_light[k]
		m.set_shader_parameter(k, (r * d).normalized())


# ---------------------------------------------------------------- кадр

func _process(delta: float) -> void:
	if live == null:
		return
	if not paused or step_once:
		var dt: float = (1.0 / 60.0 if step_once else delta) * SPEEDS[speed_i]
		step_once = false
		live.process(dt)
		_t += dt
		if state.begins_with("act:") and not live.once_busy():
			state = "idle"
	_update_hud()


func _update_hud() -> void:
	if hud == null or live == null:
		return
	var v: Actor3D = live.view
	var act := String(v.get("_act_name"))
	var lines := [
		"%s, %d — %s   %s" % [INFO[IDS[who]]["name"], int(INFO[IDS[who]]["age"]), INFO[IDS[who]].get("role", ""), "(БЕЗ поправок движка)" if raw else ""],
		"Состояние: %s   слой действия: %s, вес %.2f" % [state, act if act != "" else "—", v.shown_act_w()],
		"Камера: поворот %d°, высота %d°%s   масштаб ×%.2f" % [roundi(cam_yaw), roundi(cam_elev), "  (= игровой ракурс)" if roundi(cam_yaw) % 360 == 0 and roundi(cam_elev) == 14 else "", zoom],
		"Свет: %s   BodyClear живой: %s" % ["за камерой (как в игре)" if light_follows else "неподвижен", _bc_text()],
		"Время стенда %.2f с   скорость ×%s%s   FPS %d" % [_t, str(SPEEDS[speed_i]), "   ПАУЗА" if paused else "", Engine.get_frames_per_second()],
	]
	hud.text = "\n".join(lines)


func _bc_text() -> String:
	if live.arm_body == null:
		return "нет (в данных нет arm_body)"
	return "вкл" if live.arm_body.active else "ВЫКЛ (запечённая поправка в клипах остаётся)"


# ---------------------------------------------------------------- ввод

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_by(1.12)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_by(1.0 / 1.12)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = 1 if mb.pressed else 0
		elif mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_drag = 2 if mb.pressed else 0
	elif ev is InputEventMouseMotion and _drag != 0:
		var mm := ev as InputEventMouseMotion
		if _drag == 1:
			cam_yaw = fposmod(cam_yaw - mm.relative.x * 0.4, 360.0)
			cam_elev = clampf(cam_elev + mm.relative.y * 0.3, -10.0, 80.0)
			_place_camera()
		else:
			pan += mm.relative
			_place_npc()
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		_key((ev as InputEventKey).physical_keycode)
	elif ev is InputEventKey and ev.pressed and ev.echo:
		var pk := (ev as InputEventKey).physical_keycode
		if pk in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_PERIOD]:
			_key(pk)


func _key(k: int) -> void:
	match k:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9: _switch(k - KEY_1)
		KEY_0: _switch(9)
		KEY_TAB: _switch(posmod(who + (-1 if Input.is_key_pressed(KEY_SHIFT) else 1), IDS.size()))
		KEY_I: _set_state("idle")
		KEY_T: _set_state("talk")
		KEY_L: _set_state("listen")
		KEY_N:
			if not _extra.is_empty():
				_play_extra(_extra[_extra_i % _extra.size()])
				_extra_i += 1
		KEY_LEFT: _orbit(15.0, 0.0)
		KEY_RIGHT: _orbit(-15.0, 0.0)
		KEY_UP: _orbit(0.0, 5.0)
		KEY_DOWN: _orbit(0.0, -5.0)
		KEY_F: _view(0.0)
		KEY_S: _view(90.0)
		KEY_B: _view(180.0)
		KEY_HOME: _reset_view()
		KEY_SPACE: paused = not paused
		KEY_PERIOD:
			paused = true
			step_once = true
		KEY_BRACKETLEFT: speed_i = maxi(speed_i - 1, 0)
		KEY_BRACKETRIGHT: speed_i = mini(speed_i + 1, SPEEDS.size() - 1)
		KEY_V:
			light_follows = not light_follows
			_apply_light()
		KEY_C:
			if live != null and live.arm_body != null:
				live.arm_body.active = not live.arm_body.active
		KEY_R:
			raw = not raw
			_spawn()
		KEY_H: ui.visible = not ui.visible
		KEY_P: _shot()


func _switch(i: int) -> void:
	if i < 0 or i >= IDS.size() or (i == who and live != null):
		return
	who = i
	if state.begins_with("act:"):
		state = "idle"
	_spawn()


func _orbit(dyaw: float, delev: float) -> void:
	cam_yaw = fposmod(cam_yaw + dyaw, 360.0)
	cam_elev = clampf(cam_elev + delev, -10.0, 80.0)
	_place_camera()


func _view(yaw: float) -> void:
	cam_yaw = yaw
	cam_elev = GAME_ELEV
	_place_camera()


func _reset_view() -> void:
	cam_yaw = 0.0
	cam_elev = GAME_ELEV
	zoom = 1.0
	pan = Vector2.ZERO
	_place_npc()
	_place_camera()


func _zoom_by(f: float) -> void:
	zoom = clampf(zoom * f, 0.4, 4.0)
	_place_npc()


func _shot() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	var p := "user://shots/%s_%s_%03d_%02d_%07.2f.png" % [IDS[who], state.replace(":", "_"), roundi(cam_yaw), roundi(cam_elev), _t]
	get_viewport().get_texture().get_image().save_png(p)
	print("снимок: ", ProjectSettings.globalize_path(p))


# ---------------------------------------------------------------- интерфейс

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var root := PanelContainer.new()
	root.position = Vector2(16, 16)
	root.custom_minimum_size = Vector2(760, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.075, 0.07, 0.82)
	sb.set_content_margin_all(12)
	sb.set_corner_radius_all(6)
	root.add_theme_stylebox_override("panel", sb)
	ui.add_child(root)
	panel = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 8)
	root.add_child(panel)
	hud = Label.new()
	hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # длинная роль персонажа переносится, панель не растёт
	hud.custom_minimum_size = Vector2(736, 0)
	hud.add_theme_font_size_override("font_size", 18)
	panel.add_child(hud)
	var people := []
	for i in IDS.size():
		var n: int = i
		people.append(["%s [%d]" % [INFO[IDS[i]]["name"], (i + 1) % 10], func(): _switch(n)])
	panel.add_child(_row(people))
	panel.add_child(_row([["idle [I]", func(): _set_state("idle")], ["talk [T]", func(): _set_state("talk")], ["listen [L]", func(): _set_state("listen")]]))
	panel.add_child(_row([["Спереди [F]", func(): _view(0.0)], ["Сбоку [S]", func(): _view(90.0)], ["Сзади [B]", func(): _view(180.0)], ["Сброс [Home]", func(): _reset_view()]]))
	actions_box = HFlowContainer.new()
	actions_box.add_theme_constant_override("separation", 6)
	panel.add_child(actions_box)
	var help := Label.new()
	help.add_theme_font_size_override("font_size", 15)
	help.modulate = Color(1, 1, 1, 0.75)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(736, 0)
	help.text = "\n".join([
		"1…9, 0 — персонаж (Tab / Shift+Tab — следующий / предыдущий)",
		"Левая кнопка мыши + тянуть — камера вокруг фигуры (влево-вправо — поворот, вверх-вниз — высота)",
		"← → — поворот на 15°, ↑ ↓ — высота на 5°; колесо — масштаб; правая/средняя кнопка + тянуть — сдвиг",
		"Пробел — пауза, «.» — кадр вперёд (1/60 с), [ ] — скорость ×0.1…×1; N — следующее разовое действие",
		"V — свет за камерой / неподвижен; C — живой BodyClear вкл/выкл; R — без поправок движка (сырые клипы)",
		"P — снимок в user://shots; H — спрятать панель",
	])
	panel.add_child(help)


func _row(items: Array) -> HFlowContainer:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("separation", 6)
	for it in items:
		var b := Button.new()
		b.text = it[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(it[1])
		h.add_child(b)
	return h


func _rebuild_action_buttons() -> void:
	for c in actions_box.get_children():
		c.queue_free()
	var l := Label.new()
	l.text = "Разовые действия:" if not _extra.is_empty() else "Разовых действий у фигуры нет"
	actions_box.add_child(l)
	for clip in _extra:
		var b := Button.new()
		b.text = clip
		b.focus_mode = Control.FOCUS_NONE
		var c: String = clip
		b.pressed.connect(func(): _play_extra(c))
		actions_box.add_child(b)
