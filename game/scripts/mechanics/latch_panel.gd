extends MechanicPanel
## A stiff latch bar to be lifted out of its catch at the right moment (Director 23.10, F8: «остановиться
## нужно в нужной зоне, а иначе неудача и падала палочка») — the H1 shutter (M03): the shutters are swollen
## with the damp, Agata works the latch bar up and down; caught high (the green of the «Точный удар» bar under
## the picture — TimingBar, the same component as the brace), it clears the catch and the shutters swing
## open — event "opened". Released anywhere else, the bar drops back into the catch with a clack; she tries
## again, nothing lost.
## Art (data): `closed` — the closed-shutter layer of the room and `region` of it; `open` — what is behind
## (the room's own background) and `open_region` — the same place in its pixels; `bar` — the latch bar's rect in
## the closed layer, `patch` — a strip of the same shutter just above it (covers the painted bar, the bar is
## drawn turning), `pivot` — the rivet it turns about, `max_deg` — how high it lifts at the top of the sweep.

var view_rect: Rect2 = Rect2()
var m: float = 1.0                 # closed-layer px → screen
var halves: Array[Control] = []    # the two shutter leaves (swing open on success)
var bar: TextureRect = null
var timing: TimingBar = null
var opened_t: float = -1.0
var drops: int = 0


func build() -> void:
	var art: Dictionary = spec.get("art", {})
	var reg: Array = spec.get("region", [1180, 120, 420, 400])
	var vr: Array = spec.get("view", [500, 110, 920, 0])
	var w := float(vr[2])
	m = w / float(reg[2])
	view_rect = Rect2(float(vr[0]), float(vr[1]), w, float(reg[3]) * m)
	# Behind: the window as it is with the shutters open (the room's background).
	var orr: Array = spec.get("open_region", reg)
	var open_img := crop(String(art.get("open", "")), orr, view_rect.position, view_rect.size.x / float(orr[2]))
	open_img.name = "Open"
	open_img.size = view_rect.size
	# The two leaves: the closed layer split at the gap between them; each swings about its hinge side.
	var gap := float(spec.get("gap_x", float(reg[0]) + float(reg[2]) * 0.5))
	var lw := gap - float(reg[0])
	var leaves := [[float(reg[0]), lw, 0.0], [gap, float(reg[0]) + float(reg[2]) - gap, 1.0]]
	for i in 2:
		var lf: Array = leaves[i]
		var holder := Control.new()
		holder.name = "Leaf%d" % i
		holder.position = view_rect.position + Vector2((float(lf[0]) - float(reg[0])) * m, 0)
		holder.size = Vector2(float(lf[1]) * m, view_rect.size.y)
		holder.pivot_offset = Vector2(holder.size.x * float(lf[2]), holder.size.y * 0.5)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(holder)
		crop(String(art.get("closed", "")), [float(lf[0]), float(reg[1]), float(lf[1]), float(reg[3])], Vector2.ZERO, m, holder).name = "Image"
		halves.append(holder)
	# The painted bar covered by the shutter just above it; the bar itself drawn turning about its rivet.
	var b: Array = spec.get("bar", [1356, 329, 44, 12])
	var pt: Array = spec.get("patch", [b[0], float(b[1]) - float(b[3]) - 1.0, b[2], b[3]])
	var patch := crop(String(art.get("closed", "")), pt, _to_screen(Vector2(float(b[0]), float(b[1]))), m, halves[0])
	patch.position -= halves[0].position
	patch.name = "Patch"
	var piv := v2(spec.get("pivot", [1359, 334]))
	bar = crop(String(art.get("closed", "")), b, _to_screen(Vector2(float(b[0]), float(b[1]))), m, halves[0])
	bar.position -= halves[0].position
	bar.name = "Bar"
	bar.pivot_offset = (piv - Vector2(float(b[0]), float(b[1]))) * m
	# The bar under the picture: «Точный удар», one catch.
	timing = TimingBar.new()
	timing.name = "Timing"
	var tr: Array = spec.get("timing_rect", [560, 930, 800, 60])
	timing.position = Vector2(float(tr[0]), float(tr[1]))
	timing.size = Vector2(float(tr[2]), float(tr[3]))
	add_child(timing)
	timing.setup(spec.get("timing", {"hits": 1, "period_s": 2.2, "green": 0.22, "center": 0.8}))
	timing.struck.connect(_on_struck)
	var hit := hit_area(view_rect, _on_view_input, "Shutter")
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	label(text("label_hint"), Vector2(view_rect.end.x + 40.0, view_rect.position.y + 40.0), 1920.0 - view_rect.end.x - 80.0, &"CloseupLabel")
	if flag(String(spec.get("done_flag", ""))):
		_show_open(1.0)
		timing.visible = false


func _to_screen(p: Vector2) -> Vector2:
	var reg: Array = spec.get("region", [1180, 120, 420, 400])
	return view_rect.position + (p - Vector2(float(reg[0]), float(reg[1]))) * m


func _on_view_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if timing.visible:
			timing.strike()


func _on_struck(r: String) -> void:
	match r:
		"done":
			sound("shutter")
			opened_t = 0.0
			timing.visible = false
		"miss":
			drops += 1
			sound("knock")
			if drops == 1:
				say("dropped")


func _show_open(x: float) -> void:
	for i in halves.size():
		var h := halves[i]
		h.scale = Vector2(lerpf(1.0, 0.12, x), 1.0)
		h.modulate = Color(1, 1, 1).darkened(0.35 * x)


func tick(delta: float) -> void:
	if opened_t >= 0.0:
		opened_t += delta
		var x := clampf(opened_t / 0.7, 0.0, 1.0)
		_show_open(x * x * (3.0 - 2.0 * x))
		if opened_t >= 0.8 and not flag(String(spec.get("done_flag", ""))):
			event("opened")
		bar.rotation_degrees = -float(spec.get("max_deg", 70.0))
		return
	if timing.logic == null:
		return
	# The bar follows the sweep: in the catch at the bottom, up at the top; after a miss it drops back.
	var p := timing.logic.pos() if timing.logic.state != "miss" else 0.0
	bar.rotation_degrees = lerpf(bar.rotation_degrees, -float(spec.get("max_deg", 70.0)) * p, clampf(delta * 18.0, 0.0, 1.0))


func probe() -> Dictionary:
	return {"timing": timing.probe() if timing != null else {}, "shutter": center_of(get_node_or_null("Shutter")),
		"drops": drops, "opened": opened_t >= 0.0, "bar_deg": bar.rotation_degrees}
