extends MechanicPanel
## Q06 «Второй верстак» (Director 23.10 11:51): Ilya's cramped workshop (the shed in his yard, O4 — there is no room
## inside, so it plays as this close-up). Mitya: «Два человека здесь уже не помещаются» — Ilya: «Тогда сделаем место
## третьему». A second bench is put together, step by step, each step a story flag (`steps`, set by the events), so a
## close-up put away midway opens again at the same step and a load replays nothing:
##   1. "fitted"    — the groove of the bench top against two fastenings: a click on one tries it in the groove; the
##                    one that `fits` slides in, the other wobbles there and comes back with Ilya's word why;
##   2. "stopped"   — the stop block (painted in the groove) is seated: a click on it, it sinks in against the key;
##   3. "tightened" — the wooden screw: «Точный удар» (TimingBar — a click on the screw or the bar, or Space),
##                    `timing.hits` in a row; a miss — the screw slips back, the series starts again;
##   4. "checked"   — a board laid on the new bench with Ilya: it holds.
## Nothing is lost on a wrong try. Art (партия 8б): `art.bg` — the close-up of the second bench (closeup_second_bench,
## full canvas 1672×941): the pine top with the groove, the stop block in it, the wooden screw lying on the top. The
## painted stop block and screw are taken from the picture itself (`parts.stop.region`, `parts.screw.region` — crops
## laid exactly over their place, so they move without showing a second copy); the two fastenings and the board are the
## engine's, cut from the picture's own pine (`tex_center` — where on the picture their wood is taken). Without the
## art (`stub`) the engine draws a stand-in. Coordinates — canvas px; `timing_rect`, `step_pos`, `hint_pos` — screen.

const CANVAS := Vector2(1672, 941)

var k: float = 1.0
var art_root: Control = null
var art_tex: Texture2D = null
var parts: Node2D = null            # canvas px, scaled by k
var fasten: Dictionary = {}         # id -> {node, hit, rest, fits, caption, text, into}
var stop_node: Node2D = null
var stop_hit: Control = null
var screw_node: Node2D = null
var screw_hit: Control = null
var board: Polygon2D = null
var board_hit: Control = null
var timing: TimingBar = null
var hint: Label = null
var step_label: Label = null
var tries_wrong: int = 0
var slips: int = 0
var turns: int = 0                  # screw turns in the current series
var _anim: Dictionary = {}          # node -> {from, to, t, dur, then, id}
var _wobble: Dictionary = {}        # id -> t
var _press_t: float = -1.0          # the stop block sinking in
var _screw_t: float = -1.0          # the screw's jolt (a hit) / shake (a miss)
var _screw_miss: bool = false
var _board_t: float = -1.0          # the board laid and pressed
var _checked_t: float = -1.0


func build() -> void:
	var art: Dictionary = spec.get("art", {})
	k = 1920.0 / CANVAS.x
	art_root = Control.new()
	art_root.name = "Art"
	art_root.size = CANVAS
	art_root.scale = Vector2(k, k)
	art_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art_root)
	var bg := String(art.get("bg", ""))
	if bg != "" and ResourceLoader.exists(bg):
		art_tex = load(bg)
		crop(bg, [0, 0, CANVAS.x, CANVAS.y], Vector2.ZERO, 1.0, art_root).name = "Bench"
	else:
		var st := PlaceholderArt.stand_in(spec.get("stub", {}))
		st.name = "BenchStandIn"
		art_root.add_child(st)
	parts = Node2D.new()
	parts.name = "Parts"
	parts.scale = Vector2(k, k)
	add_child(parts)
	var pc: Dictionary = spec.get("parts", {})
	# The painted stop block and screw: crops of the picture over their own place.
	stop_node = _region_sprite(pc.get("stop", {}).get("region", [752, 346, 224, 130]), "Stop")
	stop_hit = hit_area(_screen(_rect(pc.get("stop", {}).get("region", [752, 346, 224, 130])).grow(10.0)), _on_stop, "StopHit")
	screw_node = _region_sprite(pc.get("screw", {}).get("region", [924, 272, 542, 182]), "Screw")
	screw_hit = hit_area(_screen(_rect(pc.get("screw", {}).get("region", [924, 272, 542, 182])).grow(10.0)), _on_screw, "ScrewHit")
	# The two fastenings lying on the top, and their names.
	for f in pc.get("fastenings", []):
		var id := String(f.get("id", "f"))
		var shape := _points(f.get("shape", [[-60, -20], [60, -20], [60, 20], [-60, 20]]))
		var n := _piece(shape, f, "Fastening_" + id)
		var rest := v2(f.get("at", [300, 340]))
		n.position = rest
		var hb := _bounds(shape).grow(22.0)
		var hit := hit_area(_screen(Rect2(rest + hb.position, hb.size)), _on_fastening.bind(id), "Hit_" + id)
		var cap_at := v2(f.get("caption_at", [rest.x, rest.y + hb.end.y + 4.0]))
		var cap := label(StoryData.text(String(f.get("label", id))), (cap_at - Vector2(110, 0)) * k, 220.0 * k)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.name = "Caption_" + id
		fasten[id] = {"node": n, "hit": hit, "rest": rest, "fits": bool(f.get("fits", false)), "caption": cap,
			"text": String(f.get("text", "")), "into": v2(f.get("into", [570, 391]))}
	# The board for the check: leaning at the bench's end, laid along the top when Ilya checks it.
	var bd: Dictionary = pc.get("board", {})
	board = _piece(_points(bd.get("rest", [[1560, 200], [1600, 205], [1580, 760], [1540, 755]])), bd, "Board")
	board_hit = hit_area(_screen(_bounds(board.polygon).grow(16.0)), _on_board, "BoardHit")
	timing = TimingBar.new()
	timing.name = "Timing"
	var tr: Array = spec.get("timing_rect", [560, 965, 800, 56])
	timing.position = Vector2(float(tr[0]), float(tr[1]))
	timing.size = Vector2(float(tr[2]), float(tr[3]))
	add_child(timing)
	timing.setup(spec.get("timing", {"hits": 3, "period_s": 1.9, "green": 0.2}))
	timing.struck.connect(_on_struck)
	strike_bar = timing   # G26: while the screw's bar is up, a click anywhere on the bench strikes too
	step_label = label("", v2(spec.get("step_pos", [1180, 96])), 700, &"CloseupTitle")
	hint = label("", v2(spec.get("hint_pos", [1180, 150])), 700)
	_place_static()
	_refresh()


