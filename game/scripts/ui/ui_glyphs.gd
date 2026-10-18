class_name UiGlyphs
extends RefCounted
## Small drawings of the interface — cursors and exit icons — drawn as SVG by hand in one engraving
## style (Director 18.10: «старорусский курсор», «значок места назначения у подписи выхода»):
##   game/assets/ui/glyphs/cursor_<kind>.svg — 32×32 (UiCursors), exit_<name>.svg — 28×28 (exit icons).
## The files are imported as «keep» (exported as is, .svg.import → importer="keep"), so the game reads
## the SVG text and rasterises it itself (Image.load_svg_from_string, the same ThorVG as the editor) at
## the pixel size it needs: 32 / 64 px cursors, exit icons at 2× for a sharp picture when the window is
## larger than 1920×1080. Names of the exit icons are data: rooms/_index.json → exit_cue.icons
## (destination room → icon), a room exit may override with its own `icon` (StoryExit.icon_name()).
## tools/validate_rooms.py checks that every exit resolves to an existing exit_<name>.svg.

const DIR := "res://assets/ui/glyphs/"
const EXIT_PREFIX := "exit_"
const CURSOR_PREFIX := "cursor_"

static var _svg: Dictionary = {}       # file name (no .svg) -> text
static var _img: Dictionary = {}       # "name@scale" -> Image
static var _tex: Dictionary = {}       # "name@scale" -> ImageTexture


static func path(glyph: String) -> String:
	return DIR + glyph + ".svg"


static func exists(glyph: String) -> bool:
	return FileAccess.file_exists(path(glyph))


static func svg(glyph: String) -> String:
	if not _svg.has(glyph):
		_svg[glyph] = FileAccess.get_file_as_string(path(glyph)) if exists(glyph) else ""
	return _svg[glyph]


## The glyph rasterised at `scale` (1.0 = its viewBox size in px). null when missing or broken.
static func image(glyph: String, scale: float = 1.0) -> Image:
	var key := "%s@%.3f" % [glyph, scale]
	if _img.has(key):
		return _img[key]
	var text := svg(glyph)
	var img: Image = null
	if text != "":
		img = Image.new()
		if img.load_svg_from_string(text, scale) != OK or img.is_empty():
			push_warning("UiGlyphs: '%s' failed to rasterise" % glyph)
			img = null
		else:
			img.convert(Image.FORMAT_RGBA8)
	else:
		push_warning("UiGlyphs: no glyph '%s'" % path(glyph))
	_img[key] = img
	return img


## A texture with mipmaps (drawn smaller than its pixels when the window is below 1920×1080).
static func texture(glyph: String, scale: float = 2.0) -> Texture2D:
	var key := "%s@%.3f" % [glyph, scale]
	if _tex.has(key):
		return _tex[key]
	var img := image(glyph, scale)
	var tex: Texture2D = null
	if img != null:
		var copy := img.duplicate() as Image
		copy.generate_mipmaps()
		tex = ImageTexture.create_from_image(copy)
	_tex[key] = tex
	return tex


## Exit icon names that have a drawing (exit_<name>.svg), sorted.
static func exit_icon_names() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.begins_with(EXIT_PREFIX) and f.ends_with(".svg"):
			out.append(f.trim_prefix(EXIT_PREFIX).trim_suffix(".svg"))
	out.sort()
	return out


## Exit icon texture by icon name ("" or unknown → null).
static func exit_icon(icon_name: String) -> Texture2D:
	if icon_name == "" or not exists(EXIT_PREFIX + icon_name):
		return null
	return texture(EXIT_PREFIX + icon_name, 2.0)
