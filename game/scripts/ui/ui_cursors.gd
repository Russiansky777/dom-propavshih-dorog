class_name UiCursors
extends RefCounted
## The game's mouse cursors — one engraved set in the old-Russian book style (Director 18.10: «внедрить
## старорусский курсор»; the big exit arrows are gone: «стрелка … слишком большая, её вообще уберём»).
## Drawings: game/assets/ui/glyphs/cursor_<kind>.svg (UiGlyphs), dark-brown ink with a warm cream
## contour and a thin dark edge — reads on snow and on a dark floor alike. Size as a system cursor:
## 32 px, 64 px on a HiDPI screen (pixel_scale()), the hot spot at the very tip.
##   arrow — «стрела-указка», the ordinary pointer everywhere (also over exits and the interface);
##   look  — «перст-указатель»: an object one can examine or take (also bag pockets, a handle);
##   talk  — arrow and speech banderole: a character;
##   use   — the pointing hand with a spark: an item from the bag is in hand, over a hotspot;
##   grab / grip — open / closed hand on close-ups (take a part / carry it).
## install() puts each image on its Input cursor shape once; GameUi only switches
## Input.set_default_cursor_shape(); Controls keep their own shapes (the bag's pointing hand, the
## close-up's open/closed hand) and get the same drawings. In the web build Godot turns the image into
## the canvas CSS cursor (tools/ui_web.mjs reads it back).

## kind -> Input cursor shape that carries its image.
const SHAPES := {
	"arrow": Input.CURSOR_ARROW,
	"look": Input.CURSOR_POINTING_HAND,
	"talk": Input.CURSOR_HELP,
	"use": Input.CURSOR_CROSS,
	"grab": Input.CURSOR_DRAG,
	"grip": Input.CURSOR_CAN_DROP,
}
## Hot spot of each drawing at 32 px (the tip of the arrow / the finger, the middle of the palm).
const HOTSPOTS := {
	"arrow": Vector2i(2, 2),
	"look": Vector2i(5, 1),
	"talk": Vector2i(2, 2),
	"use": Vector2i(5, 1),
	"grab": Vector2i(13, 14),
	"grip": Vector2i(14, 18),
}
## Direction each pointer points to (its tip is the extreme opaque point that way) — tests.
const POINTS := {
	"arrow": Vector2(-0.7071, -0.7071),
	"look": Vector2(-0.5736, -0.8192),
	"talk": Vector2(-0.7071, -0.7071),
	"use": Vector2(-0.5736, -0.8192),
}
const BASE := 32

static var installed_scale: int = 0


static func shape(kind: String) -> Input.CursorShape:
	return SHAPES.get(kind, Input.CURSOR_ARROW)


## 2 on a HiDPI desktop screen (Windows / Linux at ≥ 175 % scaling), else 1. The web build and macOS
## show the image in logical pixels (a 64 px image would be twice as large), so they keep 32 px.
static func pixel_scale() -> int:
	if OS.has_feature("web") or OS.get_name() == "macOS" or DisplayServer.get_name() == "headless":
		return 1
	return 2 if DisplayServer.screen_get_dpi() >= 168 else 1


static func image(kind: String, scale: int = 1) -> Image:
	return UiGlyphs.image(UiGlyphs.CURSOR_PREFIX + kind, float(scale))


static func hotspot(kind: String, scale: int = 1) -> Vector2:
	return Vector2(HOTSPOTS.get(kind, Vector2i(2, 2))) * scale


static func install() -> void:
	var s := pixel_scale()
	if installed_scale == s:
		return
	installed_scale = s
	for kind in SHAPES.keys():
		var img := image(kind, s)
		if img == null:
			continue
		Input.set_custom_mouse_cursor(img, shape(kind), hotspot(kind, s))