func opened() -> void:
	sound("knock")


# --- Steps -------------------------------------------------------------------------------------

## 0..4: how many steps are done (`steps` — the flags of "fitted", "stopped", "tightened", "checked").
func step() -> int:
	var n := 0
	for f in spec.get("steps", []):
		if not flag(String(f)):
			return n
		n += 1
	return n


func flags_changed() -> void:
	if parts != null:
		_place_static()
		_refresh()


func _busy() -> bool:
	return not _anim.is_empty() or not _wobble.is_empty() or _press_t >= 0.0 or _board_t >= 0.0 or _checked_t >= 0.0 or dialogue_up()


func _refresh() -> void:
	var s := step()
	for id in fasten:
		var fd: Dictionary = fasten[id]
		var placed: bool = bool(fd["fits"]) and s >= 1
		(fd["hit"] as Control).visible = s == 0
		(fd["caption"] as Label).visible = s == 0
		(fd["node"] as Node2D).visible = s == 0 or placed
	stop_hit.visible = s == 1
	screw_hit.visible = s == 2
	timing.visible = s == 2
	board_hit.visible = s == 3
	var keys := ["label_step1", "label_step2", "label_step3", "label_step4"]
	step_label.text = text(keys[s]) if s < 4 else text("label_done")
	hint.text = text("label_hint%d" % (s + 1)) if s < 4 else ""


## Where the parts stand for the steps already done (opened again midway, or after a load).
func _place_static() -> void:
	var s := step()
	for id in fasten:
		var fd: Dictionary = fasten[id]
		if bool(fd["fits"]) and s >= 1 and not _anim.has(fd["node"]):
			(fd["node"] as Node2D).position = fd["into"]
	if s >= 2 and _press_t < 0.0:
		stop_node.position = _base(stop_node) + v2(spec.get("parts", {}).get("stop", {}).get("press", [-8, 5])) * 0.4
	if s >= 4 or _checked_t >= 0.0:
		_lay_board(1.0)


func _hits_needed() -> int:
	return int(spec.get("timing", {}).get("hits", 3))


## The board between leaning (0) and laid along the top (1): its corners move from `rest` to `laid`.
func _lay_board(x: float) -> void:
	var bd: Dictionary = spec.get("parts", {}).get("board", {})
	var a := _points(bd.get("rest", []))
	var b := _points(bd.get("laid", bd.get("rest", [])))
	if a.size() != b.size() or a.is_empty():
		return
	var e := x * x * (3.0 - 2.0 * x)
	var pts := PackedVector2Array()
	for i in a.size():
		pts.append(a[i].lerp(b[i], e))
	_set_piece_polygon(board, pts, bd)


# --- Input -------------------------------------------------------------------------------------

func _clicked(ev: InputEvent) -> bool:
	return ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT


