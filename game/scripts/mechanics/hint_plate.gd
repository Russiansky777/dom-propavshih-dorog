class_name HintPlate
extends Control
## A dark see-through plate under the words of a mini-game that lie over a painting (Director 16.11, 00:28: «подложку
## можем добавить где нужно»; the review of 15.11, предложение 3: the windlass's «Бревно должно лечь…» over the snow,
## the fishing's hint over the snowy fence, the knot's over the moss, the map's over the paper read on the limit).
## It stands in the labels' parent right under the first of them and hugs the words themselves — the rectangle of the
## characters the labels draw now, not the labels' boxes: a short line gets a short plate, two labels one under the
## other (the lantern's) share one plate, no words on screen — no plate. MechanicPanel.plate() makes it.

const PAD := Vector2(18, 9)
const BG := Color(0.07, 0.05, 0.035, 0.68)
const RADIUS := 8

var labels: Array[Label] = []
var words := Rect2()   # what the plate hugs: the labels' characters, in the parent's coordinates (tests)
var _key := ""
var _box: StyleBoxFlat = null


static func under(over: Array[Label]) -> HintPlate:
	var p := HintPlate.new()
	p.name = "HintPlate"
	p.labels = over
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var first := over[0]
	first.get_parent().add_child(p)
	first.get_parent().move_child(p, first.get_index())
	p.fit()
	return p


func _ready() -> void:
	_box = StyleBoxFlat.new()
	_box.bg_color = BG
	_box.set_corner_radius_all(RADIUS)
	_box.anti_aliasing = true


func _process(_dt: float) -> void:
	var k := ""
	for l in labels:
		if is_instance_valid(l):
			k += "%s|%s|%s|%s|%s|%d;" % [l.text, l.visible, l.position, l.size, l.scale, l.horizontal_alignment]
	if k != _key:
		_key = k
		fit()


## The rectangle of the characters of one label, in its parent's coordinates (empty — nothing drawn).
static func words_of(l: Label) -> Rect2:
	var r := Rect2()
	if l == null or not is_instance_valid(l) or not l.visible:
		return r
	var any := false
	for i in l.text.length():
		var b := l.get_character_bounds(i)
		if b.size.x <= 0.0 or b.size.y <= 0.0:
			continue
		r = r.merge(b) if any else b
		any = true
	if not any:
		return Rect2()
	return Rect2(l.position + r.position * l.scale, r.size * l.scale)


func fit() -> void:
	var r := Rect2()
	var any := false
	for l in labels:
		var w := words_of(l)
		if w.size.x <= 0.0:
			continue
		r = r.merge(w) if any else w
		any = true
	words = r
	visible = any
	if any:
		position = r.position - PAD
		size = r.size + PAD * 2.0
	queue_redraw()


func _draw() -> void:
	if _box != null and words.size.x > 0.0:
		draw_style_box(_box, Rect2(Vector2.ZERO, size))
