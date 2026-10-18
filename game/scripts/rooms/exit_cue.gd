class_name ExitCue
extends Node2D
## Visible mark of an exit that is NOT drawn in the art — off the frame edge (down towards the viewer,
## to a side) or along a path into the depth. Director 18.10: «Проход в галерею не интуитивен, что
## нужно нажать вниз». A light double chevron with a soft dark halo, at the frame edge in the exit's
## direction, half-transparent and slowly «breathing»; while the pointer is on the exit (GameUi hover)
## or the reveal key is down it turns brighter and warmer and leans forward. During a dialogue, a panel
## or the plan the marks fade out (GameUi sets ExitCue.suppressed).
##
## Exits through a door/opening drawn in the art get no mark (cue "door"): hovering one shows its
## caption with the destination icon (GameUi); the cursor stays the ordinary one (UiCursors, 18.10).
##
## Data — data/story/rooms/<LOC>.json → exits[]:
##   "cue": "door" | "left" | "right" | "down" | "up"   — explicit (wins);
##   "cue_at": [x, y]                                     — optional mark position (screen px).
## Without `cue`: `side` left/right/bottom → left/right/down ("back" → door); else a rect touching a
## frame edge → that edge (two edges: the one the rect runs along — tall → side, wide → bottom); else
## "door" (an inner rect is a drawn door/opening; tools/validate_rooms.py warns to make it explicit).
## The same rules: tools/validate_rooms.py::exit_cue. Placement: a direction that matches a touched
## edge puts the mark at that edge (EDGE_INSET from it, along the rect); otherwise at the rect centre.

const FRAME := Vector2(1920, 1080)
const DIRS: Array[String] = ["left", "right", "down", "up"]
const EDGE_TOL := 8.0          # a rect this close to the frame edge «touches» it
const EDGE_INSET := 44.0       # chevron centre ↔ frame edge
const SIDE_MARGIN := 96.0      # a bottom mark stays this far from the frame corners
const TOP_SAFE := 150.0        # a side mark never rises into the top bar / bag (TOP_H 80 + room)
const BOTTOM_SAFE := 1080.0 - 70.0
## Shape (1920×1080 px): chevron width, depth, stroke, gap between the two chevrons.
const W := 52.0
const D := 21.0
const STROKE := 7.0
const GAP := 18.0
const BREATH_S := 2.6
const COLOR_IDLE := Color(0.96, 0.92, 0.84)      # UiTheme.CREAM, a touch lighter
const COLOR_HOT := Color(1.0, 0.89, 0.64)        # UiTheme.GOLD_BRIGHT
const ALPHA_IDLE := 0.74
const ALPHA_CLOSED := 0.50                       # closed / not built yet: still there, quieter
const MARK_CANVAS := 96.0                        # texture size (the mark is drawn centred on it)

## Marks fade out while a dialogue / panel / the plan is open (set by GameUi every frame).
static var suppressed: bool = false
static var _tex: Dictionary = {}

var direction: String = "down"
var hot: bool = false          # pointer on the exit (GameUi)
var revealed: bool = false     # reveal key (GameUi → HotspotReveal)
var exit_node: Node = null     # StoryExit, for is_open()
var _t: float = 0.0
var _alpha: float = 0.0        # eased (rooms fade the marks in on entry)
var _hot_k: float = 0.0        # 0 idle … 1 hot, eased


## {dir, at: Vector2, source: "cue"|"side"|"edge"|"default", edges: Array[String]} for an exit dict
## and its rect (RoomBuilder.exit_geometry).
static func classify(ex: Dictionary, rect: Rect2) -> Dictionary:
	var edges := touched_edges(rect)
	var dir := ""
	var source := ""
	var cue := String(ex.get("cue", ""))
	if cue != "":
		dir = cue
		source = "cue"
	else:
		match String(ex.get("side", "")):
			"left":
				dir = "left"
			"right":
				dir = "right"
			"bottom":
				dir = "down"
			"back":
				dir = "door"
		if dir != "":
			source = "side"
		elif not edges.is_empty():
			source = "edge"
			if edges.size() == 1:
				dir = edges[0]
			elif edges.has("down"):
				var side_edge: String = "left" if edges.has("left") else "right"
				dir = side_edge if rect.size.y >= rect.size.x else "down"
			else:
				dir = edges[0]
		else:
			dir = "door"
			source = "default"
	var at := rect.get_center()
	if ex.has("cue_at"):
		var p: Array = ex["cue_at"]
		at = Vector2(float(p[0]), float(p[1]))
	elif edges.has(dir):
		at = edge_point(dir, rect)
	return {"dir": dir, "at": at, "source": source, "edges": edges}


## Frame edges the rect touches, as mark directions ("down" = the bottom edge). The top edge is the
## UI bar: never an exit edge.
static func touched_edges(rect: Rect2) -> Array[String]:
	var out: Array[String] = []
	if rect.position.x <= EDGE_TOL:
		out.append("left")
	if rect.end.x >= FRAME.x - EDGE_TOL:
		out.append("right")
	if rect.end.y >= FRAME.y - EDGE_TOL:
		out.append("down")
	return out


static func edge_point(dir: String, rect: Rect2) -> Vector2:
	var c := rect.get_center()
	match dir:
		"down":
			return Vector2(clampf(c.x, SIDE_MARGIN, FRAME.x - SIDE_MARGIN), FRAME.y - EDGE_INSET)
		"left":
			return Vector2(EDGE_INSET, clampf(c.y, TOP_SAFE, BOTTOM_SAFE))
		"right":
			return Vector2(FRAME.x - EDGE_INSET, clampf(c.y, TOP_SAFE, BOTTOM_SAFE))
	return c