func _on_fastening(ev: InputEvent, id: String) -> void:
	if not _clicked(ev):
		return
	accept_event()
	if step() != 0 or _busy():
		return
	var fd: Dictionary = fasten[id]
	var n: Node2D = fd["node"]
	if bool(fd["fits"]):
		_anim[n] = {"from": n.position, "to": fd["into"], "t": 0.0, "dur": 0.5, "then": "fitted"}
	else:
		tries_wrong += 1
		_anim[n] = {"from": n.position, "to": fd["into"], "t": 0.0, "dur": 0.4, "then": "wobble", "id": id}


func _on_stop(ev: InputEvent) -> void:
	if not _clicked(ev):
		return
	accept_event()
	if step() != 1 or _busy():
		return
	_press_t = 0.0


func _on_screw(ev: InputEvent) -> void:
	if not _clicked(ev):
		return
	accept_event()
	if step() == 2 and not _busy():
		timing.strike()


func _on_struck(r: String) -> void:
	match r:
		"hit", "done":
			turns = timing.logic.hits
			_screw_t = 0.0
			_screw_miss = false
			sound("ring_creak")
			if r == "done":
				turns = _hits_needed()
				timing.visible = false
				event("tightened")
		"miss":
			turns = 0
			slips += 1
			_screw_t = 0.0
			_screw_miss = true
			sound("clank")
			if slips == 1:
				say("screw_slipped")


func _on_board(ev: InputEvent) -> void:
	if not _clicked(ev):
		return
	accept_event()
	if step() != 3 or _busy():
		return
	_board_t = 0.0
	sound("knock")


# --- Time --------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	for n in _anim.keys():
		var a: Dictionary = _anim[n]
		a["t"] = float(a["t"]) + delta
		var x := clampf(float(a["t"]) / float(a["dur"]), 0.0, 1.0)
		var e := x * x * (3.0 - 2.0 * x)
		(n as Node2D).position = (a["from"] as Vector2).lerp(a["to"], e)
		if x >= 1.0:
			_anim.erase(n)
			_arrived(a)
	for id in _wobble.keys():
		var t := float(_wobble[id]) + delta
		_wobble[id] = t
		var n2: Node2D = fasten[id]["node"]
		n2.rotation_degrees = 7.0 * sin(t * 26.0) * maxf(0.0, 1.0 - t / 0.7)
		if t >= 0.7:
			_wobble.erase(id)
			n2.rotation_degrees = 0.0
			_anim[n2] = {"from": n2.position, "to": fasten[id]["rest"], "t": 0.0, "dur": 0.45, "then": ""}
	if _press_t >= 0.0:
		# The stop block sinks into the groove against the key: a short push and a settle.
		_press_t += delta
		var pr := v2(spec.get("parts", {}).get("stop", {}).get("press", [-8, 5]))
		var x2 := clampf(_press_t / 0.35, 0.0, 1.0)
		stop_node.position = _base(stop_node) + pr * sin(x2 * PI) * 0.6 + pr * 0.4 * x2
		if _press_t >= 0.45:
			_press_t = -1.0
			stop_node.position = _base(stop_node) + pr * 0.4
			sound("knock")
			event("stopped")
			_refresh()
	if _screw_t >= 0.0:
		_screw_t += delta
		var d := _screw_t / (0.5 if _screw_miss else 0.3)
		if _screw_miss:
			screw_node.position = _base(screw_node) + Vector2(6.0 * sin(_screw_t * 48.0) * maxf(0.0, 1.0 - d), 0.0)
			screw_node.rotation_degrees = 0.0
		else:
			screw_node.rotation_degrees = 2.2 * sin(clampf(d, 0.0, 1.0) * PI)
		if d >= 1.0:
			_screw_t = -1.0
			screw_node.position = _base(screw_node)
			screw_node.rotation_degrees = 0.0
	if _board_t >= 0.0:
		# Ilya lays the board along the top, then leans on it: it holds (a short tremble, no give).
		_board_t += delta
		_lay_board(clampf(_board_t / 0.7, 0.0, 1.0))
		if _board_t > 0.7:
			board.position.y = 3.0 * sin((_board_t - 0.7) * 40.0) * maxf(0.0, 1.0 - (_board_t - 0.7) / 0.5)
		if _board_t >= 1.25:
			_board_t = -1.0
			board.position = Vector2.ZERO
			_checked_t = 0.0
			sound("knock")
			event("checked")
	if _checked_t >= 0.0:
		_checked_t += delta


func _arrived(a: Dictionary) -> void:
	match String(a.get("then", "")):
		"fitted":
			sound("knock")
			event("fitted")
		"wobble":
			sound("knock")
			_wobble[String(a["id"])] = 0.0
			var t := String(fasten[String(a["id"])].get("text", ""))
			if t != "":
				say(t)
	_refresh()


# --- Helpers -----------------------------------------------------------------------------------

func _screen(r: Rect2) -> Rect2:
	return Rect2(r.position * k, r.size * k)


