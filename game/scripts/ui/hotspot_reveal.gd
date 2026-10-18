class_name HotspotReveal
extends Control
## The reveal key (Space, input action `reveal_hotspots`): for DURATION seconds every active hotspot
## and every exit of the room is shown — a soft ring with its name for objects, a warm ring with the
## place's name for exits; exit marks (ExitCue) light up too. Drawn by GameUi under its bars and
## panels; click-through. Pressing again restarts the time; a dialogue, a panel or a room change ends
## it at once.

const DURATION := 1.5
const FADE_IN := 0.12
const FADE_OUT := 0.35
const RING_R := 20.0
const FONT_SIZE := 25
const OUTLINE := 7
const TOP_LIMIT := 86.0          # under the top bar (GameUi.TOP_H 80)
const PAD := 6.0

var targets: Array = []          # [{kind, id, label, at: Vector2, dir, label_rect: Rect2}]
var _left: float = 0.0
var _cues: Array = []            # ExitCue lit while revealing


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = Vector2(1920, 1080)
	visible = false


func active() -> bool:
	return _left > 0.0


## Shows `p_targets` (GameUi.reveal_targets()) for DURATION seconds and lights the given exit marks.
func show_targets(p_targets: Array, cues: Array) -> void:
	_set_cues(false)
	targets = p_targets
	_cues = cues
	_set_cues(true)
	_layout_labels()
	_left = DURATION
	visible = true
	queue_redraw()


func cancel() -> void:
	_left = 0.0
	_set_cues(false)
	_cues = []
	visible = false


func _set_cues(on: bool) -> void:
	for c in _cues:
		if c != null and is_instance_valid(c):
			c.set("revealed", on)


func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	if _left <= 0.0:
		cancel()
		return
	queue_redraw()


func _alpha() -> float:
	var t := DURATION - _left
	if t < FADE_IN:
		return t / FADE_IN
	if _left < FADE_OUT:
		return _left / FADE_OUT
	return 1.0


## Label boxes: below the ring (exit marks — towards the inside of the frame), else above / right /
## left, the first that stays on screen under the top bar and does not cover an earlier label.
func _layout_labels() -> void:
	var font := UiTheme.font("body_bold")
	var placed: Array[Rect2] = []
	for t in targets:
		var text := String(t.get("label", ""))
		var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE) + Vector2(OUTLINE * 2, 4)
		var at: Vector2 = t["at"]
		var gap := RING_R + 10.0
		var below := Rect2(at + Vector2(-sz.x * 0.5, gap), sz)
		var above := Rect2(at + Vector2(-sz.x * 0.5, -gap - sz.y), sz)
		var right := Rect2(at + Vector2(gap, -sz.y * 0.5), sz)
		var left := Rect2(at + Vector2(-gap - sz.x, -sz.y * 0.5), sz)
		var order: Array = [below, above, right, left]
		match String(t.get("dir", "")):
			"down":
				order = [above, right, left, below]
			"left":
				order = [right, above, below, left]
			"right":
				order = [left, above, below, right]
			"up":
				order = [below, right, left, above]
		var best: Rect2 = order[0]
		var found := false
		for r in order:
			var c := _clamp_rect(r)
			if c != r:
				continue
			var hit := false
			for p in placed:
				if p.grow(PAD).intersects(c):
					hit = true
					break
			if not hit:
				best = c
				found = true
				break
		if not found:
			best = _clamp_rect(order[0])
			# Still covering another label: step down until free (bounded).
			for i in 6:
				var hit2 := false
				for p in placed:
					if p.grow(PAD).intersects(best):
						hit2 = true
						break
				if not hit2:
					break
				best.position.y += sz.y + PAD
				best = _clamp_rect(best)
		placed.append(best)
		t["label_rect"] = best


func _clamp_rect(r: Rect2) -> Rect2:
	var p := r.position
	p.x = clampf(p.x, 8.0, 1920.0 - 8.0 - r.size.x)
	p.y = clampf(p.y, TOP_LIMIT, 1080.0 - 6.0 - r.size.y)
	return Rect2(p, r.size)


func _draw() -> void:
	var a := _alpha()
	if a <= 0.0:
		return
	var font := UiTheme.font("body_bold")
	for t in targets:
		var at: Vector2 = t["at"]
		var exit := String(t.get("kind", "")) == "exit"
		var ring := UiTheme.GOLD_BRIGHT if exit else UiTheme.CREAM
		if not (exit and String(t.get("dir", "door")) != "door"):
			# Objects and drawn doors: a ring with a soft dark rim (the exit marks light up by themselves).
			draw_arc(at, RING_R, 0, TAU, 40, Color(0, 0, 0, 0.35 * a), 7.0, true)
			draw_arc(at, RING_R, 0, TAU, 40, Color(ring.r, ring.g, ring.b, 0.95 * a), 3.0, true)
			draw_circle(at, 4.0, Color(ring.r, ring.g, ring.b, 0.95 * a))
		var r: Rect2 = t.get("label_rect", Rect2(at, Vector2.ZERO))
		var base := Vector2(r.position.x + OUTLINE, r.position.y + font.get_ascent(FONT_SIZE) + 2.0)
		var text := String(t.get("label", ""))
		draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, OUTLINE, Color(UiTheme.OUTLINE, 0.92 * a))
		var tc := UiTheme.GOLD_BRIGHT if exit else UiTheme.CREAM
		draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(tc.r, tc.g, tc.b, a))
