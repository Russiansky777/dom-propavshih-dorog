class_name ActorSheet
extends RefCounted
## Builds SpriteFrames for an actor from `data/actors/<id>.json` + the sheet's `sprites.json`.
## Rows of a sheet are directions, columns are frames. Animations are named "<action>_<dir>".

var id: String = ""
var frame_w: int = 288
var frame_h: int = 384
var pivot: Vector2 = Vector2(0.5, 0.946)
var directions: int = 8
var actions: Dictionary = {}       # action -> {sheet, frames, fps}
var direction_map: Dictionary = {"zero_screen_angle_deg": 90.0, "step_deg": 45.0, "clockwise_on_screen": true}
var figure_height_px: float = 337.0
var walk_px_per_frame: float = 12.0
var idle_action: String = "idle"
var walk_action: String = "walk"
var idle_static_frame: int = -1   # >= 0: the idle animation uses only this frame (turn clips, placeholders)
var sheet_dir: String = ""
var frames: SpriteFrames = null
var load_error: String = ""


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed


static func load_actor(actor_id: String) -> ActorSheet:
	var a := ActorSheet.new()
	a.id = actor_id
	var spec = _read_json("res://data/actors/%s.json" % actor_id)
	if typeof(spec) != TYPE_DICTIONARY:
		a.load_error = "missing data/actors/%s.json" % actor_id
		return a
	a.sheet_dir = String(spec.get("sheet_dir", "res://assets/characters/" + actor_id))
	a.direction_map = spec.get("direction_map", a.direction_map)
	a.figure_height_px = float(spec.get("figure_height_px", a.figure_height_px))
	a.walk_px_per_frame = float(spec.get("walk_px_per_frame", a.walk_px_per_frame))
	a.idle_action = String(spec.get("idle_action", "idle"))
	a.walk_action = String(spec.get("walk_action", "walk"))
	a.idle_static_frame = int(spec.get("idle_static_frame", -1))
	var sprites = _read_json(a.sheet_dir + "/" + String(spec.get("sprites", "sprites.json")))
	if typeof(sprites) != TYPE_DICTIONARY:
		a.load_error = "missing sprites.json in " + a.sheet_dir
		return a
	a.frame_w = int(sprites.get("frame_w", 288))
	a.frame_h = int(sprites.get("frame_h", 384))
	var p: Dictionary = sprites.get("pivot", {})
	a.pivot = Vector2(float(p.get("x", 0.5)), float(p.get("y", 0.946)))
	a.directions = int(sprites.get("directions", 8))
	a.actions = sprites.get("actions", {})
	a._build_frames()
	return a


func _build_frames() -> void:
	frames = SpriteFrames.new()
	frames.remove_animation("default")
	for action in actions.keys():
		var act: Dictionary = actions[action]
		var path := sheet_dir + "/" + String(act.get("sheet", action + ".png"))
		if not ResourceLoader.exists(path):
			load_error = "missing sheet " + path
			continue
		var tex: Texture2D = load(path)
		var n := int(act.get("frames", 1))
		var fps := float(act.get("fps", 8))
		var frame_ids := range(n)
		if String(action) == idle_action and idle_static_frame >= 0 and idle_static_frame < n:
			frame_ids = [idle_static_frame]
		for d in directions:
			var anim := "%s_%d" % [action, d]
			frames.add_animation(anim)
			frames.set_animation_speed(anim, fps)
			frames.set_animation_loop(anim, true)
			for i in frame_ids:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(i * frame_w, d * frame_h, frame_w, frame_h)
				frames.add_frame(anim, at)


func is_loaded() -> bool:
	return load_error == "" and frames != null and frames.get_animation_names().size() > 0


## Sprite offset so that the pivot (feet) sits at the node origin (AnimatedSprite2D centered=false).
func sprite_offset() -> Vector2:
	return Vector2(-pivot.x * frame_w, -pivot.y * frame_h)


## Screen motion vector (y down) → direction row index. The only place the mapping lives.
func direction_index(motion: Vector2) -> int:
	if motion.length_squared() < 0.000001:
		return 0
	var deg := rad_to_deg(atan2(motion.y, motion.x))
	var zero := float(direction_map.get("zero_screen_angle_deg", 90.0))
	var step := float(direction_map.get("step_deg", 45.0))
	var rel := (deg - zero) if bool(direction_map.get("clockwise_on_screen", true)) else (zero - deg)
	return wrapi(int(round(rel / step)), 0, directions)


func anim_name(action: String, dir: int) -> String:
	return "%s_%d" % [action, dir]
