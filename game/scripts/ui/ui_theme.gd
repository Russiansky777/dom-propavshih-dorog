class_name UiTheme
extends RefCounted
## The game's one UI look, built in code (no .tres to drift): warm dark panels with a thin brass
## rule, cream text, two typefaces with full Cyrillic under SIL OFL (game/assets/fonts/*/OFL.txt,
## Docs/ASSET_PROVENANCE.md):
##   - Old Standard TT (headings, room name, buttons, menu) — a revival of the "Modern" book faces
##     of late-19th / early-20th-century printing, Russian books of the time included;
##   - PT Serif (dialogue, journal, hints, tooltips) — ParaType's antiqua made for Russian text,
##     large x-height, reads well small.
## Sizes are for the 1920×1080 canvas; at 1280×720 they are ×2/3 (dialogue 31 → 20.7 px).
## Controls pick a role with `theme_type_variation` (RoomTitle, SpeakerLabel, DialogueText …).
## UiTheme.get_theme() is cached; nothing here reads autoloads, so tests may reference it freely.

const FONT_DIR := "res://assets/fonts/"

# Palette (Russian North interior: smoked wood, brass, unbleached linen).
const PANEL_BG := Color(0.105, 0.078, 0.058, 0.94)
const BAR_BG := Color(0.085, 0.063, 0.047, 0.95)
const BORDER := Color(0.68, 0.55, 0.35, 0.78)
const BORDER_DIM := Color(0.68, 0.55, 0.35, 0.36)
const CREAM := Color(0.94, 0.89, 0.79)
const GOLD := Color(0.95, 0.80, 0.52)
const GOLD_BRIGHT := Color(1.0, 0.89, 0.64)
const MUTED := Color(0.74, 0.67, 0.56)
const OUTLINE := Color(0.06, 0.04, 0.025, 0.92)
const BUTTON_BG := Color(0.20, 0.145, 0.10, 0.88)
const BUTTON_HOVER := Color(0.30, 0.21, 0.135, 0.95)
const BUTTON_PRESSED := Color(0.13, 0.095, 0.068, 0.95)

static var _theme: Theme = null
static var _fonts: Dictionary = {}


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


## head / head_bold (Old Standard TT), body / body_italic / body_bold (PT Serif).
static func font(role: String) -> Font:
	if _fonts.is_empty():
		var files := {
			"head": "old_standard_tt/OldStandard-Regular.ttf",
			"head_bold": "old_standard_tt/OldStandard-Bold.ttf",
			"body": "pt_serif/PT_Serif-Web-Regular.ttf",
			"body_italic": "pt_serif/PT_Serif-Web-Italic.ttf",
			"body_bold": "pt_serif/PT_Serif-Web-Bold.ttf",
		}
		for k in files.keys():
			var path: String = FONT_DIR + String(files[k])
			_fonts[k] = load(path) as Font if ResourceLoader.exists(path) else ThemeDB.fallback_font
	return _fonts.get(role, ThemeDB.fallback_font)


static func panel_style(bg: Color = PANEL_BG, border: Color = BORDER, margin_h: float = 22.0, margin_v: float = 16.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	sb.anti_aliasing = true
	return sb


static func _button_style(bg: Color, border: Color, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	return sb


static func _circle(radius: int, fill: Color, rim: Color) -> ImageTexture:
	var d := radius * 2 + 2
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := Vector2(d / 2.0, d / 2.0)
	for y in d:
		for x in d:
			var r := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := clampf(radius + 0.5 - r, 0.0, 1.0)
			if a <= 0.0:
				continue
			var col := rim if r > radius - 2.5 else fill
			img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * a))
	return ImageTexture.create_from_image(img)


