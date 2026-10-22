class_name InventoryBag
extends PanelContainer
## The bag in the top bar: a strip of worn leather with SLOTS pockets (BagSlot), drawn in code.
## It renders GameState.inventory / StoryRunner.selected_item and never decides story logic.
##
##  - icons: res://assets/icons/<item_id>.png (tools/sync_icons.sh copies them from assets/icons);
##    an item without an icon shows a canvas patch with its first letter — a new icon needs no code;
##  - hover a pocket: tooltip with the item name (items.json), its short line (@item.<id>, data/story/
##    text) and what a click does;
##  - click: take the item in hand (StoryRunner.select_item) — the pocket glows, the cursor carries a
##    small icon (GameUi); click again or right-click: put it back;
##  - a received item flies into its pocket (StoryRunner.item_received; never on load);
##  - more items than pockets: ‹ › arrows (and the mouse wheel over the strip) page through.
## Sounds are requested, not played: `sound_requested(kind)` — "receive" | "select" | "deselect".
## The item under the pointer is announced, not voiced: `pocket_hover_changed(old, new)` when the pointer
## comes onto a pocket with an item (new = its id) or leaves it / the item under it changes (new = "" —
## arriving items never count as the player resting on a pocket). GameUi relays it to VoiceDirector.

signal sound_requested(kind: String)
signal pocket_hover_changed(old_item: String, new_item: String)

const SLOTS: int = 8
const SLOT_SIZE := Vector2(64, 64)
const SLOT_GAP: int = 8
const ICON_DIR := "res://assets/icons/"
const FLY_START_SIZE: float = 112.0
const FLY_SECONDS: float = 0.55
const FLY_STAGGER: float = 0.12
const TOOLTIP_W: float = 420.0

const LEATHER := Color(0.30, 0.185, 0.105)
const LEATHER_DARK := Color(0.12, 0.075, 0.045)
const THREAD := Color(0.84, 0.70, 0.47, 0.5)

static var _icon_cache: Dictionary = {}

var page: int = 0
var slots: Array[BagSlot] = []
var prev_button: Button
var next_button: Button
var empty_label: Label
var tooltip: PanelContainer
var tip_name: Label
var tip_desc: Label
var tip_action: Label
## Where flying icons are drawn (a full-screen Control above the rest of the UI); self if unset.
var fx_parent: Control = null
## Bottom edge of the top bar: the tooltip opens under it, over the scene.
var tooltip_top: float = 86.0

var _row: HBoxContainer
var _hover: BagSlot = null
var _hover_item: String = ""       # the item whose pocket the pointer came onto (pocket_hover_changed)
var _arriving: Dictionary = {}     # item_id -> flying BagSlot
var _batch: int = 0
var _batch_reset_queued: bool = false


