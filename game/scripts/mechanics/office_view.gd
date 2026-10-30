class_name OfficeView
extends Node2D
## The mill office as the office mirror shows it — now (canon: «Зеркало показывает нынешний вид со своего
## прежнего места»). Lives inside a SubViewport of OfficeMirrorPanel and is redrawn every frame, so what
## happens at the mill (Pavel's lantern at the gap, his hook, the bar) is in the glass the same frame it
## happens.
## Art: «Контора — вид на дверь» (партия 3): M3_view_bg (the door, three hinges, the empty bar brackets; the
## fallen shelf of the delivery lies outside `region` — Р4, Director 29.10: no shelf anywhere), and layers on the same 1672×941 canvas, placed at (0, 0): the lantern light in the gap,
## the hook (drawn at the lowered bar), the bar in its brackets. Order: bg → light → hook → bar. The bar
## lifted is the same layer 46 px higher (bar_up_translation_px of the delivery), the hook goes up with it.
## Data (mechanic.office.art): images, `region` [x, y, w, h] — the part of the canvas the glass shows,
## `gap` [top, bottom] — the gap's span in canvas px, `bar_y` — the bar's centre, `lift_px`.

var spec: Dictionary = {}
var light_on: bool = false
var hook_visible: bool = false
var hook_frac: float = 0.0       # 0 top of the gap … 1 bottom
var hook_bar: float = 0.5        # where the hook meets the bar (HookPuzzle.bar)
var bar_lift: float = 0.0        # 0 in the brackets … 1 out (lifted by the hook)
var door_given: bool = false     # the door has moved a little (bar out)
var door_shut: bool = true       # the door not yet opened together with Pavel (Р4: no shelf anywhere — the glass shows only the door)

var _art: Node2D
var _light: Sprite2D
var _hook: Sprite2D
var _bar: Sprite2D
var _gap: Vector2 = Vector2(95, 705)
var _lift_px: float = 46.0


func setup(p_spec: Dictionary) -> void:
	spec = p_spec
	var size := MechanicPanel.v2(spec.get("size", [297, 582]))
	var art: Dictionary = spec.get("art", {})
	var reg: Array = art.get("region", [520, 80, 380, 660])
	var g: Array = art.get("gap", [95, 705])
	_gap = Vector2(float(g[0]), float(g[1]))
	_lift_px = float(art.get("lift_px", 46.0))
	_art = Node2D.new()
	_art.name = "Art"
	var k := Vector2(size.x / float(reg[2]), size.y / float(reg[3]))
	_art.scale = k
	_art.position = -Vector2(float(reg[0]), float(reg[1])) * k
	add_child(_art)
	_layer("Office", String(art.get("bg", "")))
	_light = _layer("Light", String(art.get("light", "")))
	_hook = _layer("Hook", String(art.get("hook", "")))
	_bar = _layer("Bar", String(art.get("bar", "")))
	refresh()


func _layer(node_name: String, image: String) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = node_name
	s.centered = false
	if image != "" and ResourceLoader.exists(image):
		s.texture = load(image)
	_art.add_child(s)
	return s


## The bar's centre line in canvas px (lifted with `bar_lift`).
func bar_y() -> float:
	return float(spec.get("art", {}).get("bar_y", 346.0)) - _lift_px * bar_lift


## Where the hook is along the gap, canvas px (the hook layer is drawn at the bar: offset 0 there).
func hook_y() -> float:
	return lerpf(_gap.x, _gap.y, hook_frac)


func refresh() -> void:
	if _light == null:
		return
	_light.visible = light_on
	_bar.position = Vector2(0, -_lift_px * bar_lift)
	_hook.visible = hook_visible
	var at_bar := lerpf(_gap.x, _gap.y, hook_bar)
	_hook.position = Vector2(0, hook_y() - at_bar - _lift_px * bar_lift)
