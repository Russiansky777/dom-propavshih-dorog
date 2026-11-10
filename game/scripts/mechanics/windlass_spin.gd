class_name WindlassSpin
extends Node2D
## Ilya's windlass turns (Director 10.11, 16:15: «чтобы как-то крутился реально ворот у Ильи, когда он с Агатой
## брёвна ставит… оживить его, установку эту»). The site's painting has the windlass whole — the drum with the rope's
## coils between two posts and two cranks (the left one up, the right one down); in the close-up of the first span
## (WindlassPanel) its parts move, made from the painting by tools/make_windlass_layers.py (windlass.json beside them):
##   · the painted cranks are covered with the same ground (windlass_clean.png);
##   · each crank is drawn again at its angle: the arm from the axle's hub to the grip — a dark iron bar; the wooden
##     grip is the painting's own (windlass_grip_l/r.png). The arm goes round in the plane across the windlass's axis;
##     we look at the windlass nearly from its side, so the round is seen as a narrow oval (data arm.rx × arm.ry);
##     the right crank is half a turn from the left one, as painted;
##   · the rope's coils on the drum slide along it (windlass_drum.png, a shader shifts them by one coil per turn —
##     what a wound drum looks like when it turns), inside the drum's own outline.
## `angle` — the left crank's angle (rad): 0 — straight up; the panel turns it while Ilya cranks and lets it come to
## the painted pose when he stops (rest()). Coordinates: canvas px of the painting × `k` = screen px.

const ARM_DARK := Color(0.2, 0.165, 0.145)
const ARM_LIGHT := Color(0.44, 0.38, 0.33)
const REST := 0.35      # the painted pose: the left crank up and a little towards us

const DRUM_SHADER := "
shader_type canvas_item;
uniform float shift = 0.0;      // texture px along the drum
uniform float width_px = 49.0;
uniform float slope = 0.0;      // the drum's tilt on the picture: dy per dx (texture px)
uniform float height_px = 54.0;
void fragment() {
	float dx = fract(UV.x + shift / width_px) - UV.x;
	vec2 uv = vec2(UV.x + dx, clamp(UV.y + slope * dx * width_px / height_px, 0.0, 1.0));
	COLOR = vec4(texture(TEXTURE, uv).rgb, texture(TEXTURE, UV).a);
}
"

var k: float = 1.0
var meta: Dictionary = {}
var angle: float = REST:
	set(v):
		angle = v
		_apply()
var _grips: Dictionary = {}     # side → Texture2D
var _drum: Sprite2D = null


## The windlass's parts beside the site's picture (`waiting_path` — …/beam_waiting.png); null when they are not there
## (the painting stays as it is).
static func make(waiting_path: String, p_k: float) -> WindlassSpin:
	var dir := waiting_path.get_base_dir()
	var jp := dir + "/windlass.json"
	if not FileAccess.file_exists(jp):
		return null
	var m = JSON.parse_string(FileAccess.get_file_as_string(jp))
	if not (m is Dictionary) or not m.has("axles"):
		return null
	var s := WindlassSpin.new()
	s.name = "WindlassSpin"
	s.k = p_k
	s.meta = m
	var clean: Dictionary = m.get("clean", {})
	var ct := s._tex(dir, String(clean.get("file", "")))
	if ct != null:
		var cs := Sprite2D.new()
		cs.name = "Clean"
		cs.texture = ct
		cs.centered = false
		cs.position = Vector2(float(clean["at"][0]), float(clean["at"][1])) * p_k
		cs.scale = Vector2(p_k, p_k)
		s.add_child(cs)
	var drum: Dictionary = m.get("drum", {})
	var dt := s._tex(dir, String(drum.get("file", "")))
	if dt != null:
		var ds := Sprite2D.new()
		ds.name = "Drum"
		ds.texture = dt
		ds.centered = false
		ds.position = Vector2(float(drum["at"][0]), float(drum["at"][1])) * p_k
		ds.scale = Vector2(p_k, p_k)
		var sh := Shader.new()
		sh.code = DRUM_SHADER
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("width_px", float(drum["size"][0]))
		mat.set_shader_parameter("height_px", float(drum["size"][1]))
		mat.set_shader_parameter("slope", float(drum.get("slope", -0.1)))
		ds.material = mat
		s.add_child(ds)
		s._drum = ds
	for side in m.get("grips", {}):
		var gt := s._tex(dir, String(m["grips"][side].get("file", "")))
		if gt != null:
			s._grips[side] = gt
	s._apply()
	return s


func _tex(dir: String, file: String) -> Texture2D:
	if file == "" or not ResourceLoader.exists(dir + "/" + file):
		return null
	return load(dir + "/" + file) as Texture2D


## Where a crank's arm ends (the grip's joint) on screen: side "l" or "r". The round is fitted to the painting: at
## REST the arm ends exactly where the painted grip sits (grips[side].joint), so nothing moves when the close-up opens
## over the painted windlass or closes — the left crank up, the right one down, half a turn apart. The grip's round is
## an oval `arm.rx` wide (we look at the cranks nearly edge-on), as high as the painted arm makes it, its centre set
## off the hub along the axle as painted.
func tip(side: String) -> Vector2:
	var a: Array = meta.get("axles", {}).get(side, [0, 0])
	var j: Array = meta.get("grips", {}).get(side, {}).get("joint", a)
	var d := Vector2(float(j[0]) - float(a[0]), float(j[1]) - float(a[1]))   # the painted arm
	var rx := float(meta.get("arm", {}).get("rx", 9.0))
	var p0 := REST + (PI if side == "r" else 0.0)
	var ph := angle + (PI if side == "r" else 0.0)
	var ry := absf(d.y) / maxf(absf(cos(p0)), 0.2)
	var cx := d.x - rx * sin(p0)
	return (Vector2(float(a[0]), float(a[1])) + Vector2(cx + rx * sin(ph), -ry * cos(ph))) * k


## The angle the crank comes to when let go: the painted pose, the nearest one ahead in the turning direction `dir`.
static func rest_after(now: float, dir: float) -> float:
	var turns := (now - REST) / TAU
	return REST + (ceilf(turns - 0.0001) if dir >= 0.0 else floorf(turns + 0.0001)) * TAU


func _apply() -> void:
	if _drum != null and _drum.material != null:
		var pitch := float(meta.get("drum", {}).get("pitch", 7.0))
		(_drum.material as ShaderMaterial).set_shader_parameter("shift", pitch * angle / TAU)
	queue_redraw()


func _draw() -> void:
	var arm: Dictionary = meta.get("arm", {})
	var w := float(arm.get("width", 6.0)) * k
	for side in ["l", "r"]:
		if not meta.get("axles", {}).has(side):
			continue
		var a: Array = meta["axles"][side]
		var ax := Vector2(float(a[0]), float(a[1])) * k
		var t := tip(side)
		draw_line(ax, t, ARM_DARK, w, true)
		var up := Vector2(-0.7, -0.7) * (w * 0.22)
		draw_line(ax + up, t + up, ARM_LIGHT, maxf(1.0, w * 0.22), true)
		draw_circle(t, w * 0.62, ARM_DARK)
		if _grips.has(side):
			var g: Dictionary = meta["grips"][side]
			var tex: Texture2D = _grips[side]
			var off := (Vector2(float(g["at"][0]), float(g["at"][1])) - Vector2(float(g["joint"][0]), float(g["joint"][1]))) * k
			draw_texture_rect(tex, Rect2(t + off, tex.get_size() * k), false)