func _init() -> void:
	name = "Bag"
	var sb := StyleBoxFlat.new()
	sb.bg_color = LEATHER
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = LEATHER_DARK
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 2)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_row = HBoxContainer.new()
	_row.name = "Pockets"
	_row.add_theme_constant_override("separation", SLOT_GAP)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.mouse_filter = Control.MOUSE_FILTER_PASS   # the wheel over a pocket reaches the strip
	add_child(_row)
	prev_button = _arrow("‹", "BagPrev", -1)
	_row.add_child(prev_button)
	for i in SLOTS:
		var s := BagSlot.new()
		s.name = "Slot%d" % i
		s.index = i
		s.custom_minimum_size = SLOT_SIZE
		s.mouse_filter = Control.MOUSE_FILTER_PASS   # clicks are accepted by the pocket, the wheel goes on
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.clicked.connect(_on_slot_clicked)
		s.mouse_entered.connect(_on_slot_hover.bind(s))
		s.mouse_exited.connect(_on_slot_unhover.bind(s))
		_row.add_child(s)
		slots.append(s)
	next_button = _arrow("›", "BagNext", 1)
	_row.add_child(next_button)

	# "The bag is empty" on a small dark plate over the middle pockets (not across the seams).
	var empty_center := CenterContainer.new()
	empty_center.name = "EmptyCenter"
	empty_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(empty_center)
	empty_label = Label.new()
	empty_label.name = "Empty"
	empty_label.theme_type_variation = &"BagEmptyLabel"
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.10, 0.065, 0.04, 0.92)
	plate.border_color = Color(0.84, 0.70, 0.47, 0.35)
	plate.set_border_width_all(1)
	plate.set_corner_radius_all(6)
	plate.content_margin_left = 16
	plate.content_margin_right = 16
	plate.content_margin_top = 3
	plate.content_margin_bottom = 5
	empty_label.add_theme_stylebox_override("normal", plate)
	empty_center.add_child(empty_label)

	tooltip = PanelContainer.new()
	tooltip.name = "BagTooltip"
	tooltip.theme_type_variation = &"BagTooltipPanel"
	var tip := StyleBoxFlat.new()   # the bag draws itself: the tooltip keeps its look with any theme
	tip.bg_color = Color(0.11, 0.08, 0.058, 0.97)
	tip.border_color = Color(0.68, 0.55, 0.35, 0.78)
	tip.set_border_width_all(2)
	tip.set_corner_radius_all(8)
	tip.shadow_color = Color(0, 0, 0, 0.45)
	tip.shadow_size = 8
	tip.shadow_offset = Vector2(0, 4)
	tip.content_margin_left = 16
	tip.content_margin_right = 16
	tip.content_margin_top = 10
	tip.content_margin_bottom = 12
	tooltip.add_theme_stylebox_override("panel", tip)
	tooltip.top_level = true
	tooltip.visible = false
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tooltip)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 4)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.add_child(tv)
	tip_name = Label.new()
	tip_name.name = "Name"
	tip_name.theme_type_variation = &"BagTooltipTitle"
	tip_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_name.custom_minimum_size = Vector2(TOOLTIP_W, 0)
	tv.add_child(tip_name)
	tip_desc = Label.new()
	tip_desc.name = "Desc"
	tip_desc.theme_type_variation = &"BagTooltipText"
	tip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_desc.custom_minimum_size = Vector2(TOOLTIP_W, 0)
	tv.add_child(tip_desc)
	tip_action = Label.new()
	tip_action.name = "Action"
	tip_action.theme_type_variation = &"BagTooltipHint"
	tip_action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_action.custom_minimum_size = Vector2(TOOLTIP_W, 0)
	tv.add_child(tip_action)


func _arrow(text: String, node_name: String, step: int) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = &"BagArrow"
	b.custom_minimum_size = Vector2(26, SLOT_SIZE.y)
	b.pressed.connect(func(): flip(step))
	return b


func _ready() -> void:
	empty_label.text = StoryData.text("@ui.inventory_empty")
	refresh()


# --- Data --------------------------------------------------------------------------

## The item's icon: res://assets/icons/<icon>.png, where <icon> is items.json `icon` (the pipeline's file name,
## e.g. photo_bridge → bridge_photo) or the item id itself. No file → null (a patch with a letter).
static func icon_for(item_id: String) -> Texture2D:
	if _icon_cache.has(item_id):
		return _icon_cache[item_id]
	var path := ICON_DIR + icon_name(item_id) + ".png"
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_icon_cache[item_id] = tex
	return tex


static func icon_name(item_id: String) -> String:
	var n := String(StoryData.item(item_id).get("icon", ""))
	return n if n != "" else item_id


static func item_hint(item_id: String) -> String:
	var key := "item." + item_id
	return StoryData.text("@" + key) if StoryData.texts.has(key) else ""


func pages() -> int:
	return maxi(1, ceili(float(GameState.inventory.size()) / float(SLOTS)))


func page_of(item_id: String) -> int:
	var i := GameState.inventory.find(item_id)
	return i / SLOTS if i >= 0 else -1


## Slot showing `item_id` on the current page, or null.
func slot_of(item_id: String) -> BagSlot:
	for s in slots:
		if s.item_id == item_id:
			return s
	return null


func visible_items() -> Array[String]:
	var out: Array[String] = []
	for s in slots:
		if s.item_id != "":
			out.append(s.item_id)
	return out


# --- Rendering ---------------------------------------------------------------------

func refresh() -> void:
	page = clampi(page, 0, pages() - 1)
	var inv: Array[String] = GameState.inventory
	for i in SLOTS:
		var s := slots[i]
		var k := page * SLOTS + i
		var id: String = inv[k] if k < inv.size() else ""
		s.item_id = id
		s.item_name = StoryData.item_name(id) if id != "" else ""
		s.icon = icon_for(id) if id != "" else null
		s.selected = id != "" and StoryRunner.selected_item == id
		s.arriving = _arriving.has(id)
		s.tooltip_text = ""
	var multi := pages() > 1
	for b in [prev_button, next_button]:
		b.disabled = not multi
		b.modulate.a = 1.0 if multi else 0.0
		b.mouse_filter = Control.MOUSE_FILTER_STOP if multi else Control.MOUSE_FILTER_IGNORE
	if multi:
		prev_button.disabled = page == 0
		next_button.disabled = page >= pages() - 1
	empty_label.visible = inv.is_empty()
	if _hover_item != "" and (_hover == null or _hover.item_id != _hover_item):
		_set_hover_item("")   # the item under the pointer changed (arrival, page flip): not a new rest
	if _hover != null and _hover.item_id == "":
		_on_slot_unhover(_hover)
	elif _hover != null:
		_show_tooltip(_hover)
	queue_redraw()


