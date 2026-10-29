class_name BagSlot
extends Control
## One pocket of the bag strip (InventoryBag), drawn in code — no pictures besides the item icon:
## a darker leather pocket with a stitched seam and a shadowed opening at the top; the item icon
## (res://assets/icons/<item_id>.png) sits in it with a soft drop shadow. Without an icon the item
## shows as a canvas patch with the first letter of its name, so a missing icon never breaks the bag.
## `loose = true` draws only the item (no pocket): the flying icon and the icon carried by the cursor.
## «Рассмотреть» (F9): a double click on the pocket, or a click on the magnifier in its corner (shown while
## the pointer is over a pocket with an item), asks for the item's close-up — `examine_requested`.

signal clicked(slot: BagSlot, button_index: int)
signal examine_requested(slot: BagSlot)

const BADGE := 24.0   # the magnifier in the pocket's lower right corner

const LEATHER_POCKET := Color(0.17, 0.105, 0.062)
const LEATHER_EDGE := Color(0.075, 0.045, 0.028)
const THREAD := Color(0.84, 0.70, 0.47, 0.55)
const HOVER_RIM := Color(0.96, 0.82, 0.55, 0.55)
const SELECT_RIM := Color(1.0, 0.83, 0.46, 1.0)
const SELECT_FILL := Color(0.33, 0.21, 0.11)
const GLOW := Color(1.0, 0.74, 0.33, 0.38)
const PATCH := Color(0.80, 0.72, 0.56)
const PATCH_SEAM := Color(0.42, 0.30, 0.18, 0.85)
const PATCH_INK := Color(0.29, 0.19, 0.11)

var index: int = -1
var item_id: String = "":
	set(v):
		item_id = v
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if v != "" else Control.CURSOR_ARROW
		queue_redraw()
var item_name: String = "":
	set(v):
		item_name = v
		queue_redraw()
var icon: Texture2D = null:
	set(v):
		icon = v
		queue_redraw()
var selected: bool = false:
	set(v):
		if selected != v:
			selected = v
			queue_redraw()
var hovered: bool = false:
	set(v):
		if hovered != v:
			hovered = v
			queue_redraw()
var arriving: bool = false:   # the item's icon is still flying in: the pocket waits empty
	set(v):
		if arriving != v:
			arriving = v
			queue_redraw()
var loose: bool = false
var _pulse_tween: Tween = null


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # 192 px icon → 56 px stays clean
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	mouse_entered.connect(func(): hovered = true)
	mouse_exited.connect(func(): hovered = false)
	resized.connect(func(): pivot_offset = size / 2.0)
	pivot_offset = size / 2.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and \
			(event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		accept_event()
		if event.button_index == MOUSE_BUTTON_LEFT and item_id != "" and not loose and \
				(event.double_click or badge_rect().has_point(event.position)):
			examine_requested.emit(self)
			return
		clicked.emit(self, event.button_index)


## The magnifier's rect in the pocket (local px).
func badge_rect() -> Rect2:
	return Rect2(size - Vector2(BADGE + 1, BADGE + 1), Vector2(BADGE, BADGE))


## Short "landed" bounce with a warm flash (an item has just arrived in this pocket).
func pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	scale = Vector2.ONE
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, "scale", Vector2(1.14, 1.14), 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(self, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func has_item() -> bool:
	return item_id != ""


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if not loose:
		_draw_pocket(r)
	if item_id == "" or arriving:
		return
	var inset := 5.0 if not loose else 0.0
	var ir := r.grow(-inset)
	if selected and not loose:
		ir = Rect2(ir.position + Vector2(0, -2), ir.size)   # lifted out of the pocket a little
	if icon != null:
		var shadow := Rect2(ir.position + Vector2(2, 3), ir.size)
		draw_texture_rect(icon, shadow, false, Color(0, 0, 0, 0.38))
		draw_texture_rect(icon, ir, false)
	else:
		_draw_patch(ir.grow(-4.0 if not loose else -6.0))
	if hovered and not loose:
		_draw_badge()


func _draw_pocket(r: Rect2) -> void:
	# J (Director 29.10, стр. 208: «ближе к стилю паузы»): a niche cut into the board — a dark recess with its upper
	# edge in shadow and a fine gold bead round it, as on the pause board's carvings (was a stitched leather pocket).
	var sb := StyleBoxFlat.new()
	sb.bg_color = SELECT_FILL if selected else Color(0.075, 0.046, 0.028, 0.92)
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.03, 0.018, 0.01)
	if selected:
		sb.shadow_color = GLOW
		sb.shadow_size = 9
	draw_style_box(sb, r)
	draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4, 7)), Color(0, 0, 0, 0.38))   # the cut's shadow
	var bead := StyleBoxFlat.new()
	bead.draw_center = false
	bead.set_border_width_all(1)
	bead.border_color = Color(0.93, 0.76, 0.45, 0.55)
	bead.set_corner_radius_all(3)
	draw_style_box(bead, r.grow(-3.0))
	draw_line(Vector2(6, r.size.y - 2), Vector2(r.size.x - 6, r.size.y - 2), Color(1.0, 0.86, 0.6, 0.12), 1.0)   # lit lower lip
	if selected:
		var rim := StyleBoxFlat.new()
		rim.draw_center = false
		rim.set_border_width_all(3)
		rim.border_color = SELECT_RIM
		rim.set_corner_radius_all(8)
		draw_style_box(rim, r.grow(1.0))
	elif hovered and item_id != "":
		var hr := StyleBoxFlat.new()
		hr.draw_center = false
		hr.set_border_width_all(2)
		hr.border_color = HOVER_RIM
		hr.set_corner_radius_all(7)
		draw_style_box(hr, r)