static func _label_variation(t: Theme, name: StringName, f: String, size: int, color: Color, outline: int = 0) -> void:
	t.set_type_variation(name, &"Label")
	t.set_font(&"font", name, font(f))
	t.set_font_size(&"font_size", name, size)
	t.set_color(&"font_color", name, color)
	if outline > 0:
		t.set_color(&"font_outline_color", name, OUTLINE)
		t.set_constant(&"outline_size", name, outline)


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = font("body")
	t.default_font_size = 26

	# Plain labels: body face, cream.
	t.set_color(&"font_color", &"Label", CREAM)
	t.set_color(&"font_outline_color", &"Label", OUTLINE)

	_label_variation(t, &"RoomTitle", "head_bold", 33, CREAM)
	t.set_color(&"font_shadow_color", &"RoomTitle", Color(0, 0, 0, 0.55))
	t.set_constant(&"shadow_offset_x", &"RoomTitle", 0)
	t.set_constant(&"shadow_offset_y", &"RoomTitle", 2)
	_label_variation(t, &"RoomCode", "body", 19, GOLD)
	_label_variation(t, &"HeaderLarge", "head_bold", 46, GOLD)
	_label_variation(t, &"HeaderSmall", "head_bold", 28, GOLD)
	_label_variation(t, &"SpeakerLabel", "head_bold", 31, GOLD)
	_label_variation(t, &"BodyLabel", "body", 29, CREAM)
	_label_variation(t, &"SmallLabel", "body", 23, CREAM)
	_label_variation(t, &"SlotNameLabel", "head_bold", 27, CREAM)
	_label_variation(t, &"MutedLabel", "body_italic", 22, MUTED)
	_label_variation(t, &"HoverLabel", "body_bold", 27, CREAM, 8)
	_label_variation(t, &"HintLabel", "body_italic", 28, CREAM, 8)
	_label_variation(t, &"BagEmptyLabel", "body_italic", 22, MUTED)
	_label_variation(t, &"BagTooltipTitle", "head_bold", 28, GOLD)
	_label_variation(t, &"BagTooltipText", "body", 23, CREAM)
	_label_variation(t, &"BagTooltipHint", "body_italic", 20, MUTED)
	# Plan of Zarechye: dark ink names on small paper plates; the current place in red ochre.
	_label_variation(t, &"MapLabel", "head_bold", 26, Color(0.20, 0.12, 0.06))
	_label_variation(t, &"MapLabelHere", "head_bold", 28, Color(0.50, 0.11, 0.06))
	_label_variation(t, &"MapLabelFaint", "head_bold", 25, Color(0.42, 0.34, 0.25))   # not visited yet
	_label_variation(t, &"MapHereLabel", "body_italic", 22, Color(1.0, 0.95, 0.88))
	_label_variation(t, &"MapHint", "body_italic", 21, Color(0.96, 0.92, 0.84), 6)
	for v in [[&"MapLabel", Color(0.96, 0.91, 0.80, 0.90), Color(0.40, 0.27, 0.15, 0.85), 1],
			[&"MapLabelHere", Color(0.99, 0.94, 0.84, 0.95), Color(0.62, 0.15, 0.08, 1.0), 2],
			[&"MapLabelFaint", Color(0.93, 0.89, 0.80, 0.80), Color(0.55, 0.45, 0.33, 0.45), 1],
			[&"MapHereLabel", Color(0.62, 0.15, 0.08, 0.92), Color(0.35, 0.08, 0.04, 1.0), 1]]:
		var plate := StyleBoxFlat.new()
		plate.bg_color = v[1]
		plate.border_color = v[2]
		plate.set_border_width_all(v[3])
		plate.set_corner_radius_all(4)
		plate.shadow_color = Color(0, 0, 0, 0.28)
		plate.shadow_size = 3
		plate.shadow_offset = Vector2(1, 2)
		plate.content_margin_left = 10
		plate.content_margin_right = 10
		plate.content_margin_top = 1
		plate.content_margin_bottom = 3
		t.set_stylebox(&"normal", v[0], plate)
	_label_variation(t, &"CloseupLabel", "body", 24, CREAM, 5)
	_label_variation(t, &"CloseupTitle", "head_bold", 34, GOLD, 5)

	# Rich text: dialogue and journal.
	t.set_font(&"normal_font", &"RichTextLabel", font("body"))
	t.set_font(&"italics_font", &"RichTextLabel", font("body_italic"))
	t.set_font(&"bold_font", &"RichTextLabel", font("body_bold"))
	t.set_font_size(&"normal_font_size", &"RichTextLabel", 27)
	t.set_font_size(&"italics_font_size", &"RichTextLabel", 27)
	t.set_font_size(&"bold_font_size", &"RichTextLabel", 27)
	t.set_color(&"default_color", &"RichTextLabel", CREAM)
	t.set_constant(&"line_separation", &"RichTextLabel", 5)
	for v in [[&"DialogueText", 31], [&"JournalText", 26]]:
		t.set_type_variation(v[0], &"RichTextLabel")
		for k in [&"normal_font_size", &"italics_font_size", &"bold_font_size"]:
			t.set_font_size(k, v[0], v[1])

	# Panels.
	t.set_stylebox(&"panel", &"PanelContainer", panel_style())
	t.set_stylebox(&"panel", &"Panel", panel_style())
	# Dialogue: lighter so the room shows through, a little tighter.
	t.set_type_variation(&"DialoguePanel", &"PanelContainer")
	var dlg := panel_style(Color(0.09, 0.066, 0.048, 0.80), BORDER, 28.0, 12.0)
	dlg.content_margin_bottom = 14
	t.set_stylebox(&"panel", &"DialoguePanel", dlg)
	t.set_type_variation(&"TopBarPanel", &"PanelContainer")
	var bar := StyleBoxFlat.new()
	bar.bg_color = BAR_BG
	bar.border_color = BORDER
	bar.border_width_bottom = 2
	bar.shadow_color = Color(0, 0, 0, 0.42)
	bar.shadow_size = 10
	bar.shadow_offset = Vector2(0, 3)
	bar.content_margin_left = 22
	bar.content_margin_right = 14
	bar.content_margin_top = 4
	bar.content_margin_bottom = 4
	t.set_stylebox(&"panel", &"TopBarPanel", bar)
	t.set_type_variation(&"BagTooltipPanel", &"PanelContainer")
	var tip := panel_style(Color(0.11, 0.08, 0.058, 0.97), BORDER, 16.0, 10.0)
	tip.shadow_size = 8
	t.set_stylebox(&"panel", &"BagTooltipPanel", tip)
	t.set_stylebox(&"panel", &"TooltipPanel", tip)
	t.set_font(&"font", &"TooltipLabel", font("body"))
	t.set_font_size(&"font_size", &"TooltipLabel", 21)
	t.set_color(&"font_color", &"TooltipLabel", CREAM)

	# Buttons: Old Standard on dark wood with a brass rule; no focus ring (mouse-only game).
	t.set_font(&"font", &"Button", font("head_bold"))
	t.set_font_size(&"font_size", &"Button", 27)
	t.set_color(&"font_color", &"Button", CREAM)
	t.set_color(&"font_hover_color", &"Button", GOLD_BRIGHT)
	t.set_color(&"font_pressed_color", &"Button", GOLD)
	t.set_color(&"font_hover_pressed_color", &"Button", GOLD_BRIGHT)
	t.set_color(&"font_focus_color", &"Button", CREAM)
	t.set_color(&"font_disabled_color", &"Button", Color(0.58, 0.53, 0.46, 0.7))
	t.set_stylebox(&"normal", &"Button", _button_style(BUTTON_BG, BORDER_DIM))
	t.set_stylebox(&"hover", &"Button", _button_style(BUTTON_HOVER, BORDER))
	t.set_stylebox(&"pressed", &"Button", _button_style(BUTTON_PRESSED, GOLD))
	t.set_stylebox(&"hover_pressed", &"Button", _button_style(BUTTON_PRESSED, GOLD_BRIGHT))
	t.set_stylebox(&"disabled", &"Button", _button_style(Color(BUTTON_BG, 0.4), Color(BORDER_DIM, 0.2)))
	t.set_stylebox(&"focus", &"Button", StyleBoxEmpty.new())

	# Top-bar buttons: lighter, they sit on the bar itself.
	t.set_type_variation(&"BarButton", &"Button")
	t.set_stylebox(&"normal", &"BarButton", _button_style(Color(0.16, 0.115, 0.08, 0.55), BORDER_DIM))
	t.set_font_size(&"font_size", &"BarButton", 27)

	# Dialogue options: body face, left aligned, a brass bar on the left when hovered.
	t.set_type_variation(&"DialogueOption", &"Button")
	t.set_font(&"font", &"DialogueOption", font("body"))
	t.set_font_size(&"font_size", &"DialogueOption", 28)
	var opt_n := _button_style(Color(0.17, 0.125, 0.09, 0.55), Color(0, 0, 0, 0), 0)
	opt_n.border_width_left = 3
	opt_n.border_color = BORDER_DIM
	var opt_h := _button_style(Color(0.30, 0.21, 0.135, 0.9), GOLD, 0)
	opt_h.border_width_left = 3
	t.set_stylebox(&"normal", &"DialogueOption", opt_n)
	t.set_stylebox(&"hover", &"DialogueOption", opt_h)
	t.set_stylebox(&"pressed", &"DialogueOption", opt_h)

	# Bag page arrows: bare glyphs.
	t.set_type_variation(&"BagArrow", &"Button")
	t.set_font_size(&"font_size", &"BagArrow", 38)
	for s in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		t.set_stylebox(s, &"BagArrow", StyleBoxEmpty.new())
	t.set_color(&"font_disabled_color", &"BagArrow", Color(0.84, 0.70, 0.47, 0.25))
	t.set_font(&"font", &"BagSlot", font("head_bold"))

	# Music slider (menu).
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.06, 0.045, 0.032)
	track.border_color = BORDER_DIM
	track.set_border_width_all(1)
	track.set_corner_radius_all(4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = Color(0.62, 0.48, 0.28)
	var fill_h := track.duplicate() as StyleBoxFlat
	fill_h.bg_color = GOLD
	t.set_stylebox(&"slider", &"HSlider", track)
	t.set_stylebox(&"grabber_area", &"HSlider", fill)
	t.set_stylebox(&"grabber_area_highlight", &"HSlider", fill_h)
	t.set_icon(&"grabber", &"HSlider", _circle(12, CREAM, Color(0.45, 0.33, 0.2)))
	t.set_icon(&"grabber_highlight", &"HSlider", _circle(13, GOLD_BRIGHT, Color(0.5, 0.36, 0.2)))
	return t