func flip(step: int) -> void:
	var p := clampi(page + step, 0, pages() - 1)
	if p == page:
		return
	page = p
	refresh()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_LEFT:
			flip(-1)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			flip(1)
			accept_event()


func _draw() -> void:
	# Stitched seam along the strip and a worn highlight on its upper edge.
	var r := Rect2(Vector2.ZERO, size).grow(-5.0)
	draw_line(Vector2(12, 3), Vector2(size.x - 12, 3), Color(1.0, 0.9, 0.7, 0.10), 1.0)
	for e in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.position.x, r.end.y), r.end]]:
		draw_dashed_line(e[0] + Vector2(6, 0), e[1] - Vector2(6, 0), THREAD, 1.3, 5.0)
	# Page dots under the pockets when the bag has more than one page.
	var n := pages()
	if n > 1:
		var cx := size.x / 2.0 - (n - 1) * 7.0
		for i in n:
			var c := Color(1.0, 0.84, 0.52, 0.95) if i == page else Color(0.84, 0.70, 0.47, 0.35)
			draw_circle(Vector2(cx + i * 14.0, size.y - 3.0), 2.6, c)


# --- Hover and click ------------------------------------------------------------------

func _on_slot_hover(s: BagSlot) -> void:
	_hover = s
	if s.item_id != "":
		_show_tooltip(s)
	_set_hover_item(s.item_id)


func _on_slot_unhover(s: BagSlot) -> void:
	if _hover == s:
		_hover = null
	tooltip.visible = false
	if _hover == null:
		_set_hover_item("")


func _set_hover_item(item_id: String) -> void:
	if item_id == _hover_item:
		return
	var old := _hover_item
	_hover_item = item_id
	pocket_hover_changed.emit(old, item_id)


## The item the pointer rests on ("" — none).
func hover_item() -> String:
	return _hover_item


## The tooltip is open for `item_id` under the pointer and no icon is flying in.
func tooltip_shows(item_id: String) -> bool:
	return item_id != "" and _hover_item == item_id and _hover != null and _hover.item_id == item_id \
		and tooltip.visible and not is_animating()


func _show_tooltip(s: BagSlot) -> void:
	if s.item_id == "":
		tooltip.visible = false
		return
	tip_name.text = StoryData.item_name(s.item_id)
	var hint := item_hint(s.item_id)
	tip_desc.text = hint
	tip_desc.visible = hint != ""
	tip_action.text = StoryData.text("@ui.bag_put_back" if s.selected else "@ui.bag_take")
	tooltip.visible = true
	tooltip.reset_size()
	_place_tooltip.call_deferred(s)


func _place_tooltip(s: BagSlot) -> void:
	if not is_instance_valid(s) or not tooltip.visible:
		return
	tooltip.reset_size()
	var r := s.get_global_rect()
	var w := tooltip.size.x
	tooltip.global_position = Vector2(clampf(r.get_center().x - w / 2.0, 8.0, 1920.0 - w - 8.0), tooltip_top + 6.0)


func _on_slot_clicked(s: BagSlot, button_index: int) -> void:
	if s.item_id == "":
		if button_index == MOUSE_BUTTON_RIGHT:
			put_back()
		return
	if button_index == MOUSE_BUTTON_RIGHT:
		put_back()
		return
	click_item(s.item_id)


## The same as a left click on the item's pocket: take it in hand, or put it back when already held.
## Returns the selection after the click. Used by tests and the probe as "click on the slot".
func click_item(item_id: String) -> String:
	if not GameState.has_item(item_id):
		return StoryRunner.selected_item
	var p := page_of(item_id)
	if p >= 0 and p != page:
		page = p
		refresh()
	StoryRunner.select_item(item_id)   # toggles: same item again → nothing selected
	sound_requested.emit("select" if StoryRunner.selected_item == item_id else "deselect")
	return StoryRunner.selected_item


