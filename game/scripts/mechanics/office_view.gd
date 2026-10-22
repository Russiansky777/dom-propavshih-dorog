class_name OfficeView
extends Node2D
## The mill office as the office mirror shows it — now (canon: «Зеркало показывает нынешний вид со своего
## прежнего места»). Lives inside a SubViewport of OfficeMirrorPanel and is redrawn every frame, so what
## happens at the mill (Pavel's lantern at the gap, his hook, the bar) is in the glass the same frame it
## happens. Stand-in art until the ordered «контора изнутри, вид на дверь» (BRIEF_CHATGPT_v4 §C1):
## a crop of the delivered office painting (M3) round its door, with the fallen shelf, the bar in its
## brackets, the gap, the light and the hook drawn by the engine. Coordinates — the viewport's pixels
## (data: mechanic.office).

var spec: Dictionary = {}
var light_on: bool = false
var hook_visible: bool = false
var hook_frac: float = 0.0       # 0 top of the gap … 1 bottom
var bar_lift: float = 0.0        # 0 in the brackets … 1 out (lifted by the hook)
var door_given: bool = false     # the door has moved a little (bar out)
var shelf_down: bool = true      # the shelf still lies on the door

var _bg: Sprite2D
var _shelf: Node2D
var _bar: Node2D
var _light: Node2D
var _hook: Line2D
var _gap_dark: Polygon2D


func setup(p_spec: Dictionary) -> void:
	spec = p_spec
	var size := MechanicPanel.v2(spec.get("size", [297, 582]))
	var reg: Array = spec.get("region", [419, 52, 284, 557])
	_bg = Sprite2D.new()
	_bg.name = "Office"
	_bg.centered = false
	var img := String(spec.get("image", ""))
	if ResourceLoader.exists(img):
		var at := AtlasTexture.new()
		at.atlas = load(img)
		at.region = Rect2(float(reg[0]), float(reg[1]), float(reg[2]), float(reg[3]))
		_bg.texture = at
		_bg.scale = Vector2(size.x / float(reg[2]), size.y / float(reg[3]))
	_bg.modulate = Color(0.78, 0.76, 0.74)   # the office is dim: a year with the shutters shut
	add_child(_bg)
	var gap: Dictionary = spec.get("gap", {})
	var gx := float(gap.get("x", 244))
	var top := float(gap.get("top", 62))
	var bottom := float(gap.get("bottom", 550))
	_gap_dark = Polygon2D.new()
	_gap_dark.name = "Gap"
	_gap_dark.color = Color(0.03, 0.025, 0.02, 0.95)
	add_child(_gap_dark)
	_light = Node2D.new()
	_light.name = "Light"
	var strip := Polygon2D.new()
	strip.name = "Strip"
	strip.color = Color(1.0, 0.86, 0.52, 0.95)
	strip.polygon = PackedVector2Array([Vector2(gx - 2.5, top + 6), Vector2(gx + 2.5, top + 6), Vector2(gx + 2.5, bottom - 6), Vector2(gx - 2.5, bottom - 6)])
	_light.add_child(strip)
	var steps := 6
	for i in steps:
		var y := lerpf(top + 30, bottom - 30, float(i) / float(steps - 1))
		var g := PlaceholderArt.glow(Vector2(gx, y), 38.0, Color(1.0, 0.72, 0.35, 0.55))
		_light.add_child(g)
	add_child(_light)
	_shelf = Node2D.new()
	_shelf.name = "Shelf"
	var board := Polygon2D.new()
	board.color = Color(0.20, 0.14, 0.09)
	board.polygon = PlaceholderArt._points(spec.get("shelf", [[0, 520], [60, 576], [236, 332], [198, 300]]))
	_shelf.add_child(board)
	var edge := Line2D.new()
	edge.points = board.polygon
	edge.closed = true
	edge.width = 2.0
	edge.default_color = Color(0.42, 0.31, 0.2)
	_shelf.add_child(edge)
	for w in spec.get("weights", []):
		var c := Polygon2D.new()
		c.color = Color(0.12, 0.12, 0.13)
		c.polygon = PlaceholderArt.circle_points(Vector2(float(w[0]), float(w[1])), float(w[2]))
		_shelf.add_child(c)
	add_child(_shelf)
	_bar = Node2D.new()
	_bar.name = "Bar"
	var b: Dictionary = spec.get("bar", {})
	var by := bar_y()
	var x0 := float(b.get("x0", 136))
	var x1 := float(b.get("x1", 252))
	var rod := Polygon2D.new()
	rod.name = "Rod"
	rod.color = Color(0.16, 0.16, 0.17)
	rod.polygon = PackedVector2Array([Vector2(x0, by - 5), Vector2(x1, by - 5), Vector2(x1, by + 5), Vector2(x0, by + 5)])
	_bar.add_child(rod)
	add_child(_bar)
	for bx in [x1 - 12.0, x0 + 14.0]:
		var br := Polygon2D.new()
		br.name = "Bracket"
		br.color = Color(0.1, 0.1, 0.1)
		br.polygon = PackedVector2Array([Vector2(bx - 6, by - 11), Vector2(bx + 6, by - 11), Vector2(bx + 6, by + 11), Vector2(bx - 6, by + 11)])
		add_child(br)
	_hook = Line2D.new()
	_hook.name = "Hook"
	_hook.width = 3.0
	_hook.default_color = Color(0.32, 0.31, 0.3)
	_hook.joint_mode = Line2D.LINE_JOINT_ROUND
	add_child(_hook)
	refresh()


func bar_y() -> float:
	var gap: Dictionary = spec.get("gap", {})
	var top := float(gap.get("top", 62))
	var bottom := float(gap.get("bottom", 550))
	return lerpf(top, bottom, float(spec.get("bar", {}).get("at", 0.5)))


func hook_y() -> float:
	var gap: Dictionary = spec.get("gap", {})
	return lerpf(float(gap.get("top", 62)), float(gap.get("bottom", 550)), hook_frac)


func refresh() -> void:
	var gap: Dictionary = spec.get("gap", {})
	var gx := float(gap.get("x", 244))
	var top := float(gap.get("top", 62))
	var bottom := float(gap.get("bottom", 550))
	var w := 7.0 if door_given else 2.5
	_gap_dark.polygon = PackedVector2Array([Vector2(gx - w, top), Vector2(gx + w, top), Vector2(gx + w, bottom), Vector2(gx - w, bottom)])
	_light.visible = light_on
	_shelf.visible = shelf_down
	_bar.position = Vector2(0, -26.0 * bar_lift)
	_bar.rotation_degrees = -4.0 * bar_lift
	_hook.visible = hook_visible
	if hook_visible:
		var hy := hook_y() - 26.0 * bar_lift
		_hook.points = PackedVector2Array([Vector2(gx + 1, top - 4), Vector2(gx, hy), Vector2(gx - 10, hy + 7), Vector2(gx - 15, hy - 1)])