## A part of the picture laid exactly over its own place (it can then move or turn a little about its centre).
func _region_sprite(region: Array, n: String) -> Node2D:
	var holder := Node2D.new()
	holder.name = n
	parts.add_child(holder)
	if art_tex == null:
		return holder
	var r := _rect(region)
	var at := AtlasTexture.new()
	at.atlas = art_tex
	at.region = r
	var spr := Sprite2D.new()
	spr.name = "Image"
	spr.texture = at
	spr.centered = true
	holder.add_child(spr)
	# the holder stands at the region's centre: it turns about the part's own centre
	holder.position = r.get_center()
	holder.set_meta("center", r.get_center())
	return holder


func _base(n: Node2D) -> Vector2:
	return n.get_meta("center", Vector2.ZERO)


## A loose wooden piece (a fastening, the board): the picture's own wood — `uv_quad` (texture points for the polygon's
## corners, so the grain runs along the piece) or `tex_center` (where on the picture its wood is centred) — darkened by
## `tint` to read apart from the top it lies on; a flat `color` without the art. `depth` px — its thickness, a darker
## copy under it (a block, not a sticker); a shadow under that and a darker edge.
func _piece(pts: PackedVector2Array, cfg: Dictionary, n: String) -> Polygon2D:
	var p := Polygon2D.new()
	p.name = n
	var shadow := Polygon2D.new()
	shadow.name = "Shadow"
	shadow.color = Color(0, 0, 0, 0.34)
	shadow.show_behind_parent = true
	p.add_child(shadow)
	var side := Polygon2D.new()
	side.name = "Side"
	side.show_behind_parent = true
	p.add_child(side)
	var edge := Line2D.new()
	edge.name = "Edge"
	edge.width = 2.5
	p.add_child(edge)
	parts.add_child(p)
	_set_piece_polygon(p, pts, cfg)
	return p


func _set_piece_polygon(p: Polygon2D, pts: PackedVector2Array, cfg: Dictionary) -> void:
	p.polygon = pts
	var col := Color.html(String(cfg.get("color", "#d8b27a")))
	var depth := float(cfg.get("depth", 0.0))
	if art_tex != null and (cfg.has("tex_center") or cfg.has("uv_quad")):
		p.texture = art_tex
		var uv := PackedVector2Array()
		if cfg.has("uv_quad") and (cfg["uv_quad"] as Array).size() == pts.size():
			uv = _points(cfg["uv_quad"])
		else:
			var c := Vector2.ZERO
			for q in pts:
				c += q
			c /= maxf(float(pts.size()), 1.0)
			var tc := v2(cfg["tex_center"])
			for q in pts:
				uv.append(tc + (q - c))
		p.uv = uv
		p.color = Color.html(String(cfg.get("tint", "#ffffff")))
		col = Color.html(String(cfg.get("edge_color", "#8a6238")))
		var side := p.get_node("Side") as Polygon2D
		side.texture = art_tex
		side.uv = uv
		side.color = p.color.darkened(0.42)
	else:
		p.color = col
		(p.get_node("Side") as Polygon2D).color = col.darkened(0.42)
	var down := PackedVector2Array()
	for q in pts:
		down.append(q + Vector2(0, depth))
	(p.get_node("Side") as Polygon2D).polygon = down
	(p.get_node("Side") as Polygon2D).visible = depth > 0.0
	var sh := PackedVector2Array()
	for q in pts:
		sh.append(q + Vector2(5, 7 + depth))
	(p.get_node("Shadow") as Polygon2D).polygon = sh
	var closed := PackedVector2Array(pts)
	closed.append(pts[0])
	(p.get_node("Edge") as Line2D).points = closed
	(p.get_node("Edge") as Line2D).default_color = col.darkened(0.35)


static func _points(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in a:
		out.append(Vector2(float(q[0]), float(q[1])))
	return out


static func _bounds(pts: PackedVector2Array) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var r := Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		r = r.expand(q)
	return r


static func _rect(a) -> Rect2:
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


func probe() -> Dictionary:
	var f := {}
	for id in fasten:
		var fd: Dictionary = fasten[id]
		f[id] = center_of(fd["hit"])
		f[id]["fits"] = fd["fits"]
		f[id]["visible"] = (fd["hit"] as Control).visible
	return {"step": step(), "fastenings": f, "stop": center_of(stop_hit), "stop_visible": stop_hit.visible,
		"screw": center_of(screw_hit), "screw_visible": screw_hit.visible, "strike": center_of(screw_hit),
		"timing": timing.probe() if timing.visible else {}, "turns": turns, "slips": slips,
		"board": center_of(board_hit), "board_visible": board_hit.visible, "tries_wrong": tries_wrong,
		"busy": _busy(), "stand_in": art_root.get_node_or_null("BenchStandIn") != null}