## Unit vector of a direction (screen: +y is down).
static func dir_vector(dir: String) -> Vector2:
	match dir:
		"left":
			return Vector2.LEFT
		"right":
			return Vector2.RIGHT
		"up":
			return Vector2.UP
	return Vector2.DOWN


## Screen rect the mark may cover at its brightest (hot: scaled and pushed forward) — for the
## layout checks (top bar, frame, exit rect).
func covered_rect() -> Rect2:
	var s := 1.18
	var halo := (STROKE + 13.0) * 0.5   # the widest shadow stroke (textures())
	var half := Vector2(W * 0.5 + halo, D * 0.5 + GAP * 0.5 + halo) * s
	if direction == "left" or direction == "right":
		half = Vector2(half.y, half.x)
	var r := Rect2(global_position - half, half * 2.0)
	r = r.merge(Rect2(r.position + dir_vector(direction) * 6.0, r.size))   # leaning forward
	return r.merge(Rect2(r.position + Vector2(0, 2.5), r.size))           # shadow offset


func current_alpha() -> float:
	return _alpha


func is_hot() -> bool:
	return hot or revealed


func _ready() -> void:
	z_index = 4096            # above the occluders and the drizzle; the UI CanvasLayer stays above it
	z_as_relative = false
	_t = randf() * BREATH_S   # neighbouring marks do not breathe in step


func _process(delta: float) -> void:
	_t += delta
	var open := true
	if exit_node != null and is_instance_valid(exit_node) and exit_node.has_method("is_open"):
		open = bool(exit_node.call("is_open")) and (not exit_node.has_method("target_exists") or bool(exit_node.call("target_exists")))
	var want_hot := 1.0 if is_hot() else 0.0
	_hot_k = move_toward(_hot_k, want_hot, delta * 6.0)
	var base := ALPHA_IDLE if open else ALPHA_CLOSED
	var target := 0.0 if suppressed else lerpf(base, 1.0, _hot_k)
	_alpha = move_toward(_alpha, target, delta * 2.5)
	queue_redraw()


func _draw() -> void:
	if _alpha <= 0.003:
		return
	var breath := 0.5 + 0.5 * sin(_t * TAU / BREATH_S)            # 0…1
	var a := _alpha * lerpf(0.78 + 0.22 * breath, 1.0, _hot_k)    # idle: alpha breathes ±11 %
	var lean := lerpf(3.0 * breath, 6.0, _hot_k)                    # leans towards the exit
	var s := lerpf(1.0, 1.18, _hot_k)
	var col := COLOR_IDLE.lerp(COLOR_HOT, _hot_k)
	var rot := 0.0
	match direction:
		"up":
			rot = PI
		"left":
			rot = PI * 0.5
		"right":
			rot = -PI * 0.5
	var tex := textures()
	var off := Vector2(0, lean).rotated(rot)
	var half: Vector2 = (tex["mark"] as Texture2D).get_size() * 0.5
	# Soft dark halo a little below (screen space) — reads on snow and on dark floors alike.
	draw_set_transform(off + Vector2(0, 2.5), rot, Vector2(s, s))
	draw_texture(tex["shadow"], -half, Color(1, 1, 1, a))
	draw_set_transform(off, rot, Vector2(s, s))
	draw_texture(tex["mark"], -half, Color(col.r, col.g, col.b, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The mark pointing down, rasterised once from SVG (antialiased, round caps; two chevrons — the
## trailing one fainter) and its soft shadow (stacked faint strokes). White mark: tinted by modulate.
static func textures() -> Dictionary:
	if not _tex.is_empty():
		return _tex
	var c := MARK_CANVAS * 0.5
	var mark := ""
	var shadow := ""
	for i in 2:
		var y0 := c + GAP * 0.5 - GAP * float(i)   # i 0: the leading chevron (towards the exit)
		var k := 1.0 if i == 0 else 0.55
		var line := "<polyline points='%.1f,%.1f %.1f,%.1f %.1f,%.1f'" % [c - W * 0.5, y0 - D * 0.5, c, y0 + D * 0.5, c + W * 0.5, y0 - D * 0.5]
		mark += "%s stroke-width='%.1f' stroke-opacity='%.2f'/>" % [line, STROKE, k]
		for w in [[STROKE + 13.0, 0.14], [STROKE + 8.0, 0.20], [STROKE + 3.5, 0.32]]:
			shadow += "%s stroke-width='%.1f' stroke-opacity='%.3f'/>" % [line, w[0], w[1] * k]
	var head := "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d'><g fill='none' stroke='%s' stroke-linecap='round' stroke-linejoin='round'>"
	_tex["mark"] = _svg_texture(head % [int(MARK_CANVAS), int(MARK_CANVAS), "#ffffff"] + mark + "</g></svg>")
	_tex["shadow"] = _svg_texture(head % [int(MARK_CANVAS), int(MARK_CANVAS), "#0d0805"] + shadow + "</g></svg>")
	return _tex


static func _svg_texture(svg: String) -> Texture2D:
	var img := Image.new()
	var err := img.load_svg_from_string(svg, 1.0)
	if err != OK or img.is_empty():
		push_warning("ExitCue: SVG rasterisation failed (%d); a plain mark is used" % err)
		img = Image.create(int(MARK_CANVAS), int(MARK_CANVAS), false, Image.FORMAT_RGBA8)
		var c := MARK_CANVAS * 0.5
		for y in range(int(c + 4), int(c + 12)):
			for x in range(int(c - 14), int(c + 14)):
				img.set_pixel(x, y, Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)
