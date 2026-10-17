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
## Direction mapping (data): `direction_zero` = where row 0 faces on screen ("down" = towards the
## viewer), `direction_order` = how rows go on screen ("ccw" or "cw").
var direction_zero: String = "down"
var direction_order: String = "ccw"
var figure_height_px: float = 337.0
var character_height_m: float = 1.657
var speed_mps: float = 1.12          # walking speed in model metres per second
var cycle_meters: float = 1.3        # ground covered by one full walk cycle (two steps)
var direction_threshold_px: float = 0.5
## Foot lock: the drawn figure advances only when the walk frame changes (by exactly one stride),
## so the planted foot never drifts while a frame is shown. The logical position still moves smoothly.
var foot_lock: bool = true
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
	a.direction_zero = String(spec.get("direction_zero", "down"))
	a.direction_order = String(spec.get("direction_order", "ccw"))
	a.figure_height_px = float(spec.get("figure_height_px", a.figure_height_px))
	var walk: Dictionary = spec.get("walk", {})
	a.speed_mps = float(walk.get("speed_mps", a.speed_mps))
	a.cycle_meters = float(walk.get("cycle_meters", a.cycle_meters))
	a.direction_threshold_px = float(walk.get("direction_threshold_px", a.direction_threshold_px))
	a.foot_lock = bool(walk.get("foot_lock", a.foot_lock))
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
	a.character_height_m = float(sprites.get("character_height_m", a.character_height_m))
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


## Screen motion vector (y down) → direction row index. Evaluates the data mapping:
## a = atan2(vy, vx) in degrees; row = round((zero − a) / step) mod rows for "ccw", (a − zero) for "cw".
func direction_index(motion: Vector2) -> int:
	if motion.length_squared() < 0.000001:
		return 0
	var deg := rad_to_deg(atan2(motion.y, motion.x))
	var zero: float = float({"down": 90.0, "right": 0.0, "up": -90.0, "left": 180.0}.get(direction_zero, 90.0))
	var step: float = 360.0 / float(directions)
	var rel: float = (zero - deg) if direction_order == "ccw" else (deg - zero)
	return wrapi(int(round(rel / step)), 0, directions)


## Pixels per model metre at a given node scale (frame height spans the model's height).
func px_per_meter(scale: float) -> float:
	return float(frame_h) * scale / maxf(character_height_m, 0.01)


## Walking speed in screen px/s at a given depth scale (constant in metres per second).
func walk_speed_px(scale: float) -> float:
	return speed_mps * px_per_meter(scale)


## Frame rate of the walk cycle for a given screen speed and scale:
## fps = frames × speed_px / (cycle_meters × px_per_m).
func walk_fps(speed_px: float, scale: float) -> float:
	var n := walk_frames()
	return float(n) * speed_px / maxf(cycle_meters * px_per_meter(scale), 0.001)


func walk_frames() -> int:
	return int(actions.get(walk_action, {}).get("frames", 12))


## Ground covered by one walk frame, in sheet pixels (node scale 1): cycle_px / frames.
## This is the distance the planted foot slides back between two consecutive sheet frames
## (measured on the sheet by tools/measure_stride.py), so the figure may advance by exactly
## this much per frame without the foot drifting.
func stride_px_unit() -> float:
	return cycle_meters * px_per_meter(1.0) / float(maxi(walk_frames(), 1))


func anim_name(action: String, dir: int) -> String:
	return "%s_%d" % [action, dir]