## Put the held item back into the bag (right click, second click).
func put_back() -> void:
	if StoryRunner.selected_item == "":
		return
	StoryRunner.select_item("")
	sound_requested.emit("deselect")


# --- Item arrival ----------------------------------------------------------------------

## The icon of a newly received item flies from `from` (screen point, e.g. above Agata) into its
## pocket. Items granted together fly one after another; one "receive" sound per batch.
func fly_in(item_id: String, from: Vector2) -> void:
	if not GameState.has_item(item_id) or _arriving.has(item_id):
		return
	var p := page_of(item_id)
	if p >= 0:
		page = p
	var delay := _batch * FLY_STAGGER
	var first := _batch == 0
	from += Vector2(_batch * 36.0, -_batch * 10.0)   # a batch starts fanned out, not stacked
	_batch += 1
	if not _batch_reset_queued:
		_batch_reset_queued = true
		_reset_batch.call_deferred()
	var fly := BagSlot.new()
	fly.name = "Fly_" + item_id
	fly.loose = true
	fly.item_id = item_id
	fly.item_name = StoryData.item_name(item_id)
	fly.icon = icon_for(item_id)
	fly.top_level = true
	fly.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fly.size = Vector2(FLY_START_SIZE, FLY_START_SIZE)
	fly.global_position = from - fly.size / 2.0
	fly.modulate.a = 0.0
	(fx_parent if fx_parent != null else self).add_child(fly)
	fly.pivot_offset = fly.size / 2.0
	fly.scale = Vector2(0.6, 0.6)
	_arriving[item_id] = fly
	refresh()
	var tw := fly.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(fly, "modulate:a", 1.0, 0.14)
	tw.parallel().tween_property(fly, "scale", Vector2(1.08, 1.08), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.12)
	tw.tween_method(_fly_step.bind(fly, from, item_id), 0.0, 1.0, FLY_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_land.bind(fly, item_id, first))


func _reset_batch() -> void:
	_batch = 0
	_batch_reset_queued = false


func _fly_target(item_id: String) -> Rect2:
	var s := slot_of(item_id)
	if s != null:
		return s.get_global_rect()
	return Rect2(get_global_rect().get_center() - SLOT_SIZE / 2.0, SLOT_SIZE)


func _fly_step(t: float, fly: BagSlot, from: Vector2, item_id: String) -> void:
	if not is_instance_valid(fly):
		return
	var target := _fly_target(item_id)
	var to := target.get_center()
	var ctrl := Vector2(lerpf(from.x, to.x, 0.25), to.y + 40.0)   # rises first, then glides over
	var u := 1.0 - t
	var p := u * u * from + 2.0 * u * t * ctrl + t * t * to
	var sz := lerpf(FLY_START_SIZE, target.size.x - 10.0, t)
	fly.size = Vector2(sz, sz)
	fly.pivot_offset = fly.size / 2.0
	fly.scale = Vector2.ONE * lerpf(1.08, 1.0, t)
	fly.global_position = p - fly.size / 2.0


func _land(fly: BagSlot, item_id: String, first: bool) -> void:
	if is_instance_valid(fly):
		fly.queue_free()
	_arriving.erase(item_id)
	refresh()
	var s := slot_of(item_id)
	if s != null:
		s.pulse()
	if first:
		sound_requested.emit("receive")


func is_animating() -> bool:
	return not _arriving.is_empty()


## Load / new game while icons are in flight: drop the flights, pockets show their items at once.
func cancel_flights() -> void:
	for id in _arriving.keys():
		var f = _arriving[id]
		if is_instance_valid(f):
			f.queue_free()
	_arriving.clear()
	_batch = 0
	refresh()


# --- Probe ----------------------------------------------------------------------------

func probe() -> Dictionary:
	var out := {"page": page, "pages": pages(), "slots": SLOTS, "items": {}, "selected": StoryRunner.selected_item,
		"animating": is_animating(), "tooltip": tooltip.visible}
	for s in slots:
		if s.item_id != "":
			var r := s.get_global_rect()
			out["items"][s.item_id] = {"x": r.get_center().x, "y": r.get_center().y, "icon": s.icon != null,
				"selected": s.selected, "slot": s.index}
	if pages() > 1:
		out["prev"] = _center(prev_button)
		out["next"] = _center(next_button)
	return out


func _center(c: Control) -> Dictionary:
	var r := c.get_global_rect()
	return {"x": r.get_center().x, "y": r.get_center().y}
