class_name ExitCursors
extends RefCounted
## Exit cursors (Director 18.10: the player must see where one can go). The project had no cursor art,
## so they are drawn here as SVG in the UI palette — cream fill, dark-brown rim, a soft shadow:
##   up / down / left / right — an arrow in the exit's direction (ExitCue.classify);
##   door — a doorway with an arrow into it (an exit through a door or opening drawn in the art).
## Over objects the cursor stays the ordinary pointer («осмотреть / взять»).
##
## install() puts each image on a spare cursor shape once; GameUi then only switches
## Input.set_default_cursor_shape() while an exit is under the pointer — the pointer over the UI
## (bars, panels, the bag) keeps its own shapes. In the web build Godot sets the canvas CSS cursor to
## the image (tools/exits_web.mjs reads it back).

const SIZE := 48
## Spare shapes: nothing in the game's UI uses them (no splitters, resizers or drag-and-drop).
const SHAPES := {
	"up": Input.CURSOR_VSPLIT,
	"down": Input.CURSOR_VSIZE,
	"left": Input.CURSOR_HSPLIT,
	"right": Input.CURSOR_HSIZE,
	"door": Input.CURSOR_MOVE,
}
const FILL := "#f3e8d2"
const RIM := "#24170c"

static var _installed: bool = false
static var images: Dictionary = {}   # kind -> Image (tests, shots)


## Cursor shape for an exit kind ("" or unknown → the ordinary arrow).
static func shape(kind: String) -> Input.CursorShape:
	return SHAPES.get(kind, Input.CURSOR_ARROW)


static func install() -> void:
	if _installed:
		return
	_installed = true
	for kind in SHAPES.keys():
		var img := image(kind)
		if img == null:
			continue
		var hotspot := Vector2(SIZE * 0.5, SIZE * 0.5)
		Input.set_custom_mouse_cursor(img, shape(kind), hotspot)


static func image(kind: String) -> Image:
	if images.has(kind):
		return images[kind]
	var img := Image.new()
	if img.load_svg_from_string(svg(kind), 1.0) != OK or img.is_empty():
		push_warning("ExitCursors: SVG for '%s' failed to rasterise" % kind)
		return null
	images[kind] = img
	return img


static func svg(kind: String) -> String:
	var body := ""
	if kind == "door":
		# A doorway (round-topped frame) with an arrow going in.
		var arch := "M13 43 V21 A11 11 0 0 1 35 21 V43"
		var arrow := "M24 16 L32.5 26 L27.5 26 L27.5 37 L20.5 37 L20.5 26 L15.5 26 Z"
		body = ("<g transform='translate(1.5 2.5)' opacity='0.38'><path d='%s' fill='none' stroke='#000' stroke-width='7.5' stroke-linecap='round'/>" +
			"<path d='%s' fill='#000'/></g>") % [arch, arrow]
		body += "<path d='%s' fill='none' stroke='%s' stroke-width='7.5' stroke-linecap='round'/>" % [arch, RIM]
		body += "<path d='%s' fill='none' stroke='%s' stroke-width='3.6' stroke-linecap='round'/>" % [arch, FILL]
		body += "<path d='%s' fill='%s' stroke='%s' stroke-width='2.2' stroke-linejoin='round'/>" % [arrow, FILL, RIM]
	else:
		var angle: int = {"up": 0, "right": 90, "down": 180, "left": 270}.get(kind, 0)
		# An arrow pointing up, turned to the direction; the shadow stays below in screen space.
		var arrow := "M24 4.5 L41 22.5 L30.5 22.5 L30.5 42.5 L17.5 42.5 L17.5 22.5 L7 22.5 Z"
		body = "<g transform='translate(1.5 2.5)'><path d='%s' fill='#000' opacity='0.38' transform='rotate(%d 24 24)'/></g>" % [arrow, angle]
		body += "<path d='%s' fill='%s' stroke='%s' stroke-width='2.4' stroke-linejoin='round' transform='rotate(%d 24 24)'/>" % [arrow, FILL, RIM, angle]
	return "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' viewBox='0 0 48 48'>%s</svg>" % [SIZE, SIZE, body]
