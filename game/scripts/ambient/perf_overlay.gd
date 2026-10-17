class_name AmbientPerf
extends CanvasLayer
## Hidden performance overlay (F3) — for the Director to read the numbers on a real computer:
## FPS (now, the lowest over the last 5 s), frame time in ms (frame / game logic / physics), draw calls
## and objects of the frame, and what the ambient layer of the room holds (quality, rain layers and
## streaks, sway regions, water, puddles, dust motes, splashes and prints so far).
##   F3 — show / hide;  F4 — effects quality Высокое ↔ Низкое (saved);  F2 — «Живой мир» on / off.
## Created once by AmbientBuilder.build (first room). Takes no mouse input (the label ignores the mouse).

static var _instance: AmbientPerf = null

var label: Label = null
var _samples: Array[float] = []      # frame times, s (last 5 s)
var _acc: float = 0.0


static func ensure() -> void:
	if _instance != null and is_instance_valid(_instance):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	_instance = AmbientPerf.new()
	_instance.name = "AmbientPerf"
	tree.root.add_child.call_deferred(_instance)


static func instance() -> AmbientPerf:
	return _instance if _instance != null and is_instance_valid(_instance) else null


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	label = Label.new()
	label.name = "Text"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = Vector2(16, 96)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_content_margin_all(10)
	label.add_theme_stylebox_override("normal", bg)
	add_child(label)
	visible = false


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_F3:
			visible = not visible
			_refresh()
			get_viewport().set_input_as_handled()
		KEY_F4:
			var next := "low" if AmbientBuilder.quality().get("id", "high") == "high" else "high"
			AmbientBuilder.set_quality(next, _room())
			_refresh()
			get_viewport().set_input_as_handled()
		KEY_F2:
			AmbientBuilder.enabled = not AmbientBuilder.enabled
			var amb := AmbientBuilder.of(_room())
			if amb != null:
				amb.set_active(AmbientBuilder.enabled)
			elif AmbientBuilder.enabled:
				AmbientBuilder.rebuild(_room())
			_refresh()
			get_viewport().set_input_as_handled()


func _room() -> Node:
	var rm := get_node_or_null("/root/RoomManager")
	return rm.get("current_room") if rm != null else null


func _process(delta: float) -> void:
	_samples.append(delta)
	var total := 0.0
	for s in _samples:
		total += s
	while total > 5.0 and _samples.size() > 1:
		total -= _samples.pop_front()
	if not visible:
		return
	_acc += delta
	if _acc >= 0.25:
		_acc = 0.0
		_refresh()


func text() -> String:
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var worst := 0.0
	var mean := 0.0
	for s in _samples:
		worst = maxf(worst, s)
		mean += s
	mean = mean / maxf(float(_samples.size()), 1.0)
	var lines: Array[String] = []
	lines.append("FPS %d (мин. за 5 с: %d)   кадр %.1f мс (худший %.1f)" % [int(fps), int(1.0 / maxf(worst, 0.0001)), mean * 1000.0, worst * 1000.0])
	lines.append("логика %.1f мс   физика %.1f мс   отрисовка: %d вызовов, %d объектов" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))])
	var room := _room()
	var amb := AmbientBuilder.of(room)
	var q := AmbientBuilder.quality()
	var head := "Живой мир %s: качество %s" % [String(room.get("room_id")) if room != null else "—", String(q.get("label", q.get("id", "")))]
	if not AmbientBuilder.enabled:
		lines.append(head + " — ВЫКЛЮЧЕН (F2)")
	elif amb == null:
		lines.append(head + " — в этой комнате эффектов нет")
	else:
		var st := amb.stats()
		lines.append(head)
		lines.append("дождь: %d сл., %d капель   ветер: %d обл.   вода: %d   лужи: %d   пыль: %d" % [
			st["rain_layers"], st["rain_particles"], st["sway"], st["water"], st["puddles"], st["dust_particles"]])
		if amb.footfall != null:
			lines.append("шаги: %d   брызги: %d   следы: %d (сейчас %d)" % [st["steps"], st["splashes"], st["prints_made"], st["prints"]])
	lines.append("F3 — скрыть   F4 — качество Высокое/Низкое   F2 — живой мир вкл/выкл")
	return "\n".join(lines)


func _refresh() -> void:
	if label != null:
		label.text = text()