## The magnifier («Рассмотреть»): a brass lens with a handle on a dark disc, over the icon's corner.
func _draw_badge() -> void:
	var b := badge_rect()
	var c := b.get_center()
	draw_circle(c, BADGE * 0.5, Color(0.08, 0.05, 0.03, 0.88))
	draw_arc(c, BADGE * 0.5, 0.0, TAU, 24, Color(0.84, 0.70, 0.47, 0.8), 1.2, true)
	var lc := c + Vector2(-2.5, -2.5)
	draw_circle(lc, 5.6, Color(0.75, 0.85, 0.95, 0.25))
	draw_arc(lc, 5.6, 0.0, TAU, 20, SELECT_RIM, 2.0, true)
	draw_line(lc + Vector2(4.2, 4.2), lc + Vector2(9.0, 9.0), SELECT_RIM, 2.6, true)


## Placeholder for an item without an icon: a canvas patch with a seam and the name's first letter.
func _draw_patch(pr: Rect2) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PATCH
	sb.set_corner_radius_all(4)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(1, 2)
	draw_style_box(sb, pr)
	_dashed_rect(pr.grow(-3.0), PATCH_SEAM, 1.2, 3.0)
	var letter := item_name.strip_edges().substr(0, 1).to_upper() if item_name != "" else item_id.substr(0, 1).to_upper()
	var font: Font = get_theme_font("font", "BagSlot")
	var fsize := int(pr.size.y * 0.62)
	var asc := font.get_ascent(fsize)
	var desc := font.get_descent(fsize)
	var baseline := pr.position.y + (pr.size.y + asc - desc) / 2.0
	draw_string(font, Vector2(pr.position.x, baseline), letter, HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, fsize, PATCH_INK)


func _dashed_rect(r: Rect2, color: Color, width: float, dash: float) -> void:
	var a := r.position
	var b := Vector2(r.end.x, r.position.y)
	var c := r.end
	var d := Vector2(r.position.x, r.end.y)
	var k := 3.0   # leave the corners free, like a real seam turning
	draw_dashed_line(a + Vector2(k, 0), b - Vector2(k, 0), color, width, dash)
	draw_dashed_line(b + Vector2(0, k), c - Vector2(0, k), color, width, dash)
	draw_dashed_line(c - Vector2(k, 0), d + Vector2(k, 0), color, width, dash)
	draw_dashed_line(d - Vector2(0, k), a + Vector2(0, k), color, width, dash)
